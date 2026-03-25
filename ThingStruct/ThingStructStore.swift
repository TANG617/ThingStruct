import Foundation
import Observation
import WidgetKit

// `RootTab` 是最顶层 TabView 的选中状态。
// 用 enum 而不是 `Int` / `String` 的好处是：
// 1. 编译器能帮你检查分支是否处理完整
// 2. 改名字时 IDE 可以全局安全重构
enum RootTab: Hashable {
    case now
    case today
    case library
}

// `ThingStructStore` 是整个 app 的 UI 状态中枢。
//
// 如果你来自 C++，可以把它理解成下面三者的混合体：
// - 一部分像“应用级 controller”
// - 一部分像“view model / presenter”
// - 一部分像“command dispatcher”
//
// 它并不是纯业务层；真正的业务规则在 CoreShared 的各个 engine 里。
// 它的职责是：
// 1. 持有当前已加载的 document
// 2. 把 document 转成屏幕需要的 model
// 3. 响应用户操作并把结果持久化
// 4. 在文档变更后同步 widget / live activity / notification
@MainActor
@Observable
final class ThingStructStore {
    // MARK: State

    // `document` 是持久化数据在内存中的“当前快照”。
    // SwiftUI 页面几乎都间接依赖它。
    var document: ThingStructDocument = .init()
    var tintPreset: AppTintPreset

    // 这些字段是 UI 层状态，而不是业务模型本身：
    // - 当前哪个 tab 被选中
    // - Library 是否推到了某个子页面
    // - 当前选中的日期和 block
    var selectedTab: RootTab = .now {
        didSet {
            // 当用户切换顶层 tab 时，之前选中的 block 详情通常已失去上下文，
            // 所以这里直接清掉，避免旧选择“穿透”到新页面。
            guard oldValue != selectedTab else { return }
            selectedBlockID = nil
        }
    }
    var libraryNavigationPath: [LibraryDestination] = []
    var selectedDate: LocalDay = LocalDay.today()
    var selectedBlockID: UUID?
    var isLoaded = false
    private(set) var lastErrorMessage: String?

    // Store 本身不直接读写 JSON 文件，而是依赖一个 concrete repository。
    // 这样做有两个教育意义：
    // 1. UI 层不碰文件系统细节
    // 2. 预览/测试可以替换 repository 的落点
    private let documentRepository: ThingStructDocumentRepository

    init(documentRepository: ThingStructDocumentRepository = .appLive) {
        // tint 偏好是 UI 级偏好，不属于 document。
        tintPreset = ThingStructTintPreference.load()
        self.documentRepository = documentRepository
    }

    // MARK: Bootstrap

    func loadIfNeeded() {
        // SwiftUI 视图可能多次出现/重建，这里确保真正的加载只做一次。
        guard !isLoaded else { return }
        bootstrapDocument()
    }

    func bootstrapDocument() {
        do {
            // 启动时优先从磁盘读取；如果是首次启动，就创建 sample data。
            if let loaded = try documentRepository.load() {
                document = loaded
            } else {
                document = try SampleDataFactory.seededDocument(referenceDay: .today())
                try documentRepository.save(document)
            }

            isLoaded = true
            dismissError()
            // 加载完后立即保证当前选中日期已有实体化 day plan。
            ensureMaterialized(for: selectedDate)
            syncNotifications()
        } catch {
            isLoaded = true
            presentError(error)
        }
    }

    func reload() {
        bootstrapDocument()
    }

    // MARK: Navigation

    // “materialize” 是这个项目里的关键术语：
    // 表示“确保某个日期真的有一份具体 DayPlan 可以读”。
    // 如果当天还没有 plan，但模板规则能推导出一个，就在这里生成。
    func ensureMaterialized(for date: LocalDay) {
        do {
            let materialized = try TemplateEngine.ensureMaterializedDayPlan(
                for: date,
                existingDayPlans: document.dayPlans,
                savedTemplates: document.savedTemplates,
                weekdayRules: document.weekdayRules,
                overrides: document.overrides
            )

            if document.dayPlan(for: date) == nil {
                // 注意：这里不仅更新内存，还会持久化。
                // 因为“自动从模板推导出当天计划”也属于 document 的一部分。
                upsert(dayPlan: materialized)
                try persistDocument()
            }
        } catch {
            presentError(error)
        }
    }

    func selectDate(_ date: LocalDay) {
        // 选日期不是纯 UI 行为，它会触发 day plan 实体化。
        selectedDate = date
        selectedBlockID = nil
        ensureMaterialized(for: date)
    }

    func moveSelectedDate(by dayOffset: Int) {
        selectDate(selectedDate.adding(days: dayOffset))
    }

    func selectBlock(_ blockID: UUID?) {
        selectedBlockID = blockID
    }

    func openLibrary(destination: LibraryDestination? = nil) {
        // 这是显式导航命令，比直接在外部改 `selectedTab`/`path` 更安全。
        selectedTab = .library
        libraryNavigationPath = destination.map { [$0] } ?? []
    }

    func showNow() {
        selectedTab = .now
        selectedBlockID = nil
    }

    func showToday(date: LocalDay? = nil, blockID: UUID? = nil) {
        // 这里体现了“系统路由 -> store 命令 -> UI 状态”的思路。
        // 外部只需要给出“我想展示 today + 某个 block”，
        // 具体如何更新 tab / date / selection 由 store 统一处理。
        selectedTab = .today

        if let date {
            selectDate(date)
        } else {
            selectedBlockID = nil
        }

        selectBlock(blockID)
    }

    func showTemplates() {
        openLibrary(destination: .templates)
    }

    func applyTintPreset(_ preset: AppTintPreset) {
        guard tintPreset != preset else { return }

        tintPreset = preset
        ThingStructTintPreference.save(preset)
        // 改主题色不仅影响 app，自定义 widget/live activity 也要刷新。
        refreshVisualSystemSurfaces()
    }

    func presentError(_ error: Error) {
        // Store 只保存一个“可展示的错误消息”，让根视图统一弹窗。
        lastErrorMessage = error.localizedDescription
    }

    func presentErrorMessage(_ message: String) {
        lastErrorMessage = message
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    // MARK: Queries

    func minuteOfDay(for date: Date) -> Int {
        // 这类小 helper 让 View 层不需要直接碰 DateComponents 细节。
        date.minuteOfDay
    }

    func currentMinuteOnSelectedDate(currentDate: Date = .now) -> Int? {
        // 只有当 selectedDate 正好是“今天”时，当前时间才有意义。
        // 看历史日期时，不应该把 now 的红线/焦点带进去。
        guard selectedDate == LocalDay(date: currentDate) else { return nil }
        return currentDate.minuteOfDay
    }

    func nowScreenModel(at date: Date) throws -> NowScreenModel {
        // Query 方法的标准模式：
        // 1. 先确保 document 已准备好
        // 2. 调用纯 presentation 层做映射
        let localDay = LocalDay(date: date)
        ensureMaterialized(for: localDay)
        return try ThingStructPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: date.minuteOfDay
        )
    }

    func todayScreenModel(currentDate: Date = .now) throws -> TodayScreenModel {
        // 这里没有直接操作 SwiftUI View，而是返回一个“屏幕所需数据包”。
        // 这让页面能保持更薄，也更容易测试。
        ensureMaterialized(for: selectedDate)
        return try ThingStructPresentation.todayScreenModel(
            document: document,
            date: selectedDate,
            selectedBlockID: selectedBlockID,
            currentMinute: currentMinuteOnSelectedDate(currentDate: currentDate)
        )
    }

    func currentActiveBlockID(currentDate: Date = .now) -> UUID? {
        // `currentActiveBlockID` 主要服务于系统入口或页面初始焦点。
        let localDay = LocalDay(date: currentDate)
        guard selectedDate == localDay else { return nil }

        ensureMaterialized(for: selectedDate)
        let plan = document.dayPlan(for: selectedDate) ?? DayPlan(date: selectedDate)

        return try? DayPlanEngine.activeSelection(
            in: plan,
            at: currentDate.minuteOfDay
        ).chain.reversed().first(where: { !$0.isBlankBaseBlock })?.id
    }

    func templatesScreenModel(referenceDay: LocalDay? = nil) throws -> TemplatesScreenModel {
        // 模板页会同时展示“今天”和“明天”的调度情况，所以这里会确保两天都 materialize。
        let resolvedReferenceDay = referenceDay ?? LocalDay.today()
        ensureMaterialized(for: resolvedReferenceDay)
        ensureMaterialized(for: resolvedReferenceDay.adding(days: 1))
        return try ThingStructPresentation.templatesScreenModel(
            document: document,
            referenceDay: resolvedReferenceDay
        )
    }

    var selectedBlockDetail: BlockDetailModel? {
        // 这是“派生状态”，不是独立存储。
        // 好处是：源数据始终只有 document + selectedDate + selectedBlockID。
        guard isLoaded, let selectedBlockID else {
            return nil
        }

        return try? blockDetailModel(on: selectedDate, blockID: selectedBlockID)
    }

    func blockDetailModel(on date: LocalDay, blockID: UUID) throws -> BlockDetailModel? {
        // 这里复用了 today 的 presentation 结果，而不是再手写一遍 block detail 映射。
        let todayModel = try ThingStructPresentation.todayScreenModel(
            document: document,
            date: date,
            selectedBlockID: blockID,
            currentMinute: nil
        )
        return todayModel.selectedBlock
    }

    var savedTemplates: [SavedDayTemplate] {
        document.savedTemplates
    }

    func savedTemplate(id: UUID) -> SavedDayTemplate? {
        document.savedTemplates.first(where: { $0.id == id })
    }

    func assignedTemplateID(for weekday: Weekday) -> UUID? {
        document.weekdayRules.first(where: { $0.weekday == weekday })?.savedTemplateID
    }

    func overrideTemplateID(for date: LocalDay) -> UUID? {
        document.overrides.first(where: { $0.date == date })?.savedTemplateID
    }

    var tomorrowOverrideTemplateID: UUID? {
        overrideTemplateID(for: LocalDay.today().adding(days: 1))
    }

    func persistedBlock(on date: LocalDay, blockID: UUID) -> TimeBlock? {
        // “persistedBlock” 和 `BlockDetailModel` 的区别：
        // - 前者是 document 里真实存储的业务对象
        // - 后者是给 UI 用的展示模型
        document.dayPlan(for: date)?.blocks.first(where: { $0.id == blockID })
    }

    func exportTodayBlocksYAML(today: LocalDay = .today()) throws -> String {
        try ThingStructPortableDayBlocks.exportYAML(from: materializedDayPlan(on: today))
    }

    func previewTodayBlocksImport(_ yaml: String) throws -> PortableDayBlocksSummary {
        try ThingStructPortableDayBlocks.summary(fromYAML: yaml)
    }

    func importTodayBlocksYAML(_ yaml: String, today: LocalDay = .today()) throws {
        // 导入不是“增量 merge”，而是按项目定义转换成新的 DayPlan，然后提交。
        let existingPlan = try materializedDayPlan(on: today)
        let importedPlan = try ThingStructPortableDayBlocks.dayPlanForImport(
            fromYAML: yaml,
            on: today,
            dayPlanID: existingPlan.id,
            lastGeneratedAt: existingPlan.lastGeneratedAt
        )

        if selectedDate == today {
            selectedBlockID = nil
        }

        try commit(dayPlan: importedPlan)
    }

    // MARK: Commands

    func toggleTask(on date: LocalDay, blockID: UUID, taskID: UUID) {
        // 这种“读 plan -> 改一处 -> 提交”的写法，是 store 里最常见的命令模式。
        mutateDayPlan(for: date) { plan in
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else { return }
            guard let taskIndex = plan.blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

            plan.blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
            plan.blocks[blockIndex].tasks[taskIndex].completedAt = plan.blocks[blockIndex].tasks[taskIndex].isCompleted ? Date() : nil
        }
    }

    func startCurrentBlockLiveActivity(referenceDate: Date = .now) {
        // 这里用 `Task` 启动异步工作，而不是阻塞主线程等待系统 API 返回。
        Task {
            guard #available(iOS 16.1, *) else { return }
            do {
                _ = try await ThingStructCurrentBlockLiveActivityController.start(
                    using: .appLive,
                    at: referenceDate
                )
            } catch {
                presentError(error)
            }
        }
    }

    func endCurrentBlockLiveActivity() {
        Task {
            guard #available(iOS 16.1, *) else { return }
            await ThingStructCurrentBlockLiveActivityController.endAll()
        }
    }

    func syncCurrentBlockLiveActivity(referenceDate: Date = .now) {
        // “sync” 比 “start” 更适合常态刷新：
        // 如果活动已存在就更新，不存在时按规则新建，不需要时结束。
        Task {
            guard #available(iOS 16.1, *) else { return }
            do {
                _ = try await ThingStructCurrentBlockLiveActivityController.sync(
                    using: .appLive,
                    at: referenceDate
                )
            } catch {
                presentError(error)
            }
        }
    }

    func saveBlockDraft(_ draft: BlockDraft, for date: LocalDay) throws -> UUID {
        // 这是编辑器保存的核心入口。
        // `BlockDraft` 是 UI 编辑态，真正落库之前要转回 `TimeBlock`。
        ensureMaterialized(for: date)
        guard var plan = document.dayPlan(for: date) else {
            throw ThingStructCoreError.missingDayPlanForDate(date)
        }

        let savedBlockID: UUID

        switch draft.mode {
        case .createBase:
            // 创建底层 block：没有 parent。
            let block = draft.makeBlock(dayPlanID: plan.id)
            savedBlockID = block.id
            plan.blocks.append(block)

        case let .createOverlay(parentBlockID, layerIndex):
            // 创建 overlay：需要挂到父 block 下，并设置正确层级。
            var block = draft.makeBlock(dayPlanID: plan.id)
            block.parentBlockID = parentBlockID
            block.layerIndex = layerIndex
            savedBlockID = block.id
            plan.blocks.append(block)

        case let .edit(blockID):
            // 编辑时保留 identity（id/parent/layer），只替换可编辑内容。
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else {
                throw ThingStructCoreError.missingBlock(blockID)
            }

            let existing = plan.blocks[blockIndex]
            guard !existing.isBlankBaseBlock else {
                throw ThingStructCoreError.missingBlock(existing.id)
            }

            var updated = draft.makeBlock(dayPlanID: plan.id)
            updated.id = existing.id
            updated.parentBlockID = existing.parentBlockID
            updated.layerIndex = existing.layerIndex
            updated.isCancelled = existing.isCancelled
            plan.blocks[blockIndex] = updated
            savedBlockID = existing.id
        }

        // 一旦用户显式保存，就标记为“有用户编辑”，后续 regeneration 会受影响。
        plan.hasUserEdits = true
        let resolved = try DayPlanEngine.resolved(plan)
        upsert(dayPlan: resolved)
        try persistDocument()
        return savedBlockID
    }

    func cancelBlock(on date: LocalDay, blockID: UUID) {
        do {
            // 注意这个 cancel 不是简单 bool toggle，而是一个结构重写操作。
            var collapsed = try DayPlanEngine.cancelBlock(blockID, in: materializedDayPlan(on: date))
            collapsed.hasUserEdits = true
            if selectedBlockID == blockID {
                selectedBlockID = nil
            }
            try commit(dayPlan: collapsed)
        } catch {
            presentError(error)
        }
    }

    func resizeBounds(on date: LocalDay, blockID: UUID) -> BlockResizeBounds? {
        // UI 手势层先问“合法区间”再拖动，比拖完了再报错更友好。
        ensureMaterialized(for: date)
        guard let plan = document.dayPlan(for: date) else {
            return nil
        }

        return try? DayPlanEngine.resizeBounds(for: blockID, in: plan)
    }

    func resizeBlockEnd(on date: LocalDay, blockID: UUID, proposedEndMinuteOfDay: Int) {
        do {
            // 视图层只提供“用户拖到了哪个分钟”，真正是否合法由 engine 判断。
            var resized = try DayPlanEngine.resizeBlockEnd(
                blockID,
                in: materializedDayPlan(on: date),
                proposedEndMinuteOfDay: proposedEndMinuteOfDay
            )
            resized.hasUserEdits = true
            try commit(dayPlan: resized)
        } catch {
            presentError(error)
        }
    }

    func resizeBlockStart(on date: LocalDay, blockID: UUID, proposedStartMinuteOfDay: Int) {
        do {
            var resized = try DayPlanEngine.resizeBlockStart(
                blockID,
                in: materializedDayPlan(on: date),
                proposedStartMinuteOfDay: proposedStartMinuteOfDay
            )
            resized.hasUserEdits = true
            try commit(dayPlan: resized)
        } catch {
            presentError(error)
        }
    }

    func saveSuggestedTemplate(from sourceDate: LocalDay, title: String) {
        do {
            // 候选模板不是长期持久化对象；用户保存后才会转成 `SavedDayTemplate`。
            let suggested = try TemplateEngine.suggestedTemplates(
                referenceDay: LocalDay.today(),
                from: document.dayPlans
            )
            guard let template = suggested.first(where: { $0.sourceDate == sourceDate }) else { return }
            let saved = TemplateEngine.saveSuggestedTemplate(template, title: title)
            document.savedTemplates.append(saved)
            try persistDocument()
        } catch {
            presentError(error)
        }
    }

    func assignWeekday(_ weekday: Weekday, to templateID: UUID?) {
        // 这里采用“先删旧值，再写新值”的方式维持 weekday -> template 的 1:1 映射。
        document.weekdayRules.removeAll { $0.weekday == weekday }
        if let templateID {
            document.weekdayRules.append(.init(weekday: weekday, savedTemplateID: templateID))
        }

        do {
            try persistDocument()
        } catch {
            presentError(error)
        }
    }

    func setOverride(templateID: UUID?, for date: LocalDay) {
        // override 的优先级高于 weekday 规则，所以单独存一张表。
        document.overrides.removeAll { $0.date == date }
        if let templateID {
            document.overrides.append(.init(date: date, savedTemplateID: templateID))
        }

        do {
            try persistDocument()
        } catch {
            presentError(error)
        }
    }

    func setTomorrowOverride(templateID: UUID?) {
        setOverride(templateID: templateID, for: LocalDay.today().adding(days: 1))
    }

    func assignedWeekdays(for templateID: UUID) -> Set<Weekday> {
        Set(
            document.weekdayRules
                .filter { $0.savedTemplateID == templateID }
                .map(\.weekday)
        )
    }

    func occupiedWeekdays(excluding templateID: UUID) -> Set<Weekday> {
        Set(
            document.weekdayRules
                .filter { $0.savedTemplateID != templateID }
                .map(\.weekday)
        )
    }

    func saveEditedTemplate(
        _ templateID: UUID,
        title: String,
        blocks: [BlockTemplate],
        assignedWeekdays: Set<Weekday>
    ) throws {
        // 模板编辑逻辑继续委托给 TemplateEngine，Store 只负责接 UI 输入与持久化。
        document = try TemplateEngine.updateSavedTemplate(
            templateID,
            title: title,
            blocks: blocks,
            assignedWeekdays: assignedWeekdays,
            in: document
        )
        try persistDocument()
    }

    func deleteSavedTemplate(_ templateID: UUID) {
        document = TemplateEngine.deleteSavedTemplate(templateID, from: document)

        do {
            try persistDocument()
        } catch {
            presentError(error)
        }
    }

    func regenerateFutureDayPlan(for date: LocalDay) {
        do {
            // regenerate 只允许未来日期，且会受 `hasUserEdits` / 完成任务等条件限制。
            let regenerated = try TemplateEngine.regenerateFutureDayPlan(
                for: date,
                today: LocalDay.today(),
                existingDayPlans: document.dayPlans,
                savedTemplates: document.savedTemplates,
                weekdayRules: document.weekdayRules,
                overrides: document.overrides
            )
            if selectedDate == date {
                selectedBlockID = nil
            }
            try commit(dayPlan: regenerated)
        } catch {
            presentError(error)
        }
    }

    func rebuildDayPlan(for date: LocalDay, generatedAt: Date = .now) {
        do {
            // rebuild 比 regenerate 更激进，允许用当前模板体系重建指定日期的 plan。
            let rebuilt = try TemplateEngine.rebuildDayPlan(
                for: date,
                existingDayPlans: document.dayPlans,
                savedTemplates: document.savedTemplates,
                weekdayRules: document.weekdayRules,
                overrides: document.overrides,
                generatedAt: generatedAt
            )
            if selectedDate == date {
                selectedBlockID = nil
            }
            try commit(dayPlan: rebuilt)
        } catch {
            presentError(error)
        }
    }

    private func mutateDayPlan(for date: LocalDay, mutation: (inout DayPlan) -> Void) {
        do {
            var plan = try materializedDayPlan(on: date)

            mutation(&plan)
            // 统一把“通过 store 命令产生的修改”记为用户编辑。
            plan.hasUserEdits = true
            try commit(dayPlan: plan)
        } catch {
            presentError(error)
        }
    }

    private func materializedDayPlan(on date: LocalDay) throws -> DayPlan {
        // 这个 helper 把“应该存在”的软约定提升为“若不存在就抛错”的硬约束。
        ensureMaterialized(for: date)
        guard let plan = document.dayPlan(for: date) else {
            throw ThingStructCoreError.missingDayPlanForDate(date)
        }
        return plan
    }

    private func commit(dayPlan: DayPlan) throws {
        // 所有写操作最终都应该收敛到这里，避免出现多个不同的持久化路径。
        upsert(dayPlan: dayPlan)
        try persistDocument()
    }

    private func upsert(dayPlan: DayPlan) {
        // `upsert = update or insert`，是数据库/存储层常见术语。
        if let index = document.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            document.dayPlans[index] = dayPlan
        } else {
            document.dayPlans.append(dayPlan)
            document.dayPlans.sort { $0.date < $1.date }
        }
    }

    private func persistDocument() throws {
        // 文档写盘后，统一走一个“文档已变更”钩子，刷新所有系统表面。
        try documentRepository.save(document)
        documentDidChange()
    }

    // MARK: Persistence & System Sync

    private func documentDidChange() {
        // 为什么拆成一个单独钩子？
        // 因为以后只要是“写文档成功”，都应该触发同一套副作用。
        refreshVisualSystemSurfaces()
        syncNotifications()
    }

    private func refreshVisualSystemSurfaces() {
        // Widget / Live Activity 都是 document 的外部投影，需要和主 app 保持一致。
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        syncCurrentBlockLiveActivity()
    }

    private func syncNotifications() {
        // 通知计划和当前 document 强相关，所以每次文档变动都重新对齐。
        ThingStructNotificationCoordinator.shared.sync(with: document)
    }
}
