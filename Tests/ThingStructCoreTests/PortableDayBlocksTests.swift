import XCTest
@testable import ThingStructCore

final class PortableDayBlocksTests: XCTestCase {
    func testRoundTripPreservesNestedStructureAndTaskCompletion() throws {
        let day = LocalDay(year: 2026, month: 3, day: 24)
        let morningID = UUID()
        let focusID = UUID()

        let morning = TimeBlock(
            id: morningID,
            layerIndex: 0,
            title: "Morning",
            note: "Plan\nWork",
            reminders: [
                ReminderRule(triggerMode: .atStart),
                ReminderRule(triggerMode: .beforeStart, offsetMinutes: 10)
            ],
            tasks: [
                TaskItem(title: "Plan the session", isCompleted: true),
                TaskItem(title: "Do the work", order: 1)
            ],
            timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720)
        )
        let focus = TimeBlock(
            id: focusID,
            parentBlockID: morningID,
            layerIndex: 1,
            title: "Focus",
            tasks: [TaskItem(title: "Deep work")],
            timing: .relative(startOffsetMinutes: 30, requestedDurationMinutes: 120)
        )

        let plan = try DayPlanEngine.resolved(
            DayPlan(
                date: day,
                blocks: [morning, focus]
            )
        )

        let yaml = try ThingStructPortableDayBlocks.exportYAML(from: plan)
        XCTAssertTrue(yaml.contains("kind: day_blocks"))
        XCTAssertTrue(yaml.contains("children:"))
        XCTAssertTrue(yaml.contains("10m_before"))

        let summary = try ThingStructPortableDayBlocks.summary(fromYAML: yaml)
        XCTAssertEqual(summary.sourceDate, day)
        XCTAssertEqual(summary.baseBlockCount, 1)
        XCTAssertEqual(summary.totalBlockCount, 2)
        XCTAssertEqual(summary.taskCount, 3)

        let imported = try ThingStructPortableDayBlocks.dayPlanForImport(fromYAML: yaml, on: day)
        XCTAssertEqual(imported.blocks.count, 2)

        let importedMorning = try XCTUnwrap(imported.blocks.first(where: { $0.layerIndex == 0 }))
        let importedFocus = try XCTUnwrap(imported.blocks.first(where: { $0.layerIndex == 1 }))

        XCTAssertEqual(importedMorning.title, "Morning")
        XCTAssertEqual(importedMorning.note, "Plan\nWork")
        XCTAssertEqual(importedMorning.reminders.count, 2)
        XCTAssertEqual(importedMorning.tasks.map(\.isCompleted), [true, false])
        XCTAssertEqual(importedMorning.tasks.map(\.title), ["Plan the session", "Do the work"])

        XCTAssertEqual(importedFocus.parentBlockID, importedMorning.id)
        if case let .relative(offsetMinutes, durationMinutes) = importedFocus.timing {
            XCTAssertEqual(offsetMinutes, 30)
            XCTAssertEqual(durationMinutes, 120)
        } else {
            XCTFail("Expected imported child block to keep relative timing.")
        }
    }

    func testExportSkipsCancelledAndBlankBlocks() throws {
        let day = LocalDay(year: 2026, month: 3, day: 24)
        let active = TimeBlock(
            layerIndex: 0,
            title: "Active",
            timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720)
        )
        var cancelled = TimeBlock(
            layerIndex: 0,
            title: "Cancelled",
            timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 900)
        )
        cancelled.isCancelled = true
        let blank = TimeBlock(
            layerIndex: 0,
            kind: .blankBase,
            title: "Blank",
            timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 480)
        )

        let yaml = try ThingStructPortableDayBlocks.exportYAML(
            from: DayPlan(date: day, blocks: [blank, active, cancelled])
        )

        XCTAssertTrue(yaml.contains("\"Active\""))
        XCTAssertFalse(yaml.contains("\"Cancelled\""))
        XCTAssertFalse(yaml.contains("\"Blank\""))
    }

    func testImportRejectsInvalidTimes() {
        let yaml = """
        version: 1
        kind: day_blocks
        source_date: 2026-03-24
        blocks:
          - title: "Morning"
            timing:
              type: absolute
              start: "25:00"
        """

        XCTAssertThrowsError(try ThingStructPortableDayBlocks.summary(fromYAML: yaml)) { error in
            XCTAssertTrue(error.localizedDescription.contains("timing.start"))
        }
    }

    func testImportedDayPlanKeepsRequestedIdentityAndManualState() throws {
        let day = LocalDay(year: 2026, month: 3, day: 24)
        let dayPlanID = UUID()
        let generatedAt = Date(timeIntervalSince1970: 123_456)
        let yaml = """
        version: 1
        kind: day_blocks
        source_date: 2026-03-20
        blocks:
          - title: "Morning"
            timing:
              type: absolute
              start: "08:00"
              end: "10:00"
            tasks:
              - title: "Done already"
                completed: true
        """

        let imported = try ThingStructPortableDayBlocks.dayPlanForImport(
            fromYAML: yaml,
            on: day,
            dayPlanID: dayPlanID,
            lastGeneratedAt: generatedAt
        )

        XCTAssertEqual(imported.id, dayPlanID)
        XCTAssertEqual(imported.date, day)
        XCTAssertEqual(imported.lastGeneratedAt, generatedAt)
        XCTAssertNil(imported.sourceSavedTemplateID)
        XCTAssertTrue(imported.hasUserEdits)

        let block = try XCTUnwrap(imported.blocks.first)
        XCTAssertEqual(block.dayPlanID, dayPlanID)
        XCTAssertEqual(block.tasks.first?.isCompleted, true)
        XCTAssertNil(block.tasks.first?.completedAt)
    }
}
