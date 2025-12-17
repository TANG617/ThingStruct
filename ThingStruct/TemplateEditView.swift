import SwiftUI
import SwiftData

@MainActor
struct TemplateEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let template: TaskTemplate?
    
    init(template: TaskTemplate? = nil) {
        self.template = template
    }
    
    var body: some View {
        if let existingTemplate = template {
            TaskInputView(
                navigationTitle: "Edit Template",
                titlePlaceholder: "Template Title",
                confirmButtonTitle: "Save",
                initialTitle: existingTemplate.title,
                initialChecklistItems: existingTemplate.checklistItems.sorted(by: { $0.order < $1.order }).map { $0.title }
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
            TaskInputView(
                navigationTitle: "New Template",
                titlePlaceholder: "Template Title",
                confirmButtonTitle: "Save"
            ) { title, checklistItems in
                let template = TaskTemplate(title: title)
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

#Preview {
    TemplateEditView()
        .modelContainer(for: [TaskTemplate.self, ChecklistItem.self], inMemory: true)
}
