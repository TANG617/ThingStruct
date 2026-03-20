import XCTest
@testable import ThingStructCore

final class DayPlanResizeTests: XCTestCase {
    func testResizeBaseBlockClampsToNextSiblingAndFiveMinuteGrid() throws {
        let morningID = UUID()
        let afternoonID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: morningID,
                title: "Morning",
                start: 540,
                requestedEnd: 720
            ),
            baseBlock(
                id: afternoonID,
                title: "Afternoon",
                start: 780,
                requestedEnd: 900
            )
        ])

        let bounds = try DayPlanEngine.resizeBounds(for: morningID, in: plan)
        XCTAssertEqual(bounds.minimumEndMinuteOfDay, 545)
        XCTAssertEqual(bounds.maximumEndMinuteOfDay, 780)

        let resized = try DayPlanEngine.resizeBlockEnd(
            morningID,
            in: plan,
            proposedEndMinuteOfDay: 793
        )
        let updated = try XCTUnwrap(resized.blocks.first(where: { $0.id == morningID }))

        XCTAssertEqual(updated.resolvedEndMinuteOfDay, 780)
        if case let .absolute(_, requestedEndMinuteOfDay) = updated.timing {
            XCTAssertEqual(requestedEndMinuteOfDay, 780)
        } else {
            XCTFail("Expected absolute timing after resizing a base block.")
        }
    }

    func testResizeOverlayUpdatesRelativeDuration() throws {
        let baseID = UUID()
        let sprintID = UUID()
        let reviewID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: baseID,
                title: "Work Block",
                start: 540,
                requestedEnd: 720
            ),
            overlayRelative(
                id: sprintID,
                parentID: baseID,
                layerIndex: 1,
                title: "Sprint",
                offset: 30,
                duration: 120
            ),
            overlayRelative(
                id: reviewID,
                parentID: baseID,
                layerIndex: 1,
                title: "Review",
                offset: 150,
                duration: 30
            )
        ])

        let bounds = try DayPlanEngine.resizeBounds(for: sprintID, in: plan)
        XCTAssertEqual(bounds.maximumEndMinuteOfDay, 690)

        let resized = try DayPlanEngine.resizeBlockEnd(
            sprintID,
            in: plan,
            proposedEndMinuteOfDay: 675
        )
        let updated = try XCTUnwrap(resized.blocks.first(where: { $0.id == sprintID }))

        XCTAssertEqual(updated.resolvedEndMinuteOfDay, 675)
        if case let .relative(startOffsetMinutes, requestedDurationMinutes) = updated.timing {
            XCTAssertEqual(startOffsetMinutes, 30)
            XCTAssertEqual(requestedDurationMinutes, 105)
        } else {
            XCTFail("Expected relative timing after resizing an overlay block.")
        }
    }

    func testResizeBaseBlockStartClampsToPreviousSiblingAndUpdatesAbsoluteStart() throws {
        let firstID = UUID()
        let secondID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: firstID,
                title: "Breakfast",
                start: 480,
                requestedEnd: 540
            ),
            baseBlock(
                id: secondID,
                title: "Work",
                start: 600,
                requestedEnd: 720
            )
        ])

        let bounds = try DayPlanEngine.resizeBounds(for: secondID, in: plan)
        XCTAssertEqual(bounds.minimumStartMinuteOfDay, 540)
        XCTAssertEqual(bounds.maximumStartMinuteOfDay, 715)

        let resized = try DayPlanEngine.resizeBlockStart(
            secondID,
            in: plan,
            proposedStartMinuteOfDay: 523
        )
        let updated = try XCTUnwrap(resized.blocks.first(where: { $0.id == secondID }))

        XCTAssertEqual(updated.resolvedStartMinuteOfDay, 540)
        XCTAssertEqual(updated.resolvedEndMinuteOfDay, 720)
        if case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay) = updated.timing {
            XCTAssertEqual(startMinuteOfDay, 540)
            XCTAssertEqual(requestedEndMinuteOfDay, 720)
        } else {
            XCTFail("Expected absolute timing after resizing a base block start.")
        }
    }

    func testResizeOverlayStartUpdatesRelativeOffsetAndDuration() throws {
        let baseID = UUID()
        let overlayID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: baseID,
                title: "Morning",
                start: 540,
                requestedEnd: 720
            ),
            overlayRelative(
                id: overlayID,
                parentID: baseID,
                layerIndex: 1,
                title: "Focus",
                offset: 30,
                duration: 90
            )
        ])

        let bounds = try DayPlanEngine.resizeBounds(for: overlayID, in: plan)
        XCTAssertEqual(bounds.minimumStartMinuteOfDay, 540)
        XCTAssertEqual(bounds.maximumStartMinuteOfDay, 655)

        let resized = try DayPlanEngine.resizeBlockStart(
            overlayID,
            in: plan,
            proposedStartMinuteOfDay: 585
        )
        let updated = try XCTUnwrap(resized.blocks.first(where: { $0.id == overlayID }))

        XCTAssertEqual(updated.resolvedStartMinuteOfDay, 585)
        XCTAssertEqual(updated.resolvedEndMinuteOfDay, 660)
        if case let .relative(startOffsetMinutes, requestedDurationMinutes) = updated.timing {
            XCTAssertEqual(startOffsetMinutes, 45)
            XCTAssertEqual(requestedDurationMinutes, 75)
        } else {
            XCTFail("Expected relative timing after resizing an overlay block start.")
        }
    }

    func testResizeBoundsRespectDescendantEnd() throws {
        let baseID = UUID()
        let overlayID = UUID()
        let nestedID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: baseID,
                title: "Morning",
                start: 540,
                requestedEnd: 720
            ),
            overlayRelative(
                id: overlayID,
                parentID: baseID,
                layerIndex: 1,
                title: "Focus",
                offset: 20,
                duration: 100
            ),
            overlayRelative(
                id: nestedID,
                parentID: overlayID,
                layerIndex: 2,
                title: "Deep Focus",
                offset: 40,
                duration: 30
            )
        ])

        let bounds = try DayPlanEngine.resizeBounds(for: overlayID, in: plan)
        XCTAssertEqual(bounds.minimumEndMinuteOfDay, 630)

        let resized = try DayPlanEngine.resizeBlockEnd(
            overlayID,
            in: plan,
            proposedEndMinuteOfDay: 605
        )
        let updated = try XCTUnwrap(resized.blocks.first(where: { $0.id == overlayID }))

        XCTAssertEqual(updated.resolvedEndMinuteOfDay, 630)
    }

    func testResizeOverlayStartRespectsDescendantTimingConstraints() throws {
        let baseID = UUID()
        let overlayID = UUID()
        let nestedID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: baseID,
                title: "Morning",
                start: 540,
                requestedEnd: 720
            ),
            overlayRelative(
                id: overlayID,
                parentID: baseID,
                layerIndex: 1,
                title: "Focus",
                offset: 20,
                duration: 100
            ),
            overlayAbsolute(
                id: nestedID,
                parentID: overlayID,
                layerIndex: 2,
                title: "Pinned Review",
                start: 585,
                requestedEnd: 610
            )
        ])

        let bounds = try DayPlanEngine.resizeBounds(for: overlayID, in: plan)
        XCTAssertEqual(bounds.maximumStartMinuteOfDay, 585)

        let resized = try DayPlanEngine.resizeBlockStart(
            overlayID,
            in: plan,
            proposedStartMinuteOfDay: 600
        )
        let updated = try XCTUnwrap(resized.blocks.first(where: { $0.id == overlayID }))

        XCTAssertEqual(updated.resolvedStartMinuteOfDay, 585)
        XCTAssertEqual(updated.resolvedEndMinuteOfDay, 660)
    }
}
