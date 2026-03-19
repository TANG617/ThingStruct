import Foundation

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
    func dayPlan(for date: LocalDay) -> DayPlan? {
        dayPlans.first(where: { $0.date == date })
    }
}

public enum SampleDataFactory {
    public static func seededDocument(
        referenceDay: LocalDay = .today(),
        generatedAt: Date = Date()
    ) throws -> ThingStructDocument {
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
