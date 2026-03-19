import Foundation

public struct LocalDay: Hashable, Codable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var weekday: Weekday {
        weekday(in: .thingStructGregorian)
    }

    public func weekday(in calendar: Calendar) -> Weekday {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            preconditionFailure("Invalid LocalDay: \(self)")
        }

        return Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    public func adding(days: Int, calendar: Calendar = .thingStructGregorian) -> LocalDay {
        guard
            let startDate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            let adjustedDate = calendar.date(byAdding: .day, value: days, to: startDate)
        else {
            preconditionFailure("Unable to adjust LocalDay: \(self)")
        }

        let components = calendar.dateComponents([.year, .month, .day], from: adjustedDate)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Unable to decode adjusted LocalDay: \(self)")
        }

        return LocalDay(year: year, month: month, day: day)
    }
}

extension LocalDay: CustomStringConvertible {
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public extension Calendar {
    static var thingStructGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

public enum Weekday: Int, Codable, CaseIterable, Hashable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
}

public enum ReminderTriggerMode: String, Codable, Hashable, Sendable {
    case atStart
    case beforeStart
}

public struct ReminderRule: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var triggerMode: ReminderTriggerMode
    public var offsetMinutes: Int

    public init(
        id: UUID = UUID(),
        triggerMode: ReminderTriggerMode,
        offsetMinutes: Int = 0
    ) {
        self.id = id
        self.triggerMode = triggerMode
        self.offsetMinutes = offsetMinutes
    }
}

public struct TaskItem: Identifiable, Equatable, Codable, Sendable {
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

public struct TaskBlueprint: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var order: Int

    public init(
        id: UUID = UUID(),
        title: String,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.order = order
    }
}

public enum TimeBlockTiming: Equatable, Codable, Sendable {
    case absolute(startMinuteOfDay: Int, requestedEndMinuteOfDay: Int?)
    case relative(startOffsetMinutes: Int, requestedDurationMinutes: Int?)
}

public struct TimeBlock: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var dayPlanID: UUID?
    public var parentBlockID: UUID?
    public var layerIndex: Int
    public var title: String
    public var note: String?
    public var reminders: [ReminderRule]
    public var tasks: [TaskItem]
    public var timing: TimeBlockTiming
    public var resolvedStartMinuteOfDay: Int?
    public var resolvedEndMinuteOfDay: Int?
    public var isCancelled: Bool

    public init(
        id: UUID = UUID(),
        dayPlanID: UUID? = nil,
        parentBlockID: UUID? = nil,
        layerIndex: Int,
        title: String,
        note: String? = nil,
        reminders: [ReminderRule] = [],
        tasks: [TaskItem] = [],
        timing: TimeBlockTiming,
        resolvedStartMinuteOfDay: Int? = nil,
        resolvedEndMinuteOfDay: Int? = nil,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.dayPlanID = dayPlanID
        self.parentBlockID = parentBlockID
        self.layerIndex = layerIndex
        self.title = title
        self.note = note
        self.reminders = reminders
        self.tasks = tasks
        self.timing = timing
        self.resolvedStartMinuteOfDay = resolvedStartMinuteOfDay
        self.resolvedEndMinuteOfDay = resolvedEndMinuteOfDay
        self.isCancelled = isCancelled
    }
}

public extension TimeBlock {
    var hasIncompleteTasks: Bool {
        tasks.contains { !$0.isCompleted }
    }
}

public struct DayPlan: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var date: LocalDay
    public var blocks: [TimeBlock]

    public init(
        id: UUID = UUID(),
        date: LocalDay,
        blocks: [TimeBlock] = []
    ) {
        self.id = id
        self.date = date
        self.blocks = blocks
    }
}

public struct BlockTemplate: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var parentTemplateBlockID: UUID?
    public var layerIndex: Int
    public var title: String
    public var note: String?
    public var reminders: [ReminderRule]
    public var taskBlueprints: [TaskBlueprint]
    public var timing: TimeBlockTiming

    public init(
        id: UUID = UUID(),
        parentTemplateBlockID: UUID? = nil,
        layerIndex: Int,
        title: String,
        note: String? = nil,
        reminders: [ReminderRule] = [],
        taskBlueprints: [TaskBlueprint] = [],
        timing: TimeBlockTiming
    ) {
        self.id = id
        self.parentTemplateBlockID = parentTemplateBlockID
        self.layerIndex = layerIndex
        self.title = title
        self.note = note
        self.reminders = reminders
        self.taskBlueprints = taskBlueprints
        self.timing = timing
    }
}

public struct SuggestedDayTemplate: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var sourceDate: LocalDay
    public var sourceDayPlanID: UUID
    public var blocks: [BlockTemplate]

    public init(
        id: UUID = UUID(),
        sourceDate: LocalDay,
        sourceDayPlanID: UUID,
        blocks: [BlockTemplate]
    ) {
        self.id = id
        self.sourceDate = sourceDate
        self.sourceDayPlanID = sourceDayPlanID
        self.blocks = blocks
    }
}

public struct SavedDayTemplate: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceSuggestedTemplateID: UUID
    public var blocks: [BlockTemplate]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        sourceSuggestedTemplateID: UUID,
        blocks: [BlockTemplate],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceSuggestedTemplateID = sourceSuggestedTemplateID
        self.blocks = blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WeekdayTemplateRule: Equatable, Codable, Sendable {
    public var weekday: Weekday
    public var savedTemplateID: UUID

    public init(weekday: Weekday, savedTemplateID: UUID) {
        self.weekday = weekday
        self.savedTemplateID = savedTemplateID
    }
}

public struct DateTemplateOverride: Equatable, Codable, Sendable {
    public var date: LocalDay
    public var savedTemplateID: UUID

    public init(date: LocalDay, savedTemplateID: UUID) {
        self.date = date
        self.savedTemplateID = savedTemplateID
    }
}

public struct ActiveSelection: Equatable, Sendable {
    public let chain: [TimeBlock]
    public let taskSourceBlock: TimeBlock?

    public init(chain: [TimeBlock], taskSourceBlock: TimeBlock?) {
        self.chain = chain
        self.taskSourceBlock = taskSourceBlock
    }

    public var activeBlock: TimeBlock? {
        chain.last
    }
}
