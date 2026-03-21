import Foundation

// SwiftUI previews are much more useful when they can boot realistic app state quickly.
// This helper centralizes preview-only factories so production files do not need to
// contain mock-building code inline.
@MainActor
enum PreviewSupport {
    static var referenceDay: LocalDay {
        LocalDay.today()
    }

    static var generatedAt: Date {
        Date(timeIntervalSince1970: 1_710_000_000)
    }

    static func seededDocument(on referenceDay: LocalDay? = nil) -> ThingStructDocument {
        let day = referenceDay ?? self.referenceDay
        return try! SampleDataFactory.seededDocument(referenceDay: day, generatedAt: generatedAt)
    }

    static func store(
        tab: RootTab = .now,
        selectedDate: LocalDay? = nil,
        loaded: Bool = true,
        document: ThingStructDocument? = nil,
        selectedBlockID: UUID? = nil,
        lastErrorMessage: String? = nil
    ) -> ThingStructStore {
        let day = selectedDate ?? referenceDay
        // Each preview gets its own temporary file URL so previews do not interfere
        // with one another or with the real app document.
        let documentStore = ThingStructDocumentStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "ThingStructPreview")
                .appending(path: "\(UUID().uuidString).json")
        )
        let store = ThingStructStore(documentStore: documentStore)
        store.selectedTab = tab
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
        // These helpers skip the UI store entirely and ask the presentation layer directly.
        // That makes previews good for validating pure view layout.
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
        todayModel().selectedBlock!
    }

    static func blankBlockDetailModel() -> BlockDetailModel {
        let blankBlock = todayModel(document: ThingStructDocument(), currentMinute: nil)
            .blocks
            .first(where: \.isBlank)!

        return BlockDetailModel(
            id: blankBlock.id,
            title: blankBlock.title,
            note: blankBlock.note,
            layerIndex: blankBlock.layerIndex,
            startMinuteOfDay: blankBlock.startMinuteOfDay,
            endMinuteOfDay: blankBlock.endMinuteOfDay,
            isBlank: true,
            tasks: [],
            parentBlockID: blankBlock.parentBlockID,
            parentBlockTitle: nil
        )
    }

    static func persistedSelectedBlock() -> TimeBlock {
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
        let parentID = persistedSelectedBlock().id
        var draft = BlockDraft.overlay(parentBlockID: parentID, layerIndex: 2)
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
        BlockDraft.editing(
            detail: selectedBlockDetailModel(),
            sourceBlock: persistedSelectedBlock()
        )
    }

    static func sampleTemplateBlock() -> BlockTemplate {
        savedTemplate().blocks.first!
    }

    static func sampleOverlayTemplateBlock() -> BlockTemplate {
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
