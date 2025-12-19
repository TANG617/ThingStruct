/*
 * StateTemplateEditView.swift
 * State Template Edit View
 *
 * Create or edit state templates.
 * Reuses StateInputView component for consistent UI.
 */

import SwiftUI
import SwiftData

// MARK: - State Template Edit View

@MainActor
struct StateTemplateEditView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// nil = create mode, non-nil = edit mode
    let template: StateTemplate?
    
    // MARK: - Init
    
    init(template: StateTemplate? = nil) {
        self.template = template
    }
    
    // MARK: - Body
    
    var body: some View {
        if let existingTemplate = template {
            // Edit Mode
            StateInputView(
                navigationTitle: "Edit Template",
                titlePlaceholder: "Template Title",
                confirmButtonTitle: "Save",
                initialTitle: existingTemplate.title,
                initialChecklistItems: existingTemplate.checklistItems
                    .sorted(by: { $0.order < $1.order })
                    .map { $0.title }
            ) { title, checklistItems in
                existingTemplate.title = title
                
                for oldItem in existingTemplate.checklistItems {
                    modelContext.delete(oldItem)
                }
                existingTemplate.checklistItems.removeAll()
                
                for (index, itemTitle) in checklistItems.enumerated() {
                    let checklistItem = ChecklistItem(title: itemTitle, order: index)
                    modelContext.insert(checklistItem)
                    existingTemplate.checklistItems.append(checklistItem)
                }
            }
        } else {
            // Create Mode
            StateInputView(
                navigationTitle: "New State Template",
                titlePlaceholder: "Template Title",
                confirmButtonTitle: "Save"
            ) { title, checklistItems in
                let template = StateTemplate(title: title)
                modelContext.insert(template)
                
                for (index, itemTitle) in checklistItems.enumerated() {
                    let checklistItem = ChecklistItem(title: itemTitle, order: index)
                    modelContext.insert(checklistItem)
                    template.checklistItems.append(checklistItem)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    StateTemplateEditView()
        .modelContainer(for: [StateTemplate.self, ChecklistItem.self], inMemory: true)
}
