/*
 * StateTemplateLibraryView.swift
 * State Template Library View
 *
 * Displays all saved state templates for management:
 * - Tap template to create a new state
 * - Swipe left to edit template
 * - Swipe right to delete template
 * - Add new templates
 */

import SwiftUI
import SwiftData

// MARK: - State Template Library View

@MainActor
struct StateTemplateLibraryView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Queries
    
    @Query(sort: \StateTemplate.title) private var templates: [StateTemplate]
    @Query(sort: \StateItem.order) private var allStates: [StateItem]
    
    // MARK: - State
    
    @State private var showingAddTemplate = false
    @State private var editingTemplate: StateTemplate?
    
    // MARK: - Computed Properties
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date.now)
    }
    
    private var todayStates: [StateItem] {
        allStates.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(templates) { template in
                    StateTemplateRowView(template: template) {
                        createStateFromTemplate(template)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            editingTemplate = template
                        } label: {
                            Label("Edit", systemImage: "pencil.circle.fill")
                        }
                        .tint(.accentColor)
                    }
                }
                .onDelete(perform: deleteTemplates)
                
                if templates.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No State Templates", systemImage: "doc.on.doc")
                        } description: {
                            Text("Tap + to create a state template")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("State Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTemplate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showingAddTemplate) {
                StateTemplateEditView()
            }
            .sheet(item: $editingTemplate) { template in
                StateTemplateEditView(template: template)
            }
        }
    }
    
    // MARK: - Actions
    
    private func createStateFromTemplate(_ template: StateTemplate) {
        _ = template.createState(for: Date.now, order: todayStates.count, modelContext: modelContext)
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

// MARK: - State Template Row View

@MainActor
struct StateTemplateRowView: View {
    let template: StateTemplate
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    if !template.checklistItems.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(template.checklistItems.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StateTemplateRowButtonStyle())
    }
}

// MARK: - Button Style

@MainActor
struct StateTemplateRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    StateTemplateLibraryView()
        .modelContainer(for: [StateTemplate.self, ChecklistItem.self, StateItem.self], inMemory: true)
}
