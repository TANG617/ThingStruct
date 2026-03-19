import XCTest
@testable import ThingStructCore

final class TemplateEngineTests: XCTestCase {
    func testSuggestedTemplatesKeepRollingThreeDayWindow() throws {
        let day0 = LocalDay(year: 2026, month: 3, day: 17)
        let day1 = LocalDay(year: 2026, month: 3, day: 18)
        let day2 = LocalDay(year: 2026, month: 3, day: 19)
        let day3 = LocalDay(year: 2026, month: 3, day: 20)

        let plans = [
            makePlan(date: day0, blocks: [baseBlock(title: "Day0", start: 0, requestedEnd: 1440)]),
            makePlan(date: day1, blocks: [baseBlock(title: "Day1", start: 0, requestedEnd: 1440)]),
            makePlan(date: day2, blocks: [baseBlock(title: "Day2", start: 0, requestedEnd: 1440)]),
            makePlan(date: day3, blocks: [baseBlock(title: "Day3", start: 0, requestedEnd: 1440)])
        ]

        let suggested = try TemplateEngine.suggestedTemplates(referenceDay: day3, from: plans)

        XCTAssertEqual(suggested.map(\.sourceDate), [day1, day2, day3])
    }

    func testSavingSuggestedTemplateCopiesInsteadOfReferencing() throws {
        let dayPlan = makePlan(
            blocks: [baseBlock(title: "Morning", start: 0, requestedEnd: 300)]
        )
        let suggested = try XCTUnwrap(
            TemplateEngine.suggestedTemplates(referenceDay: dayPlan.date, from: [dayPlan]).first
        )

        var saved = TemplateEngine.saveSuggestedTemplate(suggested, title: "Weekday")
        saved.blocks[0].title = "Changed"

        XCTAssertEqual(suggested.blocks[0].title, "Morning")
        XCTAssertEqual(saved.blocks[0].title, "Changed")
        XCTAssertNotEqual(suggested.blocks[0].id, saved.blocks[0].id)
    }

    func testDateOverrideBeatsWeekdayRule() throws {
        let firstTemplate = SavedDayTemplate(
            title: "Rule Template",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
        let secondTemplate = SavedDayTemplate(
            title: "Override Template",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
        let date = LocalDay(year: 2026, month: 3, day: 20)

        let selected = try TemplateEngine.selectedSavedTemplate(
            for: date,
            savedTemplates: [firstTemplate, secondTemplate],
            weekdayRules: [WeekdayTemplateRule(weekday: .friday, savedTemplateID: firstTemplate.id)],
            overrides: [DateTemplateOverride(date: date, savedTemplateID: secondTemplate.id)]
        )

        XCTAssertEqual(selected?.id, secondTemplate.id)
    }

    func testInstantiatingSavedTemplateResetsTaskCompletion() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_234)
        let template = SavedDayTemplate(
            title: "Morning Template",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                BlockTemplate(
                    layerIndex: 0,
                    title: "Morning",
                    taskBlueprints: [
                        TaskBlueprint(title: "Brush teeth", order: 0),
                        TaskBlueprint(title: "Stretch", order: 1)
                    ],
                    timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 120)
                )
            ]
        )

        let dayPlan = try TemplateEngine.instantiateDayPlan(
            from: template,
            for: LocalDay(year: 2026, month: 3, day: 21),
            generatedAt: generatedAt
        )

        XCTAssertEqual(dayPlan.date, LocalDay(year: 2026, month: 3, day: 21))
        XCTAssertEqual(dayPlan.sourceSavedTemplateID, template.id)
        XCTAssertEqual(dayPlan.lastGeneratedAt, generatedAt)
        XCTAssertFalse(dayPlan.hasUserEdits)
        XCTAssertEqual(dayPlan.blocks.count, 1)
        XCTAssertEqual(dayPlan.blocks[0].tasks.map { $0.isCompleted }, [false, false])
        XCTAssertEqual(dayPlan.blocks[0].resolvedStartMinuteOfDay, 0)
        XCTAssertEqual(dayPlan.blocks[0].resolvedEndMinuteOfDay, 120)
    }

    func testSuggestedTemplatesSkipEmptyDayPlans() throws {
        let empty = DayPlan(date: LocalDay(year: 2026, month: 3, day: 17))
        let nonEmpty = makePlan(
            date: LocalDay(year: 2026, month: 3, day: 19),
            blocks: [baseBlock(title: "Day2", start: 0, requestedEnd: 60)]
        )

        let suggested = try TemplateEngine.suggestedTemplates(
            referenceDay: LocalDay(year: 2026, month: 3, day: 19),
            from: [empty, nonEmpty]
        )

        XCTAssertEqual(suggested.map(\.sourceDate), [LocalDay(year: 2026, month: 3, day: 19)])
    }

    func testEnsureMaterializedReturnsExistingPlanWithoutReplacingIt() throws {
        let existing = DayPlan(
            id: UUID(),
            date: LocalDay(year: 2026, month: 3, day: 21),
            sourceSavedTemplateID: nil,
            lastGeneratedAt: nil,
            hasUserEdits: true,
            blocks: [baseBlock(title: "Manual", start: 30, requestedEnd: 90)]
        )
        let template = SavedDayTemplate(
            title: "Template",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                BlockTemplate(
                    layerIndex: 0,
                    title: "Generated",
                    timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 120)
                )
            ]
        )

        let materialized = try TemplateEngine.ensureMaterializedDayPlan(
            for: existing.date,
            existingDayPlans: [existing],
            savedTemplates: [template],
            weekdayRules: [WeekdayTemplateRule(weekday: existing.date.weekday, savedTemplateID: template.id)],
            overrides: []
        )

        XCTAssertEqual(materialized, existing)
    }

    func testEnsureMaterializedCreatesEmptyPlanWhenNoTemplateMatches() throws {
        let generatedAt = Date(timeIntervalSince1970: 2_000)
        let date = LocalDay(year: 2026, month: 3, day: 22)

        let materialized = try TemplateEngine.ensureMaterializedDayPlan(
            for: date,
            existingDayPlans: [],
            savedTemplates: [],
            weekdayRules: [],
            overrides: [],
            generatedAt: generatedAt
        )

        XCTAssertEqual(materialized.date, date)
        XCTAssertTrue(materialized.blocks.isEmpty)
        XCTAssertNil(materialized.sourceSavedTemplateID)
        XCTAssertEqual(materialized.lastGeneratedAt, generatedAt)
        XCTAssertFalse(materialized.hasUserEdits)
    }

    func testEnsureMaterializedInstantiatesTemplateUsingOverridePriority() throws {
        let generatedAt = Date(timeIntervalSince1970: 3_000)
        let date = LocalDay(year: 2026, month: 3, day: 20)
        let weekdayTemplate = SavedDayTemplate(
            title: "Weekday",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                BlockTemplate(
                    layerIndex: 0,
                    title: "Weekday Block",
                    timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 120)
                )
            ]
        )
        let overrideTemplate = SavedDayTemplate(
            title: "Override",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                BlockTemplate(
                    layerIndex: 0,
                    title: "Override Block",
                    timing: .absolute(startMinuteOfDay: 120, requestedEndMinuteOfDay: 240)
                )
            ]
        )

        let materialized = try TemplateEngine.ensureMaterializedDayPlan(
            for: date,
            existingDayPlans: [],
            savedTemplates: [weekdayTemplate, overrideTemplate],
            weekdayRules: [WeekdayTemplateRule(weekday: .friday, savedTemplateID: weekdayTemplate.id)],
            overrides: [DateTemplateOverride(date: date, savedTemplateID: overrideTemplate.id)],
            generatedAt: generatedAt
        )

        XCTAssertEqual(materialized.sourceSavedTemplateID, overrideTemplate.id)
        XCTAssertEqual(materialized.lastGeneratedAt, generatedAt)
        XCTAssertEqual(materialized.blocks.map(\.title), ["Override Block"])
    }

    func testRegenerateFutureDayPlanRejectsTodayAndPast() {
        let today = LocalDay(year: 2026, month: 3, day: 19)

        XCTAssertThrowsError(
            try TemplateEngine.regenerateFutureDayPlan(
                for: today,
                today: today,
                existingDayPlans: [],
                savedTemplates: [],
                weekdayRules: [],
                overrides: []
            )
        ) { error in
            XCTAssertEqual(
                error as? ThingStructCoreError,
                .regenerationNotAllowedForNonFutureDate(today)
            )
        }
    }

    func testRegenerateFutureDayPlanRejectsUserEditedOrCompletedPlans() {
        let today = LocalDay(year: 2026, month: 3, day: 19)
        let future = LocalDay(year: 2026, month: 3, day: 20)

        let editedPlan = DayPlan(
            date: future,
            hasUserEdits: true,
            blocks: [baseBlock(title: "Edited", start: 0, requestedEnd: 60)]
        )
        XCTAssertThrowsError(
            try TemplateEngine.regenerateFutureDayPlan(
                for: future,
                today: today,
                existingDayPlans: [editedPlan],
                savedTemplates: [],
                weekdayRules: [],
                overrides: []
            )
        ) { error in
            XCTAssertEqual(
                error as? ThingStructCoreError,
                .regenerationBlockedByUserEdits(future)
            )
        }

        let completedPlan = DayPlan(
            date: future,
            hasUserEdits: false,
            blocks: [baseBlock(title: "Completed", start: 0, requestedEnd: 60, tasks: [task("Done", completed: true)])]
        )
        XCTAssertThrowsError(
            try TemplateEngine.regenerateFutureDayPlan(
                for: future,
                today: today,
                existingDayPlans: [completedPlan],
                savedTemplates: [],
                weekdayRules: [],
                overrides: []
            )
        ) { error in
            XCTAssertEqual(
                error as? ThingStructCoreError,
                .regenerationBlockedByCompletedTasks(future)
            )
        }
    }

    func testRegenerateFutureDayPlanReusesExistingIDAndRefreshesSnapshot() throws {
        let today = LocalDay(year: 2026, month: 3, day: 19)
        let future = LocalDay(year: 2026, month: 3, day: 20)
        let generatedAt = Date(timeIntervalSince1970: 4_000)
        let existingID = UUID()
        let existing = DayPlan(
            id: existingID,
            date: future,
            sourceSavedTemplateID: nil,
            lastGeneratedAt: Date(timeIntervalSince1970: 10),
            hasUserEdits: false,
            blocks: []
        )
        let template = SavedDayTemplate(
            title: "Future Template",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                BlockTemplate(
                    layerIndex: 0,
                    title: "Generated Block",
                    timing: .absolute(startMinuteOfDay: 30, requestedEndMinuteOfDay: 90)
                )
            ]
        )

        let regenerated = try TemplateEngine.regenerateFutureDayPlan(
            for: future,
            today: today,
            existingDayPlans: [existing],
            savedTemplates: [template],
            weekdayRules: [WeekdayTemplateRule(weekday: future.weekday, savedTemplateID: template.id)],
            overrides: [],
            generatedAt: generatedAt
        )

        XCTAssertEqual(regenerated.id, existingID)
        XCTAssertEqual(regenerated.sourceSavedTemplateID, template.id)
        XCTAssertEqual(regenerated.lastGeneratedAt, generatedAt)
        XCTAssertEqual(regenerated.blocks.map(\.title), ["Generated Block"])
        XCTAssertEqual(regenerated.blocks.first?.resolvedStartMinuteOfDay, 30)
        XCTAssertEqual(regenerated.blocks.first?.resolvedEndMinuteOfDay, 90)
    }
}
