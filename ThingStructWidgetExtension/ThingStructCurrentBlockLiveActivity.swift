import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct ThingStructCurrentBlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThingStructCurrentBlockActivityAttributes.self) { context in
            ThingStructLiveActivityLockScreenView(context: context)
                .widgetURL(URL(string: context.attributes.deepLinkURL))
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let topTaskTitle = context.state.topTaskTitle {
                            HStack(spacing: 8) {
                                Image(systemName: "checklist")
                                    .foregroundStyle(.tint)

                                Text(topTaskTitle)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Button(intent: CompleteCurrentTaskControlIntent()) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        } else if let statusMessage = context.state.statusMessage {
                            Text(statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(context.state.remainingMinutes)m")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Text("\(min(context.state.remainingTaskCount, 9))")
                    .font(.caption2.weight(.semibold))
            }
            .widgetURL(URL(string: context.attributes.deepLinkURL))
            .keylineTint(.orange)
        }
    }
}

@available(iOS 16.1, *)
private struct ThingStructLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ThingStructCurrentBlockActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.state.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(context.state.remainingMinutes)m")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
            }

            Text(context.state.timeRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            taskSection
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var taskSection: some View {
        if let topTaskTitle = context.state.topTaskTitle {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label(taskSummary, systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button(intent: CompleteCurrentTaskControlIntent()) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(.tint.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete current task")
                }

                Text(topTaskTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(taskSummary)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let statusMessage = context.state.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var taskSummary: String {
        context.state.remainingTaskCount == 0
            ? "All caught up"
            : "\(context.state.remainingTaskCount) tasks left"
    }

    private var statusIconName: String {
        context.state.remainingTaskCount == 0
            ? "checkmark.circle.fill"
            : "info.circle.fill"
    }
}

#Preview("Live Activity Active", as: .content, using: ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    blockID: UUID().uuidString,
    deepLinkURL: ThingStructSystemRoute.now(source: .liveActivity).url?.absoluteString ?? "thingstruct://now"
)) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    ThingStructCurrentBlockActivityAttributes.ContentState(
        title: "Focus Sprint",
        timeRangeText: "09:00 - 11:00",
        remainingMinutes: 42,
        remainingTaskCount: 2,
        topTaskTitle: "Ship system surfaces",
        statusMessage: nil
    )
}

#Preview("Live Activity Caught Up", as: .content, using: ThingStructCurrentBlockActivityAttributes(
    dateISO: "2026-03-22",
    blockID: UUID().uuidString,
    deepLinkURL: ThingStructSystemRoute.now(source: .liveActivity).url?.absoluteString ?? "thingstruct://now"
)) {
    ThingStructCurrentBlockLiveActivity()
} contentStates: {
    ThingStructCurrentBlockActivityAttributes.ContentState(
        title: "AM",
        timeRangeText: "10:00 - 23:00",
        remainingMinutes: 442,
        remainingTaskCount: 0,
        topTaskTitle: nil,
        statusMessage: "No incomplete tasks in this chain."
    )
}
