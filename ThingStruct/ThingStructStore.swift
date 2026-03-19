import Foundation
import Observation

enum RootTab: Hashable {
    case now
    case today
    case templates
}

@MainActor
@Observable
final class ThingStructStore {
    var document: ThingStructDocument = .init()
    var selectedTab: RootTab = .now
    var selectedDate: LocalDay = LocalDay.today()
    var selectedBlockID: UUID?
    var isLoaded = false
    var lastErrorMessage: String?

    private let persistence: ThingStructDocumentPersistence
    private let legacyMigration: ThingStructLegacyMigration

    init(
        persistence: ThingStructDocumentPersistence? = nil,
        legacyMigration: ThingStructLegacyMigration? = nil
    ) {
        self.persistence = persistence ?? ThingStructDocumentPersistence.live
        self.legacyMigration = legacyMigration ?? ThingStructLegacyMigration.live
    }

    func loadIfNeeded() {
        guard !isLoaded else { return }
        reload()
    }

    func reload() {
        do {
            if let loaded = try persistence.load() {
                document = loaded
            } else if let migrated = try legacyMigration.load() {
                document = migrated
                try persistence.save(document)
            } else {
                document = try SampleDataFactory.seededDocument(referenceDay: .today())
                try persistence.save(document)
            }

            isLoaded = true
            lastErrorMessage = nil
            ensureMaterialized(for: selectedDate)
        } catch {
            isLoaded = true
            lastErrorMessage = error.localizedDescription
        }
    }

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
                try persist()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func selectDate(_ date: LocalDay) {
        selectedDate = date
        selectedBlockID = nil
        ensureMaterialized(for: date)
    }

    func selectBlock(_ blockID: UUID?) {
        selectedBlockID = blockID
    }

    func minuteOfDay(for date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    func nowScreenModel(at date: Date) throws -> NowScreenModel {
        let localDay = LocalDay(date: date)
        ensureMaterialized(for: localDay)
        return try ThingStructPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: minuteOfDay(for: date)
        )
    }

    func todayScreenModel(currentDate: Date = .now) throws -> TodayScreenModel {
        ensureMaterialized(for: selectedDate)
        let currentMinute = selectedDate == LocalDay(date: currentDate) ? minuteOfDay(for: currentDate) : nil
        return try ThingStructPresentation.todayScreenModel(
            document: document,
            date: selectedDate,
            selectedBlockID: selectedBlockID,
            currentMinute: currentMinute
        )
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

    func blockDetail(for date: LocalDay, blockID: UUID) throws -> BlockDetailModel? {
        let todayModel = try ThingStructPresentation.todayScreenModel(
            document: document,
            date: date,
            selectedBlockID: blockID,
            currentMinute: nil
        )
        return todayModel.selectedBlock
    }

    func persistedBlock(on date: LocalDay, blockID: UUID) -> TimeBlock? {
        document.dayPlan(for: date)?.blocks.first(where: { $0.id == blockID })
    }

    func runtimeBlock(on date: LocalDay, blockID: UUID) -> TimeBlock? {
        let plan = document.dayPlan(for: date) ?? DayPlan(date: date)
        return try? DayPlanEngine.runtimeResolved(plan).blocks.first(where: { $0.id == blockID })
    }

    func toggleTask(on date: LocalDay, blockID: UUID, taskID: UUID) {
        mutateDayPlan(for: date) { plan in
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else { return }
            guard let taskIndex = plan.blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

            plan.blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
            plan.blocks[blockIndex].tasks[taskIndex].completedAt = plan.blocks[blockIndex].tasks[taskIndex].isCompleted ? Date() : nil
        }
    }

    func saveBlockDraft(_ draft: BlockDraft, for date: LocalDay) throws {
        ensureMaterialized(for: date)
        guard var plan = document.dayPlan(for: date) else { return }

        switch draft.mode {
        case .createBase:
            plan.blocks.append(draft.makeBlock(dayPlanID: plan.id))

        case let .createOverlay(parentBlockID, layerIndex):
            var block = draft.makeBlock(dayPlanID: plan.id)
            block.parentBlockID = parentBlockID
            block.layerIndex = layerIndex
            plan.blocks.append(block)

        case let .edit(blockID):
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else {
                return
            }

            let existing = plan.blocks[blockIndex]
            guard !existing.isBlankBaseBlock else { return }

            var updated = draft.makeBlock(dayPlanID: plan.id)
            updated.id = existing.id
            updated.parentBlockID = existing.parentBlockID
            updated.layerIndex = existing.layerIndex
            updated.isCancelled = existing.isCancelled
            plan.blocks[blockIndex] = updated
        }

        plan.hasUserEdits = true
        let resolved = try DayPlanEngine.resolved(plan)
        upsert(dayPlan: resolved)
        try persist()
    }

    func cancelBlock(on date: LocalDay, blockID: UUID) {
        do {
            ensureMaterialized(for: date)
            guard let existingPlan = document.dayPlan(for: date) else { return }
            var collapsed = try DayPlanEngine.cancelBlock(blockID, in: existingPlan)
            collapsed.hasUserEdits = true
            upsert(dayPlan: collapsed)
            if selectedBlockID == blockID {
                selectedBlockID = nil
            }
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
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
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func assignWeekday(_ weekday: Weekday, to templateID: UUID?) {
        document.weekdayRules.removeAll { $0.weekday == weekday }
        if let templateID {
            document.weekdayRules.append(.init(weekday: weekday, savedTemplateID: templateID))
        }

        do {
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setTomorrowOverride(templateID: UUID?) {
        let tomorrow = LocalDay.today().adding(days: 1)
        document.overrides.removeAll { $0.date == tomorrow }
        if let templateID {
            document.overrides.append(.init(date: tomorrow, savedTemplateID: templateID))
        }

        do {
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
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
        try persist()
    }

    func deleteSavedTemplate(_ templateID: UUID) {
        document = TemplateEngine.deleteSavedTemplate(templateID, from: document)

        do {
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
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
            upsert(dayPlan: regenerated)
            if selectedDate == date {
                selectedBlockID = nil
            }
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func mutateDayPlan(for date: LocalDay, mutation: (inout DayPlan) -> Void) {
        ensureMaterialized(for: date)
        guard var plan = document.dayPlan(for: date) else { return }

        mutation(&plan)
        plan.hasUserEdits = true
        upsert(dayPlan: plan)

        do {
            try persist()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func upsert(dayPlan: DayPlan) {
        if let index = document.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            document.dayPlans[index] = dayPlan
        } else {
            document.dayPlans.append(dayPlan)
            document.dayPlans.sort { $0.date < $1.date }
        }
    }

    private func persist() throws {
        try persistence.save(document)
    }
}

struct ThingStructDocumentPersistence {
    let fileURL: URL

    func load() throws -> ThingStructDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ThingStructDocument.self, from: data)
    }

    func save(_ document: ThingStructDocument) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder.pretty.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated static var live: ThingStructDocumentPersistence {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return ThingStructDocumentPersistence(
            fileURL: baseURL.appending(path: "ThingStruct/document.json")
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
