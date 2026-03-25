import Foundation

// 这些 `ThingStructSystem*` 类型是“系统表面专用的中间结果”：
// 它们不直接等于业务模型，也不直接等于 SwiftUI 页面模型。
// 它们的存在是为了服务：
// - widget
// - live activity
// - shortcut / control / notification 动作
// 这些入口往往只需要“当前 block / 当前任务 / 跳转 URL”等有限信息。
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

struct ThingStructSystemLiveActivitySnapshot: Equatable, Sendable {
    let date: LocalDay
    let minuteOfDay: Int
    let currentBlock: ThingStructSystemBlockReference?
    let displayBlock: ThingStructSystemBlockReference?
    let displayTask: ThingStructSystemTaskReference?
    let displayNote: String?
    let displaySourceBlockTitle: String?
    let remainingTaskCount: Int
    let statusMessage: String?

    func tapURL(source: ThingStructSystemSource = .liveActivity) -> URL? {
        // Live Activity 整体点击时，默认跳回 Now 页面。
        ThingStructSystemRoute.now(source: source).url
    }

    func deepLinkURL(source: ThingStructSystemSource = .liveActivity) -> URL? {
        // 更细粒度的 deep link 优先级：
        // 任务 > 展示 block > 当前 block > Now
        if let displayTask {
            return ThingStructSystemRoute.today(
                date: displayTask.date,
                blockID: displayTask.blockID,
                taskID: displayTask.taskID,
                source: source
            ).url
        }

        if let displayBlock {
            return ThingStructSystemRoute.today(
                date: displayBlock.date,
                blockID: displayBlock.blockID,
                taskID: nil,
                source: source
            ).url
        }

        if let currentBlock {
            return ThingStructSystemRoute.today(
                date: currentBlock.date,
                blockID: currentBlock.blockID,
                taskID: nil,
                source: source
            ).url
        }

        return ThingStructSystemRoute.now(source: source).url
    }
}

// `ThingStructSystemActionExecutor` 是系统入口层的小门面(facade)。
// AppIntent / 快捷操作 / widget control 不直接碰 document，而是通过它拿结果。
struct ThingStructSystemActionExecutor {
    let repository: ThingStructDocumentRepository

    init(repository: ThingStructDocumentRepository = .appLive) {
        self.repository = repository
    }

    func currentSnapshot(at date: Date = .now) throws -> ThingStructSystemNowSnapshot {
        try repository.systemNowSnapshot(at: date)
    }

    func openURL(for route: ThingStructSystemRoute) -> URL? {
        // 这个方法很薄，但保留它能让调用方只依赖 executor，而不必关心 route 自身实现。
        route.url
    }

    func openCurrentBlockURL(
        at date: Date = .now,
        source: ThingStructSystemSource? = nil
    ) throws -> URL? {
        // 先问 repository“当前 block 是谁”，再生成 today deep link。
        guard let block = try repository.currentBlockReference(at: date) else {
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
        try repository.completeTopTask(at: date)
    }
}

extension ThingStructDocumentRepository {
    // 这里的 extension 很值得注意：
    // repository 仍然只负责“文档层”的读写，但系统层额外给它扩展了
    // “如何从文档推导系统 snapshot / 完成当前任务”这类能力。
    // 也就是说：存储对象本身不懂 UI，但系统支持层可以基于它做高层操作。
    @discardableResult
    func toggleTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now
    ) throws -> Bool {
        // 对 widget 而言，“切任务”意味着：
        // 1. 读最新 document
        // 2. 确保当天 plan 已 materialize
        // 3. 找到对应 task
        // 4. 翻转完成状态并写回
        guard try load() != nil else {
            return false
        }

        let outcome = try mutate { document in
            let prepared = try materializedDocument(
                from: document,
                for: date,
                generatedAt: completedAt
            )
            document = prepared.document

            guard let planIndex = document.dayPlans.firstIndex(where: { $0.date == date }) else {
                return false
            }
            guard let blockIndex = document.dayPlans[planIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
                return false
            }
            guard let taskIndex = document.dayPlans[planIndex].blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
                return false
            }

            document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
            document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].completedAt =
                document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted ? completedAt : nil
            document.dayPlans[planIndex].hasUserEdits = true
            return true
        }

        return outcome.value
    }

    @discardableResult
    func completeTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now
    ) throws -> Bool {
        // `completeTask` 和 `toggleTask` 的区别是：
        // - toggle 会翻转 true/false
        // - complete 只允许从 false -> true
        guard try load() != nil else {
            return false
        }

        let outcome = try mutate { document in
            try completeTask(
                on: date,
                blockID: blockID,
                taskID: taskID,
                completedAt: completedAt,
                in: &document
            )
        }

        return outcome.value
    }

    @discardableResult
    func completeTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now,
        in document: inout ThingStructDocument
    ) throws -> Bool {
        // 这个重载允许对“调用者已经持有的 document”就地修改，
        // 测试里会很常用，因为它避免真实文件 I/O。
        let prepared = try materializedDocument(
            from: document,
            for: date,
            generatedAt: completedAt
        )
        document = prepared.document

        guard let planIndex = document.dayPlans.firstIndex(where: { $0.date == date }) else {
            return false
        }
        guard let blockIndex = document.dayPlans[planIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
            return false
        }
        guard let taskIndex = document.dayPlans[planIndex].blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return false
        }

        guard !document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted else {
            return false
        }

        document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted = true
        document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].completedAt = completedAt
        document.dayPlans[planIndex].hasUserEdits = true
        return true
    }

    func systemNowSnapshot(at date: Date) throws -> ThingStructSystemNowSnapshot {
        // 先把 document 映射成 `NowScreenModel`，再映射成系统快照。
        // 这说明系统表面和页面其实共用了同一份“当前链路”理解。
        let now = try preparedNowScreenModel(at: date)
        return systemNowSnapshot(from: now)
    }

    func systemNowSnapshot(from now: NowScreenModel) -> ThingStructSystemNowSnapshot {
        // 这里把页面模型压缩成系统更关心的最小集合：
        // 当前 block、可见 block 链、顶部任务、剩余任务数。
        let activeBlocks = blockReferences(from: now)

        let topTask = prioritizedTaskReference(from: now)
        let remainingTaskCount = remainingTaskCount(from: now)

        return ThingStructSystemNowSnapshot(
            date: now.date,
            minuteOfDay: now.minuteOfDay,
            currentBlock: activeBlocks.first(where: \.isCurrent) ?? activeBlocks.first,
            activeBlocks: activeBlocks,
            topTask: topTask,
            remainingTaskCount: remainingTaskCount,
            statusMessage: now.statusMessage
        )
    }

    func liveActivitySnapshot(at date: Date) throws -> ThingStructSystemLiveActivitySnapshot {
        let now = try preparedNowScreenModel(at: date)
        return liveActivitySnapshot(from: now)
    }

    func liveActivitySnapshot(from now: NowScreenModel) -> ThingStructSystemLiveActivitySnapshot {
        // Live Activity 的展示规则和页面不同：
        // 它会在上层任务做完时向下回退到更低层 block/task/note。
        let activeBlocks = blockReferences(from: now)
        let blocksByID = Dictionary(uniqueKeysWithValues: activeBlocks.map { ($0.blockID, $0) })
        let remainingTaskCount = remainingTaskCount(from: now)
        let displaySelection = liveActivityDisplaySelection(
            from: now,
            blocksByID: blocksByID
        )
        let currentBlock = activeBlocks.first(where: \.isCurrent) ?? activeBlocks.first
        let displaySourceBlockTitle: String?
        if
            let currentBlock,
            let displayBlock = displaySelection?.block,
            currentBlock.blockID != displayBlock.blockID
        {
            displaySourceBlockTitle = displayBlock.title
        } else {
            displaySourceBlockTitle = nil
        }
        let statusMessage: String?
        if displaySelection != nil {
            statusMessage = nil
        } else if remainingTaskCount == 0, currentBlock != nil {
            statusMessage = "No incomplete tasks in this chain."
        } else {
            statusMessage = now.statusMessage
        }

        return ThingStructSystemLiveActivitySnapshot(
            date: now.date,
            minuteOfDay: now.minuteOfDay,
            currentBlock: currentBlock,
            displayBlock: displaySelection?.block,
            displayTask: displaySelection?.task,
            displayNote: displaySelection?.note,
            displaySourceBlockTitle: displaySourceBlockTitle,
            remainingTaskCount: remainingTaskCount,
            statusMessage: statusMessage
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
        // “完成当前任务”本质上是：
        // 先定位 topTask，再调用通用 completeTask。
        guard let task = try topTaskReference(at: date) else {
            return nil
        }

        let changed = try completeTask(
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
        // 这个版本用于通知/特定 block 操作，优先在指定 block 内找第一条未完成任务。
        let generatedAt = date.date() ?? .now
        let document = try preparedDocument(at: generatedAt)

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

        let changed = try completeTask(
            on: date,
            blockID: blockID,
            taskID: task.taskID,
            completedAt: completedAt
        )

        return changed ? task : nil
    }

    func preparedNowScreenModel(at date: Date) throws -> NowScreenModel {
        // “prepared” 的含义是：不仅加载 document，还会按需要自动 materialize 当天计划。
        let localDay = LocalDay(date: date)
        let document = try preparedDocument(at: date)
        return try ThingStructPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: date.minuteOfDay
        )
    }

    func preparedDocument(at date: Date) throws -> ThingStructDocument {
        // 对系统入口来说，“今天的计划应该随用随准备好”，
        // 所以这里即便从空 document 开始，也会尝试推导当天计划。
        let localDay = LocalDay(date: date)

        guard try load() != nil else {
            return try materializedDocument(
                from: ThingStructDocument(),
                for: localDay,
                generatedAt: date
            ).document
        }

        let outcome = try mutate { document in
            let prepared = try materializedDocument(
                from: document,
                for: localDay,
                generatedAt: date
            )
            document = prepared.document
            return prepared.didMaterialize
        }

        return outcome.document
    }

    private func materializedDocument(
        from document: ThingStructDocument,
        for date: LocalDay,
        generatedAt: Date
    ) throws -> (document: ThingStructDocument, didMaterialize: Bool) {
        // 如果已有当天 plan，则直接返回原 document；
        // 否则按模板规则生成并插入。
        guard document.dayPlan(for: date) == nil else {
            return (document, false)
        }

        let dayPlan = try TemplateEngine.ensureMaterializedDayPlan(
            for: date,
            existingDayPlans: document.dayPlans,
            savedTemplates: document.savedTemplates,
            weekdayRules: document.weekdayRules,
            overrides: document.overrides,
            generatedAt: generatedAt
        )

        var updated = document
        if let existingIndex = updated.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            updated.dayPlans[existingIndex] = dayPlan
        } else {
            updated.dayPlans.append(dayPlan)
            updated.dayPlans.sort { $0.date < $1.date }
        }

        return (updated, true)
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

    private func blockReferences(
        from now: NowScreenModel
    ) -> [ThingStructSystemBlockReference] {
        now.activeChain.map { item in
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
    }

    private func liveActivityDisplaySelection(
        from now: NowScreenModel,
        blocksByID: [UUID: ThingStructSystemBlockReference]
    ) -> (
        block: ThingStructSystemBlockReference,
        task: ThingStructSystemTaskReference,
        note: String?
    )? {
        let tasksByBlockID = Dictionary(uniqueKeysWithValues: now.taskSections.map { ($0.id, $0) })
        let notesByBlockID = Dictionary(uniqueKeysWithValues: now.noteSections.map { ($0.id, $0.note) })

        for item in now.activeChain {
            guard
                let section = tasksByBlockID[item.id],
                let task = section.tasks.first(where: { !$0.isCompleted }),
                let block = blocksByID[item.id]
            else {
                continue
            }

            return (
                block: block,
                task: ThingStructSystemTaskReference(
                    date: now.date,
                    blockID: section.id,
                    taskID: task.id,
                    title: task.title,
                    blockTitle: section.title,
                    layerIndex: section.layerIndex,
                    isCurrentBlock: section.isCurrent
                ),
                note: notesByBlockID[item.id]
            )
        }

        return nil
    }

    private func remainingTaskCount(
        from now: NowScreenModel
    ) -> Int {
        now.taskSections
            .flatMap(\.tasks)
            .filter { !$0.isCompleted }
            .count
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
