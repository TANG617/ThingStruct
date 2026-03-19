import Foundation

public struct LegacyChecklistSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var order: Int
    public var isCompleted: Bool
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        order: Int = 0,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

public struct LegacyStateSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var order: Int
    public var date: LocalDay
    public var isCompleted: Bool
    public var checklistItems: [LegacyChecklistSnapshot]

    public init(
        id: UUID = UUID(),
        title: String,
        order: Int = 0,
        date: LocalDay,
        isCompleted: Bool = false,
        checklistItems: [LegacyChecklistSnapshot] = []
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.date = date
        self.isCompleted = isCompleted
        self.checklistItems = checklistItems
    }
}

public struct LegacyStateTemplateSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var checklistItems: [LegacyChecklistSnapshot]

    public init(
        id: UUID = UUID(),
        title: String,
        checklistItems: [LegacyChecklistSnapshot] = []
    ) {
        self.id = id
        self.title = title
        self.checklistItems = checklistItems
    }
}

public struct LegacyRoutineTemplateSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var repeatDays: Set<Weekday>
    public var stateTemplates: [LegacyStateTemplateSnapshot]

    public init(
        id: UUID = UUID(),
        title: String,
        repeatDays: Set<Weekday> = [],
        stateTemplates: [LegacyStateTemplateSnapshot] = []
    ) {
        self.id = id
        self.title = title
        self.repeatDays = repeatDays
        self.stateTemplates = stateTemplates
    }
}

public enum LegacyImportEngine {
    public static func importDocument(
        states: [LegacyStateSnapshot],
        stateTemplates: [LegacyStateTemplateSnapshot],
        routineTemplates: [LegacyRoutineTemplateSnapshot],
        importedAt: Date = Date()
    ) throws -> ThingStructDocument {
        let dayPlans = try importedDayPlans(from: states, importedAt: importedAt)

        var savedTemplates: [SavedDayTemplate] = []
        var weekdayRules: [WeekdayTemplateRule] = []
        var occupiedWeekdays: Set<Weekday> = []

        for routineTemplate in routineTemplates.sorted(by: legacyTemplateSort) {
            let savedTemplate = importedSavedTemplate(
                title: routineTemplate.title,
                stateTemplates: routineTemplate.stateTemplates,
                importedAt: importedAt
            )
            savedTemplates.append(savedTemplate)

            for weekday in Weekday.mondayFirst where routineTemplate.repeatDays.contains(weekday) {
                guard occupiedWeekdays.insert(weekday).inserted else { continue }
                weekdayRules.append(
                    WeekdayTemplateRule(
                        weekday: weekday,
                        savedTemplateID: savedTemplate.id
                    )
                )
            }
        }

        let referencedStateTemplateIDs = Set(
            routineTemplates.flatMap(\.stateTemplates).map(\.id)
        )

        for stateTemplate in stateTemplates.sorted(by: legacyTemplateSort) where !referencedStateTemplateIDs.contains(stateTemplate.id) {
            savedTemplates.append(
                importedSavedTemplate(
                    title: stateTemplate.title,
                    stateTemplates: [stateTemplate],
                    importedAt: importedAt
                )
            )
        }

        return ThingStructDocument(
            dayPlans: dayPlans.sorted { $0.date < $1.date },
            savedTemplates: savedTemplates.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            },
            weekdayRules: weekdayRules.sorted { $0.weekday.rawValue < $1.weekday.rawValue },
            overrides: []
        )
    }

    private static func importedDayPlans(
        from states: [LegacyStateSnapshot],
        importedAt: Date
    ) throws -> [DayPlan] {
        let groupedStates = Dictionary(grouping: states, by: \.date)

        return try groupedStates.keys.sorted().map { date in
            let statesForDay = groupedStates[date, default: []].sorted(by: legacyStateSort)
            let blocks = statesForDay.enumerated().map { index, state in
                TimeBlock(
                    dayPlanID: nil,
                    layerIndex: 0,
                    title: state.title,
                    tasks: importedTasks(from: state),
                    timing: .absolute(
                        startMinuteOfDay: legacySlotStart(index: index, count: statesForDay.count),
                        requestedEndMinuteOfDay: legacySlotEnd(index: index, count: statesForDay.count)
                    )
                )
            }

            return try DayPlanEngine.resolved(
                DayPlan(
                    date: date,
                    sourceSavedTemplateID: nil,
                    lastGeneratedAt: importedAt,
                    hasUserEdits: true,
                    blocks: blocks
                )
            )
        }
    }

    private static func importedSavedTemplate(
        title: String,
        stateTemplates: [LegacyStateTemplateSnapshot],
        importedAt: Date
    ) -> SavedDayTemplate {
        let blocks = stateTemplates.enumerated()
            .map { index, stateTemplate in
                BlockTemplate(
                    layerIndex: 0,
                    title: stateTemplate.title,
                    taskBlueprints: importedTaskBlueprints(from: stateTemplate.checklistItems),
                    timing: .absolute(
                        startMinuteOfDay: legacySlotStart(index: index, count: stateTemplates.count),
                        requestedEndMinuteOfDay: legacySlotEnd(index: index, count: stateTemplates.count)
                    )
                )
            }

        return SavedDayTemplate(
            title: title,
            sourceSuggestedTemplateID: UUID(),
            blocks: blocks,
            createdAt: importedAt,
            updatedAt: importedAt
        )
    }

    private static func importedTasks(from state: LegacyStateSnapshot) -> [TaskItem] {
        let importedChecklist = state.checklistItems
            .sorted(by: legacyChecklistSort)
            .enumerated()
            .map { index, item in
                TaskItem(
                    title: item.title,
                    order: index,
                    isCompleted: item.isCompleted,
                    completedAt: item.completedAt
                )
            }

        guard importedChecklist.isEmpty, state.isCompleted else {
            return importedChecklist
        }

        return [
            TaskItem(
                title: "Imported completion",
                order: 0,
                isCompleted: true,
                completedAt: nil
            )
        ]
    }

    private static func importedTaskBlueprints(from checklistItems: [LegacyChecklistSnapshot]) -> [TaskBlueprint] {
        checklistItems
            .sorted(by: legacyChecklistSort)
            .enumerated()
            .map { index, item in
                TaskBlueprint(title: item.title, order: index)
            }
    }

    private static func legacySlotStart(index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index * 1440) / count
    }

    private static func legacySlotEnd(index: Int, count: Int) -> Int {
        guard count > 0 else { return 1440 }
        return ((index + 1) * 1440) / count
    }
}

private func legacyStateSort(_ lhs: LegacyStateSnapshot, _ rhs: LegacyStateSnapshot) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    if lhs.title != rhs.title {
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

private func legacyTemplateSort(_ lhs: LegacyStateTemplateSnapshot, _ rhs: LegacyStateTemplateSnapshot) -> Bool {
    if lhs.title != rhs.title {
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

private func legacyTemplateSort(_ lhs: LegacyRoutineTemplateSnapshot, _ rhs: LegacyRoutineTemplateSnapshot) -> Bool {
    if lhs.title != rhs.title {
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

private func legacyChecklistSort(_ lhs: LegacyChecklistSnapshot, _ rhs: LegacyChecklistSnapshot) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    if lhs.title != rhs.title {
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
