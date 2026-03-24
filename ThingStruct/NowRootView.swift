import SwiftUI

// `NowRootView` renders a live "what matters right now?" screen.
//
// Two important SwiftUI ideas show up here:
// 1. The view itself stays declarative: it asks the store for a `NowScreenModel`
//    and renders that model.
// 2. `TimelineView` periodically re-evaluates the body so the screen can react to time.
struct NowRootView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // Every minute, `TimelineView` re-runs this subtree with a new `context.date`.
                RootScreenContainer(
                    isLoaded: store.isLoaded,
                    loadingTitle: "Loading Now",
                    loadingSystemImage: "clock",
                    loadingDescription: "Refreshing your active block and task chain.",
                    errorTitle: "Unable to Load Now",
                    retry: store.reload,
                    load: {
                        try store.nowScreenModel(at: context.date)
                    }
                ) { model in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            NowNotesSectionView(sections: model.noteSections)
                            NowTasksSectionView(
                                sections: model.taskSections,
                                statusMessage: model.statusMessage,
                                activeChain: model.activeChain
                            ) { blockID, taskID in
                                store.toggleTask(on: model.date, blockID: blockID, taskID: taskID)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .navigationTitle(model.date.nowNavigationTitle)
                }
            }
            .navigationTitle(LocalDay.today().nowNavigationTitle)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct NowNotesSectionView: View {
    let sections: [NowNoteSection]

    var body: some View {
        // SwiftUI encourages composing many tiny views like this.
        // Think of them as cheap rendering functions with local structure.
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                ForEach(sections) { section in
                    NowNoteCard(section: section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NowTasksSectionView: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let sections: [NowTaskSection]
    let statusMessage: String?
    let activeChain: [NowChainItem]
    let onToggle: (UUID, UUID) -> Void

    private var remainingTaskCount: Int {
        sections
            .flatMap(\.tasks)
            .filter { !$0.isCompleted }
            .count
    }

    private var currentItem: NowChainItem? {
        activeChain.first(where: \.isCurrent) ?? activeChain.first
    }

    private var emptyStyle: LayerVisualStyle {
        guard let currentItem else {
            return LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true, preset: tintPreset)
        }

        return LayerVisualStyle.forBlock(
            layerIndex: currentItem.layerIndex,
            isBlank: currentItem.isBlank,
            preset: tintPreset
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The task section is intentionally derived from a presentation model,
            // not from raw `TimeBlock` values, so it can focus purely on rendering.
            HStack(alignment: .firstTextBaseline) {
                Text("Tasks")
                    .font(.title2.weight(.semibold))

                Spacer()

                if !sections.isEmpty {
                    Text(remainingTaskCount > 0 ? "\(remainingTaskCount) remaining" : "All caught up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if sections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing to act on right now")
                        .font(.headline)

                    Text(statusMessage ?? "No tasks right now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(emptyStyle.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(emptyStyle.border, lineWidth: 1)
                )
            } else {
                ForEach(sections) { section in
                    NowTaskCard(section: section) { taskID in
                        onToggle(section.id, taskID)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NowNoteCard: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let section: NowNoteSection

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: section.layerIndex,
            isBlank: section.isBlank,
            preset: tintPreset
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(style.marker)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(section.isCurrent ? .subheadline.weight(.semibold) : .subheadline.weight(.medium))
                    .lineLimit(2)

                Text(section.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style.border.opacity(0.42), lineWidth: 1)
        )
    }
}

private struct NowTaskCard: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let section: NowTaskSection
    let onToggle: (UUID) -> Void

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: section.layerIndex,
            isBlank: false,
            preset: tintPreset
        )
    }

    private var incompleteTasks: [TaskItem] {
        section.tasks.filter { !$0.isCompleted }
    }

    private var completedTaskCount: Int {
        section.tasks.count - incompleteTasks.count
    }

    private var completedSummary: String {
        let count = section.tasks.count
        return count == 1 ? "1 task completed" : "\(count) tasks completed"
    }

    var body: some View {
        if section.isComplete {
            compactCompletedCard
        } else {
            expandedTaskCard
        }
    }

    private var expandedTaskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(section.isCurrent ? .headline : .subheadline.weight(.semibold))
                        .lineLimit(2)

                    if completedTaskCount > 0 {
                        Text(completedTaskCount == 1 ? "1 task completed" : "\(completedTaskCount) tasks completed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if section.isCurrent {
                    NowBadge(
                        title: "Current",
                        background: style.badgeBackground,
                        foreground: style.badgeForeground
                    )
                }
            }

            ForEach(incompleteTasks) { task in
                Button {
                    onToggle(task.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "circle")
                            .font(section.isCurrent ? .title3 : .body)
                            .foregroundStyle(style.accent)
                            .padding(.top, 1)

                        Text(task.title)
                            .font(section.isCurrent ? .body : .subheadline)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .foregroundStyle(.primary)
            }
        }
        .padding(section.isCurrent ? 18 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.strongSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(section.isCurrent ? style.accent : style.border, lineWidth: section.isCurrent ? 1.5 : 1)
        )
    }

    private var compactCompletedCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(style.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(section.isCurrent ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(completedSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if section.isCurrent {
                NowBadge(
                    title: "Current",
                    background: style.badgeBackground,
                    foreground: style.badgeForeground
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(section.isCurrent ? style.border : style.border.opacity(0.78), lineWidth: section.isCurrent ? 1.25 : 1)
        )
    }
}

private struct NowBadge: View {
    let title: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }
}

@MainActor
private enum NowPreviewFactory {
    static func layeredDocument() -> ThingStructDocument {
        let day = PreviewSupport.referenceDay
        let baseID = UUID()
        let overlayID = UUID()

        let plan = try! DayPlanEngine.resolved(
            DayPlan(
                date: day,
                blocks: [
                    TimeBlock(
                        id: baseID,
                        layerIndex: 0,
                        title: "Maker Day",
                        note: "Base plan note that stays visible while overlays stack on top.",
                        tasks: [
                            TaskItem(title: "Review priorities"),
                            TaskItem(title: "Keep admin light", order: 1),
                            TaskItem(title: "Pack the essentials", order: 2)
                        ],
                        timing: .absolute(
                            startMinuteOfDay: 0,
                            requestedEndMinuteOfDay: 23 * 60 + 59
                        )
                    ),
                    TimeBlock(
                        id: overlayID,
                        parentBlockID: baseID,
                        layerIndex: 1,
                        title: "Launch Window",
                        note: "Top layer note should stay visible, but its completed tasks should collapse into a compact summary.",
                        tasks: [
                            TaskItem(title: "Confirm release notes", isCompleted: true),
                            TaskItem(title: "Watch live metrics", order: 1, isCompleted: true)
                        ],
                        timing: .relative(
                            startOffsetMinutes: 0,
                            requestedDurationMinutes: 23 * 60 + 59
                        )
                    )
                ]
            )
        )

        return ThingStructDocument(dayPlans: [plan])
    }

    static func notesOnlyDocument() -> ThingStructDocument {
        let day = PreviewSupport.referenceDay
        let baseID = UUID()
        let overlayID = UUID()

        let plan = try! DayPlanEngine.resolved(
            DayPlan(
                date: day,
                blocks: [
                    TimeBlock(
                        id: baseID,
                        layerIndex: 0,
                        title: "Planning Day",
                        note: "A calm base layer with notes but no task list.",
                        timing: .absolute(
                            startMinuteOfDay: 0,
                            requestedEndMinuteOfDay: 23 * 60 + 59
                        )
                    ),
                    TimeBlock(
                        id: overlayID,
                        parentBlockID: baseID,
                        layerIndex: 1,
                        title: "Thinking Block",
                        note: "Use this preview to check the Notes-first layout and empty task state.",
                        timing: .relative(
                            startOffsetMinutes: 0,
                            requestedDurationMinutes: 23 * 60 + 59
                        )
                    )
                ]
            )
        )

        return ThingStructDocument(dayPlans: [plan])
    }

    static func layeredModel() -> NowScreenModel {
        try! ThingStructPresentation.nowScreenModel(
            document: layeredDocument(),
            date: PreviewSupport.referenceDay,
            minuteOfDay: 12 * 60
        )
    }

    static func notesOnlyModel() -> NowScreenModel {
        try! ThingStructPresentation.nowScreenModel(
            document: notesOnlyDocument(),
            date: PreviewSupport.referenceDay,
            minuteOfDay: 12 * 60
        )
    }
}

#Preview("Now Root") {
    NowRootView()
        .environment(PreviewSupport.store(tab: .now))
}

#Preview("Now Root - Layer Stack") {
    NowRootView()
        .environment(
            PreviewSupport.store(
                tab: .now,
                document: NowPreviewFactory.layeredDocument()
            )
        )
}

#Preview("Now Root - Notes First") {
    NowRootView()
        .environment(
            PreviewSupport.store(
                tab: .now,
                document: NowPreviewFactory.notesOnlyDocument()
            )
        )
}

#Preview("Now Root - Empty Day") {
    NowRootView()
        .environment(
            PreviewSupport.store(
                tab: .now,
                document: ThingStructDocument()
            )
        )
}

#Preview("Now Root - Loading") {
    NowRootView()
        .environment(PreviewSupport.store(tab: .now, loaded: false))
}

#Preview("Now Notes Section") {
    let model = NowPreviewFactory.layeredModel()

    ScrollView {
        NowNotesSectionView(sections: model.noteSections)
            .padding(20)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Now Note Card") {
    let model = NowPreviewFactory.layeredModel()

    NowNoteCard(section: model.noteSections[0])
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Now Tasks Section") {
    let model = NowPreviewFactory.layeredModel()

    ScrollView {
        NowTasksSectionView(
            sections: model.taskSections,
            statusMessage: model.statusMessage,
            activeChain: model.activeChain,
            onToggle: { _, _ in }
        )
        .padding(20)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Now Task Card - Current Done") {
    let model = NowPreviewFactory.layeredModel()

    NowTaskCard(section: model.taskSections[0], onToggle: { _ in })
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Now Task Card - Active") {
    let model = NowPreviewFactory.layeredModel()

    NowTaskCard(section: model.taskSections[1], onToggle: { _ in })
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Now Tasks Section - Empty") {
    let model = NowPreviewFactory.notesOnlyModel()

    ScrollView {
        NowTasksSectionView(
            sections: model.taskSections,
            statusMessage: model.statusMessage,
            activeChain: model.activeChain,
            onToggle: { _, _ in }
        )
        .padding(20)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
