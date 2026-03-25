import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// 这是 Live Activity 的 UI 定义文件。
// 和普通 Widget 的最大区别是：
// - 数据来源是 `ActivityAttributes + ContentState`
// - 展示位置包括锁屏和 Dynamic Island
// - 内容会随着 activity state 更新而变化
@available(iOS 16.1, *)
struct ThingStructCurrentBlockLiveActivity: Widget {
    private var themeTint: Color {
        AppTintPreset.current.tintColor
    }

    var body: some WidgetConfiguration {
        // `ActivityConfiguration` 相当于 Live Activity 世界里的根配置入口。
        ActivityConfiguration(for: ThingStructCurrentBlockActivityAttributes.self) { context in
            ThingStructLiveActivityLockScreenView(context: context)
                .widgetURL(context.tapURL)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Dynamic Island 展开态的左上角区域。
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
                    // 展开态底部放更详细的信息和动作按钮。
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
        // 这是一个纯展示用的小徽章，不带业务逻辑。
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
        // 锁屏态比 Dynamic Island 空间更大，所以排版更舒展。
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
        // 这是 Dynamic Island 展开态底部内容。
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
        // 细节区会按“来源块 -> note -> 当前任务/完成状态”的顺序显示。
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
        // note 行只是一个小型复合视图，抽成私有 helper 让主体更易读。
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
        // Live Activity 按钮同样通过 intent 触发，而不是直接持有 store/repository。
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
        // 没有可直接操作的任务时，显示一个只读状态区。
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
        // activity 点击跳回 app 时，系统只知道这里提供的 URL。
        URL(string: state.tapURL)
    }
}

@available(iOS 16.1, *)
private extension ThingStructCurrentBlockActivityAttributes.ContentState {
    var hasActionableTask: Bool {
        actionableTaskIntent != nil && actionableTaskTitle != nil
    }

    var actionableTaskIntent: CompleteLiveActivityTaskIntent? {
        // 只有在 state 里携带了完整的日期/block/task 标识时，才生成可执行 intent。
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
        // 紧凑态图标根据是否有任务可操作、是否已全部完成来变化。
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
        // 预览数据和正式 activity 使用同一个 ContentState 结构，
        // 这能让预览更接近真实运行效果。
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

// 这些预览覆盖了几类关键状态：
// - 顶层 block 有可完成任务
// - 任务来源回退到下层/上层块
// - 全部完成
// - 长文本挤压
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
