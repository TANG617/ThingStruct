import Foundation

// `PreviewSupport` 是 SwiftUI 预览专用的样本数据工厂。
// 它解决两个常见问题：
// 1. 预览想直接看到“像真实 app 一样”的画面，而不是一堆空白
// 2. 正式代码不应该混进大量 mock/演示数据构造逻辑
// 对 C++ 开发者可以理解成：专门给 UI 调试准备的一组 fixture / test data builder。
@MainActor
enum PreviewSupport {
    static var referenceDay: LocalDay {
        LocalDay.today()
    }

    static var generatedAt: Date {
        Date(timeIntervalSince1970: 1_710_000_000)
    }

    static func seededDocument(on referenceDay: LocalDay? = nil) -> ThingStructDocument {
        // `try!` 在生产代码里通常要谨慎，但在预览辅助里是合理的：
        // 如果样本数据都构不出来，预览本身就没有继续展示的意义。
        let day = referenceDay ?? self.referenceDay
        return try! SampleDataFactory.seededDocument(referenceDay: day, generatedAt: generatedAt)
    }

    static func store(
        tab: RootTab = .now,
        libraryNavigationPath: [LibraryDestination] = [],
        tintPreset: AppTintPreset = .ocean,
        selectedDate: LocalDay? = nil,
        loaded: Bool = true,
        document: ThingStructDocument? = nil,
        selectedBlockID: UUID? = nil,
        lastErrorMessage: String? = nil
    ) -> ThingStructStore {
        let day = selectedDate ?? referenceDay
        // 每个预览实例都拿一份独立的临时文件地址。
        // 这样多个 preview 不会互相污染，也不会误碰真实 app 文档。
        let documentRepository = ThingStructDocumentRepository(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "ThingStructPreview")
                .appending(path: "\(UUID().uuidString).json")
        )
        let store = ThingStructStore(documentRepository: documentRepository)
        store.selectedTab = tab
        store.libraryNavigationPath = libraryNavigationPath
        store.tintPreset = tintPreset
        store.selectedDate = day

        if loaded {
            store.document = document ?? seededDocument(on: day)
            store.isLoaded = true
            store.ensureMaterialized(for: day)
            store.selectedBlockID = selectedBlockID
        }

        if let lastErrorMessage {
            store.presentErrorMessage(lastErrorMessage)
        }

        return store
    }

    static func nowModel(
        document: ThingStructDocument? = nil,
        minuteOfDay: Int = 9 * 60 + 30
    ) -> NowScreenModel {
        // 这里直接调用 presentation 层，而不是先造一个完整 store。
        // 好处是：
        // - 预览更轻
        // - 更适合单独验证“某个 View 的布局是否正确”
        let day = referenceDay
        return try! ThingStructPresentation.nowScreenModel(
            document: document ?? seededDocument(on: day),
            date: day,
            minuteOfDay: minuteOfDay
        )
    }

    static func todayModel(
        document: ThingStructDocument? = nil,
        selectedBlockID: UUID? = nil,
        currentMinute: Int? = 9 * 60 + 30
    ) -> TodayScreenModel {
        let day = referenceDay
        return try! ThingStructPresentation.todayScreenModel(
            document: document ?? seededDocument(on: day),
            date: day,
            selectedBlockID: selectedBlockID,
            currentMinute: currentMinute
        )
    }

    static func templatesModel(document: ThingStructDocument? = nil) -> TemplatesScreenModel {
        let day = referenceDay
        return try! ThingStructPresentation.templatesScreenModel(
            document: document ?? seededDocument(on: day),
            referenceDay: day
        )
    }

    static func savedTemplate(document: ThingStructDocument? = nil) -> SavedDayTemplate {
        let resolvedDocument = document ?? seededDocument()
        return resolvedDocument.savedTemplates.last!
    }

    static func emptyTemplate() -> SavedDayTemplate {
        SavedDayTemplate(
            title: "Empty Template",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
    }

    static func selectedBlockDetailModel() -> BlockDetailModel {
        // 预览经常需要一个“当前选中的 block 详情”来驱动编辑器或详情页。
        todayModel().selectedBlock!
    }

    static func persistedSelectedBlock() -> TimeBlock {
        // 这里拿的是 document 里真正持久化的 `TimeBlock`，而不是 screen model。
        // 学习时要特别注意这两者的区别：前者是业务真值，后者是给界面展示的投影。
        let document = seededDocument()
        let detail = selectedBlockDetailModel()
        return document.dayPlan(for: referenceDay)!.blocks.first(where: { $0.id == detail.id })!
    }

    static func sampleBlockDraftBase() -> BlockDraft {
        var draft = BlockDraft.base(startMinute: 8 * 60, endMinute: 10 * 60 + 30)
        draft.title = "Morning Focus"
        draft.note = "Protect this block for deep work."
        draft.tasks = [
            TaskItem(title: "Plan the session"),
            TaskItem(title: "Write the draft", order: 1)
        ]
        return draft
    }

    static func sampleBlockDraftOverlay() -> BlockDraft {
        let parent = persistedSelectedBlock()
        // overlay 草稿需要知道父块当前已经解析出来的时间范围，
        // 因为它的相对时间是基于父块算出来的。
        var draft = BlockDraft.overlay(
            parentBlockID: parent.id,
            layerIndex: 2,
            parentResolvedRange: parent.resolvedStartMinuteOfDay.flatMap { start in
                parent.resolvedEndMinuteOfDay.map { end in (start, end) }
            }
        )
        draft.title = "Sprint"
        draft.note = "Short, intense burst inside the parent block."
        draft.relativeOffsetMinutes = 15
        draft.relativeDurationMinutes = 45
        draft.tasks = [
            TaskItem(title: "Review notes"),
            TaskItem(title: "Ship one small win", order: 1)
        ]
        return draft
    }

    static func sampleBlockDraftEdit() -> BlockDraft {
        // “编辑已有 block” 和 “新建 block” 的草稿来源不同：
        // 编辑时要把原始 block 与详情模型一起喂给 `BlockDraft.editing(...)`。
        let block = persistedSelectedBlock()
        return BlockDraft.editing(
            detail: selectedBlockDetailModel(),
            sourceBlock: block,
            parentResolvedRange: block.parentBlockID.flatMap { parentID in
                let document = seededDocument()
                guard
                    let parent = document.dayPlan(for: referenceDay)?.blocks.first(where: { $0.id == parentID }),
                    let start = parent.resolvedStartMinuteOfDay,
                    let end = parent.resolvedEndMinuteOfDay
                else {
                    return nil
                }
                return (start, end)
            }
        )
    }

    static func sampleTemplateBlock() -> BlockTemplate {
        savedTemplate().blocks.first!
    }

    static func sampleOverlayTemplateBlock() -> BlockTemplate {
        // 这个样本专门用于展示模板里的相对块。
        let baseID = UUID()
        return BlockTemplate(
            parentTemplateBlockID: baseID,
            layerIndex: 1,
            title: "Overlay Sprint",
            note: "Relative block preview",
            taskBlueprints: [
                TaskBlueprint(title: "Prepare"),
                TaskBlueprint(title: "Execute", order: 1)
            ],
            timing: .relative(startOffsetMinutes: 15, requestedDurationMinutes: 60)
        )
    }
}
