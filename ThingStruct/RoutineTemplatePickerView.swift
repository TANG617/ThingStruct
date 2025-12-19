/*
 * RoutineTemplatePickerView.swift
 * Routine Template Picker View
 *
 * A simple picker for selecting a routine template from FAB.
 * User taps a template to apply the entire routine for today.
 */

import SwiftUI
import SwiftData

// MARK: - Routine Template Picker View

@MainActor
struct RoutineTemplatePickerView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Queries
    
    @Query(sort: \RoutineTemplate.title) private var templates: [RoutineTemplate]
    
    // MARK: - Computed Properties
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("No Routine Templates", systemImage: "calendar.day.timeline.left")
                    } description: {
                        Text("Create templates in the Routine Template Library first")
                    }
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                applyRoutineTemplate(template)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(template.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.stack")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text("\(template.stateTemplates.count) states")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
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
            .navigationTitle("Select Routine Template")
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
    
    private func applyRoutineTemplate(_ template: RoutineTemplate) {
        _ = template.createRoutine(for: today, modelContext: modelContext)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    RoutineTemplatePickerView()
        .modelContainer(for: [RoutineTemplate.self, StateTemplate.self, StateItem.self, ChecklistItem.self], inMemory: true)
}
