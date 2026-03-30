import SwiftUI

struct TemplatesRootView: View {
    @Environment(ThingStructStore.self) private var store

    @State private var sheet: TemplatesSheet?
    @State private var pendingTodayChoice: PendingTodayChoice?

    var body: some View {
        RootScreenContainer(
            isLoaded: store.isLoaded,
            loadingTitle: "Loading Templates",
            loadingSystemImage: "square.stack.3d.up",
            loadingDescription: "Preparing today’s chooser, your template library, and schedule defaults.",
            errorTitle: "Unable to Load Templates",
            retry: store.reload
        ) {
            try store.templatesScreenModel()
        } content: { model in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    todaySection(model: model)
                    savedTemplatesSection(model: model)
                    defaultsSection(model: model)
                    recentSuggestionsSection(model: model)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
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
        .confirmationDialog(
            "Replace today’s current plan?",
            isPresented: Binding(
                get: { pendingTodayChoice != nil },
                set: { if !$0 { pendingTodayChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace Today’s Plan", role: .destructive) {
                guard let pendingTodayChoice else { return }
                attemptUseToday(
                    templateID: pendingTodayChoice.templateID,
                    source: pendingTodayChoice.source,
                    forceReplace: true
                )
            }

            Button("Keep Current Plan", role: .cancel) {
                pendingTodayChoice = nil
            }
        } message: {
            Text("Today already has edits or completed checklist items. Replacing it will rebuild the day from the selected template.")
        }
    }

    private func todaySection(model: TemplatesScreenModel) -> some View {
        let chooser = model.todayChooser
        let currentTitle = chooser.currentSelection?.title
            ?? (chooser.requiresSelection ? "Choose today’s template" : "No template today")

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Today",
                subtitle: chooser.requiresSelection
                    ? "Choose today explicitly before Now and Today enter running mode."
                    : "Switch today quickly without leaving the template library."
            )

            TemplateCard(isEmphasized: true) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.todaySchedule.date.titleText)
                            .font(.headline)

                        Text(chooser.requiresSelection ? "Waiting for today’s choice" : "Today is already running")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    TemplateBadge(
                        title: chooser.requiresSelection ? "Choose Today" : "Running",
                        tint: chooser.requiresSelection ? Color.accentColor : .secondary
                    )
                }

                VStack(spacing: 10) {
                    TodaySummaryRow(title: "Current", value: currentTitle)
                    TodaySummaryRow(
                        title: "Default",
                        value: chooser.defaultTemplate?.title ?? "No weekday default"
                    )

                    if let overrideTitle = model.todaySchedule.overrideTemplateTitle {
                        TodaySummaryRow(title: "Special Day", value: overrideTitle)
                    }
                }

                if let currentSelection = chooser.currentSelection {
                    TemplateCandidateSummaryBlock(
                        template: currentSelection,
                        showCurrentBadge: true,
                        showDefaultBadge: currentSelection.isDefaultForToday,
                        showWeekdays: false
                    )
                } else if !chooser.requiresSelection {
                    Text("Today is intentionally empty until you pick another template.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let defaultTemplate = chooser.defaultTemplate {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recommended Default")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TemplateCandidateSummaryBlock(
                            template: defaultTemplate,
                            showCurrentBadge: defaultTemplate.isCurrentForToday,
                            showDefaultBadge: true,
                            showWeekdays: false
                        )

                        Button {
                            attemptUseToday(
                                templateID: defaultTemplate.id,
                                source: .confirmedDefault,
                                forceReplace: false
                            )
                        } label: {
                            Label(
                                defaultTemplate.isCurrentForToday ? "Using Today" : "Use Default",
                                systemImage: "checkmark.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(defaultTemplate.isCurrentForToday)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Switch")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if chooser.availableTemplates.isEmpty {
                        Text("Save a recent suggestion first to make quick template switches available here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(chooser.availableTemplates) { template in
                                Button {
                                    attemptUseToday(
                                        templateID: template.id,
                                        source: template.isDefaultForToday ? .confirmedDefault : .pickedTemplate,
                                        forceReplace: false
                                    )
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(template.title)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            if let timeRangeText = template.timeRangeText {
                                                Text(timeRangeText)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer(minLength: 8)

                                        if template.isCurrentForToday {
                                            TemplateBadge(title: "Current", tint: Color.accentColor)
                                        } else if template.isDefaultForToday {
                                            TemplateBadge(title: "Default", tint: .secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                                .disabled(template.isCurrentForToday)
                            }
                        }
                    }
                }

                if chooser.canChooseNoTemplate {
                    Button {
                        attemptUseToday(
                            templateID: nil,
                            source: .noTemplate,
                            forceReplace: false
                        )
                    } label: {
                        Label("No Template Today", systemImage: "square.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func savedTemplatesSection(model: TemplatesScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Saved Templates",
                subtitle: model.savedTemplates.isEmpty
                    ? "Save a recent suggestion first to build your reusable library."
                    : "Each template stays readable at a glance so you can choose today, set tomorrow, or edit in place."
            )

            if model.savedTemplates.isEmpty {
                ContentUnavailableView(
                    "No Saved Templates",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Recent Suggestions will help you turn strong recent days into reusable templates.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            } else {
                ForEach(model.savedTemplates) { template in
                    SavedTemplateCard(
                        template: template,
                        isSelectedForTomorrow: model.tomorrowSchedule.finalTemplateID == template.id,
                        onUseToday: {
                            attemptUseToday(
                                templateID: template.id,
                                source: template.isDefaultForToday ? .confirmedDefault : .pickedTemplate,
                                forceReplace: false
                            )
                        },
                        onUseTomorrow: {
                            store.setTomorrowOverride(templateID: template.id)
                        },
                        onEdit: {
                            sheet = .edit(templateID: template.id)
                        }
                    )
                }
            }
        }
    }

    private func defaultsSection(model: TemplatesScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Defaults & Schedule",
                subtitle: "Defaults shape the usual week. Use a special-day override only when a date should deliberately break from the default."
            )

            TemplateScheduleCard(
                schedule: model.todaySchedule,
                heading: "Today",
                actionTitle: "Rebuild Today"
            ) {
                store.rebuildDayPlan(for: model.todaySchedule.date)
            }

            TemplateScheduleCard(
                schedule: model.tomorrowSchedule,
                heading: "Tomorrow",
                actionTitle: "Regenerate Tomorrow"
            ) {
                store.regenerateFutureDayPlan(for: model.tomorrowSchedule.date)
            }

            if model.savedTemplates.isEmpty {
                ContentUnavailableView(
                    "No Templates to Assign",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Save a template before setting defaults or special-day overrides.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            } else {
                WeekdayRulesCard(
                    templates: store.savedTemplates,
                    selectionForWeekday: weekdaySelection(for:)
                )

                TemplateOverrideCard(
                    heading: "Today Special Day",
                    helpText: "Use this only when today should temporarily ignore the weekday default.",
                    templates: store.savedTemplates,
                    selection: overrideSelection(for: model.todaySchedule.date, shouldRebuildDayPlan: true)
                )

                TemplateOverrideCard(
                    heading: "Tomorrow Special Day",
                    helpText: "Use this only when tomorrow should temporarily ignore the weekday default.",
                    templates: store.savedTemplates,
                    selection: overrideSelection(for: model.tomorrowSchedule.date, shouldRebuildDayPlan: false)
                )
            }
        }
    }

    private func recentSuggestionsSection(model: TemplatesScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Recent Suggestions",
                subtitle: model.suggestedTemplates.isEmpty
                    ? "Suggestions appear when recent days have enough reusable structure."
                    : "Turn strong recent days into reusable templates once they are worth keeping."
            )

            if model.suggestedTemplates.isEmpty {
                ContentUnavailableView(
                    "No Recent Suggestions",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("Keep running real days and save the ones that become repeatable.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            } else {
                ForEach(model.suggestedTemplates) { template in
                    SuggestedTemplateCard(template: template) {
                        sheet = .save(sourceDate: template.sourceDate)
                    }
                }
            }
        }
    }

    private func attemptUseToday(
        templateID: UUID?,
        source: DayTemplateSelectionSource,
        forceReplace: Bool
    ) {
        do {
            let result = try store.chooseTemplate(
                for: LocalDay.today(),
                templateID: templateID,
                source: source,
                forceReplace: forceReplace
            )

            switch result {
            case .applied:
                pendingTodayChoice = nil

            case .requiresConfirmation:
                pendingTodayChoice = PendingTodayChoice(
                    templateID: templateID,
                    source: source
                )
            }
        } catch {
            store.presentError(error)
        }
    }

    private func weekdaySelection(for weekday: Weekday) -> Binding<UUID?> {
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

private struct PendingTodayChoice: Equatable {
    let templateID: UUID?
    let source: DayTemplateSelectionSource
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

private struct TodaySummaryRow: View {
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

private struct SuggestedTemplateCard: View {
    let template: SuggestedTemplateSummary
    let onSave: () -> Void

    var body: some View {
        TemplateCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.sourceDate.titleText)
                        .font(.headline)

                    Text(template.timeRangeText ?? "No resolved time range")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                TemplateBadge(title: "Suggestion", tint: .secondary)
            }

            TemplatePreviewRow(
                titles: template.previewTitles,
                totalCount: template.totalBlockCount
            )

            TemplateStatsRow(stats: [
                .init(title: "\(template.baseBlockCount) base", systemImage: "rectangle.stack"),
                .init(title: "\(template.overlayCount) overlay", systemImage: "square.stack.3d.up"),
                .init(title: "\(template.taskBlueprintCount) tasks", systemImage: "checklist"),
                .init(title: "\(template.reminderCount) reminders", systemImage: "bell")
            ])

            Button {
                onSave()
            } label: {
                Label("Save Template", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct SavedTemplateCard: View {
    let template: TemplateCandidateSummary
    let isSelectedForTomorrow: Bool
    let onUseToday: () -> Void
    let onUseTomorrow: () -> Void
    let onEdit: () -> Void

    var body: some View {
        TemplateCard(isEmphasized: template.isCurrentForToday || isSelectedForTomorrow) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.title)
                        .font(.headline)

                    if let timeRangeText = template.timeRangeText {
                        Text(timeRangeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        badges
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        badges
                    }
                }
            }

            TemplatePreviewRow(
                titles: template.previewTitles,
                totalCount: template.totalBlockCount
            )

            TemplateStatsRow(stats: [
                .init(title: "\(template.baseBlockCount) base", systemImage: "rectangle.stack"),
                .init(title: "\(template.overlayCount) overlay", systemImage: "square.stack.3d.up"),
                .init(title: "\(template.taskCount) tasks", systemImage: "checklist"),
                .init(title: "\(template.reminderCount) reminders", systemImage: "bell")
            ])

            if !template.assignedWeekdays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Defaults")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TemplateChipRow(titles: template.assignedWeekdays.map(\.shortName))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    useTodayButton
                    useTomorrowButton
                    editButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    useTodayButton
                    useTomorrowButton
                    editButton
                }
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if template.isCurrentForToday {
            TemplateBadge(title: "Current", tint: Color.accentColor)
        }

        if template.isDefaultForToday {
            TemplateBadge(title: "Default", tint: .secondary)
        }

        if isSelectedForTomorrow {
            TemplateBadge(title: "Tomorrow", tint: .secondary)
        }
    }

    private var useTodayButton: some View {
        Button(template.isCurrentForToday ? "Using Today" : "Use Today", action: onUseToday)
            .buttonStyle(.borderedProminent)
            .disabled(template.isCurrentForToday)
    }

    private var useTomorrowButton: some View {
        Button(isSelectedForTomorrow ? "Using Tomorrow" : "Use Tomorrow", action: onUseTomorrow)
            .buttonStyle(.bordered)
            .disabled(isSelectedForTomorrow)
    }

    private var editButton: some View {
        Button("Edit", action: onEdit)
            .buttonStyle(.bordered)
    }
}

private struct TemplateCandidateSummaryBlock: View {
    let template: TemplateCandidateSummary
    let showCurrentBadge: Bool
    let showDefaultBadge: Bool
    let showWeekdays: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(.headline)

                    if let timeRangeText = template.timeRangeText {
                        Text(timeRangeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        summaryBadges
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        summaryBadges
                    }
                }
            }

            TemplatePreviewRow(
                titles: template.previewTitles,
                totalCount: template.totalBlockCount
            )

            TemplateStatsRow(stats: [
                .init(title: "\(template.baseBlockCount) base", systemImage: "rectangle.stack"),
                .init(title: "\(template.overlayCount) overlay", systemImage: "square.stack.3d.up"),
                .init(title: "\(template.taskCount) tasks", systemImage: "checklist"),
                .init(title: "\(template.reminderCount) reminders", systemImage: "bell")
            ])

            if showWeekdays && !template.assignedWeekdays.isEmpty {
                TemplateChipRow(titles: template.assignedWeekdays.map(\.shortName))
            }
        }
    }

    @ViewBuilder
    private var summaryBadges: some View {
        if showCurrentBadge {
            TemplateBadge(title: "Current", tint: Color.accentColor)
        }

        if showDefaultBadge {
            TemplateBadge(title: "Default", tint: .secondary)
        }
    }
}

private struct WeekdayRulesCard: View {
    let templates: [SavedDayTemplate]
    let selectionForWeekday: (Weekday) -> Binding<UUID?>

    var body: some View {
        TemplateCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Defaults")
                    .font(.headline)

                Text("Choose the template that each weekday should fall back to by default.")
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
                    Text("Follow Defaults").tag(UUID?.none)
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
                    TemplateBadge(title: "Special Day", tint: Color.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("\(heading) Uses")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(schedule.finalTemplateTitle ?? "No template assigned")
                    .font(.title3.weight(.semibold))

                Text(schedule.overrideTemplateTitle != nil
                    ? "A special-day override is currently taking precedence over the weekday default."
                    : "\(heading) will follow the weekday default unless you add a special-day override.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ScheduleValueRow(title: "Default", value: schedule.weekdayTemplateTitle ?? "None")
                ScheduleValueRow(title: "Special Day", value: schedule.overrideTemplateTitle ?? "None")
                ScheduleValueRow(title: "Current Result", value: schedule.finalTemplateTitle ?? "None")
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

            if titles.isEmpty {
                Text("No visible blocks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
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
            TemplateBadge(title: title, tint: Color.accentColor)
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
    TemplatesRootView()
        .environment(PreviewSupport.store(tab: .library))
}

#Preview("Templates Root - Choosing Today") {
    TemplatesRootView()
        .environment(
            PreviewSupport.store(
                tab: .library,
                document: ThingStructDocument(
                    savedTemplates: PreviewSupport.seededDocument().savedTemplates,
                    weekdayRules: PreviewSupport.seededDocument().weekdayRules
                )
            )
        )
}
