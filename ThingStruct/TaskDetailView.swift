import SwiftUI
import SwiftData

@MainActor
struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: Task
    @State private var editingTitle = false
    @State private var newTitle: String = ""
    @FocusState private var isTitleFocused: Bool
    
    var body: some View {
        List {
            Section {
                if editingTitle {
                    TextField("Task Title", text: $newTitle)
                        .focused($isTitleFocused)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .onSubmit {
                            saveTitle()
                        }
                        .task {
                            newTitle = task.title
                            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
                            isTitleFocused = true
                        }
                } else {
                    HStack(spacing: 12) {
                        Text(task.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .onTapGesture {
                        editingTitle = true
                    }
                }
            } header: {
                if !task.checklistItems.isEmpty {
                    HStack(spacing: 8) {
                        Text("Checklist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("\(task.totalChecklistCount - task.incompleteChecklistCount)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("/")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(task.totalChecklistCount)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            if !task.checklistItems.isEmpty {
                Section {
                    ForEach(task.checklistItems.sorted(by: { $0.order < $1.order })) { item in
                        ChecklistItemRow(item: item, task: task)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onDelete(perform: deleteChecklistItems)
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("No Checklist Items", systemImage: "checklist")
                    } description: {
                        Text("Tap the + button to add checklist items")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addChecklistItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    private func saveTitle() {
        let trimmed = newTitle.trimmingCharacters(in: CharacterSet.whitespaces)
        if !trimmed.isEmpty {
            task.title = trimmed
        }
        editingTitle = false
    }
    
    private func addChecklistItem() {
        let newItem = ChecklistItem(title: "", order: task.checklistItems.count)
        modelContext.insert(newItem)
        task.checklistItems.append(newItem)
    }
    
    private func deleteChecklistItems(offsets: IndexSet) {
        let sortedItems = task.checklistItems.sorted(by: { $0.order < $1.order })
        for index in offsets {
            if let item = sortedItems[safe: index] {
                task.checklistItems.removeAll { $0.id == item.id }
            }
        }
        for (index, item) in task.checklistItems.enumerated() {
            item.order = index
        }
    }
}

@MainActor
struct ChecklistItemRow: View {
    @Bindable var item: ChecklistItem
    let task: Task
    @Environment(\.modelContext) private var modelContext
    @State private var editingTitle = false
    @State private var newTitle: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    item.isCompleted.toggle()
                    task.updateCompletionStatus()
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: item.isCompleted)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if editingTitle || item.title.isEmpty {
                TextField("Checklist item", text: $newTitle)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .onSubmit {
                        saveTitle()
                    }
                    .onChange(of: newTitle) { newValue in
                        let trimmed = newValue.trimmingCharacters(in: CharacterSet.whitespaces)
                        if trimmed.isEmpty && !newTitle.isEmpty {
                            _Concurrency.Task { @MainActor in
                                try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                                if item.title.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                                    deleteItem()
                                }
                            }
                        }
                    }
                    .task {
                        if item.title.isEmpty {
                            newTitle = ""
                        } else {
                            newTitle = item.title
                        }
                        editingTitle = true
                        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
                        isFocused = true
                    }
            } else {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .onTapGesture {
                        editingTitle = true
                    }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if !editingTitle && !item.title.isEmpty {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    item.isCompleted.toggle()
                    task.updateCompletionStatus()
                }
            }
        }
    }
    
    private func saveTitle() {
        let trimmed = newTitle.trimmingCharacters(in: CharacterSet.whitespaces)
        if trimmed.isEmpty {
            deleteItem()
        } else {
            item.title = trimmed
            editingTitle = false
        }
    }
    
    private func deleteItem() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            task.checklistItems.removeAll { $0.id == item.id }
            modelContext.delete(item)
            for (index, remainingItem) in task.checklistItems.enumerated() {
                remainingItem.order = index
            }
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    NavigationStack {
        TaskDetailView(task: Task(title: "Sample Task"))
    }
    .modelContainer(for: [Task.self, ChecklistItem.self], inMemory: true)
}
