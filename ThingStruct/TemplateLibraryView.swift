import SwiftUI
import SwiftData

@MainActor
struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskTemplate.title) private var templates: [TaskTemplate]
    @Query(sort: \Task.order) private var allTasks: [Task]
    @State private var showingAddTemplate = false
    @State private var editingTemplate: TaskTemplate?
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private var todayTasks: [Task] {
        allTasks.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Templates", systemImage: "list.bullet.rectangle.portrait")
                        } description: {
                            Text("Tap the + button to create your first template")
                        }
                    }
                } else {
                    ForEach(templates) { template in
                        TemplateRowView(template: template, onTap: {
                            createTaskFromTemplate(template)
                        })
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingTemplate = template
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.accentColor)
                        }
                    }
                    .onDelete(perform: deleteTemplates)
                }
            }
            .navigationTitle("Template Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddTemplate = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Add Template")
                }
            }
            .sheet(isPresented: $showingAddTemplate) {
                TemplateEditView()
            }
            .sheet(item: $editingTemplate) { template in
                TemplateEditView(template: template)
            }
        }
    }
    
    private func createTaskFromTemplate(_ template: TaskTemplate) {
        _ = template.createTask(for: Date(), order: todayTasks.count, modelContext: modelContext)
        dismiss()
    }
    
    private func deleteTemplates(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                modelContext.delete(templates[index])
            }
        }
    }
}

@MainActor
struct TemplateRowView: View {
    let template: TaskTemplate
    let onTap: () -> Void
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .foregroundColor(.primary)
                    if !template.checklistItems.isEmpty {
                        Text("\(template.checklistItems.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TemplateRowButtonStyle())
    }
}

@MainActor
struct TemplateRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    TemplateLibraryView()
        .modelContainer(for: [TaskTemplate.self, ChecklistItem.self], inMemory: true)
}
