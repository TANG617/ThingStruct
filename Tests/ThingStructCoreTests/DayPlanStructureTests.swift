import XCTest
@testable import ThingStructCore

final class DayPlanStructureTests: XCTestCase {
    func testRejectsOverlayWithoutParent() {
        let orphan = TimeBlock(
            layerIndex: 1,
            title: "Orphan",
            timing: .absolute(startMinuteOfDay: 60, requestedEndMinuteOfDay: 120)
        )

        let plan = makePlan(blocks: [orphan])

        XCTAssertThrowsError(try DayPlanEngine.validate(plan)) { error in
            XCTAssertEqual(error as? ThingStructCoreError, .invalidRootBlock(orphan.id))
        }
    }

    func testRejectsCycle() {
        let firstID = UUID()
        let secondID = UUID()

        let first = TimeBlock(
            id: firstID,
            parentBlockID: secondID,
            layerIndex: 2,
            title: "First",
            timing: .absolute(startMinuteOfDay: 60, requestedEndMinuteOfDay: 120)
        )
        let second = TimeBlock(
            id: secondID,
            parentBlockID: firstID,
            layerIndex: 1,
            title: "Second",
            timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 180)
        )
        let base = baseBlock(title: "Base", start: 0, requestedEnd: 600)

        let plan = makePlan(blocks: [base, first, second])

        XCTAssertThrowsError(try DayPlanEngine.validate(plan)) { error in
            XCTAssertEqual(error as? ThingStructCoreError, .cycleDetected(firstID))
        }
    }

    func testRejectsDuplicateBlockIDs() {
        let duplicateID = UUID()
        let first = baseBlock(id: duplicateID, title: "Morning", start: 0, requestedEnd: 720)
        let second = baseBlock(id: duplicateID, title: "Afternoon", start: 720, requestedEnd: 1440)

        let plan = makePlan(blocks: [first, second])

        XCTAssertThrowsError(try DayPlanEngine.validate(plan)) { error in
            XCTAssertEqual(error as? ThingStructCoreError, .duplicateBlockID(duplicateID))
        }
    }
}
