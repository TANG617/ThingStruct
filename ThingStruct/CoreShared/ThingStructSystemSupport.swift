import Foundation

struct ThingStructSystemTaskReference: Equatable, Sendable {
    let date: LocalDay
    let blockID: UUID
    let taskID: UUID
    let title: String
    let blockTitle: String
    let layerIndex: Int
    let isCurrentBlock: Bool
}

struct ThingStructSystemBlockReference: Equatable, Sendable {
    let date: LocalDay
    let blockID: UUID
    let title: String
    let layerIndex: Int
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let timeRangeText: String
    let isBlank: Bool
    let isCurrent: Bool
    let remainingTaskCount: Int
}

struct ThingStructSystemNowSnapshot: Equatable, Sendable {
    let date: LocalDay
    let minuteOfDay: Int
    let currentBlock: ThingStructSystemBlockReference?
    let activeBlocks: [ThingStructSystemBlockReference]
    let topTask: ThingStructSystemTaskReference?
    let remainingTaskCount: Int
    let statusMessage: String?
}

struct ThingStructSystemActionExecutor {
    let client: ThingStructSharedDocumentClient

    init(client: ThingStructSharedDocumentClient = .appLive) {
        self.client = client
    }

    func currentSnapshot(at date: Date = .now) throws -> ThingStructSystemNowSnapshot {
        try client.systemNowSnapshot(at: date)
    }

    func openURL(for route: ThingStructSystemRoute) -> URL? {
        route.url
    }

    func openCurrentBlockURL(
        at date: Date = .now,
        source: ThingStructSystemSource? = nil
    ) throws -> URL? {
        guard let block = try client.currentBlockReference(at: date) else {
            return nil
        }

        return ThingStructSystemRoute.today(
            date: block.date,
            blockID: block.blockID,
            taskID: nil,
            source: source
        ).url
    }

    @discardableResult
    func completeCurrentTask(at date: Date = .now) throws -> ThingStructSystemTaskReference? {
        try client.completeTopTask(at: date)
    }
}

extension ThingStructSharedDocumentClient {
    func systemNowSnapshot(at date: Date) throws -> ThingStructSystemNowSnapshot {
        let now = try nowScreenModel(at: date)
        let activeBlocks = now.activeChain.map { item in
            let remainingTaskCount = now.taskSections
                .filter { $0.id == item.id }
                .flatMap(\.tasks)
                .filter { !$0.isCompleted }
                .count

            return ThingStructSystemBlockReference(
                date: now.date,
                blockID: item.id,
                title: item.title,
                layerIndex: item.layerIndex,
                startMinuteOfDay: item.startMinuteOfDay,
                endMinuteOfDay: item.endMinuteOfDay,
                timeRangeText: formattedTimeRange(
                    startMinuteOfDay: item.startMinuteOfDay,
                    endMinuteOfDay: item.endMinuteOfDay
                ),
                isBlank: item.isBlank,
                isCurrent: item.isCurrent,
                remainingTaskCount: remainingTaskCount
            )
        }

        let topTask = prioritizedTaskReference(from: now)

        return ThingStructSystemNowSnapshot(
            date: now.date,
            minuteOfDay: now.minuteOfDay,
            currentBlock: activeBlocks.first(where: \.isCurrent) ?? activeBlocks.first,
            activeBlocks: activeBlocks,
            topTask: topTask,
            remainingTaskCount: now.taskSections
                .flatMap(\.tasks)
                .filter { !$0.isCompleted }
                .count,
            statusMessage: now.statusMessage
        )
    }

    func currentBlockReference(at date: Date) throws -> ThingStructSystemBlockReference? {
        try systemNowSnapshot(at: date).currentBlock
    }

    func topTaskReference(at date: Date) throws -> ThingStructSystemTaskReference? {
        try systemNowSnapshot(at: date).topTask
    }

    @discardableResult
    func completeTopTask(
        at date: Date,
        completedAt: Date = .now
    ) throws -> ThingStructSystemTaskReference? {
        guard let task = try topTaskReference(at: date) else {
            return nil
        }

        let changed = try toggleTask(
            on: task.date,
            blockID: task.blockID,
            taskID: task.taskID,
            completedAt: completedAt
        )

        return changed ? task : nil
    }

    func topTaskReference(
        on date: LocalDay,
        in blockID: UUID
    ) throws -> ThingStructSystemTaskReference? {
        let generatedAt = date.date() ?? .now
        let document = try documentPreparedForNow(at: generatedAt)

        guard
            let block = document.dayPlan(for: date)?.blocks.first(where: { $0.id == blockID }),
            !block.isCancelled
        else {
            return nil
        }

        guard let task = block.tasks.sorted(by: { taskSort(lhs: $0, rhs: $1) }).first(where: { !$0.isCompleted }) else {
            return nil
        }

        return ThingStructSystemTaskReference(
            date: date,
            blockID: blockID,
            taskID: task.id,
            title: task.title,
            blockTitle: block.title,
            layerIndex: block.layerIndex,
            isCurrentBlock: false
        )
    }

    @discardableResult
    func completeTopTask(
        on date: LocalDay,
        in blockID: UUID,
        completedAt: Date = .now
    ) throws -> ThingStructSystemTaskReference? {
        guard let task = try topTaskReference(on: date, in: blockID) else {
            return nil
        }

        let changed = try toggleTask(
            on: date,
            blockID: blockID,
            taskID: task.taskID,
            completedAt: completedAt
        )

        return changed ? task : nil
    }

    private func prioritizedTaskReference(
        from now: NowScreenModel
    ) -> ThingStructSystemTaskReference? {
        let prioritizedSections: [NowTaskSection]
        if let current = now.taskSections.first(where: \.isCurrent) {
            prioritizedSections = [current] + now.taskSections.filter { $0.id != current.id }
        } else {
            prioritizedSections = now.taskSections
        }

        for section in prioritizedSections {
            guard let task = section.tasks.first(where: { !$0.isCompleted }) else {
                continue
            }

            return ThingStructSystemTaskReference(
                date: now.date,
                blockID: section.id,
                taskID: task.id,
                title: task.title,
                blockTitle: section.title,
                layerIndex: section.layerIndex,
                isCurrentBlock: section.isCurrent
            )
        }

        return nil
    }

    private func formattedTimeRange(
        startMinuteOfDay: Int,
        endMinuteOfDay: Int
    ) -> String {
        "\(formattedTime(startMinuteOfDay)) - \(formattedTime(endMinuteOfDay))"
    }

    private func formattedTime(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func taskSort(lhs: TaskItem, rhs: TaskItem) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
