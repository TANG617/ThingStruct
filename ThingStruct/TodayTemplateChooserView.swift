import SwiftUI

struct TodayTemplateChooserView: View {
    @Environment(ThingStructStore.self) private var store

    let date: LocalDay
    var onApplied: (() -> Void)? = nil

    @State private var pendingChoice: PendingChoice?

    var body: some View {
        Group {
            if let chooser = try? store.todayTemplateChooserModel(for: date) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(chooser: chooser)

                        if let currentSelection = chooser.currentSelection {
                            summaryCard(
                                title: "Current Today",
                                template: currentSelection,
                                accentColor: Color.accentColor
                            )
                        }

                        if let defaultTemplate = chooser.defaultTemplate {
                            defaultCard(defaultTemplate)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Templates")
                                .font(.title3.weight(.semibold))

                            ForEach(chooser.availableTemplates) { template in
                                candidateCard(template)
                            }
                        }

                        Button {
                            attemptChoice(
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .confirmationDialog(
                    "Replace today’s current plan?",
                    isPresented: Binding(
                        get: { pendingChoice != nil },
                        set: { if !$0 { pendingChoice = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Replace Today’s Plan", role: .destructive) {
                        guard let pendingChoice else { return }
                        attemptChoice(
                            templateID: pendingChoice.templateID,
                            source: pendingChoice.source,
                            forceReplace: true
                        )
                    }
                    Button("Keep Current Plan", role: .cancel) {
                        pendingChoice = nil
                    }
                } message: {
                    Text("Today already has edits or completed checklist items. Replacing it will rebuild the day from the selected template.")
                }
            } else {
                RecoverableErrorView(
                    title: "Unable to Load Today’s Templates",
                    message: "ThingStruct could not prepare the choices for today.",
                    retry: store.reload
                )
            }
        }
    }

    private func header(chooser: DayTemplateChooserModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chooser.requiresSelection ? "Choose Today" : "Switch Today")
                .font(.largeTitle.weight(.bold))

            Text(chooser.date.titleText)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Pick the version of today you want to run. Once selected, ThingStruct will rebuild the day and return to execution.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func defaultCard(_ template: TemplateCandidateSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended Default")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(template.title)
                        .font(.headline)

                    if let timeRangeText = template.timeRangeText {
                        Text(timeRangeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Text("Default")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            chooserPreview(for: template)

            Button {
                attemptChoice(
                    templateID: template.id,
                    source: .confirmedDefault,
                    forceReplace: false
                )
            } label: {
                Label("Use Default", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1.5)
        )
    }

    private func candidateCard(_ template: TemplateCandidateSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
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

                HStack(spacing: 8) {
                    if template.isCurrentForToday {
                        chooserBadge(title: "Current", tint: Color.accentColor)
                    }

                    if template.isDefaultForToday {
                        chooserBadge(title: "Default", tint: .secondary)
                    }
                }
            }

            chooserPreview(for: template)
            chooserStats(for: template)

            Button {
                attemptChoice(
                    templateID: template.id,
                    source: .pickedTemplate,
                    forceReplace: false
                )
            } label: {
                Text(template.isCurrentForToday ? "Using Today" : "Use Today")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(template.isCurrentForToday)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func summaryCard(
        title: String,
        template: TemplateCandidateSummary,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(template.title)
                .font(.headline)

            if let timeRangeText = template.timeRangeText {
                Text(timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            chooserPreview(for: template)
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1.25)
        )
    }

    private func chooserPreview(for template: TemplateCandidateSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                previewChips(for: template)
            }

            VStack(alignment: .leading, spacing: 8) {
                previewChips(for: template)
            }
        }
    }

    @ViewBuilder
    private func previewChips(for template: TemplateCandidateSummary) -> some View {
        ForEach(template.previewTitles, id: \.self) { title in
            chooserBadge(title: title, tint: .primary, soft: false)
        }
    }

    private func chooserStats(for template: TemplateCandidateSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chooserBadge(title: "\(template.baseBlockCount) base", tint: .secondary)
                chooserBadge(title: "\(template.overlayCount) overlays", tint: .secondary)
                chooserBadge(title: "\(template.taskCount) tasks", tint: .secondary)
                chooserBadge(title: "\(template.reminderCount) reminders", tint: .secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                chooserBadge(title: "\(template.baseBlockCount) base", tint: .secondary)
                chooserBadge(title: "\(template.overlayCount) overlays", tint: .secondary)
                chooserBadge(title: "\(template.taskCount) tasks", tint: .secondary)
                chooserBadge(title: "\(template.reminderCount) reminders", tint: .secondary)
            }
        }
    }

    private func chooserBadge(
        title: String,
        tint: Color,
        soft: Bool = true
    ) -> some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tint.opacity(soft ? 0.12 : 0.08),
                in: Capsule()
            )
    }

    private func attemptChoice(
        templateID: UUID?,
        source: DayTemplateSelectionSource,
        forceReplace: Bool
    ) {
        do {
            let result = try store.chooseTemplate(
                for: date,
                templateID: templateID,
                source: source,
                forceReplace: forceReplace
            )

            switch result {
            case .applied:
                pendingChoice = nil
                onApplied?()

            case .requiresConfirmation:
                pendingChoice = PendingChoice(
                    templateID: templateID,
                    source: source
                )
            }
        } catch {
            store.presentError(error)
        }
    }
}

private struct PendingChoice: Equatable {
    let templateID: UUID?
    let source: DayTemplateSelectionSource
}

#Preview("Choose Today") {
    TodayTemplateChooserView(date: PreviewSupport.referenceDay)
        .environment(
            PreviewSupport.store(
                tab: .now,
                document: ThingStructDocument(
                    savedTemplates: PreviewSupport.seededDocument().savedTemplates,
                    weekdayRules: PreviewSupport.seededDocument().weekdayRules
                )
            )
        )
}
