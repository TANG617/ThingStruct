import Foundation

public struct NowChainItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isBlank: Bool
    public var hasIncompleteTasks: Bool
}

public struct NowScreenModel: Equatable, Sendable {
    public var date: LocalDay
    public var minuteOfDay: Int
    public var activeChain: [NowChainItem]
    public var activeBlockTitle: String
    public var statusMessage: String?
    public var tasks: [TaskItem]
    public var taskSourceBlockID: UUID?
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

        let activeChain = selection.chain.compactMap { block -> NowChainItem? in
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
                hasIncompleteTasks: block.hasIncompleteTasks
            )
        }

        let activeBlockTitle = selection.activeBlock?.title ?? "No Active Block"
        let statusMessage: String?
        if selection.taskSourceBlock != nil {
            statusMessage = nil
        } else if selection.activeBlock?.isBlankBaseBlock == true {
            statusMessage = "当前为空白时段"
        } else if selection.activeBlock != nil {
            statusMessage = "当前链条没有未完成任务"
        } else {
            statusMessage = "今天还没有计划"
        }

        return NowScreenModel(
            date: date,
            minuteOfDay: minuteOfDay,
            activeChain: activeChain,
            activeBlockTitle: activeBlockTitle,
            statusMessage: statusMessage,
            tasks: selection.taskSourceBlock?.tasks.sorted(by: taskSort) ?? [],
            taskSourceBlockID: selection.taskSourceBlock?.id
        )
    }

    public static func todayScreenModel(
        document: ThingStructDocument,
        date: LocalDay,
        selectedBlockID: UUID?,
        initialMinute: Int?
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

        let selectedBlock = runtimePlan.blocks
            .first(where: { $0.id == selectedBlockID && !$0.isCancelled })
            .flatMap(detailModel)

        let fallbackMinute = sortedBlocks.first(where: { !$0.isBlank })?.startMinuteOfDay ?? 0

        return TodayScreenModel(
            date: date,
            blocks: sortedBlocks,
            selectedBlock: selectedBlock,
            initialScrollMinute: initialMinute ?? fallbackMinute
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

private nonisolated func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
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
