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
    
    private var currentTask: Task? {
        todayTasks.first { !$0.isCompleted }
    }
    
    private var pendingTasks: [Task] {
        guard let current = currentTask else {
            return todayTasks.filter { !$0.isCompleted }
        }
        return todayTasks.filter { !$0.isCompleted && $0.id != current.id }
    }
    
    private var completedTasks: [Task] {
        todayTasks.filter { $0.isCompleted }
    }
    
    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        let dateString = formatter.string(from: Date())
        
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.current
        weekdayFormatter.dateFormat = "EEE"
        let weekday = weekdayFormatter.string(from: Date())
        
        return "\(dateString), \(weekday)"
    }
    
    var body: some View {
        NavigationStack {
            List {
                if let current = currentTask {
                    Section {
                        ForEach([current]) { task in
                            CurrentTaskCardView(task: task, onTap: {
                                selectedTask = task
                            })
                        }
                        .onDelete { _ in
                            if let task = currentTask {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    modelContext.delete(task)
                                }
                            }
                        }
                    } header: {
                        Text("Current")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !pendingTasks.isEmpty {
                    Section {
                        ForEach(pendingTasks) { task in
                            CompactTaskRowView(task: task, onTap: {
                                selectedTask = task
                            })
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    selectedTask = task
                                } label: {
                                    Label("Details", systemImage: "info.circle.fill")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .onMove(perform: movePendingTasks)
                        .onDelete(perform: deletePendingTasks)
                    } header: {
                        Text("Pending")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !completedTasks.isEmpty {
                    Section {
                        ForEach(completedTasks) { task in
                            CompactTaskRowView(task: task, onTap: {
                                selectedTask = task
                            })
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    selectedTask = task
                                } label: {
                                    Label("Details", systemImage: "info.circle.fill")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .onDelete(perform: deleteCompletedTasks)
                    } header: {
                        Text("Completed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if todayTasks.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Tasks Today", systemImage: "checklist")
                        } description: {
                            Text("Tap the + button to add a new task")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(todayTitle)
            .navigationDestination(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTemplateLibrary = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .fontWeight(.medium)
                    }
                    .tint(.accentColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .fontWeight(.medium)
                    }
                    .tint(.accentColor)
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
    
    private func movePendingTasks(from source: IndexSet, to destination: Int) {
        var tasks = pendingTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        
        let currentOrder = currentTask?.order ?? -1
        for (index, task) in tasks.enumerated() {
            task.order = currentOrder + 1 + index
        }
    }
    
    private func deletePendingTasks(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                modelContext.delete(pendingTasks[index])
            }
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
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    if task.totalChecklistCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(task.totalChecklistCount - task.incompleteChecklistCount)/\(task.totalChecklistCount) completed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    onTap()
                } label: {
                    Label("Details", systemImage: "info.circle.fill")
                }
                .tint(.accentColor)
            }
            
            if !task.checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(task.checklistItems.sorted(by: { $0.order < $1.order })) { item in
                        ChecklistItemCompactRow(item: item, task: task)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
    }
}

@MainActor
struct ChecklistItemCompactRow: View {
    @Bindable var item: ChecklistItem
    let task: Task
    
    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    item.isCompleted.toggle()
                    task.updateCompletionStatus()
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                    .font(.title3)
                    .symbolEffect(.bounce, value: item.isCompleted)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Text(item.title)
                .font(.body)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                item.isCompleted.toggle()
                task.updateCompletionStatus()
            }
        }
    }
}

@MainActor
struct CompactTaskRowView: View {
    @Bindable var task: Task
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                if task.totalChecklistCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(task.totalChecklistCount - task.incompleteChecklistCount)/\(task.totalChecklistCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Task.self, ChecklistItem.self, TaskTemplate.self], inMemory: true)
}
