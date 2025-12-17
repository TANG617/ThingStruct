import SwiftUI
import SwiftData

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Task.order) private var allTasks: [Task]
    @State private var showingAddTask = false
    @State private var showingTemplateLibrary = false
    @State private var selectedTask: Task?
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private var todayTasks: [Task] {
        allTasks.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    private var activeTasks: [Task] {
        todayTasks.filter { !$0.isCompleted }
    }
    
    private var completedTasks: [Task] {
        todayTasks.filter { $0.isCompleted }
    }
    
    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        let dateString = formatter.string(from: Date())
        
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US")
        weekdayFormatter.dateFormat = "EEE"
        let weekday = weekdayFormatter.string(from: Date())
        
        return "\(dateString), \(weekday)"
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !activeTasks.isEmpty {
                    Section {
                        ForEach(activeTasks) { task in
                            Group {
                                if task.id == activeTasks.first?.id {
                                    CurrentTaskCardView(task: task)
                                } else {
                                    CompactTaskRowView(task: task, onTap: {
                                        selectedTask = task
                                    })
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            selectedTask = task
                                        } label: {
                                            Label("Details", systemImage: "info.circle")
                                        }
                                        .tint(.accentColor)
                                    }
                                }
                            }
                        }
                        .onMove(perform: moveActiveTasks)
                    }
                } else if activeTasks.isEmpty && completedTasks.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Tasks", systemImage: "checklist")
                        } description: {
                            Text("Tap the + button to add your first task")
                        }
                    }
                }
                
                if !completedTasks.isEmpty {
                    Section("Completed") {
                        ForEach(completedTasks) { task in
                            CompactTaskRowView(task: task, onTap: {
                                selectedTask = task
                            })
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    selectedTask = task
                                } label: {
                                    Label("Details", systemImage: "info.circle")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .onDelete(perform: deleteCompletedTasks)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(todayTitle)
            .navigationDestination(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingTemplateLibrary = true
                    } label: {
                        Label("Library", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .accessibilityLabel("Template Library")
                    
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Add Task")
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskView()
            }
            .sheet(isPresented: $showingTemplateLibrary) {
                TemplateLibraryView()
            }
        }
    }
    
    private func moveActiveTasks(from source: IndexSet, to destination: Int) {
        var tasks = activeTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        
        for (index, task) in tasks.enumerated() {
            task.order = index
        }
    }
    
    private func deleteCompletedTasks(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                modelContext.delete(completedTasks[index])
            }
        }
    }
}

@MainActor
struct CurrentTaskCardView: View {
    @Bindable var task: Task
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if task.totalChecklistCount > 0 {
                        Text("\(task.totalChecklistCount - task.incompleteChecklistCount)/\(task.totalChecklistCount) completed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            if !task.checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(task.checklistItems.sorted(by: { $0.order < $1.order })) { item in
                        ChecklistItemCompactRow(item: item, task: task)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(.vertical, 8)
    }
}

@MainActor
struct ChecklistItemCompactRow: View {
    @Bindable var item: ChecklistItem
    let task: Task
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    item.isCompleted.toggle()
                    task.updateCompletionStatus()
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(item.isCompleted ? .accentColor : .secondary)
                    .font(.title3)
                    .symbolEffect(.bounce, value: item.isCompleted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Text(item.title)
                .font(.body)
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        item.isCompleted.toggle()
                        task.updateCompletionStatus()
                    }
                }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

@MainActor
struct CompactTaskRowView: View {
    @Bindable var task: Task
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .foregroundColor(.primary)
                
                if task.totalChecklistCount > 0 {
                    Text("\(task.totalChecklistCount - task.incompleteChecklistCount)/\(task.totalChecklistCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Task.self, ChecklistItem.self, TaskTemplate.self], inMemory: true)
}
