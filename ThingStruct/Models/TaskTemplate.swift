import Foundation
import SwiftData

@Model
final class TaskTemplate {
    var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade) var checklistItems: [ChecklistItem]
    
    init(title: String) {
        self.id = UUID()
        self.title = title
        self.checklistItems = []
    }
    
    func createTask(for date: Date, order: Int, modelContext: ModelContext) -> Task {
        let task = Task(title: title, date: date, order: order)
        modelContext.insert(task)
        for (index, item) in checklistItems.enumerated() {
            let newItem = ChecklistItem(title: item.title, order: index)
            modelContext.insert(newItem)
            task.checklistItems.append(newItem)
        }
        return task
    }
}
