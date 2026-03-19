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
                    ScreenLoadingView(
                        title: "Loading Templates",
                        systemImage: "square.stack.3d.up",
                        description: "Preparing suggested templates and tomorrow's schedule."
                    )
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
                        RecoverableErrorView(
                            title: "Unable to Load Templates",
                            message: error.localizedDescription
                        ) {
                            store.reload()
                        }
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
                            .lineLimit(2)

                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Label("\(template.baseBlockCount) base", systemImage: "rectangle.stack")
                                Label("\(template.totalBlockCount) total", systemImage: "square.stack.3d.up")
                                Label("\(template.taskBlueprintCount) tasks", systemImage: "checklist")
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(template.baseBlockCount) base blocks", systemImage: "rectangle.stack")
                                Label("\(template.totalBlockCount) total blocks", systemImage: "square.stack.3d.up")
                                Label("\(template.taskBlueprintCount) task blueprints", systemImage: "checklist")
                            }
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

                        ViewThatFits(in: .horizontal) {
                            HStack {
                                editTemplateButton(for: template)
                                useTomorrowButton(for: template)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                editTemplateButton(for: template)
                                useTomorrowButton(for: template)
                            }
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
            TomorrowScheduleCard(schedule: model.tomorrowSchedule) {
                store.regenerateFutureDayPlan(for: model.tomorrowSchedule.date)
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

    private func editTemplateButton(for template: SavedTemplateSummary) -> some View {
        Button("Edit") {
            if let source = store.document.savedTemplates.first(where: { $0.id == template.id }) {
                editingTemplate = source
            }
        }
        .buttonStyle(.bordered)
    }

    private func useTomorrowButton(for template: SavedTemplateSummary) -> some View {
        Button("Use for Tomorrow") {
            store.setTomorrowOverride(templateID: template.id)
        }
        .buttonStyle(.borderedProminent)
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

private struct TomorrowScheduleCard: View {
    let schedule: TomorrowScheduleSummary
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(schedule.date.titleText)
                    .font(.headline)

                Label(schedule.weekday.fullName, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Tomorrow Uses")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if schedule.overrideTemplateTitle != nil {
                        Text("Override Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }

                Text(schedule.finalTemplateTitle ?? "None")
                    .font(.title3.weight(.semibold))
            }

            Divider()

            LabeledContent("Weekday Rule", value: schedule.weekdayTemplateTitle ?? "None")
            LabeledContent("Override", value: schedule.overrideTemplateTitle ?? "None")
            LabeledContent("Final", value: schedule.finalTemplateTitle ?? "None")

            Button {
                onRegenerate()
            } label: {
                Label("Regenerate Tomorrow Plan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Templates Root") {
    TemplatesRootView()
        .environment(PreviewSupport.store(tab: .templates))
}

#Preview("Templates Root - Empty") {
    TemplatesRootView()
        .environment(
            PreviewSupport.store(
                tab: .templates,
                document: ThingStructDocument()
            )
        )
}

#Preview("Templates Root - Loading") {
    TemplatesRootView()
        .environment(PreviewSupport.store(tab: .templates, loaded: false))
}

#Preview("Save Template Sheet") {
    SaveTemplateSheet(sourceDate: PreviewSupport.referenceDay) { _ in }
}

#Preview("Tomorrow Schedule Card") {
    TomorrowScheduleCard(schedule: PreviewSupport.templatesModel().tomorrowSchedule) {
    }
    .padding()
}

#Preview("Tomorrow Schedule Card - Override") {
    TomorrowScheduleCard(
        schedule: TomorrowScheduleSummary(
            date: PreviewSupport.referenceDay.adding(days: 1),
            weekday: PreviewSupport.referenceDay.adding(days: 1).weekday,
            weekdayTemplateID: UUID(),
            weekdayTemplateTitle: "Workday",
            overrideTemplateID: UUID(),
            overrideTemplateTitle: "Travel Day",
            finalTemplateID: UUID(),
            finalTemplateTitle: "Travel Day"
        )
    ) {
    }
    .padding()
}
