import Foundation
import Observation
import WidgetKit

enum RootTab: Hashable {
    case now
    case today
    case library
}

@MainActor
@Observable
final class ThingStructStore {
    // MARK: State

    var document: ThingStructDocument = .init()
    var tintPreset: AppTintPreset

    var selectedTab: RootTab = .now {
        didSet {
            guard oldValue != selectedTab else { return }
            selectedBlockID = nil
        }
    }
    var libraryNavigationPath: [LibraryDestination] = []
    var selectedDate: LocalDay = LocalDay.today()
    var selectedBlockID: UUID?
    var isLoaded = false
    private(set) var lastErrorMessage: String?

    private let documentRepository: ThingStructDocumentRepository

    init(documentRepository: ThingStructDocumentRepository = .appLive) {
        tintPreset = ThingStructTintPreference.load()
        self.documentRepository = documentRepository
    }

    // MARK: Bootstrap

    func loadIfNeeded() {
        guard !isLoaded else { return }
        bootstrapDocument()
    }

    func bootstrapDocument() {
        do {
            if let loaded = try documentRepository.load() {
                document = loaded
            } else {
                document = try SampleDataFactory.seededDocument(referenceDay: .today())
                try documentRepository.save(document)
            }

            isLoaded = true
            dismissError()
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
                upsert(dayPlan: materialized)
                try persistDocument()
            }
        } catch {
            presentError(error)
        }
    }

    func selectDate(_ date: LocalDay) {
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
        selectedTab = .library
        libraryNavigationPath = destination.map { [$0] } ?? []
    }

    func showNow() {
        selectedTab = .now
        selectedBlockID = nil
    }

    func showToday(date: LocalDay? = nil, blockID: UUID? = nil) {
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
        refreshVisualSystemSurfaces()
    }

    func presentError(_ error: Error) {
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
        date.minuteOfDay
    }

    func currentMinuteOnSelectedDate(currentDate: Date = .now) -> Int? {
        guard selectedDate == LocalDay(date: currentDate) else { return nil }
        return currentDate.minuteOfDay
    }

    func nowScreenModel(at date: Date) throws -> NowScreenModel {
        let localDay = LocalDay(date: date)
        ensureMaterialized(for: localDay)
        return try ThingStructPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: date.minuteOfDay
        )
    }

    func todayScreenModel(currentDate: Date = .now) throws -> TodayScreenModel {
        ensureMaterialized(for: selectedDate)
        return try ThingStructPresentation.todayScreenModel(
            document: document,
            date: selectedDate,
            selectedBlockID: selectedBlockID,
            currentMinute: currentMinuteOnSelectedDate(currentDate: currentDate)
        )
    }

    func currentActiveBlockID(currentDate: Date = .now) -> UUID? {
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
        let resolvedReferenceDay = referenceDay ?? LocalDay.today()
        ensureMaterialized(for: resolvedReferenceDay)
        ensureMaterialized(for: resolvedReferenceDay.adding(days: 1))
        return try ThingStructPresentation.templatesScreenModel(
            document: document,
            referenceDay: resolvedReferenceDay
        )
    }

    var selectedBlockDetail: BlockDetailModel? {
        guard isLoaded, let selectedBlockID else {
            return nil
        }

        return try? blockDetailModel(on: selectedDate, blockID: selectedBlockID)
    }

    func blockDetailModel(on date: LocalDay, blockID: UUID) throws -> BlockDetailModel? {
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
        document.dayPlan(for: date)?.blocks.first(where: { $0.id == blockID })
    }

    func exportTodayBlocksYAML(today: LocalDay = .today()) throws -> String {
        try ThingStructPortableDayBlocks.exportYAML(from: materializedDayPlan(on: today))
    }

    func previewTodayBlocksImport(_ yaml: String) throws -> PortableDayBlocksSummary {
        try ThingStructPortableDayBlocks.summary(fromYAML: yaml)
    }

    func importTodayBlocksYAML(_ yaml: String, today: LocalDay = .today()) throws {
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
        mutateDayPlan(for: date) { plan in
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else { return }
            guard let taskIndex = plan.blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

            plan.blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
            plan.blocks[blockIndex].tasks[taskIndex].completedAt = plan.blocks[blockIndex].tasks[taskIndex].isCompleted ? Date() : nil
        }
    }

    func startCurrentBlockLiveActivity(referenceDate: Date = .now) {
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
        ensureMaterialized(for: date)
        guard var plan = document.dayPlan(for: date) else {
            throw ThingStructCoreError.missingDayPlanForDate(date)
        }

        let savedBlockID: UUID

        switch draft.mode {
        case .createBase:
            let block = draft.makeBlock(dayPlanID: plan.id)
            savedBlockID = block.id
            plan.blocks.append(block)

        case let .createOverlay(parentBlockID, layerIndex):
            var block = draft.makeBlock(dayPlanID: plan.id)
            block.parentBlockID = parentBlockID
            block.layerIndex = layerIndex
            savedBlockID = block.id
            plan.blocks.append(block)

        case let .edit(blockID):
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

        plan.hasUserEdits = true
        let resolved = try DayPlanEngine.resolved(plan)
        upsert(dayPlan: resolved)
        try persistDocument()
        return savedBlockID
    }

    func cancelBlock(on date: LocalDay, blockID: UUID) {
        do {
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
        ensureMaterialized(for: date)
        guard let plan = document.dayPlan(for: date) else {
            return nil
        }

        return try? DayPlanEngine.resizeBounds(for: blockID, in: plan)
    }

    func resizeBlockEnd(on date: LocalDay, blockID: UUID, proposedEndMinuteOfDay: Int) {
        do {
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
            plan.hasUserEdits = true
            try commit(dayPlan: plan)
        } catch {
            presentError(error)
        }
    }

    private func materializedDayPlan(on date: LocalDay) throws -> DayPlan {
        ensureMaterialized(for: date)
        guard let plan = document.dayPlan(for: date) else {
            throw ThingStructCoreError.missingDayPlanForDate(date)
        }
        return plan
    }

    private func commit(dayPlan: DayPlan) throws {
        upsert(dayPlan: dayPlan)
        try persistDocument()
    }

    private func upsert(dayPlan: DayPlan) {
        if let index = document.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            document.dayPlans[index] = dayPlan
        } else {
            document.dayPlans.append(dayPlan)
            document.dayPlans.sort { $0.date < $1.date }
        }
    }

    private func persistDocument() throws {
        try documentRepository.save(document)
        documentDidChange()
    }

    // MARK: Persistence & System Sync

    private func documentDidChange() {
        refreshVisualSystemSurfaces()
        syncNotifications()
    }

    private func refreshVisualSystemSurfaces() {
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        syncCurrentBlockLiveActivity()
    }

    private func syncNotifications() {
        ThingStructNotificationCoordinator.shared.sync(with: document)
    }
}
