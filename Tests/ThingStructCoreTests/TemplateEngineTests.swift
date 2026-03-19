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
            for: LocalDay(year: 2026, month: 3, day: 21)
        )

        XCTAssertEqual(dayPlan.date, LocalDay(year: 2026, month: 3, day: 21))
        XCTAssertEqual(dayPlan.blocks.count, 1)
        XCTAssertEqual(dayPlan.blocks[0].tasks.map { $0.isCompleted }, [false, false])
        XCTAssertEqual(dayPlan.blocks[0].resolvedStartMinuteOfDay, 0)
        XCTAssertEqual(dayPlan.blocks[0].resolvedEndMinuteOfDay, 120)
    }
}
