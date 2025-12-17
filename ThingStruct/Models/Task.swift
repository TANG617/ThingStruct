import Foundation
import SwiftData

@Model
final class Task {
    var id: UUID
    var title: String
    var order: Int
    var isCompleted: Bool
    var date: Date
    @Relationship(deleteRule: .cascade) var checklistItems: [ChecklistItem]
    
    init(title: String, date: Date = Date(), order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.isCompleted = false
        self.date = Calendar.current.startOfDay(for: date)
        self.checklistItems = []
    }
    
    var incompleteChecklistCount: Int {
        checklistItems.lazy.filter { !$0.isCompleted }.count
    }
    
    var totalChecklistCount: Int {
        checklistItems.count
    }
    
    func updateCompletionStatus() {
        guard !checklistItems.isEmpty else { return }
        let allCompleted = checklistItems.allSatisfy(\.isCompleted)
        if allCompleted != isCompleted {
            isCompleted = allCompleted
        }
    }
}
