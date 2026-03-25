import AppIntents
import SwiftUI
import WidgetKit

// `TimelineEntry` 是 WidgetKit 的核心概念之一。
// 你可以把它理解成：“在某个时刻，Widget 应该显示什么内容”。
struct ThingStructNowWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ThingStructWidgetSnapshot
}

// `TimelineProvider` 负责给系统提供：
// - 占位内容 placeholder
// - 预览/配置时的 snapshot
// - 正式运行时的一条 timeline
// Widget 不是一直常驻执行的，系统会按 timeline 按需拉取内容。
struct ThingStructNowWidgetProvider: TimelineProvider {
    private let repository = ThingStructDocumentRepository.widgetLive

    func placeholder(in context: Context) -> ThingStructNowWidgetEntry {
        ThingStructNowWidgetEntry(
            date: .now,
            snapshot: .placeholder()
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ThingStructNowWidgetEntry) -> Void
    ) {
        // `getSnapshot` 常用于小组件库预览、编辑配置时的即时展示。
        completion(makeEntry(at: .now, isPreview: context.isPreview))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ThingStructNowWidgetEntry>) -> Void
    ) {
        // timeline 可以看成“未来一段时间内的刷新计划”。
        let entry = makeEntry(at: .now, isPreview: context.isPreview)
        let refreshDate = ThingStructWidgetSnapshotBuilder.nextRefreshDate(
            for: entry.snapshot,
            referenceDate: entry.date
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(refreshDate)
            )
        )
    }

    private func makeEntry(
        at date: Date,
        isPreview: Bool
    ) -> ThingStructNowWidgetEntry {
        // 预览模式下不碰真实仓库，直接用占位数据。
        if isPreview {
            return ThingStructNowWidgetEntry(
                date: date,
                snapshot: .placeholder()
            )
        }

        do {
            return ThingStructNowWidgetEntry(
                date: date,
                snapshot: try repository.widgetSnapshot(
                    at: date,
                    maxTaskCount: 3
                )
            )
        } catch {
            // Widget 读不到文档时不要崩，退化成“提示用户打开 app”即可。
            return ThingStructNowWidgetEntry(
                date: date,
                snapshot: ThingStructWidgetSnapshot(
                    date: LocalDay(date: date),
                    minuteOfDay: date.minuteOfDay,
                    currentBlockTitle: nil,
                    currentBlockTimeRangeText: nil,
                    blocks: [],
                    remainingTaskCount: 0,
                    tasks: [],
                    statusMessage: "Open ThingStruct to finish setting up the widget."
                )
            )
        }
    }
}

// 真正注册给系统的小组件配置。
struct ThingStructNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ThingStructSharedConfig.widgetKind,
            provider: ThingStructNowWidgetProvider()
        ) { entry in
            // `entry` 是系统按 timeline 注入到视图里的当前快照。
            ThingStructNowWidgetEntryView(entry: entry)
                .widgetURL(entry.snapshot.destinationURL)
        }
        .configurationDisplayName("ThingStruct Now")
        .description("See your current block and check off tasks without opening the app.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular
        ])
    }
}

// 这是 widget 的根视图。
// 与 app 内普通 SwiftUI View 类似，但运行约束更严格：
// - 不能随意做副作用
// - 数据要来自 entry
// - 需要适配多种 widget family
private struct ThingStructNowWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ThingStructNowWidgetEntry

    private var shownTasks: [ThingStructWidgetTaskItem] {
        // 小组件空间非常有限，所以这里只截前 3 条。
        Array(entry.snapshot.tasks.prefix(3))
    }

    private var shownBlocks: [ThingStructWidgetBlockItem] {
        Array(entry.snapshot.blocks.prefix(3))
    }

    private var currentBlock: ThingStructWidgetBlockItem? {
        entry.snapshot.blocks.first(where: \.isCurrent) ?? entry.snapshot.blocks.first
    }

    private var currentStyle: LayerVisualStyle {
        currentBlock.map(style(for:)) ?? LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true)
    }

    private var backgroundStyle: LayerVisualStyle {
        entry.snapshot.blocks.last.map(style(for:)) ?? currentStyle
    }

    private var remainingSummary: String {
        entry.snapshot.remainingTaskCount == 0
            ? "All caught up"
            : "\(entry.snapshot.remainingTaskCount) remaining"
    }

    private var accessoryInlineText: String {
        // accessoryInline 空间极窄，所以只保留一行核心文本。
        if let title = entry.snapshot.currentBlockTitle,
           let timeRange = entry.snapshot.currentBlockTimeRangeText {
            let endTime = timeRange.split(separator: "-").last?
                .trimmingCharacters(in: .whitespaces) ?? timeRange
            return "\(title) until \(endTime)"
        }

        return entry.snapshot.statusMessage ?? "Open ThingStruct"
    }

    private var accessoryCircularValue: String {
        entry.snapshot.remainingTaskCount == 0
            ? "0"
            : "\(min(entry.snapshot.remainingTaskCount, 9))"
    }

    var body: some View {
        // WidgetKit 会告诉我们当前 family，
        // 同一个 widget 入口通常要为不同尺寸准备不同布局。
        switch family {
        case .systemSmall:
            smallLayout
        case .accessoryInline:
            accessoryInlineLayout
        case .accessoryRectangular:
            accessoryRectangularLayout
        case .accessoryCircular:
            accessoryCircularLayout
        default:
            mediumLayout
        }
    }

    private var accessoryInlineLayout: some View {
        Text(accessoryInlineText)
            .lineLimit(1)
            // `containerBackground(for: .widget)` 是 iOS 17 之后的 widget 背景声明方式。
            .containerBackground(for: .widget) {
                Color.clear
            }
    }

    private var accessoryRectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.snapshot.currentBlockTitle ?? "No plan")
                .font(.headline)
                .lineLimit(1)

            Text(entry.snapshot.currentBlockTimeRangeText ?? (entry.snapshot.statusMessage ?? "Open ThingStruct"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(remainingSummary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(currentStyle.accent)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var accessoryCircularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 1) {
                Image(systemName: entry.snapshot.remainingTaskCount == 0 ? "checkmark" : "checklist")
                    .font(.caption2.weight(.semibold))

                Text(accessoryCircularValue)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(currentStyle.accent)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if shownBlocks.isEmpty {
                emptyState(isCompact: true)
            } else {
                smallBlockStack
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    private var mediumLayout: some View {
        // 中号组件空间更大，可以左边展示当前 block，右边列任务。
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                header
                currentBlockSummary
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Group {
                if shownTasks.isEmpty {
                    emptyState(isCompact: false)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(shownTasks) { item in
                            taskRow(item, showBlockTitle: !item.isCurrentBlock)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(currentStyle.badgeForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(currentStyle.badgeBackground, in: Capsule())

            Spacer(minLength: 8)

            Text(remainingSummary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(currentStyle.accent.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var currentBlockSummary: some View {
        // 当前 block 的信息卡片。
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot.currentBlockTitle ?? "No plan for right now")
                .font(.headline.weight(.semibold))
                .lineLimit(2)

            if let timeRange = entry.snapshot.currentBlockTimeRangeText {
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(currentStyle.badgeForeground)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(currentStyle.strongSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(currentBlock == nil ? currentStyle.border : currentStyle.accent.opacity(0.38), lineWidth: 1.2)
        )
    }

    private var smallBlockStack: some View {
        // 小号组件用“叠卡片”来暗示 overlay 层次。
        let reversed = Array(shownBlocks.reversed())

        return ZStack(alignment: .topLeading) {
            ForEach(Array(reversed.enumerated()), id: \.element.id) { index, item in
                let depth = CGFloat(reversed.count - index - 1)
                blockStackCard(item, isFront: item.id == currentBlock?.id)
                    .offset(x: depth * 10, y: depth * 12)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyState(isCompact: Bool) -> some View {
        // 没有任务可显示时，用状态文案代替空列表。
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.remainingTaskCount == 0 ? "Nothing to check off" : "Tasks are up to date")
                .font(isCompact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))

            Text(entry.snapshot.statusMessage ?? "Open ThingStruct to review the full plan.")
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(currentStyle.badgeForeground)
                .lineLimit(isCompact ? 4 : 3)
        }
        .padding(isCompact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(currentStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(currentStyle.border, lineWidth: 1)
        )
    }

    private func taskRow(
        _ item: ThingStructWidgetTaskItem,
        showBlockTitle: Bool
    ) -> some View {
        let style = style(for: item)

        return Button(
            // widget 里的按钮不是普通闭包按钮，而是 intent 驱动的系统动作按钮。
            intent: ToggleTaskCompletionIntent(
                dateISO: item.dateISO,
                blockID: item.blockID,
                taskID: item.taskID
            )
        ) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(item.isCompleted ? style.marker : style.accent)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .strikethrough(item.isCompleted, color: .secondary)

                    if showBlockTitle {
                        Text(item.blockTitle)
                            .font(.caption2)
                            .foregroundStyle(style.badgeForeground)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (item.isCurrentBlock ? style.strongSurface : style.surface),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(item.isCurrentBlock ? style.accent.opacity(0.45) : style.border.opacity(0.82), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var widgetBackground: some View {
        // 背景仍然是纯声明式 SwiftUI 视图树。
        ZStack {
            LinearGradient(
                colors: [
                    currentStyle.surface,
                    backgroundStyle.surface,
                    currentStyle.strongSurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(currentStyle.badgeBackground.opacity(0.42))
                .frame(width: 160, height: 160)
                .offset(x: 68, y: 84)
                .blur(radius: 8)
        }
    }

    private func blockStackCard(
        _ item: ThingStructWidgetBlockItem,
        isFront: Bool
    ) -> some View {
        // 前景卡片和背景卡片只是在样式上有所区别，数据模型还是同一个。
        let style = style(for: item)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if item.isCurrent {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style.badgeForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(style.badgeBackground, in: Capsule())
                }

                Spacer(minLength: 0)

                if item.hasIncompleteTasks {
                    Circle()
                        .fill(style.accent)
                        .frame(width: 7, height: 7)
                }
            }

            Text(item.title)
                .font(isFront ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)

            Text(item.timeRangeText)
                .font(.caption2)
                .foregroundStyle(style.badgeForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isFront ? 10 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isFront ? style.strongSurface : style.surface).opacity(isFront ? 0.98 : 0.92),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isFront ? style.accent.opacity(0.42) : style.border.opacity(0.86), lineWidth: 1)
        )
    }

    private func style(for block: ThingStructWidgetBlockItem) -> LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: block.isBlank)
    }

    private func style(for task: ThingStructWidgetTaskItem) -> LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: task.layerIndex, isBlank: task.isBlank)
    }
}

// `#Preview` 是 Xcode 的 SwiftUI 预览声明。
// 这里给不同尺寸准备几组典型状态，方便独立调 widget 布局。
#Preview("Small - Block Stack", as: .systemSmall) {
    ThingStructNowWidget()
} timeline: {
    ThingStructNowWidgetEntry(
        date: .now,
        snapshot: .previewFocused
    )
}

#Preview("Medium - Empty State", as: .systemMedium) {
    ThingStructNowWidget()
} timeline: {
    ThingStructNowWidgetEntry(
        date: .now,
        snapshot: .previewEmpty
    )
}

private extension ThingStructWidgetSnapshot {
    var destinationURL: URL? {
        // 点击 widget 后跳回 app 时，优先把用户带到“当前块/当前任务”。
        let currentBlockID = blocks.first(where: \.isCurrent)?.blockID ?? blocks.first?.blockID
        let currentTaskID = tasks.first(where: \.isCurrentBlock)?.taskID ?? tasks.first?.taskID

        if let currentBlockID, let blockID = UUID(uuidString: currentBlockID) {
            return ThingStructSystemRoute.today(
                date: date,
                blockID: blockID,
                taskID: currentTaskID.flatMap(UUID.init(uuidString:)),
                source: .widget
            ).url
        }

        return ThingStructSystemRoute.now(source: .widget).url
    }

    static var previewFocused: ThingStructWidgetSnapshot {
        // 以下几个 preview 数据只是为了预览不同视觉状态，不参与正式业务。
        ThingStructWidgetSnapshot(
            date: LocalDay(year: 2026, month: 3, day: 22),
            minuteOfDay: 10 * 60,
            currentBlockTitle: "Focus Sprint",
            currentBlockTimeRangeText: "09:00 - 11:00",
            blocks: [
                ThingStructWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Focus Sprint",
                    layerIndex: 2,
                    timeRangeText: "09:00 - 11:00",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
                ),
                ThingStructWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Maker Session",
                    layerIndex: 1,
                    timeRangeText: "08:30 - 11:30",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                ),
                ThingStructWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Morning",
                    layerIndex: 0,
                    timeRangeText: "08:00 - 12:00",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                )
            ],
            remainingTaskCount: 3,
            tasks: [
                ThingStructWidgetTaskItem(
                    dateISO: "2026-03-22",
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Ship widget integration",
                    blockTitle: "Focus Sprint",
                    layerIndex: 2,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                ),
                ThingStructWidgetTaskItem(
                    dateISO: "2026-03-22",
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Verify simulator install",
                    blockTitle: "Focus Sprint",
                    layerIndex: 2,
                    isBlank: false,
                    isCompleted: true,
                    isCurrentBlock: true
                ),
                ThingStructWidgetTaskItem(
                    dateISO: "2026-03-22",
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Write follow-up notes",
                    blockTitle: "Morning",
                    layerIndex: 0,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: false
                )
            ],
            statusMessage: nil
        )
    }

    static var previewEmpty: ThingStructWidgetSnapshot {
        ThingStructWidgetSnapshot(
            date: LocalDay(year: 2026, month: 3, day: 22),
            minuteOfDay: 13 * 60 + 30,
            currentBlockTitle: "Lunch",
            currentBlockTimeRangeText: "13:00 - 14:00",
            blocks: [
                ThingStructWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Lunch",
                    layerIndex: 0,
                    timeRangeText: "13:00 - 14:00",
                    isBlank: false,
                    hasIncompleteTasks: false,
                    isCurrent: true
                )
            ],
            remainingTaskCount: 0,
            tasks: [],
            statusMessage: "No incomplete tasks in this chain."
        )
    }
}

#Preview("Accessory Inline", as: .accessoryInline) {
    ThingStructNowWidget()
} timeline: {
    ThingStructNowWidgetEntry(
        date: .now,
        snapshot: .previewFocused
    )
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    ThingStructNowWidget()
} timeline: {
    ThingStructNowWidgetEntry(
        date: .now,
        snapshot: .previewFocused
    )
}

#Preview("Accessory Circular", as: .accessoryCircular) {
    ThingStructNowWidget()
} timeline: {
    ThingStructNowWidgetEntry(
        date: .now,
        snapshot: .previewFocused
    )
}
