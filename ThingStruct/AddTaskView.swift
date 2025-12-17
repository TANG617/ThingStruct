import SwiftUI
import SwiftData

@MainActor
struct AddTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Task.order) private var allTasks: [Task]
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private var todayTasks: [Task] {
        allTasks.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    var body: some View {
        TaskInputView(
            navigationTitle: "New Task",
            titlePlaceholder: "Task Title",
            confirmButtonTitle: "Done"
        ) { title, checklistItems in
            let newTask = Task(
                title: title,
                date: Date(),
                order: todayTasks.count
            )
            modelContext.insert(newTask)
            
            for (index, itemTitle) in checklistItems.enumerated() {
                let checklistItem = ChecklistItem(title: itemTitle, order: index)
                modelContext.insert(checklistItem)
                newTask.checklistItems.append(checklistItem)
            }
        }
    }
}

#Preview {
    AddTaskView()
        .modelContainer(for: [Task.self], inMemory: true)
}
