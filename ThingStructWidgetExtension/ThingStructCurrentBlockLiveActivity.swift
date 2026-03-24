import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct ThingStructCurrentBlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThingStructCurrentBlockActivityAttributes.self) { context in
            ThingStructLiveActivityLockScreenView(context: context)
                .widgetURL(context.deepLinkURL)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.remainingMinutes)m")
                        .font(.headline.monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ThingStructLiveActivityExpandedContent(context: context)
                }
            } compactLeading: {
                Image(systemName: context.state.remainingTaskCount == 0 ? "checkmark.circle.fill" : "bolt.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(context.state.remainingMinutes)m")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                if context.state.remainingTaskCount == 0 {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                } else {
                    Text("\(min(context.state.remainingTaskCount, 9))")
                        .font(.caption2.weight(.semibold))
                }
            }
            .widgetURL(context.deepLinkURL)
            .keylineTint(.orange)
        }
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ThingStructCurrentBlockActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.state.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(context.state.remainingMinutes)m")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
            }

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
        context.state.remainingTaskCount == 0
            ? "All caught up"
            : "\(context.state.remainingTaskCount) tasks left"
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityExpandedContent: View {
    let context: ActivityViewContext<ThingStructCurrentBlockActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(context.state.timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(context.state.remainingTaskCount == 0 ? "Caught up" : "\(context.state.remainingTaskCount) left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let displaySourceBlockTitle = state.displaySourceBlockTitle {
                Label("From \(displaySourceBlockTitle)", systemImage: "arrow.turn.down.right")
                    .font(metaFont.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            if let displayNote = state.displayNote {
                noteRow(displayNote)
            }

            if let taskIntent = state.displayTaskIntent, let displayTaskTitle = state.displayTaskTitle {
                taskRow(title: displayTaskTitle, intent: taskIntent)
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
        HStack(alignment: .center, spacing: 10) {
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
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.tint.opacity(0.14))
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
        state.remainingTaskCount == 0
            ? "All caught up"
            : "\(state.remainingTaskCount) tasks left"
    }

    private var completionIconName: String {
        state.remainingTaskCount == 0
            ? "checkmark.circle.fill"
            : "info.circle.fill"
    }
}

@available(iOS 16.1, *)
private extension ActivityViewContext<ThingStructCurrentBlockActivityAttributes> {
    var deepLinkURL: URL? {
        URL(string: state.deepLinkURL)
    }
}

@available(iOS 16.1, *)
private extension ThingStructCurrentBlockActivityAttributes.ContentState {
    var displayTaskIntent: CompleteLiveActivityTaskIntent? {
        guard
            let displayTaskDateISO,
            let displayTaskBlockID,
            let displayTaskID
        else {
            return nil
        }

        return CompleteLiveActivityTaskIntent(
            dateISO: displayTaskDateISO,
            blockID: displayTaskBlockID,
            taskID: displayTaskID
        )
    }
}

#Preview("Live Activity Top Layer", as: .content, using: ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    currentBlockID: UUID().uuidString
)) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    ThingStructCurrentBlockActivityAttributes.ContentState(
        title: "Focus Sprint",
        timeRangeText: "09:00 - 11:00",
        remainingMinutes: 42,
        remainingTaskCount: 2,
        deepLinkURL: ThingStructSystemRoute.today(
            date: LocalDay(year: 2026, month: 3, day: 22),
            blockID: UUID(),
            taskID: UUID(),
            source: .liveActivity
        ).url?.absoluteString ?? "thingstruct://today",
        displayNote: "Protect this block for deep work and keep distractions outside the sprint.",
        displayTaskTitle: "Ship system surfaces",
        displayTaskDateISO: "2026-03-22",
        displayTaskBlockID: UUID().uuidString,
        displayTaskID: UUID().uuidString,
        displaySourceBlockTitle: nil,
        statusMessage: nil
    )
}

#Preview("Live Activity Fallback Layer", as: .content, using: ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    currentBlockID: UUID().uuidString
)) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    ThingStructCurrentBlockActivityAttributes.ContentState(
        title: "Launch Window",
        timeRangeText: "10:00 - 12:00",
        remainingMinutes: 65,
        remainingTaskCount: 3,
        deepLinkURL: ThingStructSystemRoute.today(
            date: LocalDay(year: 2026, month: 3, day: 22),
            blockID: UUID(),
            taskID: UUID(),
            source: .liveActivity
        ).url?.absoluteString ?? "thingstruct://today",
        displayNote: "Base layer still owns the next meaningful work after the upper layer wrapped.",
        displayTaskTitle: "Review progress",
        displayTaskDateISO: "2026-03-22",
        displayTaskBlockID: UUID().uuidString,
        displayTaskID: UUID().uuidString,
        displaySourceBlockTitle: "Afternoon",
        statusMessage: nil
    )
}

#Preview("Live Activity Caught Up", as: .content, using: ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    currentBlockID: UUID().uuidString
)) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    ThingStructCurrentBlockActivityAttributes.ContentState(
        title: "AM",
        timeRangeText: "10:00 - 23:00",
        remainingMinutes: 442,
        remainingTaskCount: 0,
        deepLinkURL: ThingStructSystemRoute.today(
            date: LocalDay(year: 2026, month: 3, day: 22),
            blockID: UUID(),
            taskID: nil,
            source: .liveActivity
        ).url?.absoluteString ?? "thingstruct://today",
        displayNote: nil,
        displayTaskTitle: nil,
        displayTaskDateISO: nil,
        displayTaskBlockID: nil,
        displayTaskID: nil,
        displaySourceBlockTitle: nil,
        statusMessage: "No incomplete tasks in this chain."
    )
}

#Preview("Live Activity Long Copy", as: .content, using: ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    currentBlockID: UUID().uuidString
)) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    ThingStructCurrentBlockActivityAttributes.ContentState(
        title: "Deep Focus Sprint For System Surface Polish",
        timeRangeText: "09:00 - 11:00",
        remainingMinutes: 42,
        remainingTaskCount: 2,
        deepLinkURL: ThingStructSystemRoute.today(
            date: LocalDay(year: 2026, month: 3, day: 22),
            blockID: UUID(),
            taskID: UUID(),
            source: .liveActivity
        ).url?.absoluteString ?? "thingstruct://today",
        displayNote: "Keep the copy concise enough for Lock Screen, but still clear about why this work matters right now.",
        displayTaskTitle: "Ship the lock screen layout without clipping the last line",
        displayTaskDateISO: "2026-03-22",
        displayTaskBlockID: UUID().uuidString,
        displayTaskID: UUID().uuidString,
        displaySourceBlockTitle: nil,
        statusMessage: nil
    )
}
