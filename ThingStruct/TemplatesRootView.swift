import SwiftUI

private enum TemplatesSection: String, CaseIterable, Identifiable {
    case suggested = "Suggested"
    case saved = "Saved"
    case schedule = "Schedule"

    var id: String { rawValue }
}

struct TemplatesRootView: View {
    @Environment(ThingStructStore.self) private var store
    @State private var selectedSection: TemplatesSection = .suggested
    @State private var saveSession: SaveTemplateSession?
    @State private var editingTemplate: SavedDayTemplate?

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ContentUnavailableView("Loading", systemImage: "square.stack.3d.up")
                } else {
                    let result = Result { try store.templatesScreenModel() }

                    switch result {
                    case let .success(model):
                        List {
                            Picker("Section", selection: $selectedSection) {
                                ForEach(TemplatesSection.allCases) { section in
                                    Text(section.rawValue).tag(section)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)

                            switch selectedSection {
                            case .suggested:
                                suggestedSection(model: model)
                            case .saved:
                                savedSection(model: model)
                            case .schedule:
                                scheduleSection(model: model)
                            }
                        }
                        .listStyle(.insetGrouped)

                    case let .failure(error):
                        ContentUnavailableView(
                            "Unable to Load Templates",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error.localizedDescription)
                        )
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $saveSession) { session in
            SaveTemplateSheet(sourceDate: session.sourceDate) { title in
                store.saveSuggestedTemplate(from: session.sourceDate, title: title)
            }
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(
                template: template,
                assignedWeekdays: store.assignedWeekdays(for: template.id),
                occupiedWeekdays: store.occupiedWeekdays(excluding: template.id)
            ) { title, blocks, assignedWeekdays in
                try store.saveEditedTemplate(
                    template.id,
                    title: title,
                    blocks: blocks,
                    assignedWeekdays: assignedWeekdays
                )
            } onDelete: {
                store.deleteSavedTemplate(template.id)
            }
        }
        .task {
            store.ensureMaterialized(for: LocalDay.today())
        }
    }

    @ViewBuilder
    private func suggestedSection(model: TemplatesScreenModel) -> some View {
        if model.suggestedTemplates.isEmpty {
            ContentUnavailableView(
                "No Suggested Templates",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Recent days do not yet contain any exportable plans.")
            )
        } else {
            Section("Recent 3 Days") {
                ForEach(model.suggestedTemplates) { template in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(template.sourceDate.titleText)
                            .font(.headline)
                        Text(template.previewTitles.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("\(template.baseBlockCount) base", systemImage: "rectangle.stack")
                            Label("\(template.totalBlockCount) total", systemImage: "square.stack.3d.up")
                            Label("\(template.taskBlueprintCount) tasks", systemImage: "checklist")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Button {
                            saveSession = SaveTemplateSession(sourceDate: template.sourceDate)
                        } label: {
                            Label("Save as Template", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func savedSection(model: TemplatesScreenModel) -> some View {
        if model.savedTemplates.isEmpty {
            ContentUnavailableView(
                "No Saved Templates",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Save a suggested template first.")
            )
        } else {
            Section("Saved Templates") {
                ForEach(model.savedTemplates) { template in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(template.title)
                            .font(.headline)

                        HStack {
                            Text("\(template.totalBlockCount) blocks")
                            Text("•")
                            Text("\(template.taskBlueprintCount) tasks")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if !template.assignedWeekdays.isEmpty {
                            Text(template.assignedWeekdays.map(\.shortName).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Edit") {
                                if let source = store.document.savedTemplates.first(where: { $0.id == template.id }) {
                                    editingTemplate = source
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Use for Tomorrow") {
                                store.setTomorrowOverride(templateID: template.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleSection(model: TemplatesScreenModel) -> some View {
        Section("Tomorrow") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.tomorrowSchedule.date.titleText)
                    .font(.headline)
                Label(model.tomorrowSchedule.weekday.fullName, systemImage: "calendar")
                    .foregroundStyle(.secondary)
                scheduleRow("Weekday Rule", value: model.tomorrowSchedule.weekdayTemplateTitle ?? "None")
                scheduleRow("Override", value: model.tomorrowSchedule.overrideTemplateTitle ?? "None")
                scheduleRow("Final", value: model.tomorrowSchedule.finalTemplateTitle ?? "None")

                Button {
                    store.regenerateFutureDayPlan(for: model.tomorrowSchedule.date)
                } label: {
                    Label("Regenerate Tomorrow Plan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.top, 6)
            }
        }

        Section("Weekday Rules") {
            ForEach(Weekday.mondayFirst) { weekday in
                Picker(weekday.fullName, selection: Binding(
                    get: { store.document.weekdayRules.first(where: { $0.weekday == weekday })?.savedTemplateID },
                    set: { store.assignWeekday(weekday, to: $0) }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.document.savedTemplates) { template in
                        Text(template.title).tag(UUID?.some(template.id))
                    }
                }
            }
        }

        Section("Tomorrow Override") {
            Picker("Override Template", selection: Binding(
                get: { store.document.overrides.first(where: { $0.date == LocalDay.today().adding(days: 1) })?.savedTemplateID },
                set: { store.setTomorrowOverride(templateID: $0) }
            )) {
                Text("Use Weekday Rule").tag(UUID?.none)
                ForEach(store.document.savedTemplates) { template in
                    Text(template.title).tag(UUID?.some(template.id))
                }
            }
        }
    }

    private func scheduleRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}

private struct SaveTemplateSession: Identifiable {
    let id = UUID()
    let sourceDate: LocalDay
}

private struct SaveTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceDate: LocalDay
    let onSave: (String) -> Void
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Text(sourceDate.titleText)
                }

                Section("Template Title") {
                    TextField("Title", text: $title)
                }
            }
            .navigationTitle("Save Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.isEmpty ? sourceDate.titleText : title)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
