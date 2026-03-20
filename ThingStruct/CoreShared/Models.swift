import Foundation

public struct LocalDay: Hashable, Codable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public nonisolated init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public nonisolated init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            preconditionFailure("Unable to decode LocalDay from date: \(date)")
        }

        self.init(year: year, month: month, day: day)
    }

    public nonisolated static func == (lhs: LocalDay, rhs: LocalDay) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
    }

    public nonisolated static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public nonisolated var weekday: Weekday {
        weekday(in: .thingStructGregorian)
    }

    public nonisolated func weekday(in calendar: Calendar) -> Weekday {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            preconditionFailure("Invalid LocalDay: \(self)")
        }

        return Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    public nonisolated func adding(days: Int, calendar: Calendar = .thingStructGregorian) -> LocalDay {
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

    public nonisolated static func today(calendar: Calendar = .current) -> LocalDay {
        LocalDay(date: Date.now, calendar: calendar)
    }
}

extension LocalDay: CustomStringConvertible {
    public nonisolated var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public extension Calendar {
    nonisolated static var thingStructGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

public extension Int {
    nonisolated func snapped(toStep step: Int, within range: ClosedRange<Int>) -> Int {
        precondition(step > 0, "Step must be positive.")

        let clamped = Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        let offset = clamped - range.lowerBound
        let snappedOffset = Int((Double(offset) / Double(step)).rounded()) * step
        return Swift.min(
            Swift.max(range.lowerBound + snappedOffset, range.lowerBound),
            range.upperBound
        )
    }

    nonisolated func roundedDown(toStep step: Int) -> Int {
        precondition(step > 0, "Step must be positive.")
        return Int(floor(Double(self) / Double(step))) * step
    }

    nonisolated func roundedUp(toStep step: Int) -> Int {
        precondition(step > 0, "Step must be positive.")
        return Int(ceil(Double(self) / Double(step))) * step
    }

    nonisolated func aligned(toStep step: Int, within range: ClosedRange<Int>) -> Int? {
        precondition(step > 0, "Step must be positive.")

        let lowerBound = range.lowerBound.roundedUp(toStep: step)
        let upperBound = range.upperBound.roundedDown(toStep: step)
        guard lowerBound <= upperBound else {
            return nil
        }

        let candidates = [roundedDown(toStep: step), roundedUp(toStep: step), lowerBound, upperBound]
            .filter { lowerBound ... upperBound ~= $0 }

        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs - self)
            let rhsDistance = abs(rhs - self)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs < rhs
        }
    }
}

public enum Weekday: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var id: Int { rawValue }

    public var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    public var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    public var chineseName: String {
        switch self {
        case .sunday: return "周日"
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        }
    }

    public nonisolated static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    public nonisolated static var today: Weekday {
        from(date: Date.now)
    }

    public nonisolated static var mondayFirst: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}

public extension Set where Element == Weekday {
    var toIntArray: [Int] {
        map(\.rawValue).sorted()
    }

    static func from(intArray: [Int]) -> Set<Weekday> {
        Set(intArray.compactMap(Weekday.init(rawValue:)))
    }
}

public enum TimeBlockKind: String, Equatable, Codable, Sendable {
    case userDefined
    case blankBase
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
    public var kind: TimeBlockKind
    public var title: String
    public var note: String?
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
        kind: TimeBlockKind = .userDefined,
        title: String,
        note: String? = nil,
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
        self.kind = kind
        self.title = title
        self.note = note
        self.tasks = tasks
        self.timing = timing
        self.resolvedStartMinuteOfDay = resolvedStartMinuteOfDay
        self.resolvedEndMinuteOfDay = resolvedEndMinuteOfDay
        self.isCancelled = isCancelled
    }
}

public extension TimeBlock {
    nonisolated var hasIncompleteTasks: Bool {
        tasks.contains { !$0.isCompleted }
    }

    nonisolated var isBlankBaseBlock: Bool {
        kind == .blankBase
    }
}

public struct BlockResizeBounds: Equatable, Sendable {
    public var blockID: UUID
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var minimumEndMinuteOfDay: Int
    public var maximumEndMinuteOfDay: Int

    public init(
        blockID: UUID,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        minimumEndMinuteOfDay: Int,
        maximumEndMinuteOfDay: Int
    ) {
        self.blockID = blockID
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.minimumEndMinuteOfDay = minimumEndMinuteOfDay
        self.maximumEndMinuteOfDay = maximumEndMinuteOfDay
    }
}

public struct DayPlan: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var date: LocalDay
    public var sourceSavedTemplateID: UUID?
    public var lastGeneratedAt: Date?
    public var hasUserEdits: Bool
    public var blocks: [TimeBlock]

    public init(
        id: UUID = UUID(),
        date: LocalDay,
        sourceSavedTemplateID: UUID? = nil,
        lastGeneratedAt: Date? = nil,
        hasUserEdits: Bool = false,
        blocks: [TimeBlock] = []
    ) {
        self.id = id
        self.date = date
        self.sourceSavedTemplateID = sourceSavedTemplateID
        self.lastGeneratedAt = lastGeneratedAt
        self.hasUserEdits = hasUserEdits
        self.blocks = blocks
    }
}

public extension DayPlan {
    var containsCompletedTasks: Bool {
        blocks.contains { block in
            block.tasks.contains { $0.isCompleted }
        }
    }
}

public struct BlockTemplate: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var parentTemplateBlockID: UUID?
    public var layerIndex: Int
    public var title: String
    public var note: String?
    public var taskBlueprints: [TaskBlueprint]
    public var timing: TimeBlockTiming

    public init(
        id: UUID = UUID(),
        parentTemplateBlockID: UUID? = nil,
        layerIndex: Int,
        title: String,
        note: String? = nil,
        taskBlueprints: [TaskBlueprint] = [],
        timing: TimeBlockTiming
    ) {
        self.id = id
        self.parentTemplateBlockID = parentTemplateBlockID
        self.layerIndex = layerIndex
        self.title = title
        self.note = note
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
