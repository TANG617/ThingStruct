import XCTest
@testable import ThingStructCore

final class TemplateMutationTests: XCTestCase {
    func testPreviewDayPlanResolvesTemplateBlocks() throws {
        let baseID = UUID()
        let template = SavedDayTemplate(
            title: "Preview",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                templateBlock(
                    id: baseID,
                    title: "Morning",
                    timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720)
                ),
                templateBlock(
                    parentID: baseID,
                    layerIndex: 1,
                    title: "Focus",
                    timing: .relative(startOffsetMinutes: 30, requestedDurationMinutes: 120)
                )
            ]
        )

        let preview = try TemplateEngine.previewDayPlan(from: template)

        XCTAssertEqual(preview.blocks.count, 2)
        XCTAssertEqual(preview.blocks.first(where: { $0.title == "Morning" })?.resolvedEndMinuteOfDay, 720)
        XCTAssertEqual(preview.blocks.first(where: { $0.title == "Focus" })?.resolvedStartMinuteOfDay, 510)
        XCTAssertEqual(preview.blocks.first(where: { $0.title == "Focus" })?.resolvedEndMinuteOfDay, 630)
    }

    func testUpdateSavedTemplateReplacesBlocksAndWeekdays() throws {
        let template = SavedDayTemplate(
            title: "Original",
            sourceSuggestedTemplateID: UUID(),
            blocks: [
                templateBlock(
                    title: "Morning",
                    tasks: [TaskBlueprint(title: "Old 0", order: 7), TaskBlueprint(title: "Old 1", order: 9)],
                    timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720)
                )
            ]
        )
        let otherTemplate = SavedDayTemplate(
            title: "Other",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )

        let updated = try TemplateEngine.updateSavedTemplate(
            template.id,
            title: "Updated",
            blocks: [
                templateBlock(
                    title: "Updated Block",
                    tasks: [TaskBlueprint(title: "First", order: 99), TaskBlueprint(title: "Second", order: 42)],
                    timing: .absolute(startMinuteOfDay: 600, requestedEndMinuteOfDay: 900)
                )
            ],
            assignedWeekdays: [.tuesday, .friday],
            in: ThingStructDocument(
                dayPlans: [],
                savedTemplates: [template, otherTemplate],
                weekdayRules: [
                    WeekdayTemplateRule(weekday: .monday, savedTemplateID: template.id),
                    WeekdayTemplateRule(weekday: .friday, savedTemplateID: otherTemplate.id)
                ],
                overrides: []
            )
        )

        let saved = try XCTUnwrap(updated.savedTemplates.first(where: { $0.id == template.id }))
        XCTAssertEqual(saved.title, "Updated")
        XCTAssertEqual(saved.blocks.map(\.title), ["Updated Block"])
        XCTAssertEqual(saved.blocks[0].taskBlueprints.map(\.order), [0, 1])
        XCTAssertEqual(
            updated.weekdayRules.filter { $0.savedTemplateID == template.id }.map(\.weekday),
            [.tuesday, .friday]
        )
        XCTAssertFalse(updated.weekdayRules.contains { $0.savedTemplateID == otherTemplate.id && $0.weekday == .friday })
    }

    func testDeleteSavedTemplateRemovesRulesOverridesAndClearsDayPlanSource() {
        let template = SavedDayTemplate(
            title: "Delete Me",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
        let otherTemplate = SavedDayTemplate(
            title: "Keep Me",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
        let date = LocalDay(year: 2026, month: 3, day: 20)

        let updated = TemplateEngine.deleteSavedTemplate(
            template.id,
            from: ThingStructDocument(
                dayPlans: [
                    DayPlan(date: date, sourceSavedTemplateID: template.id, blocks: [])
                ],
                savedTemplates: [template, otherTemplate],
                weekdayRules: [WeekdayTemplateRule(weekday: .friday, savedTemplateID: template.id)],
                overrides: [DateTemplateOverride(date: date, savedTemplateID: template.id)]
            )
        )

        XCTAssertEqual(updated.savedTemplates.map(\.id), [otherTemplate.id])
        XCTAssertTrue(updated.weekdayRules.isEmpty)
        XCTAssertTrue(updated.overrides.isEmpty)
        XCTAssertNil(updated.dayPlans.first?.sourceSavedTemplateID)
    }
}
