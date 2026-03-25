import Foundation

// `ThingStructDocument` 是整个应用持久化到磁盘的根对象。
// 如果把 app 的可保存状态想成一棵树，这里就是根节点，最终会被编码成 JSON。
// 一切“用户真正保存下来的东西”，都必须能从这里访问到。
public struct ThingStructDocument: Equatable, Codable, Sendable {
    public var dayPlans: [DayPlan]
    public var savedTemplates: [SavedDayTemplate]
    public var weekdayRules: [WeekdayTemplateRule]
    public var overrides: [DateTemplateOverride]

    public init(
        dayPlans: [DayPlan] = [],
        savedTemplates: [SavedDayTemplate] = [],
        weekdayRules: [WeekdayTemplateRule] = [],
        overrides: [DateTemplateOverride] = []
    ) {
        self.dayPlans = dayPlans
        self.savedTemplates = savedTemplates
        self.weekdayRules = weekdayRules
        self.overrides = overrides
    }
}

public extension ThingStructDocument {
    // 这里故意使用线性查找，而不是额外维护索引表。
    // 原因是当前文档规模还小，保持序列化结构简单、直白，比提前做复杂优化更重要。
    func dayPlan(for date: LocalDay) -> DayPlan? {
        dayPlans.first(where: { $0.date == date })
    }
}

// `SampleDataFactory` 只服务于首次启动体验和 SwiftUI 预览。
// 在用户还没有创建真实数据之前，它负责准备一份“看起来像真实使用场景”的样本文档。
public enum SampleDataFactory {
    public static func seededDocument(
        referenceDay: LocalDay = .today(),
        generatedAt: Date = Date()
    ) throws -> ThingStructDocument {
        // 样本数据只覆盖一个很小的滚动窗口：
        // - 今天：让 Now 页面有当前内容可看
        // - 最近几天：让 Templates 页面有历史样本可分析
        // - 明天：可以演示模板如何被物化成实际 day plan
        let recentDays = [
            referenceDay.adding(days: -2),
            referenceDay.adding(days: -1),
            referenceDay
        ]

        let sourcePlans = try recentDays.enumerated().map { index, day in
            try sampleDayPlan(
                for: day,
                variant: index,
                generatedAt: generatedAt
            )
        }

        let suggestedTemplates = try TemplateEngine.suggestedTemplates(
            referenceDay: referenceDay,
            from: sourcePlans
        )

        let savedTemplates = suggestedTemplates.enumerated().map { index, template in
            TemplateEngine.saveSuggestedTemplate(
                template,
                title: index == suggestedTemplates.count - 1 ? "Workday" : "Recent \(index + 1)",
                createdAt: generatedAt
            )
        }

        guard let workdayTemplate = savedTemplates.last else {
            return ThingStructDocument(dayPlans: sourcePlans)
        }

        let weekdayRules: [WeekdayTemplateRule] = [
            .init(weekday: .monday, savedTemplateID: workdayTemplate.id),
            .init(weekday: .tuesday, savedTemplateID: workdayTemplate.id),
            .init(weekday: .wednesday, savedTemplateID: workdayTemplate.id),
            .init(weekday: .thursday, savedTemplateID: workdayTemplate.id),
            .init(weekday: .friday, savedTemplateID: workdayTemplate.id)
        ]

        let tomorrow = referenceDay.adding(days: 1)
        let tomorrowPlan = try TemplateEngine.ensureMaterializedDayPlan(
            for: tomorrow,
            existingDayPlans: sourcePlans,
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: [],
            generatedAt: generatedAt
        )

        return ThingStructDocument(
            dayPlans: sourcePlans + [tomorrowPlan],
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: []
        )
    }

    private static func sampleDayPlan(
        for date: LocalDay,
        variant: Int,
        generatedAt: Date
    ) throws -> DayPlan {
        // 样本工厂先构造普通领域对象，再交给 `DayPlanEngine` 做校验和解析。
        // 这点很重要：即使是样本数据，也尽量走和生产环境一致的业务入口。
        let morning = TimeBlock(
            layerIndex: 0,
            title: "Morning",
            tasks: [TaskItem(title: "Plan the day"), TaskItem(title: "Clear inbox", order: 1)],
            timing: .absolute(startMinuteOfDay: 420, requestedEndMinuteOfDay: 720)
        )
        let lunch = TimeBlock(
            layerIndex: 0,
            title: "Lunch",
            tasks: [TaskItem(title: "Take a break")],
            timing: .absolute(startMinuteOfDay: 720, requestedEndMinuteOfDay: 780)
        )
        let afternoon = TimeBlock(
            layerIndex: 0,
            title: "Afternoon",
            tasks: [TaskItem(title: "Review progress"), TaskItem(title: "Wrap up", order: 1)],
            timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
        )
        let evening = TimeBlock(
            layerIndex: 0,
            title: "Evening",
            tasks: [TaskItem(title: "Reflect"), TaskItem(title: "Prepare tomorrow", order: 1)],
            timing: .absolute(startMinuteOfDay: 1080, requestedEndMinuteOfDay: 1320)
        )

        let focus = TimeBlock(
            parentBlockID: morning.id,
            layerIndex: 1,
            title: variant == 1 ? "Admin" : "Focus Work",
            tasks: [
                TaskItem(title: variant == 1 ? "Handle admin" : "Deep work"),
                TaskItem(title: "Reply to messages", order: 1, isCompleted: variant == 2)
            ],
            timing: .relative(startOffsetMinutes: 30, requestedDurationMinutes: 180)
        )

        let afternoonOverlay = TimeBlock(
            parentBlockID: afternoon.id,
            layerIndex: 1,
            title: variant == 0 ? "Meetings" : "Project Work",
            tasks: [
                TaskItem(title: variant == 0 ? "Sync with team" : "Ship milestone"),
                TaskItem(title: "Update notes", order: 1)
            ],
            timing: .relative(startOffsetMinutes: 15, requestedDurationMinutes: 150)
        )

        let plan = DayPlan(
            date: date,
            lastGeneratedAt: generatedAt,
            hasUserEdits: false,
            blocks: [morning, lunch, afternoon, evening, focus, afternoonOverlay]
        )

        return try DayPlanEngine.resolved(plan)
    }
}
