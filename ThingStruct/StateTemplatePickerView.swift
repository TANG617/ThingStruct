/*
 * StateTemplatePickerView.swift
 * State Template Picker View
 *
 * A simple picker for selecting a state template from FAB.
 * User taps a template to create a new state from it.
 */

import SwiftUI
import SwiftData

// MARK: - State Template Picker View

@MainActor
struct StateTemplatePickerView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Queries
    
    @Query(sort: \StateTemplate.title) private var templates: [StateTemplate]
    @Query(sort: \StateItem.order) private var allStates: [StateItem]
    
    // MARK: - Computed Properties
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private var todayStates: [StateItem] {
        allStates.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    private var nextOrder: Int {
        (todayStates.map(\.order).max() ?? -1) + 1
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("No State Templates", systemImage: "doc.on.doc")
                    } description: {
                        Text("Create templates in the State Template Library first")
                    }
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                createStateFromTemplate(template)
                            } label: {
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
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select State Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func createStateFromTemplate(_ template: StateTemplate) {
        _ = template.createState(for: today, order: nextOrder, modelContext: modelContext)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    StateTemplatePickerView()
        .modelContainer(for: [StateTemplate.self, ChecklistItem.self, StateItem.self], inMemory: true)
}
