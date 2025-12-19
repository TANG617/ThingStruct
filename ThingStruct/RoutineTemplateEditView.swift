/*
 * RoutineTemplateEditView.swift
 * Routine Template Edit View
 *
 * Create or edit routine templates.
 * Allows selecting which state templates to include in the routine.
 */

import SwiftUI
import SwiftData

// MARK: - Routine Template Edit View

@MainActor
struct RoutineTemplateEditView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Queries
    
    @Query(sort: \StateTemplate.title) private var availableStateTemplates: [StateTemplate]
    @Query private var allRoutineTemplates: [RoutineTemplate]
    
    // MARK: - Properties
    
    /// nil = create mode, non-nil = edit mode
    let template: RoutineTemplate?
    
    // MARK: - State
    
    @State private var title: String = ""
    @State private var selectedStateTemplates: [StateTemplate] = []
    @State private var selectedRepeatDays: Set<Weekday> = []
    
    // MARK: - Computed Properties (Conflict Detection)
    
    /// 被其他模板占用的日期
    private var occupiedDays: Set<Weekday> {
        RoutineTemplate.occupiedDays(in: allRoutineTemplates, excluding: template)
    }
    
    // MARK: - Init
    
    init(template: RoutineTemplate? = nil) {
        self.template = template
    }
    
    // MARK: - Computed Properties
    
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var navigationTitle: String {
        template == nil ? "New Routine Template" : "Edit Routine Template"
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                titleSection
                repeatDaysSection
                selectedStatesSection
                availableStatesSection
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadExistingData()
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var titleSection: some View {
        Section {
            TextField("Routine Title", text: $title)
        } header: {
            Text("Title")
        }
    }
    
    @ViewBuilder
    private var repeatDaysSection: some View {
        Section {
            WeekdayPicker(
                selectedDays: $selectedRepeatDays,
                occupiedDays: occupiedDays
            )
        } header: {
            Text("Repeat Days")
        } footer: {
            if occupiedDays.isEmpty {
                Text("Select days for auto-repeat, or leave empty for manual-only")
            } else {
                Text("Gray days are occupied by other templates. Leave empty for manual-only")
            }
        }
    }
    
    @ViewBuilder
    private var selectedStatesSection: some View {
        Section {
            if selectedStateTemplates.isEmpty {
                Text("No states added")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedStateTemplates) { stateTemplate in
                    selectedStateRow(stateTemplate)
                }
                .onMove(perform: moveStateTemplates)
            }
        } header: {
            Text("States in Routine")
        } footer: {
            Text("These states will be created when applying this routine")
        }
    }
    
    @ViewBuilder
    private func selectedStateRow(_ stateTemplate: StateTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stateTemplate.title)
                    .font(.body)
                
                if !stateTemplate.checklistItems.isEmpty {
                    Text("\(stateTemplate.checklistItems.count) checklist items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                removeStateTemplate(stateTemplate)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var availableStatesSection: some View {
        Section {
            if availableStateTemplates.isEmpty {
                Text("No state templates available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableStateTemplates) { stateTemplate in
                    availableStateRow(stateTemplate)
                }
            }
        } header: {
            Text("Add State Templates")
        }
    }
    
    @ViewBuilder
    private func availableStateRow(_ stateTemplate: StateTemplate) -> some View {
        let isSelected = selectedStateTemplates.contains { $0.id == stateTemplate.id }
        
        Button {
            if !isSelected {
                addStateTemplate(stateTemplate)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stateTemplate.title)
                        .font(.body)
                        .foregroundStyle(isSelected ? .secondary : .primary)
                    
                    if !stateTemplate.checklistItems.isEmpty {
                        Text("\(stateTemplate.checklistItems.count) checklist items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
    }
    
    // MARK: - Actions
    
    private func loadExistingData() {
        if let existingTemplate = template {
            title = existingTemplate.title
            selectedStateTemplates = existingTemplate.stateTemplates
            selectedRepeatDays = existingTemplate.repeatDays
        }
    }
    
    private func addStateTemplate(_ stateTemplate: StateTemplate) {
        withAnimation {
            selectedStateTemplates.append(stateTemplate)
        }
    }
    
    private func removeStateTemplate(_ stateTemplate: StateTemplate) {
        withAnimation {
            selectedStateTemplates.removeAll { $0.id == stateTemplate.id }
        }
    }
    
    private func moveStateTemplates(from source: IndexSet, to destination: Int) {
        selectedStateTemplates.move(fromOffsets: source, toOffset: destination)
    }
    
    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let existingTemplate = template {
            // Edit mode
            existingTemplate.title = trimmedTitle
            existingTemplate.stateTemplates = selectedStateTemplates
            existingTemplate.repeatDays = selectedRepeatDays
        } else {
            // Create mode
            let newTemplate = RoutineTemplate(title: trimmedTitle, repeatDays: selectedRepeatDays)
            modelContext.insert(newTemplate)
            newTemplate.stateTemplates = selectedStateTemplates
        }
        
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    RoutineTemplateEditView()
        .modelContainer(for: [RoutineTemplate.self, StateTemplate.self, ChecklistItem.self], inMemory: true)
}
