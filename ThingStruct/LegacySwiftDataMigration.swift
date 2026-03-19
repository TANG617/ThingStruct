import Foundation
import SwiftData

struct ThingStructLegacyMigration {
    let loadDocument: @MainActor () throws -> ThingStructDocument?

    @MainActor
    func load() throws -> ThingStructDocument? {
        try loadDocument()
    }

    @MainActor
    static var live: ThingStructLegacyMigration {
        ThingStructLegacyMigration(loadDocument: {
            try LegacySwiftDataDocumentImporter.importDocument()
        })
    }
}

@MainActor
private enum LegacySwiftDataDocumentImporter {
    static func importDocument() throws -> ThingStructDocument? {
        let schema = Schema([
            StateItem.self,
            ChecklistItem.self,
            StateTemplate.self,
            RoutineItem.self,
            RoutineTemplate.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let states = try context.fetch(
            FetchDescriptor<StateItem>(
                sortBy: [
                    SortDescriptor(\.date),
                    SortDescriptor(\.order),
                    SortDescriptor(\.title)
                ]
            )
        )
        let stateTemplates = try context.fetch(
            FetchDescriptor<StateTemplate>(
                sortBy: [SortDescriptor(\.title)]
            )
        )
        let routineTemplates = try context.fetch(
            FetchDescriptor<RoutineTemplate>(
                sortBy: [SortDescriptor(\.title)]
            )
        )

        guard !states.isEmpty || !stateTemplates.isEmpty || !routineTemplates.isEmpty else {
            return nil
        }

        return try LegacyImportEngine.importDocument(
            states: states.map(snapshot(from:)),
            stateTemplates: stateTemplates.map(snapshot(from:)),
            routineTemplates: routineTemplates.map(snapshot(from:))
        )
    }

    private static func snapshot(from item: ChecklistItem) -> LegacyChecklistSnapshot {
        LegacyChecklistSnapshot(
            id: item.id,
            title: item.title,
            order: item.order,
            isCompleted: item.isCompleted,
            completedAt: item.completedDate
        )
    }

    private static func snapshot(from state: StateItem) -> LegacyStateSnapshot {
        LegacyStateSnapshot(
            id: state.id,
            title: state.title,
            order: state.order,
            date: LocalDay(date: state.date),
            isCompleted: state.isCompleted,
            checklistItems: state.checklistItems.map(snapshot(from:))
        )
    }

    private static func snapshot(from template: StateTemplate) -> LegacyStateTemplateSnapshot {
        LegacyStateTemplateSnapshot(
            id: template.id,
            title: template.title,
            checklistItems: template.checklistItems.map(snapshot(from:))
        )
    }

    private static func snapshot(from template: RoutineTemplate) -> LegacyRoutineTemplateSnapshot {
        LegacyRoutineTemplateSnapshot(
            id: template.id,
            title: template.title,
            repeatDays: template.repeatDays,
            stateTemplates: template.stateTemplates.map(snapshot(from:))
        )
    }
}
