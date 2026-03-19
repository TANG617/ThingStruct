import XCTest
@testable import ThingStructCore

final class PresentationTests: XCTestCase {
    func testSeededDocumentCreatesSavedTemplatesAndTomorrowPlan() throws {
        let referenceDay = LocalDay(year: 2026, month: 3, day: 19)
        let document = try SampleDataFactory.seededDocument(referenceDay: referenceDay)

        XCTAssertFalse(document.savedTemplates.isEmpty)
        XCTAssertNotNil(document.dayPlan(for: referenceDay.adding(days: 1)))
    }

    func testNowScreenModelShowsBlankMessageWhenNoUserBlocksExist() throws {
        let model = try ThingStructPresentation.nowScreenModel(
            document: ThingStructDocument(),
            date: LocalDay(year: 2026, month: 3, day: 19),
            minuteOfDay: 600
        )

        XCTAssertEqual(model.statusMessage, "当前为空白时段")
        XCTAssertEqual(model.activeChain.count, 1)
        XCTAssertTrue(model.activeChain.first?.isBlank == true)
    }

    func testTodayScreenModelIncludesRuntimeBlankBlocks() throws {
        let morning = baseBlock(title: "Morning", start: 60, requestedEnd: 120)
        let document = ThingStructDocument(
            dayPlans: [makePlan(blocks: [morning])]
        )

        let model = try ThingStructPresentation.todayScreenModel(
            document: document,
            date: LocalDay(year: 2026, month: 3, day: 19),
            selectedBlockID: nil,
            initialMinute: nil
        )

        XCTAssertTrue(model.blocks.contains(where: \.isBlank))
        XCTAssertTrue(model.blocks.contains(where: { !$0.isBlank && $0.title == "Morning" }))
    }

    func testTemplatesScreenModelUsesOverrideForTomorrowSummary() throws {
        let referenceDay = LocalDay(year: 2026, month: 3, day: 19)
        let tomorrow = referenceDay.adding(days: 1)
        let weekdayTemplate = SavedDayTemplate(
            title: "Weekday",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
        let overrideTemplate = SavedDayTemplate(
            title: "Override",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )

        let model = try ThingStructPresentation.templatesScreenModel(
            document: ThingStructDocument(
                dayPlans: [],
                savedTemplates: [weekdayTemplate, overrideTemplate],
                weekdayRules: [WeekdayTemplateRule(weekday: tomorrow.weekday, savedTemplateID: weekdayTemplate.id)],
                overrides: [DateTemplateOverride(date: tomorrow, savedTemplateID: overrideTemplate.id)]
            ),
            referenceDay: referenceDay
        )

        XCTAssertEqual(model.tomorrowSchedule.weekdayTemplateTitle, "Weekday")
        XCTAssertEqual(model.tomorrowSchedule.overrideTemplateTitle, "Override")
        XCTAssertEqual(model.tomorrowSchedule.finalTemplateTitle, "Override")
    }
}
