import XCTest
@testable import ThingStructCore

final class CancelAndTaskSelectionTests: XCTestCase {
    func testCancelCollapsesDescendantsAndKeepsTimesStable() throws {
        let morning = baseBlock(title: "Morning", start: 0, requestedEnd: 300)
        let work = overlayRelative(
            parentID: morning.id,
            layerIndex: 1,
            title: "Work",
            offset: 60,
            duration: 180
        )
        let meeting = overlayRelative(
            parentID: work.id,
            layerIndex: 2,
            title: "Meeting",
            offset: 30,
            duration: 60
        )
        let notes = overlayRelative(
            parentID: meeting.id,
            layerIndex: 3,
            title: "Notes",
            offset: 10,
            duration: 20
        )

        let collapsed = try DayPlanEngine.cancelBlock(
            work.id,
            in: makePlan(blocks: [morning, work, meeting, notes])
        )

        let collapsedWork = try XCTUnwrap(collapsed.blocks.first(where: { $0.id == work.id }))
        let collapsedMeeting = try XCTUnwrap(collapsed.blocks.first(where: { $0.id == meeting.id }))
        let collapsedNotes = try XCTUnwrap(collapsed.blocks.first(where: { $0.id == notes.id }))

        XCTAssertTrue(collapsedWork.isCancelled)
        XCTAssertEqual(collapsedMeeting.parentBlockID, morning.id)
        XCTAssertEqual(collapsedMeeting.layerIndex, 1)
        XCTAssertEqual(collapsedMeeting.resolvedStartMinuteOfDay, 90)
        XCTAssertEqual(collapsedMeeting.resolvedEndMinuteOfDay, 150)

        XCTAssertEqual(collapsedNotes.parentBlockID, meeting.id)
        XCTAssertEqual(collapsedNotes.layerIndex, 2)
        XCTAssertEqual(collapsedNotes.resolvedStartMinuteOfDay, 100)
        XCTAssertEqual(collapsedNotes.resolvedEndMinuteOfDay, 120)
    }

    func testTaskSourceIsTopBlockWhenTopHasIncompleteTasks() throws {
        let morning = baseBlock(
            title: "Morning",
            start: 0,
            requestedEnd: 300,
            tasks: [task("Drink water", completed: true)]
        )
        let work = overlayRelative(
            parentID: morning.id,
            layerIndex: 1,
            title: "Work",
            offset: 60,
            duration: 180,
            tasks: [task("Write code", completed: false)]
        )

        let selection = try DayPlanEngine.activeSelection(
            in: makePlan(blocks: [morning, work]),
            at: 90
        )

        XCTAssertEqual(selection.activeBlock?.id, work.id)
        XCTAssertEqual(selection.taskSourceBlock?.id, work.id)
    }

    func testTaskSourceFallsBackToLowerLayerWhenTopIsComplete() throws {
        let morning = baseBlock(
            title: "Morning",
            start: 0,
            requestedEnd: 300,
            tasks: [task("Morning routine", completed: false)]
        )
        let work = overlayRelative(
            parentID: morning.id,
            layerIndex: 1,
            title: "Work",
            offset: 60,
            duration: 180,
            tasks: [task("Top task", completed: true)]
        )
        let focus = overlayRelative(
            parentID: work.id,
            layerIndex: 2,
            title: "Focus",
            offset: 10,
            duration: 30,
            tasks: [task("Deep work", completed: true)]
        )

        let selection = try DayPlanEngine.activeSelection(
            in: makePlan(blocks: [morning, work, focus]),
            at: 90
        )

        XCTAssertEqual(selection.activeBlock?.id, focus.id)
        XCTAssertEqual(selection.taskSourceBlock?.id, morning.id)
    }

    func testTaskSourceIsNilWhenEntireChainIsCompleted() throws {
        let morning = baseBlock(
            title: "Morning",
            start: 0,
            requestedEnd: 300,
            tasks: [task("Morning routine", completed: true)]
        )
        let work = overlayRelative(
            parentID: morning.id,
            layerIndex: 1,
            title: "Work",
            offset: 60,
            duration: 180,
            tasks: [task("Top task", completed: true)]
        )

        let selection = try DayPlanEngine.activeSelection(
            in: makePlan(blocks: [morning, work]),
            at: 90
        )

        XCTAssertEqual(selection.activeBlock?.id, work.id)
        XCTAssertNil(selection.taskSourceBlock)
    }
}
