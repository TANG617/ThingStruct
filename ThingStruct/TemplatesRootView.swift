import SwiftUI

// `TemplatesRootView` is the management screen for reusable schedule structure.
//
// It intentionally mixes read-only summaries with a small number of commands:
// save suggestion, edit template, assign weekday rule, set tomorrow override.
private enum TemplatesSection: String, CaseIterable, Identifiable {
    case suggested = "Suggested"
    case saved = "Saved"
    case schedule = "Schedule"

    var id: String { rawValue }
}

struct TemplatesRootView: View {
    @Environment(ThingStructStore.self) private var store
    @State private var selectedSection: TemplatesSection = .suggested

    // This enum acts like a compact "navigation state machine" for sheet presentation.
    // One optional enum is often clearer than several unrelated optional booleans/items.
    @State private var sheet: TemplatesSheet?

    var body: some View {
        RootScreenContainer(
            isLoaded: store.isLoaded,
            loadingTitle: "Loading Templates",
            loadingSystemImage: "square.stack.3d.up",
            loadingDescription: "Preparing suggested templates and tomorrow's schedule.",
            errorTitle: "Unable to Load Templates",
            retry: store.reload
        ) {
            try store.templatesScreenModel()
        } content: { model in
            VStack(spacing: 0) {
                sectionPicker

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        switch selectedSection {
                        case .suggested:
                            suggestedSection(model: model)
                        case .saved:
                            savedSection(model: model)
                        case .schedule:
                            scheduleSection(model: model)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case let .save(sourceDate):
                SaveTemplateSheet(sourceDate: sourceDate) { title in
                    store.saveSuggestedTemplate(from: sourceDate, title: title)
                }

            case let .edit(templateID):
                if let template = store.savedTemplate(id: templateID) {
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
            }
        }
    }

    private var sectionPicker: some View {
        // Segmented control is a natural fit for a small number of peer sections.
        Picker("Section", selection: $selectedSection) {
            ForEach(TemplatesSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private func suggestedSection(model: TemplatesScreenModel) -> some View {
        let slots = suggestedSlots(from: model)
        let hasSuggestions = slots.contains { $0.template != nil }

        SectionHeader(
            title: "Recent 3 Days",
            subtitle: hasSuggestions
                ? "Review your strongest recent plans and save the ones worth reusing."
                : "The last three days do not yet contain exportable plans, but the window stays visible so you can see what was checked."
        )

        ForEach(slots) { slot in
            if let template = slot.template {
                SuggestedTemplateCard(template: template) {
                    sheet = .save(sourceDate: template.sourceDate)
                }
            } else {
                SuggestedTemplateEmptyCard(date: slot.date)
            }
        }
    }

    @ViewBuilder
    private func savedSection(model: TemplatesScreenModel) -> some View {
        SectionHeader(
            title: "Saved Templates",
            subtitle: model.savedTemplates.isEmpty
                ? "Save a suggested plan first to build your template library."
                : "Keep each template recognizable at a glance, then decide which one should drive tomorrow."
        )

        if model.savedTemplates.isEmpty {
            ContentUnavailableView(
                "No Saved Templates",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Save a suggested template first.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            ForEach(model.savedTemplates) { template in
                SavedTemplateCard(
                    template: template,
                    isSelectedForTomorrow: model.tomorrowSchedule.finalTemplateID == template.id,
                    onEdit: { sheet = .edit(templateID: template.id) },
                    onUseTomorrow: { store.setTomorrowOverride(templateID: template.id) }
                )
            }
        }
    }

    @ViewBuilder
    private func scheduleSection(model: TemplatesScreenModel) -> some View {
        SectionHeader(
            title: "Schedule",
            subtitle: "Review which template applies today and tomorrow, then adjust weekday rules or a one-off override."
        )

        TemplateScheduleCard(
            schedule: model.todaySchedule,
            heading: "Today",
            actionTitle: "Rebuild Today's Plan"
        ) {
            store.rebuildDayPlan(for: model.todaySchedule.date)
        }

        TemplateScheduleCard(
            schedule: model.tomorrowSchedule,
            heading: "Tomorrow",
            actionTitle: "Regenerate Tomorrow Plan"
        ) {
            store.regenerateFutureDayPlan(for: model.tomorrowSchedule.date)
        }

        if model.savedTemplates.isEmpty {
            ContentUnavailableView(
                "No Templates to Assign",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Save a suggested template before configuring weekday rules or a one-off override.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        } else {
            WeekdayRulesCard(
                templates: store.savedTemplates,
                selectionForWeekday: weekdaySelection(for:)
            )

            TemplateOverrideCard(
                heading: "Today Override",
                helpText: "Use this to replace today's materialized plan right away.",
                templates: store.savedTemplates,
                selection: overrideSelection(for: model.todaySchedule.date, shouldRebuildDayPlan: true)
            )

            TemplateOverrideCard(
                heading: "Tomorrow Override",
                helpText: "Use this only when tomorrow should temporarily ignore the weekday rule.",
                templates: store.savedTemplates,
                selection: overrideSelection(for: model.tomorrowSchedule.date, shouldRebuildDayPlan: false)
            )
        }
    }

    private func suggestedSlots(from model: TemplatesScreenModel) -> [SuggestedTemplateSlot] {
        let suggestionsByDate = Dictionary(uniqueKeysWithValues: model.suggestedTemplates.map { ($0.sourceDate, $0) })

        return (0 ..< 3).map { offset in
            let date = LocalDay.today().adding(days: -offset)
            return SuggestedTemplateSlot(
                date: date,
                template: suggestionsByDate[date]
            )
        }
    }

    private func weekdaySelection(for weekday: Weekday) -> Binding<UUID?> {
        // `Binding` is SwiftUI's two-way data conduit.
        // This lets a child control read and write store state without owning it.
        Binding(
            get: { store.assignedTemplateID(for: weekday) },
            set: { store.assignWeekday(weekday, to: $0) }
        )
    }

    private func overrideSelection(
        for date: LocalDay,
        shouldRebuildDayPlan: Bool
    ) -> Binding<UUID?> {
        Binding(
            get: { store.overrideTemplateID(for: date) },
            set: {
                store.setOverride(templateID: $0, for: date)
                if shouldRebuildDayPlan {
                    store.rebuildDayPlan(for: date)
                }
            }
        )
    }
}

private struct SuggestedTemplateSlot: Identifiable {
    let date: LocalDay
    let template: SuggestedTemplateSummary?

    var id: LocalDay { date }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TemplateCard<Content: View>: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    var isEmphasized = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: isEmphasized ? .systemBackground : .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    isEmphasized
                        ? tintPreset.tintColor.opacity(0.28)
                        : Color(uiColor: .separator).opacity(0.12),
                    lineWidth: isEmphasized ? 1.5 : 1
                )
        )
    }
}

private struct SuggestedTemplateCard: View {
    let template: SuggestedTemplateSummary
    let onSave: () -> Void

    var body: some View {
        TemplateCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.sourceDate.titleText)
                        .font(.headline)

                    Text("Suggested from a recent day plan")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                TemplateBadge(title: "Suggested", tint: .secondary)
            }

            TemplatePreviewRow(
                titles: template.previewTitles,
                totalCount: template.totalBlockCount
            )

            TemplateStatsRow(stats: [
                .init(title: "\(template.totalBlockCount) blocks", systemImage: "square.stack.3d.up"),
                .init(title: "\(template.taskBlueprintCount) tasks", systemImage: "checklist"),
                .init(title: "\(template.baseBlockCount) base blocks", systemImage: "rectangle.stack")
            ])

            HStack(alignment: .center, spacing: 12) {
                Text("Save this structure as a reusable template.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button {
                    onSave()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SuggestedTemplateEmptyCard: View {
    let date: LocalDay

    var body: some View {
        TemplateCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(date.titleText)
                        .font(.headline)

                    Text("No exportable plan")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("This day does not yet have enough reusable structure to become a suggested template.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                TemplateBadge(title: "Checked", tint: .secondary)
            }
        }
    }
}

private struct SavedTemplateCard: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let template: SavedTemplateSummary
    let isSelectedForTomorrow: Bool
    let onEdit: () -> Void
    let onUseTomorrow: () -> Void

    var body: some View {
        TemplateCard(isEmphasized: isSelectedForTomorrow) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.title)
                        .font(.headline)

                    if !template.previewTitles.isEmpty {
                        TemplatePreviewRow(
                            titles: template.previewTitles,
                            totalCount: template.totalBlockCount
                        )
                    }
                }

                Spacer(minLength: 12)

                if isSelectedForTomorrow {
                    TemplateBadge(title: "Tomorrow", tint: tintPreset.tintColor)
                }
            }

            TemplateStatsRow(stats: [
                .init(title: "\(template.totalBlockCount) blocks", systemImage: "square.stack.3d.up"),
                .init(title: "\(template.taskBlueprintCount) tasks", systemImage: "checklist")
            ])

            if !template.assignedWeekdays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assigned Weekdays")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TemplateChipRow(titles: template.assignedWeekdays.map(\.shortName))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    editButton
                    tomorrowButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    editButton
                    tomorrowButton
                }
            }
        }
    }

    private var editButton: some View {
        Button("Edit", action: onEdit)
            .buttonStyle(.bordered)
    }

    private var tomorrowButton: some View {
        Button(isSelectedForTomorrow ? "Using Tomorrow" : "Use for Tomorrow") {
            onUseTomorrow()
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSelectedForTomorrow)
    }
}

private struct WeekdayRulesCard: View {
    let templates: [SavedDayTemplate]
    let selectionForWeekday: (Weekday) -> Binding<UUID?>

    var body: some View {
        TemplateCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Weekday Rules")
                    .font(.headline)

                Text("Set the default template for each weekday.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(Weekday.mondayFirst.enumerated()), id: \.element.id) { index, weekday in
                        HStack(spacing: 12) {
                            Text(weekday.fullName)
                                .font(.body)

                            Spacer(minLength: 12)

                            Picker("", selection: selectionForWeekday(weekday)) {
                                Text("None").tag(UUID?.none)
                                ForEach(templates) { template in
                                    Text(template.title).tag(UUID?.some(template.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.vertical, 12)

                        if index != Weekday.mondayFirst.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct TemplateOverrideCard: View {
    let heading: String
    let helpText: String
    let templates: [SavedDayTemplate]
    let selection: Binding<UUID?>

    var body: some View {
        TemplateCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(heading)
                    .font(.headline)

                Text(helpText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Override Template", selection: selection) {
                    Text("Use Weekday Rule").tag(UUID?.none)
                    ForEach(templates) { template in
                        Text(template.title).tag(UUID?.some(template.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

private enum TemplatesSheet: Identifiable {
    case save(sourceDate: LocalDay)
    case edit(templateID: UUID)

    var id: String {
        switch self {
        case let .save(sourceDate):
            return "save-\(sourceDate.description)"
        case let .edit(templateID):
            return "edit-\(templateID.uuidString)"
        }
    }
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

private struct TemplateScheduleCard: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let schedule: TemplateScheduleSummary
    let heading: String
    let actionTitle: String
    let onRegenerate: () -> Void

    var body: some View {
        TemplateCard(isEmphasized: schedule.overrideTemplateTitle != nil) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(schedule.date.titleText)
                        .font(.headline)

                    Label(schedule.weekday.fullName, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if schedule.overrideTemplateTitle != nil {
                    TemplateBadge(title: "Override Active", tint: tintPreset.tintColor)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("\(heading) Uses")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(schedule.finalTemplateTitle ?? "No Template Assigned")
                    .font(.title3.weight(.semibold))

                Text(schedule.overrideTemplateTitle != nil
                    ? "A one-off override is currently taking precedence over the weekday rule."
                    : "\(heading) will follow the weekday rule unless you set an override.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ScheduleValueRow(title: "Weekday Rule", value: schedule.weekdayTemplateTitle ?? "None")
                ScheduleValueRow(title: "Override", value: schedule.overrideTemplateTitle ?? "None")
                ScheduleValueRow(title: "Final", value: schedule.finalTemplateTitle ?? "None")
            }

            Button {
                onRegenerate()
            } label: {
                Label(actionTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ScheduleValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct TemplateStatsRow: View {
    let stats: [TemplateStat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(stats) { stat in
                    TemplateBadge(title: stat.title, systemImage: stat.systemImage, tint: .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(stats) { stat in
                    TemplateBadge(title: stat.title, systemImage: stat.systemImage, tint: .secondary)
                }
            }
        }
    }
}

private struct TemplateStat: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

private struct TemplatePreviewRow: View {
    let titles: [String]
    let totalCount: Int

    private var hiddenCount: Int {
        max(totalCount - titles.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    previewChips
                }

                VStack(alignment: .leading, spacing: 8) {
                    previewChips
                }
            }
        }
    }

    @ViewBuilder
    private var previewChips: some View {
        ForEach(titles, id: \.self) { title in
            TemplateBadge(title: title, tint: .primary, isSoft: false)
        }

        if hiddenCount > 0 {
            TemplateBadge(title: "+\(hiddenCount) more", tint: .secondary)
        }
    }
}

private struct TemplateChipRow: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let titles: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chips
            }

            VStack(alignment: .leading, spacing: 8) {
                chips
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(titles, id: \.self) { title in
            TemplateBadge(title: title, tint: tintPreset.tintColor)
        }
    }
}

private struct TemplateBadge: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color
    var isSoft = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }

            Text(title)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            tint.opacity(isSoft ? 0.12 : 0.08),
            in: Capsule()
        )
    }
}

#Preview("Templates Root") {
    NavigationStack {
        TemplatesRootView()
    }
    .environment(PreviewSupport.store(tab: .library))
}

#Preview("Templates Root - Empty") {
    NavigationStack {
        TemplatesRootView()
    }
    .environment(
        PreviewSupport.store(
            tab: .library,
            document: ThingStructDocument()
        )
    )
}

#Preview("Templates Root - Loading") {
    NavigationStack {
        TemplatesRootView()
    }
    .environment(PreviewSupport.store(tab: .library, loaded: false))
}

#Preview("Suggested Template Card") {
    SuggestedTemplateCard(
        template: PreviewSupport.templatesModel().suggestedTemplates.first!
    ) {
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Suggested Template Empty Card") {
    SuggestedTemplateEmptyCard(date: PreviewSupport.referenceDay.adding(days: -1))
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Saved Template Card") {
    SavedTemplateCard(
        template: PreviewSupport.templatesModel().savedTemplates.first!,
        isSelectedForTomorrow: true,
        onEdit: {},
        onUseTomorrow: {}
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Save Template Sheet") {
    SaveTemplateSheet(sourceDate: PreviewSupport.referenceDay) { _ in }
}

#Preview("Today Schedule Card") {
    TemplateScheduleCard(
        schedule: PreviewSupport.templatesModel().todaySchedule,
        heading: "Today",
        actionTitle: "Rebuild Today's Plan"
    ) {
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Tomorrow Schedule Card - Override") {
    TemplateScheduleCard(
        schedule: TemplateScheduleSummary(
            date: PreviewSupport.referenceDay.adding(days: 1),
            weekday: PreviewSupport.referenceDay.adding(days: 1).weekday,
            weekdayTemplateID: UUID(),
            weekdayTemplateTitle: "Workday",
            overrideTemplateID: UUID(),
            overrideTemplateTitle: "Travel Day",
            finalTemplateID: UUID(),
            finalTemplateTitle: "Travel Day"
        ),
        heading: "Tomorrow",
        actionTitle: "Regenerate Tomorrow Plan"
    ) {
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Weekday Rules Card") {
    WeekdayRulesCard(
        templates: PreviewSupport.seededDocument().savedTemplates,
        selectionForWeekday: { _ in
            .constant(PreviewSupport.seededDocument().savedTemplates.first?.id)
        }
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Template Override Card") {
    TemplateOverrideCard(
        heading: "Today Override",
        helpText: "Use this to replace today's materialized plan right away.",
        templates: PreviewSupport.seededDocument().savedTemplates,
        selection: .constant(PreviewSupport.seededDocument().savedTemplates.last?.id)
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
