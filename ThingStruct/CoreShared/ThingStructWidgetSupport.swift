import Foundation

struct ThingStructWidgetTaskItem: Identifiable, Equatable, Sendable {
    var dateISO: String
    var blockID: String
    var taskID: String
    var title: String
    var blockTitle: String
    var layerIndex: Int
    var isBlank: Bool
    var isCompleted: Bool
    var isCurrentBlock: Bool

    var id: String {
        taskID
    }
}

struct ThingStructWidgetBlockItem: Identifiable, Equatable, Sendable {
    var blockID: String
    var title: String
    var layerIndex: Int
    var timeRangeText: String
    var isBlank: Bool
    var hasIncompleteTasks: Bool
    var isCurrent: Bool

    var id: String {
        blockID
    }
}

struct ThingStructWidgetSnapshot: Equatable, Sendable {
    var date: LocalDay
    var minuteOfDay: Int
    var currentBlockTitle: String?
    var currentBlockTimeRangeText: String?
    var blocks: [ThingStructWidgetBlockItem]
    var remainingTaskCount: Int
    var tasks: [ThingStructWidgetTaskItem]
    var statusMessage: String?

    static func placeholder() -> ThingStructWidgetSnapshot {
        ThingStructWidgetSnapshot(
            date: LocalDay.today(),
            minuteOfDay: Date.now.minuteOfDay,
            currentBlockTitle: "Now",
            currentBlockTimeRangeText: "09:00 - 10:30",
            blocks: [
                ThingStructWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Focus Sprint",
                    layerIndex: 1,
                    timeRangeText: "09:00 - 10:30",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
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
            remainingTaskCount: 2,
            tasks: [
                ThingStructWidgetTaskItem(
                    dateISO: LocalDay.today().description,
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Finish the current task",
                    blockTitle: "Focus",
                    layerIndex: 1,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                ),
                ThingStructWidgetTaskItem(
                    dateISO: LocalDay.today().description,
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Prepare the next step",
                    blockTitle: "Focus",
                    layerIndex: 1,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                )
            ],
            statusMessage: nil
        )
    }
}

enum ThingStructWidgetSnapshotBuilder {
    static func makeSnapshot(
        from now: NowScreenModel,
        maxTaskCount: Int
    ) -> ThingStructWidgetSnapshot {
        let blocks = now.activeChain.map { item in
            ThingStructWidgetBlockItem(
                blockID: item.id.uuidString,
                title: item.title,
                layerIndex: item.layerIndex,
                timeRangeText: formattedTimeRange(
                    startMinuteOfDay: item.startMinuteOfDay,
                    endMinuteOfDay: item.endMinuteOfDay
                ),
                isBlank: item.isBlank,
                hasIncompleteTasks: item.hasIncompleteTasks,
                isCurrent: item.isCurrent
            )
        }
        let currentBlock = blocks.first(where: \.isCurrent) ?? blocks.first
        let prioritizedSections = prioritizedTaskSections(from: now.taskSections)
        let tasks = prioritizedSections
            .flatMap { section in
                prioritizedTasks(from: section).map { task in
                    ThingStructWidgetTaskItem(
                        dateISO: now.date.description,
                        blockID: section.id.uuidString,
                        taskID: task.id.uuidString,
                        title: task.title,
                        blockTitle: section.title,
                        layerIndex: section.layerIndex,
                        isBlank: false,
                        isCompleted: task.isCompleted,
                        isCurrentBlock: section.isCurrent
                    )
                }
            }

        return ThingStructWidgetSnapshot(
            date: now.date,
            minuteOfDay: now.minuteOfDay,
            currentBlockTitle: currentBlock?.title,
            currentBlockTimeRangeText: currentBlock?.timeRangeText,
            blocks: blocks,
            remainingTaskCount: now.taskSections
                .flatMap(\.tasks)
                .filter { !$0.isCompleted }
                .count,
            tasks: Array(tasks.prefix(max(0, maxTaskCount))),
            statusMessage: tasks.isEmpty ? now.statusMessage : nil
        )
    }

    static func nextRefreshDate(
        for snapshot: ThingStructWidgetSnapshot,
        referenceDate: Date
    ) -> Date {
        let fallback = referenceDate.addingTimeInterval(15 * 60)

        guard
            let currentBlockTimeRangeText = snapshot.currentBlockTimeRangeText,
            let endMinuteOfDay = endMinuteOfDay(from: currentBlockTimeRangeText),
            let boundary = snapshot.date.date(minuteOfDay: endMinuteOfDay)
        else {
            return fallback
        }

        return min(boundary, fallback)
    }

    private static func prioritizedTaskSections(
        from sections: [NowTaskSection]
    ) -> [NowTaskSection] {
        guard let currentSection = sections.first(where: \.isCurrent) else {
            return sections
        }

        return [currentSection] + sections.filter { $0.id != currentSection.id }
    }

    private static func prioritizedTasks(
        from section: NowTaskSection
    ) -> [TaskItem] {
        section.tasks.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isCompleted != rhs.element.isCompleted {
                    return rhs.element.isCompleted
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func formattedTimeRange(
        startMinuteOfDay: Int,
        endMinuteOfDay: Int
    ) -> String {
        "\(formattedTime(startMinuteOfDay)) - \(formattedTime(endMinuteOfDay))"
    }

    private static func formattedTime(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func endMinuteOfDay(from timeRange: String) -> Int? {
        let pieces = timeRange.components(separatedBy: " - ")
        guard pieces.count == 2 else {
            return nil
        }

        let endPieces = pieces[1].split(separator: ":")
        guard
            endPieces.count == 2,
            let hour = Int(endPieces[0]),
            let minute = Int(endPieces[1])
        else {
            return nil
        }

        return hour * 60 + minute
    }
}

extension ThingStructDocumentRepository {
    func widgetSnapshot(
        at date: Date,
        maxTaskCount: Int
    ) throws -> ThingStructWidgetSnapshot {
        let now = try preparedNowScreenModel(at: date)
        return ThingStructWidgetSnapshotBuilder.makeSnapshot(
            from: now,
            maxTaskCount: maxTaskCount
        )
    }
}
