import SwiftUI
import SwiftData

@MainActor
struct TaskInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let navigationTitle: String
    let titlePlaceholder: String
    let confirmButtonTitle: String
    let onSave: (String, [String]) -> Void
    let initialTitle: String?
    let initialChecklistItems: [String]?
    
    init(
        navigationTitle: String,
        titlePlaceholder: String,
        confirmButtonTitle: String,
        initialTitle: String? = nil,
        initialChecklistItems: [String]? = nil,
        onSave: @escaping (String, [String]) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.titlePlaceholder = titlePlaceholder
        self.confirmButtonTitle = confirmButtonTitle
        self.initialTitle = initialTitle
        self.initialChecklistItems = initialChecklistItems
        self.onSave = onSave
    }
    
    @State private var title: String = ""
    @State private var checklistItems: [String] = []
    @FocusState private var isTitleFocused: Bool
    @FocusState private var focusedChecklistIndex: Int?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(titlePlaceholder, text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .font(.body)
                        .onSubmit {
                            if checklistItems.isEmpty {
                                save()
                            }
                        }
                } header: {
                    Text("Title")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    ForEach(checklistItems.indices, id: \.self) { index in
                        TextField("Checklist item", text: $checklistItems[index])
                            .focused($focusedChecklistIndex, equals: index)
                            .submitLabel(.next)
                            .onChange(of: checklistItems[index]) { newValue in
                                let oldValue = checklistItems[index]
                                if newValue.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty && !oldValue.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                                    _Concurrency.Task { @MainActor in
                                        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
                                        if checklistItems.indices.contains(index) && checklistItems[index].trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                                            deleteChecklistItem(at: index)
                                        }
                                    }
                                }
                            }
                            .onSubmit {
                                let trimmed = checklistItems[index].trimmingCharacters(in: CharacterSet.whitespaces)
                                if trimmed.isEmpty {
                                    deleteChecklistItem(at: index)
                                } else if index == checklistItems.count - 1 {
                                    addChecklistItem()
                                } else {
                                    focusedChecklistIndex = index + 1
                                }
                            }
                    }
                    .onDelete(perform: deleteChecklistItems)
                    
                    Button {
                        addChecklistItem()
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text("Checklist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    if checklistItems.isEmpty {
                        Text("Add checklist items to create a structured task")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                if let initialTitle = initialTitle {
                    title = initialTitle
                }
                if let initialItems = initialChecklistItems {
                    checklistItems = initialItems
                }
                try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
                isTitleFocused = true
            }
        }
    }
    
    private func addChecklistItem() {
        checklistItems.append("")
        focusedChecklistIndex = checklistItems.count - 1
    }
    
    private func deleteChecklistItem(at index: Int) {
        guard index < checklistItems.count else { return }
        checklistItems.remove(at: index)
        if focusedChecklistIndex == index {
            if index < checklistItems.count {
                focusedChecklistIndex = index
            } else if index > 0 {
                focusedChecklistIndex = index - 1
            } else {
                focusedChecklistIndex = nil
            }
        } else if let currentFocus = focusedChecklistIndex, currentFocus > index {
            focusedChecklistIndex = currentFocus - 1
        }
    }
    
    private func deleteChecklistItems(offsets: IndexSet) {
        let sortedIndices = offsets.sorted(by: >)
        for index in sortedIndices where index < checklistItems.count {
            checklistItems.remove(at: index)
        }
    }
    
    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: CharacterSet.whitespaces)
        guard !trimmedTitle.isEmpty else {
            dismiss()
            return
        }
        
        let validItems = checklistItems.compactMap { item in
            let trimmed = item.trimmingCharacters(in: CharacterSet.whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        
        onSave(trimmedTitle, validItems)
        dismiss()
    }
}
