import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct ThingStructCurrentBlockLiveActivity: Widget {
    private var themeTint: Color {
        AppTintPreset.current.tintColor
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThingStructCurrentBlockActivityAttributes.self) { context in
            ThingStructLiveActivityLockScreenView(context: context)
                .widgetURL(context.tapURL)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .padding(.top, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ThingStructLiveActivitySummaryBadge(state: context.state)
                        .padding(.trailing, 8)
                        .padding(.top, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ThingStructLiveActivityExpandedContent(context: context)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: context.state.compactIconName)
                    .foregroundStyle(themeTint)
            } compactTrailing: {
                Text(context.state.compactTrailingText)
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: context.state.minimalIconName)
                    .font(.caption2.weight(.semibold))
            }
            .widgetURL(context.tapURL)
            .keylineTint(themeTint)
        }
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivitySummaryBadge: View {
    let state: ThingStructCurrentBlockActivityAttributes.ContentState

    private var themeTint: Color {
        AppTintPreset.current.tintColor
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.compactIconName)
                .imageScale(.small)

            Text(state.summaryBadgeText)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(themeTint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(themeTint.opacity(0.12), in: Capsule())
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ThingStructCurrentBlockActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context.state.title)
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 10) {
                Text(context.state.timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(summaryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ThingStructLiveActivityDetailContent(
                state: context.state,
                noteLineLimit: 3,
                taskLineLimit: 2,
                noteFont: .subheadline,
                taskFont: .body,
                metaFont: .caption
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var summaryTitle: String {
        context.state.statusSummary
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityExpandedContent: View {
    let context: ActivityViewContext<ThingStructCurrentBlockActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.state.timeRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ThingStructLiveActivityDetailContent(
                state: context.state,
                noteLineLimit: 2,
                taskLineLimit: 1,
                noteFont: .caption,
                taskFont: .subheadline,
                metaFont: .caption2
            )
        }
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityDetailContent: View {
    let state: ThingStructCurrentBlockActivityAttributes.ContentState
    let noteLineLimit: Int
    let taskLineLimit: Int
    let noteFont: Font
    let taskFont: Font
    let metaFont: Font

    private var themeTint: Color {
        AppTintPreset.current.tintColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let displaySourceBlockTitle = state.displaySourceBlockTitle {
                Label("From \(displaySourceBlockTitle)", systemImage: "arrow.turn.down.right")
                    .font(metaFont.weight(.semibold))
                    .foregroundStyle(themeTint)
                    .lineLimit(1)
            }

            if let displayNote = state.displayNote {
                noteRow(displayNote)
            }

            if let taskIntent = state.actionableTaskIntent, let taskTitle = state.actionableTaskTitle {
                taskRow(title: taskTitle, intent: taskIntent)
            } else {
                completionState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text")
                .font(metaFont.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(text)
                .font(noteFont)
                .foregroundStyle(.secondary)
                .lineLimit(noteLineLimit)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }

    private func taskRow(
        title: String,
        intent: CompleteLiveActivityTaskIntent
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Current task", systemImage: "checklist")
                    .font(metaFont.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(title)
                    .font(taskFont)
                    .foregroundStyle(.primary)
                    .lineLimit(taskLineLimit)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Button(intent: intent) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeTint)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(themeTint.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete current live activity task")
        }
    }

    private var completionState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(completionTitle, systemImage: completionIconName)
                .font(taskFont.weight(.semibold))
                .lineLimit(1)

            if let statusMessage = state.statusMessage {
                Text(statusMessage)
                    .font(metaFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var completionTitle: String {
        state.statusSummary
    }

    private var completionIconName: String {
        state.remainingTaskCount == 0
            ? "checkmark.circle.fill"
            : "checklist"
    }
}

@available(iOS 16.1, *)
private extension ActivityViewContext<ThingStructCurrentBlockActivityAttributes> {
    var tapURL: URL? {
        URL(string: state.tapURL)
    }
}

@available(iOS 16.1, *)
private extension ThingStructCurrentBlockActivityAttributes.ContentState {
    var hasActionableTask: Bool {
        actionableTaskIntent != nil && actionableTaskTitle != nil
    }

    var actionableTaskIntent: CompleteLiveActivityTaskIntent? {
        guard
            let actionableTaskDateISO,
            let actionableTaskBlockID,
            let actionableTaskID
        else {
            return nil
        }

        return CompleteLiveActivityTaskIntent(
            dateISO: actionableTaskDateISO,
            blockID: actionableTaskBlockID,
            taskID: actionableTaskID
        )
    }

    var compactIconName: String {
        if hasActionableTask {
            return "checkmark.circle"
        }
        return remainingTaskCount == 0 ? "checkmark.circle.fill" : "info.circle"
    }

    var minimalIconName: String {
        if hasActionableTask {
            return "checkmark.circle"
        }
        return remainingTaskCount == 0 ? "checkmark" : "ellipsis.circle"
    }

    var compactTrailingText: String {
        remainingTaskCount == 0 ? "Done" : "\(min(remainingTaskCount, 9))"
    }

    var summaryBadgeText: String {
        remainingTaskCount == 0 ? "Done" : "\(remainingTaskCount) left"
    }

    var statusSummary: String {
        remainingTaskCount == 0 ? "All caught up" : "\(remainingTaskCount) tasks left"
    }
}

@available(iOS 16.1, *)
private let liveActivityPreviewAttributes = ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    currentBlockID: UUID().uuidString
)

@available(iOS 16.1, *)
private extension ThingStructCurrentBlockActivityAttributes.ContentState {
    static func preview(
        title: String,
        timeRangeText: String,
        remainingTaskCount: Int,
        displayNote: String?,
        actionableTaskTitle: String?,
        displaySourceBlockTitle: String?,
        statusMessage: String?
    ) -> Self {
        let taskBlockID = UUID().uuidString
        let taskID = UUID().uuidString

        return ThingStructCurrentBlockActivityAttributes.ContentState(
            title: title,
            timeRangeText: timeRangeText,
            remainingTaskCount: remainingTaskCount,
            tapURL: ThingStructSystemRoute.now(source: .liveActivity).url?.absoluteString ?? "thingstruct://now",
            displayNote: displayNote,
            actionableTaskTitle: actionableTaskTitle,
            actionableTaskDateISO: actionableTaskTitle == nil ? nil : "2026-03-22",
            actionableTaskBlockID: actionableTaskTitle == nil ? nil : taskBlockID,
            actionableTaskID: actionableTaskTitle == nil ? nil : taskID,
            displaySourceBlockTitle: displaySourceBlockTitle,
            statusMessage: statusMessage
        )
    }

    static let previewTopLayer = preview(
        title: "Focus Sprint",
        timeRangeText: "09:00 - 11:00",
        remainingTaskCount: 2,
        displayNote: "Protect this block for deep work and keep distractions outside the sprint.",
        actionableTaskTitle: "Ship system surfaces",
        displaySourceBlockTitle: nil,
        statusMessage: nil
    )

    static let previewFallbackLayer = preview(
        title: "Launch Window",
        timeRangeText: "10:00 - 12:00",
        remainingTaskCount: 3,
        displayNote: "Base layer still owns the next meaningful work after the upper layer wrapped.",
        actionableTaskTitle: "Review progress",
        displaySourceBlockTitle: "Afternoon",
        statusMessage: nil
    )

    static let previewCaughtUp = preview(
        title: "AM",
        timeRangeText: "10:00 - 23:00",
        remainingTaskCount: 0,
        displayNote: nil,
        actionableTaskTitle: nil,
        displaySourceBlockTitle: nil,
        statusMessage: "No incomplete tasks in this chain."
    )

    static let previewLongCopy = preview(
        title: "Deep Focus Sprint For System Surface Polish",
        timeRangeText: "09:00 - 11:00",
        remainingTaskCount: 2,
        displayNote: "Keep the copy concise enough for Lock Screen, but still clear about why this work matters right now.",
        actionableTaskTitle: "Ship the lock screen layout without clipping the last line",
        displaySourceBlockTitle: nil,
        statusMessage: nil
    )
}

#Preview("Live Activity Top Layer", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewTopLayer
}

#Preview("Live Activity Fallback Layer", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewFallbackLayer
}

#Preview("Live Activity Caught Up", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewCaughtUp
}

#Preview("Live Activity Long Copy", as: .content, using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewLongCopy
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewTopLayer
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewFallbackLayer
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: liveActivityPreviewAttributes) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    .previewCaughtUp
}
