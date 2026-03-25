import Foundation

// 这是项目最核心的数据模型文件。
//
// 如果你来自 C++，这里有几个 Swift 世界观差异非常值得先建立：
// 1. 这里绝大多数模型都用 `struct`，也就是值类型(value type)。
//    传值、复制、比较会比传统“到处 new class”更常见。
// 2. `enum` 可以带关联值，很多场景下可以替代“基类 + 子类 + tag”的层级设计。
// 3. `Codable` 表示该类型可编码/解码，通常可直接写成 JSON。
// 4. `Sendable` 表示该值可以安全跨并发边界传递。
//
// 这个文件只定义“系统里有哪些数据”，不关心 UI 怎么画，也不关心文件怎么保存。

// `LocalDay` 表示“本地自然日”而不是某个精确时间点。
// 为什么不用 `Date` 直接表示日期？
// 因为 `Date` 天然带时区、秒数、绝对时间语义，而计划系统更关心“某天”。
public struct LocalDay: Hashable, Codable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public nonisolated init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // 把系统 `Date` 压缩成“年-月-日”三元组。
    // 这是从“时间点”投影到“自然日”的典型做法。
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
        // Swift 支持直接比较元组 `(a, b, c)`，这比手写多层 if 更简洁。
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
        // 注意：虽然项目 README 里“每天固定 1440 分钟”，
        // 但做日历加减时仍然使用 `Calendar`，保证年月日推进是正确的。
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
    // 业务引擎内部使用一个固定 Gregorian + GMT 的 calendar。
    // 这样可以减少不同用户地区设置对“纯规则计算”的干扰。
    // 这是一个很典型的“业务规则用稳定语义，展示层再做本地化”的思路。
    nonisolated static var thingStructGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

public extension Int {
    // 时间编辑基于 5 分钟网格，所以这里给 `Int` 加上了几个对齐/夹取 helper。
    // Swift 允许给已有类型写 extension，这点和 C++ 的自由函数 + ADL 很不一样。
    // 这些方法本质上是“把分钟数映射到合法网格”的工具。
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
        // `aligned` 的语义比 `snapped` 更严格：
        // 它要求结果必须真的落在合法范围内，否则返回 nil。
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

// 星期几使用 enum，而不是到处传播裸整数。
// 这是“让非法状态更难表达”的经典类型设计策略。
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
        // 这里是纯展示文本，不参与业务规则。
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
    // 内存里用 `Set<Weekday>` 判断包含最方便；
    // 存储/UI 里数组更常见，所以这里提供桥接 helper。
    var toIntArray: [Int] {
        map(\.rawValue).sorted()
    }

    static func from(intArray: [Int]) -> Set<Weekday> {
        Set(intArray.compactMap(Weekday.init(rawValue:)))
    }
}

// `kind` 用来区分：
// - 用户真正创建/保存的 block
// - 运行时为了填补时间空洞而临时生成的 blank block
public enum TimeBlockKind: String, Equatable, Codable, Sendable {
    case userDefined
    case blankBase
}

// `TaskItem` 是“某一天里的真实任务实例”。
// 它和模板里的 blueprint 不同：这里可以记录完成状态、完成时间。
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

// `TaskBlueprint` 是模板阶段的任务定义。
// 一旦模板被实例化成某天的 DayPlan，blueprint 才会变成真实 `TaskItem`。
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

public enum ReminderTriggerMode: String, Equatable, Codable, Sendable {
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

// Timing is modeled as an enum because a block is either:
// - absolute: anchored to the day clock
// - relative: anchored to its parent block
//
// This is much stronger than carrying optional fields for both modes at once.
public enum TimeBlockTiming: Equatable, Codable, Sendable {
    case absolute(startMinuteOfDay: Int, requestedEndMinuteOfDay: Int?)
    case relative(startOffsetMinutes: Int, requestedDurationMinutes: Int?)
}

// `TimeBlock` is the central planning primitive.
//
// A block can be:
// - a top-level base block for the day
// - a nested overlay block inside another block
// - a runtime-generated blank base block
//
// The resolved start/end values are caches produced by `DayPlanEngine`.
// The persisted truth is still `timing`.
public struct TimeBlock: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var dayPlanID: UUID?
    public var parentBlockID: UUID?
    public var layerIndex: Int
    public var kind: TimeBlockKind
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
        kind: TimeBlockKind = .userDefined,
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
        self.kind = kind
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
    // Small convenience queries keep calling code readable.
    nonisolated var hasIncompleteTasks: Bool {
        tasks.contains { !$0.isCompleted }
    }

    nonisolated var isBlankBaseBlock: Bool {
        kind == .blankBase
    }
}

// When the user drags a block edge in `Today`, the UI needs precomputed legal bounds.
public struct BlockResizeBounds: Equatable, Sendable {
    public var blockID: UUID
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var minimumStartMinuteOfDay: Int
    public var maximumStartMinuteOfDay: Int
    public var minimumEndMinuteOfDay: Int
    public var maximumEndMinuteOfDay: Int

    public init(
        blockID: UUID,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        minimumStartMinuteOfDay: Int,
        maximumStartMinuteOfDay: Int,
        minimumEndMinuteOfDay: Int,
        maximumEndMinuteOfDay: Int
    ) {
        self.blockID = blockID
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.minimumStartMinuteOfDay = minimumStartMinuteOfDay
        self.maximumStartMinuteOfDay = maximumStartMinuteOfDay
        self.minimumEndMinuteOfDay = minimumEndMinuteOfDay
        self.maximumEndMinuteOfDay = maximumEndMinuteOfDay
    }
}

// `DayPlan` is the persisted schedule for a single calendar day.
// It stores authored blocks plus metadata about whether the day came from a template
// and whether the user has diverged from that template.
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
    // Used to guard destructive operations such as regenerating a future day from templates.
    var containsCompletedTasks: Bool {
        blocks.contains { block in
            block.tasks.contains { $0.isCompleted }
        }
    }
}

// Template-side block representation.
// It mirrors `TimeBlock`, but uses `TaskBlueprint` and template parent IDs.
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

// Suggested templates are derived from recent real day plans.
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

// Saved templates are user-owned reusable plans.
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

// "Use template X for every Monday" style rule.
public struct WeekdayTemplateRule: Equatable, Codable, Sendable {
    public var weekday: Weekday
    public var savedTemplateID: UUID

    public init(weekday: Weekday, savedTemplateID: UUID) {
        self.weekday = weekday
        self.savedTemplateID = savedTemplateID
    }
}

// "Use template X on this specific date, regardless of weekday rule" style rule.
public struct DateTemplateOverride: Equatable, Codable, Sendable {
    public var date: LocalDay
    public var savedTemplateID: UUID

    public init(date: LocalDay, savedTemplateID: UUID) {
        self.date = date
        self.savedTemplateID = savedTemplateID
    }
}

// `ActiveSelection` is the result of asking:
// "Given the current minute, which chain of nested blocks is active?"
//
// `chain` contains all layers from base -> topmost active overlay.
// `taskSourceBlock` tells `Now` which block should currently own the actionable tasks.
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
