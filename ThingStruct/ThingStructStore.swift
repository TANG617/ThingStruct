import Foundation
import Observation
import WidgetKit

// `RootTab` is a small domain enum for the shell navigation state.
// Keeping it typed is safer than passing raw strings or integers around.
enum RootTab: Hashable {
    case now
    case today
    case library
}

// `ThingStructStore` is the app's UI-facing state container.
//
// A helpful mental model for a C++ developer:
// - `ThingStructDocument` is the durable domain data.
// - `ThingStructStore` is the controller/view-model that owns the document,
//   exposes screen-specific queries, and executes user commands.
// - SwiftUI views stay deliberately thin and call into this store.
//
// `@MainActor` means all accesses happen on the main UI thread.
// `@Observable` lets SwiftUI automatically track field reads and refresh views
// when those fields change.
@MainActor
@Observable
final class ThingStructStore {
    // The full persisted app state. Almost everything else is derived from this.
    var document: ThingStructDocument = .init()
    var tintPreset: AppTintPreset

    // UI selection state that is global enough to outlive a single screen render.
    var selectedTab: RootTab = .now {
        didSet {
            // Switching tabs invalidates any selected block detail sheet.
            guard oldValue != selectedTab else { return }
            selectedBlockID = nil
        }
    }
    // The Library tab owns nested destinations such as Templates and Import/Export.
    var libraryNavigationPath: [LibraryDestination] = []
    var selectedDate: LocalDay = LocalDay.today()
    var selectedBlockID: UUID?
    var isLoaded = false
    private(set) var lastErrorMessage: String?

    // Small persistence dependency. This keeps file I/O out of the store's core logic.
    private let documentStore: ThingStructDocumentStore

    init(documentStore: ThingStructDocumentStore = .live) {
        tintPreset = ThingStructTintPreference.load()
        self.documentStore = documentStore
    }

    func loadIfNeeded() {
        // SwiftUI may rebuild views many times; we only want to bootstrap once.
        guard !isLoaded else { return }
        bootstrapDocument()
    }

    // Loads the document from disk or creates a seeded one on first launch.
    // The older legacy migration path has been removed, so the startup path is now simple.
    func bootstrapDocument() {
        do {
            if let loaded = try documentStore.load() {
                document = loaded
            } else {
                document = try SampleDataFactory.seededDocument(referenceDay: .today())
                try documentStore.save(document)
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

    // "Materializing" means ensuring a concrete `DayPlan` exists for a date,
    // either because it was already stored or because it can be generated from templates.
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

    // Date selection is a UI-level concern, but it has a domain side effect:
    // we guarantee the selected date has a day plan before the screen reads it.
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

    func applyTintPreset(_ preset: AppTintPreset) {
        guard tintPreset != preset else { return }

        tintPreset = preset
        ThingStructTintPreference.save(preset)
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        syncCurrentBlockLiveActivity()
    }

    // Error routing is centralized so screens can stay focused on layout.
    func presentError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    func presentErrorMessage(_ message: String) {
        lastErrorMessage = message
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    func minuteOfDay(for date: Date) -> Int {
        date.minuteOfDay
    }

    // Many screens care about "now", but only when the selected date is actually today.
    func currentMinuteOnSelectedDate(currentDate: Date = .now) -> Int? {
        guard selectedDate == LocalDay(date: currentDate) else { return nil }
        return currentDate.minuteOfDay
    }

    // Query helpers below convert the durable document into screen-specific models.
    // This keeps transformation logic out of SwiftUI view code.
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

    // `selectedBlockDetail` is intentionally derived instead of cached.
    // The source of truth remains `document + selectedDate + selectedBlockID`.
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

    var tomorrowOverrideTemplateID: UUID? {
        let tomorrow = LocalDay.today().adding(days: 1)
        return document.overrides.first(where: { $0.date == tomorrow })?.savedTemplateID
    }

    // This is a raw persisted-block lookup. Unlike presentation models, it returns
    // the domain object stored in the selected day plan.
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

    // Commands below mutate the document. In a more classic MVC/MVVM vocabulary,
    // these are the store's "write-side" API.
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

        // Store commands often follow this pattern:
        // 1. load the source-of-truth value
        // 2. mutate a local copy
        // 3. validate/resolve it through an engine
        // 4. persist the whole updated document
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
            // Editing preserves structural identity (`id`, parent, layer) and only replaces
            // the editable content/timing payload built from the draft.
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
            // Cancellation is a structural engine operation, not just a boolean flag flip.
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
            // The store delegates all legality checks to `DayPlanEngine`; the view only
            // sends the user's proposed minute.
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

    func setTomorrowOverride(templateID: UUID?) {
        let tomorrow = LocalDay.today().adding(days: 1)
        document.overrides.removeAll { $0.date == tomorrow }
        if let templateID {
            document.overrides.append(.init(date: tomorrow, savedTemplateID: templateID))
        }

        do {
            try persistDocument()
        } catch {
            presentError(error)
        }
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

    // Shared mutation helper for "read day plan -> change it -> mark user edits -> persist".
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
        // This helper turns the soft precondition "that day plan should exist"
        // into a hard precondition "throw if it still does not".
        ensureMaterialized(for: date)
        guard let plan = document.dayPlan(for: date) else {
            throw ThingStructCoreError.missingDayPlanForDate(date)
        }
        return plan
    }

    private func commit(dayPlan: DayPlan) throws {
        // Centralizing commit keeps "replace in document + persist to disk" consistent.
        upsert(dayPlan: dayPlan)
        try persistDocument()
    }

    private func upsert(dayPlan: DayPlan) {
        // `upsert` means "update if present, insert otherwise".
        if let index = document.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            document.dayPlans[index] = dayPlan
        } else {
            document.dayPlans.append(dayPlan)
            document.dayPlans.sort { $0.date < $1.date }
        }
    }

    private func persistDocument() throws {
        // The store itself never writes files directly; persistence is delegated so it can
        // be swapped for previews/tests.
        try documentStore.save(document)
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        syncCurrentBlockLiveActivity()
        syncNotifications()
    }

    private func syncNotifications() {
        ThingStructNotificationCoordinator.shared.sync(with: document)
    }
}
