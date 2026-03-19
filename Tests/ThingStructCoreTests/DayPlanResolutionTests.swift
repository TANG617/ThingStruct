import XCTest
@testable import ThingStructCore

final class DayPlanResolutionTests: XCTestCase {
    func testBaseBlocksEndAtNextSiblingOrMidnight() throws {
        let morning = baseBlock(title: "Morning", start: 360)
        let afternoon = baseBlock(title: "Afternoon", start: 780)

        let resolved = try DayPlanEngine.resolved(makePlan(blocks: [afternoon, morning]))

        let resolvedMorning = try XCTUnwrap(resolved.blocks.first(where: { $0.id == morning.id }))
        let resolvedAfternoon = try XCTUnwrap(resolved.blocks.first(where: { $0.id == afternoon.id }))

        XCTAssertEqual(resolvedMorning.resolvedStartMinuteOfDay, 360)
        XCTAssertEqual(resolvedMorning.resolvedEndMinuteOfDay, 780)
        XCTAssertEqual(resolvedAfternoon.resolvedStartMinuteOfDay, 780)
        XCTAssertEqual(resolvedAfternoon.resolvedEndMinuteOfDay, 1440)
    }

    func testRelativeOverlayDurationIsTruncatedByParent() throws {
        let morning = baseBlock(title: "Morning", start: 0, requestedEnd: 120)
        let work = overlayRelative(
            parentID: morning.id,
            layerIndex: 1,
            title: "Work",
            offset: 30,
            duration: 200
        )

        let resolved = try DayPlanEngine.resolved(makePlan(blocks: [morning, work]))
        let resolvedWork = try XCTUnwrap(resolved.blocks.first(where: { $0.id == work.id }))

        XCTAssertEqual(resolvedWork.resolvedStartMinuteOfDay, 30)
        XCTAssertEqual(resolvedWork.resolvedEndMinuteOfDay, 120)
    }

    func testAbsoluteOverlayRequestedEndIsTruncatedByNextSibling() throws {
        let morning = baseBlock(title: "Morning", start: 0, requestedEnd: 300)
        let work = overlayAbsolute(
            parentID: morning.id,
            layerIndex: 1,
            title: "Work",
            start: 30,
            requestedEnd: 200
        )
        let breakBlock = overlayAbsolute(
            parentID: morning.id,
            layerIndex: 1,
            title: "Break",
            start: 120,
            requestedEnd: 180
        )

        let resolved = try DayPlanEngine.resolved(makePlan(blocks: [morning, work, breakBlock]))
        let resolvedWork = try XCTUnwrap(resolved.blocks.first(where: { $0.id == work.id }))
        let resolvedBreak = try XCTUnwrap(resolved.blocks.first(where: { $0.id == breakBlock.id }))

        XCTAssertEqual(resolvedWork.resolvedEndMinuteOfDay, 120)
        XCTAssertEqual(resolvedBreak.resolvedStartMinuteOfDay, 120)
        XCTAssertEqual(resolvedBreak.resolvedEndMinuteOfDay, 180)
    }

    func testInvalidTimeOutsideParentIsRejected() {
        let morning = baseBlock(title: "Morning", start: 0, requestedEnd: 120)
        let invalidOverlay = overlayAbsolute(
            parentID: morning.id,
            layerIndex: 1,
            title: "Too Late",
            start: 130,
            requestedEnd: 140
        )

        let plan = makePlan(blocks: [morning, invalidOverlay])

        XCTAssertThrowsError(try DayPlanEngine.resolved(plan)) { error in
            XCTAssertEqual(
                error as? ThingStructCoreError,
                .blockOutsideParent(blockID: invalidOverlay.id, parentID: morning.id)
            )
        }
    }

    func testRuntimeResolutionFillsBaseGapsWithBlankBlocks() throws {
        let morning = baseBlock(title: "Morning", start: 60, requestedEnd: 120)
        let evening = baseBlock(title: "Evening", start: 180, requestedEnd: 240)

        let runtimePlan = try DayPlanEngine.runtimeResolved(makePlan(blocks: [morning, evening]))
        let blankRanges = runtimePlan.blocks
            .filter(\.isBlankBaseBlock)
            .compactMap { block -> (Int, Int)? in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                return (start, end)
            }

        XCTAssertEqual(blankRanges.count, 3)
        XCTAssertEqual(blankRanges.map(\.0), [0, 120, 240])
        XCTAssertEqual(blankRanges.map(\.1), [60, 180, 1440])
    }

    func testResolvedIgnoresStaleCachedResolvedMinutes() throws {
        var staleMorning = baseBlock(title: "Morning", start: 360)
        staleMorning.resolvedStartMinuteOfDay = 999
        staleMorning.resolvedEndMinuteOfDay = 1000

        let afternoon = baseBlock(title: "Afternoon", start: 780)
        let resolved = try DayPlanEngine.resolved(makePlan(blocks: [staleMorning, afternoon]))

        let refreshedMorning = try XCTUnwrap(resolved.blocks.first(where: { $0.id == staleMorning.id }))
        XCTAssertEqual(refreshedMorning.resolvedStartMinuteOfDay, 360)
        XCTAssertEqual(refreshedMorning.resolvedEndMinuteOfDay, 780)
    }
}
