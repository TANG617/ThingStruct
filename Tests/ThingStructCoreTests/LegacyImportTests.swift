import XCTest
@testable import ThingStructCore

final class LegacyImportTests: XCTestCase {
    func testImportBuildsDayPlansFromLegacyStates() throws {
        let document = try LegacyImportEngine.importDocument(
            states: [
                LegacyStateSnapshot(
                    title: "Morning",
                    order: 0,
                    date: LocalDay(year: 2026, month: 3, day: 19),
                    checklistItems: [
                        LegacyChecklistSnapshot(title: "Stretch", order: 1),
                        LegacyChecklistSnapshot(title: "Water", order: 0, isCompleted: true)
                    ]
                ),
                LegacyStateSnapshot(
                    title: "Work",
                    order: 1,
                    date: LocalDay(year: 2026, month: 3, day: 19),
                    isCompleted: true
                )
            ],
            stateTemplates: [],
            routineTemplates: []
        )

        let plan = try XCTUnwrap(document.dayPlan(for: LocalDay(year: 2026, month: 3, day: 19)))
        XCTAssertTrue(plan.hasUserEdits)
        XCTAssertEqual(plan.blocks.count, 2)
        XCTAssertEqual(plan.blocks.map(\.title), ["Morning", "Work"])
        XCTAssertEqual(plan.blocks[0].resolvedStartMinuteOfDay, 0)
        XCTAssertEqual(plan.blocks[0].resolvedEndMinuteOfDay, 720)
        XCTAssertEqual(plan.blocks[1].resolvedStartMinuteOfDay, 720)
        XCTAssertEqual(plan.blocks[1].resolvedEndMinuteOfDay, 1440)
        XCTAssertEqual(plan.blocks[0].tasks.map(\.title), ["Water", "Stretch"])
        XCTAssertEqual(plan.blocks[1].tasks.map(\.title), ["Imported completion"])
        XCTAssertEqual(plan.blocks[1].tasks.map(\.isCompleted), [true])
    }

    func testImportCreatesSavedTemplatesAndWeekdayRulesFromLegacyTemplates() throws {
        let orphanStateTemplateID = UUID()
        let routineStateTemplateID = UUID()

        let document = try LegacyImportEngine.importDocument(
            states: [],
            stateTemplates: [
                LegacyStateTemplateSnapshot(
                    id: orphanStateTemplateID,
                    title: "Quick Reset",
                    checklistItems: [LegacyChecklistSnapshot(title: "Breathe", order: 0)]
                ),
                LegacyStateTemplateSnapshot(
                    id: routineStateTemplateID,
                    title: "Shared Template",
                    checklistItems: [LegacyChecklistSnapshot(title: "Prepare", order: 0)]
                )
            ],
            routineTemplates: [
                LegacyRoutineTemplateSnapshot(
                    title: "Workday",
                    repeatDays: [.monday, .wednesday],
                    stateTemplates: [
                        LegacyStateTemplateSnapshot(
                            id: routineStateTemplateID,
                            title: "Shared Template",
                            checklistItems: [LegacyChecklistSnapshot(title: "Prepare", order: 0)]
                        ),
                        LegacyStateTemplateSnapshot(
                            title: "Focus",
                            checklistItems: [LegacyChecklistSnapshot(title: "Ship", order: 0)]
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(document.savedTemplates.count, 2)
        XCTAssertEqual(Set(document.savedTemplates.map(\.title)), ["Quick Reset", "Workday"])

        let workdayTemplate = try XCTUnwrap(document.savedTemplates.first(where: { $0.title == "Workday" }))
        XCTAssertEqual(workdayTemplate.blocks.count, 2)
        XCTAssertEqual(workdayTemplate.blocks.map(\.title), ["Shared Template", "Focus"])

        let orphanTemplate = try XCTUnwrap(document.savedTemplates.first(where: { $0.title == "Quick Reset" }))
        XCTAssertEqual(orphanTemplate.blocks.count, 1)
        XCTAssertEqual(orphanTemplate.blocks[0].title, "Quick Reset")

        XCTAssertEqual(
            document.weekdayRules.filter { $0.savedTemplateID == workdayTemplate.id }.map(\.weekday),
            [.monday, .wednesday]
        )
    }
}
