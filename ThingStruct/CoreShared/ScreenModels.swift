import Foundation

public struct NowChainItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isBlank: Bool
    public var hasIncompleteTasks: Bool
    public var isCurrent: Bool
}

public struct NowNoteSection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var note: String
    public var isBlank: Bool
    public var isCurrent: Bool
}

public struct NowTaskSection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var tasks: [TaskItem]
    public var isCurrent: Bool
    public var isComplete: Bool
}

public struct NowScreenModel: Equatable, Sendable {
    public var date: LocalDay
    public var minuteOfDay: Int
    public var activeChain: [NowChainItem]
    public var noteSections: [NowNoteSection]
    public var statusMessage: String?
    public var taskSections: [NowTaskSection]
}

public struct TimelineBlockItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var parentBlockID: UUID?
    public var title: String
    public var note: String?
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var layerIndex: Int
    public var isBlank: Bool
    public var incompleteTaskCount: Int
}

public struct BlockDetailModel: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isBlank: Bool
    public var tasks: [TaskItem]
    public var parentBlockID: UUID?
}

public struct TodayScreenModel: Equatable, Sendable {
    public var date: LocalDay
    public var blocks: [TimelineBlockItem]
    public var selectedBlock: BlockDetailModel?
    public var initialScrollMinute: Int
    public var initialFocusBlockID: UUID?
}

public struct SuggestedTemplateSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceDate: LocalDay
    public var baseBlockCount: Int
    public var totalBlockCount: Int
    public var taskBlueprintCount: Int
    public var previewTitles: [String]
}

public struct SavedTemplateSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var totalBlockCount: Int
    public var taskBlueprintCount: Int
    public var assignedWeekdays: [Weekday]
}

public struct TomorrowScheduleSummary: Equatable, Sendable {
    public var date: LocalDay
    public var weekday: Weekday
    public var weekdayTemplateID: UUID?
    public var weekdayTemplateTitle: String?
    public var overrideTemplateID: UUID?
    public var overrideTemplateTitle: String?
    public var finalTemplateID: UUID?
    public var finalTemplateTitle: String?
}

public struct TemplatesScreenModel: Equatable, Sendable {
    public var suggestedTemplates: [SuggestedTemplateSummary]
    public var savedTemplates: [SavedTemplateSummary]
    public var tomorrowSchedule: TomorrowScheduleSummary
}

public enum ThingStructPresentation {
    public static func nowScreenModel(
        document: ThingStructDocument,
        date: LocalDay,
        minuteOfDay: Int
    ) throws -> NowScreenModel {
        let plan = document.dayPlan(for: date) ?? DayPlan(date: date)
        let selection = try DayPlanEngine.activeSelection(in: plan, at: minuteOfDay)
        let sortedChain = selection.chain.sorted(by: nowChainSort)

        let activeChain = makeNowChainItems(
            from: sortedChain,
            activeBlockID: selection.activeBlock?.id
        )
        let noteSections = makeNowNoteSections(
            from: sortedChain,
            activeBlockID: selection.activeBlock?.id
        )
        let taskSections = makeNowTaskSections(
            from: sortedChain,
            activeBlockID: selection.activeBlock?.id
        )

        let statusMessage: String?
        if !taskSections.isEmpty {
            statusMessage = nil
        } else if selection.activeBlock?.isBlankBaseBlock == true {
            statusMessage = "You're in open time right now."
        } else if selection.activeBlock != nil {
            statusMessage = "No incomplete tasks in this chain."
        } else {
            statusMessage = "No plan for today yet."
        }

        return NowScreenModel(
            date: date,
            minuteOfDay: minuteOfDay,
            activeChain: activeChain,
            noteSections: noteSections,
            statusMessage: statusMessage,
            taskSections: taskSections
        )
    }

    public static func todayScreenModel(
        document: ThingStructDocument,
        date: LocalDay,
        selectedBlockID: UUID?,
        currentMinute: Int?
    ) throws -> TodayScreenModel {
        let runtimePlan = try DayPlanEngine.runtimeResolved(document.dayPlan(for: date) ?? DayPlan(date: date))
        let sortedBlocks = runtimePlan.blocks
            .filter { !$0.isCancelled }
            .compactMap { block -> TimelineBlockItem? in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                return TimelineBlockItem(
                    id: block.id,
                    parentBlockID: block.parentBlockID,
                    title: block.title,
                    note: block.note,
                    startMinuteOfDay: start,
                    endMinuteOfDay: end,
                    layerIndex: block.layerIndex,
                    isBlank: block.isBlankBaseBlock,
                    incompleteTaskCount: block.tasks.filter { !$0.isCompleted }.count
                )
            }
            .sorted(by: timelineSort)

        let focusedBlockID: UUID?
        if let selectedBlockID {
            focusedBlockID = selectedBlockID
        } else if let currentMinute {
            focusedBlockID = try DayPlanEngine.activeSelection(
                in: document.dayPlan(for: date) ?? DayPlan(date: date),
                at: currentMinute
            ).activeBlock?.id
        } else {
            focusedBlockID = sortedBlocks.first(where: { !$0.isBlank })?.id
        }

        let selectedBlock = runtimePlan.blocks
            .first(where: { $0.id == focusedBlockID && !$0.isCancelled })
            .flatMap(detailModel)

        let fallbackMinute = sortedBlocks.first(where: { $0.id == focusedBlockID })?.startMinuteOfDay
            ?? sortedBlocks.first(where: { !$0.isBlank })?.startMinuteOfDay
            ?? 0

        return TodayScreenModel(
            date: date,
            blocks: sortedBlocks,
            selectedBlock: selectedBlock,
            initialScrollMinute: fallbackMinute,
            initialFocusBlockID: focusedBlockID
        )
    }

    public static func templatesScreenModel(
        document: ThingStructDocument,
        referenceDay: LocalDay
    ) throws -> TemplatesScreenModel {
        let suggested = try TemplateEngine.suggestedTemplates(
            referenceDay: referenceDay,
            from: document.dayPlans
        )
        .map { template in
            SuggestedTemplateSummary(
                id: template.id,
                sourceDate: template.sourceDate,
                baseBlockCount: template.blocks.filter { $0.layerIndex == 0 }.count,
                totalBlockCount: template.blocks.count,
                taskBlueprintCount: template.blocks.reduce(0) { $0 + $1.taskBlueprints.count },
                previewTitles: Array(template.blocks.map(\.title).prefix(3))
            )
        }

        let tomorrow = referenceDay.adding(days: 1)
        let selectedTemplate = try TemplateEngine.selectedSavedTemplate(
            for: tomorrow,
            savedTemplates: document.savedTemplates,
            weekdayRules: document.weekdayRules,
            overrides: document.overrides
        )

        let weekdayTemplateID = document.weekdayRules.first(where: { $0.weekday == tomorrow.weekday })?.savedTemplateID
        let weekdayTemplateTitle = document.savedTemplates.first(where: { $0.id == weekdayTemplateID })?.title
        let overrideTemplateID = document.overrides.first(where: { $0.date == tomorrow })?.savedTemplateID
        let overrideTemplateTitle = document.savedTemplates.first(where: { $0.id == overrideTemplateID })?.title

        let saved = document.savedTemplates.map { template in
            SavedTemplateSummary(
                id: template.id,
                title: template.title,
                totalBlockCount: template.blocks.count,
                taskBlueprintCount: template.blocks.reduce(0) { $0 + $1.taskBlueprints.count },
                assignedWeekdays: document.weekdayRules
                    .filter { $0.savedTemplateID == template.id }
                    .map(\.weekday)
                    .sorted(by: { $0.rawValue < $1.rawValue })
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return TemplatesScreenModel(
            suggestedTemplates: suggested,
            savedTemplates: saved,
            tomorrowSchedule: TomorrowScheduleSummary(
                date: tomorrow,
                weekday: tomorrow.weekday,
                weekdayTemplateID: weekdayTemplateID,
                weekdayTemplateTitle: weekdayTemplateTitle,
                overrideTemplateID: overrideTemplateID,
                overrideTemplateTitle: overrideTemplateTitle,
                finalTemplateID: selectedTemplate?.id,
                finalTemplateTitle: selectedTemplate?.title
            )
        )
    }

    private nonisolated static func detailModel(for block: TimeBlock) -> BlockDetailModel? {
        guard
            let start = block.resolvedStartMinuteOfDay,
            let end = block.resolvedEndMinuteOfDay
        else {
            return nil
        }

        return BlockDetailModel(
            id: block.id,
            title: block.title,
            note: block.note,
            layerIndex: block.layerIndex,
            startMinuteOfDay: start,
            endMinuteOfDay: end,
            isBlank: block.isBlankBaseBlock,
            tasks: block.tasks.sorted(by: taskSort),
            parentBlockID: block.parentBlockID
        )
    }
}

private nonisolated func makeNowChainItems(
    from chain: [TimeBlock],
    activeBlockID: UUID?
) -> [NowChainItem] {
    chain.compactMap { block in
        guard
            let start = block.resolvedStartMinuteOfDay,
            let end = block.resolvedEndMinuteOfDay
        else {
            return nil
        }

        return NowChainItem(
            id: block.id,
            title: block.title,
            layerIndex: block.layerIndex,
            startMinuteOfDay: start,
            endMinuteOfDay: end,
            isBlank: block.isBlankBaseBlock,
            hasIncompleteTasks: block.hasIncompleteTasks,
            isCurrent: block.id == activeBlockID
        )
    }
}

private nonisolated func makeNowNoteSections(
    from chain: [TimeBlock],
    activeBlockID: UUID?
) -> [NowNoteSection] {
    chain.compactMap { block in
        guard let note = normalizedNoteText(block.note) else {
            return nil
        }

        return NowNoteSection(
            id: block.id,
            title: block.title,
            layerIndex: block.layerIndex,
            note: note,
            isBlank: block.isBlankBaseBlock,
            isCurrent: block.id == activeBlockID
        )
    }
}

private nonisolated func makeNowTaskSections(
    from chain: [TimeBlock],
    activeBlockID: UUID?
) -> [NowTaskSection] {
    chain.filter { !$0.tasks.isEmpty }.compactMap { block in
        makeNowTaskSection(from: block, activeBlockID: activeBlockID)
    }
}

private nonisolated func makeNowTaskSection(
    from block: TimeBlock,
    activeBlockID: UUID?
) -> NowTaskSection? {
    guard
        let start = block.resolvedStartMinuteOfDay,
        let end = block.resolvedEndMinuteOfDay
    else {
        return nil
    }

    return NowTaskSection(
        id: block.id,
        title: block.title,
        layerIndex: block.layerIndex,
        startMinuteOfDay: start,
        endMinuteOfDay: end,
        tasks: block.tasks.sorted(by: taskSort),
        isCurrent: block.id == activeBlockID,
        isComplete: !block.hasIncompleteTasks
    )
}

private nonisolated func normalizedNoteText(_ note: String?) -> String? {
    guard let note else {
        return nil
    }

    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private nonisolated func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

private nonisolated func nowChainSort(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Bool {
    if lhs.layerIndex != rhs.layerIndex {
        return lhs.layerIndex > rhs.layerIndex
    }

    if lhs.resolvedStartMinuteOfDay != rhs.resolvedStartMinuteOfDay {
        return (lhs.resolvedStartMinuteOfDay ?? 0) < (rhs.resolvedStartMinuteOfDay ?? 0)
    }

    return lhs.id.uuidString < rhs.id.uuidString
}

private nonisolated func timelineSort(_ lhs: TimelineBlockItem, _ rhs: TimelineBlockItem) -> Bool {
    if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
        return lhs.startMinuteOfDay < rhs.startMinuteOfDay
    }
    if lhs.layerIndex != rhs.layerIndex {
        return lhs.layerIndex < rhs.layerIndex
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
