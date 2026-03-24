import Foundation

// The presentation layer converts domain models into view-friendly screen models.
//
// This file is intentionally separate from SwiftUI code:
// - it keeps layout-free transformation logic testable
// - views can stay focused on rendering
// - the store can ask for fully prepared screen data

// `Now` screen models.
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

// `Today` screen models.
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

public struct TodayOpenSlotItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int

    public var durationMinutes: Int {
        endMinuteOfDay - startMinuteOfDay
    }
}

public enum TodayAddOptionKind: Equatable, Sendable {
    case base
    case overlay(parentBlockID: UUID, layerIndex: Int)
}

public struct TodayAddOption: Identifiable, Equatable, Sendable {
    public var title: String
    public var kind: TodayAddOptionKind

    public var id: String {
        switch kind {
        case .base:
            return "base"
        case let .overlay(parentBlockID, layerIndex):
            return "overlay-\(parentBlockID.uuidString)-\(layerIndex)"
        }
    }
}

public struct BlockDetailModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isBlank: Bool
    public var tasks: [TaskItem]
    public var parentBlockID: UUID?
    public var parentBlockTitle: String?
}

public struct TodayScreenModel: Equatable, Sendable {
    public var date: LocalDay
    public var blocks: [TimelineBlockItem]
    public var openSlots: [TodayOpenSlotItem]
    public var addOptions: [TodayAddOption]
    public var selectedBlock: BlockDetailModel?
    public var initialScrollMinute: Int
    public var initialFocusBlockID: UUID?
}

// `Templates` screen models.
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
    public var previewTitles: [String]
}

public struct TemplateScheduleSummary: Equatable, Sendable {
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
    public var todaySchedule: TemplateScheduleSummary
    public var tomorrowSchedule: TemplateScheduleSummary
}

// `ThingStructPresentation` is a pure mapper from domain state to UI state.
// It should not perform persistence or mutate the document.
public enum ThingStructPresentation {
    public static func nowScreenModel(
        document: ThingStructDocument,
        date: LocalDay,
        minuteOfDay: Int
    ) throws -> NowScreenModel {
        // `Now` is all about the currently active chain of blocks at a single minute.
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
        // `Today` still asks for `runtimeResolved`, but only to derive open slots and
        // current-time behavior. The visible timeline itself stays user-authored only.
        let runtimePlan = try DayPlanEngine.runtimeResolved(document.dayPlan(for: date) ?? DayPlan(date: date))
        let openSlots = runtimePlan.blocks
            .filter { !$0.isCancelled && $0.isBlankBaseBlock }
            .compactMap { block -> TodayOpenSlotItem? in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                return TodayOpenSlotItem(
                    id: block.id,
                    startMinuteOfDay: start,
                    endMinuteOfDay: end
                )
            }
            .sorted { lhs, rhs in
                if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
                    return lhs.startMinuteOfDay < rhs.startMinuteOfDay
                }
                return lhs.endMinuteOfDay < rhs.endMinuteOfDay
            }
        let sortedBlocks = runtimePlan.blocks
            .filter { !$0.isCancelled && !$0.isBlankBaseBlock }
            .compactMap { block -> TimelineBlockItem? in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                let snappedStart = start.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
                let snappedEnd = end.snapped(
                    toStep: 5,
                    within: min(snappedStart + 5, 24 * 60) ... (24 * 60)
                )

                return TimelineBlockItem(
                    id: block.id,
                    parentBlockID: block.parentBlockID,
                    title: block.title,
                    note: block.note,
                    startMinuteOfDay: snappedStart,
                    endMinuteOfDay: snappedEnd,
                    layerIndex: block.layerIndex,
                    isBlank: false,
                    incompleteTaskCount: block.tasks.filter { !$0.isCompleted }.count
                )
            }
            .sorted(by: timelineSort)

        let addOptions = makeTodayAddOptions(
            selectedBlockID: selectedBlockID,
            blocks: runtimePlan.blocks
        )

        // Focus selection is a presentation decision:
        // explicit user selection wins; if we're on "today now", prefer the current
        // active *user* block; otherwise fall back to the first real block.
        let visibleBlockIDs = Set(sortedBlocks.map(\.id))
        let focusedBlockID: UUID?
        if let selectedBlockID, visibleBlockIDs.contains(selectedBlockID) {
            focusedBlockID = selectedBlockID
        } else if let currentMinute {
            let selection = try DayPlanEngine.activeSelection(
                in: document.dayPlan(for: date) ?? DayPlan(date: date),
                at: currentMinute
            )
            focusedBlockID = selection.chain.reversed().first(where: { !$0.isBlankBaseBlock })?.id
        } else {
            focusedBlockID = sortedBlocks.first?.id
        }

        let selectedBlock = runtimePlan.blocks
            .first(where: { $0.id == focusedBlockID && !$0.isCancelled && !$0.isBlankBaseBlock })
            .flatMap { detailModel(for: $0, allBlocks: runtimePlan.blocks) }

        let fallbackMinute = sortedBlocks.first(where: { $0.id == focusedBlockID })?.startMinuteOfDay
            ?? currentMinute
            ?? sortedBlocks.first?.startMinuteOfDay
            ?? 0

        return TodayScreenModel(
            date: date,
            blocks: sortedBlocks,
            openSlots: openSlots,
            addOptions: addOptions,
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

        let saved = document.savedTemplates.map { template in
            SavedTemplateSummary(
                id: template.id,
                title: template.title,
                totalBlockCount: template.blocks.count,
                taskBlueprintCount: template.blocks.reduce(0) { $0 + $1.taskBlueprints.count },
                assignedWeekdays: document.weekdayRules
                    .filter { $0.savedTemplateID == template.id }
                    .map(\.weekday)
                    .sorted(by: { $0.rawValue < $1.rawValue }),
                previewTitles: Array(template.blocks.map(\.title).prefix(3))
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return TemplatesScreenModel(
            suggestedTemplates: suggested,
            savedTemplates: saved,
            todaySchedule: try scheduleSummary(for: referenceDay, document: document),
            tomorrowSchedule: try scheduleSummary(for: referenceDay.adding(days: 1), document: document)
        )
    }

    private static func scheduleSummary(
        for date: LocalDay,
        document: ThingStructDocument
    ) throws -> TemplateScheduleSummary {
        let selectedTemplate = try TemplateEngine.selectedSavedTemplate(
            for: date,
            savedTemplates: document.savedTemplates,
            weekdayRules: document.weekdayRules,
            overrides: document.overrides
        )

        let weekdayTemplateID = document.weekdayRules.first(where: { $0.weekday == date.weekday })?.savedTemplateID
        let weekdayTemplateTitle = document.savedTemplates.first(where: { $0.id == weekdayTemplateID })?.title
        let overrideTemplateID = document.overrides.first(where: { $0.date == date })?.savedTemplateID
        let overrideTemplateTitle = document.savedTemplates.first(where: { $0.id == overrideTemplateID })?.title

        return TemplateScheduleSummary(
            date: date,
            weekday: date.weekday,
            weekdayTemplateID: weekdayTemplateID,
            weekdayTemplateTitle: weekdayTemplateTitle,
            overrideTemplateID: overrideTemplateID,
            overrideTemplateTitle: overrideTemplateTitle,
            finalTemplateID: selectedTemplate?.id,
            finalTemplateTitle: selectedTemplate?.title
        )
    }

    private nonisolated static func detailModel(for block: TimeBlock, allBlocks: [TimeBlock]) -> BlockDetailModel? {
        // Views consume this richer display model so they do not need to know how to
        // find parent titles, snap times, or sort tasks themselves.
        guard
            !block.isBlankBaseBlock,
            let start = block.resolvedStartMinuteOfDay,
            let end = block.resolvedEndMinuteOfDay
        else {
            return nil
        }

        let snappedStart = start.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
        let snappedEnd = end.snapped(
            toStep: 5,
            within: min(snappedStart + 5, 24 * 60) ... (24 * 60)
        )

        let parentTitle = block.parentBlockID.flatMap { parentID in
            allBlocks.first(where: { $0.id == parentID })?.title
        }

        return BlockDetailModel(
            id: block.id,
            title: block.title,
            note: block.note,
            layerIndex: block.layerIndex,
            startMinuteOfDay: snappedStart,
            endMinuteOfDay: snappedEnd,
            isBlank: false,
            tasks: block.tasks.sorted(by: taskSort),
            parentBlockID: block.parentBlockID,
            parentBlockTitle: parentTitle
        )
    }
}

private nonisolated func makeTodayAddOptions(
    selectedBlockID: UUID?,
    blocks: [TimeBlock]
) -> [TodayAddOption] {
    var options = [
        TodayAddOption(
            title: "New Base Block",
            kind: .base
        )
    ]

    guard let selectedBlockID else {
        return options
    }

    let selectableBlocks = blocks.filter { !$0.isCancelled && !$0.isBlankBaseBlock }
    let blocksByID = Dictionary(uniqueKeysWithValues: selectableBlocks.map { ($0.id, $0) })
    guard let selectedBlock = blocksByID[selectedBlockID] else {
        return options
    }

    var path: [TimeBlock] = []
    var cursor: TimeBlock? = selectedBlock

    while let block = cursor {
        path.append(block)
        cursor = block.parentBlockID.flatMap { blocksByID[$0] }
    }

    options.append(
        contentsOf: path.reversed().map { block in
            TodayAddOption(
                title: "New \(nextTimelineLayerTitle(after: block.layerIndex)) Overlay in \(block.title)",
                kind: .overlay(
                    parentBlockID: block.id,
                    layerIndex: block.layerIndex + 1
                )
            )
        }
    )

    return options
}

private nonisolated func nextTimelineLayerTitle(after layerIndex: Int) -> String {
    let nextLayerIndex = layerIndex + 1
    return nextLayerIndex == 0 ? "Base" : "L\(nextLayerIndex)"
}

private nonisolated func makeNowChainItems(
    from chain: [TimeBlock],
    activeBlockID: UUID?
) -> [NowChainItem] {
    // `nonisolated` here means this helper is just a pure mapper with no actor-bound state.
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
    // Notes become their own UI sections even though they originate from the same blocks.
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
    // Empty task lists simply do not appear in the Now tasks area.
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
    // Domain models often allow nil and empty-string separately; the UI usually does not care.
    guard let note else {
        return nil
    }

    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private nonisolated func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
    // Explicit user order wins; UUID only provides a stable tie-breaker.
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

private nonisolated func nowChainSort(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Bool {
    // Higher layer first matches the Now screen's "top overlay is most important" rule.
    if lhs.layerIndex != rhs.layerIndex {
        return lhs.layerIndex > rhs.layerIndex
    }

    if lhs.resolvedStartMinuteOfDay != rhs.resolvedStartMinuteOfDay {
        return (lhs.resolvedStartMinuteOfDay ?? 0) < (rhs.resolvedStartMinuteOfDay ?? 0)
    }

    return lhs.id.uuidString < rhs.id.uuidString
}

private nonisolated func timelineSort(_ lhs: TimelineBlockItem, _ rhs: TimelineBlockItem) -> Bool {
    // Today is visually a timeline, so chronological order dominates the sort.
    if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
        return lhs.startMinuteOfDay < rhs.startMinuteOfDay
    }
    if lhs.layerIndex != rhs.layerIndex {
        return lhs.layerIndex < rhs.layerIndex
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
