import XCTest
@testable import ThingStructCore

final class WidgetSupportTests: XCTestCase {
    func testLocalDayParsesISODateString() {
        let day = LocalDay(isoDateString: "2026-03-22")

        XCTAssertEqual(day, LocalDay(year: 2026, month: 3, day: 22))
        XCTAssertNil(LocalDay(isoDateString: "2026/03/22"))
    }

    func testWidgetSnapshotPrioritizesCurrentSectionTasksAndCountsRemaining() {
        let currentBlockID = UUID()
        let baseBlockID = UUID()
        let model = NowScreenModel(
            date: LocalDay(year: 2026, month: 3, day: 22),
            minuteOfDay: 600,
            activeChain: [
                NowChainItem(
                    id: currentBlockID,
                    title: "Focus Sprint",
                    layerIndex: 1,
                    startMinuteOfDay: 540,
                    endMinuteOfDay: 660,
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
                ),
                NowChainItem(
                    id: baseBlockID,
                    title: "Morning",
                    layerIndex: 0,
                    startMinuteOfDay: 480,
                    endMinuteOfDay: 720,
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                )
            ],
            noteSections: [],
            statusMessage: nil,
            taskSections: [
                NowTaskSection(
                    id: baseBlockID,
                    title: "Morning",
                    layerIndex: 0,
                    startMinuteOfDay: 480,
                    endMinuteOfDay: 720,
                    tasks: [task("Base task")],
                    isCurrent: false,
                    isComplete: false
                ),
                NowTaskSection(
                    id: currentBlockID,
                    title: "Focus Sprint",
                    layerIndex: 1,
                    startMinuteOfDay: 540,
                    endMinuteOfDay: 660,
                    tasks: [
                        task("Completed first", completed: true),
                        task("Current next", order: 1)
                    ],
                    isCurrent: true,
                    isComplete: false
                )
            ]
        )

        let snapshot = ThingStructWidgetSnapshotBuilder.makeSnapshot(
            from: model,
            maxTaskCount: 3
        )

        XCTAssertEqual(snapshot.currentBlockTitle, "Focus Sprint")
        XCTAssertEqual(snapshot.currentBlockTimeRangeText, "09:00 - 11:00")
        XCTAssertEqual(snapshot.blocks.map(\.title), ["Focus Sprint", "Morning"])
        XCTAssertEqual(snapshot.blocks.map(\.layerIndex), [1, 0])
        XCTAssertTrue(snapshot.blocks.first?.isCurrent == true)
        XCTAssertEqual(snapshot.remainingTaskCount, 2)
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Current next", "Completed first", "Base task"])
        XCTAssertEqual(snapshot.tasks.map(\.blockTitle), ["Focus Sprint", "Focus Sprint", "Morning"])
        XCTAssertEqual(snapshot.tasks.map(\.layerIndex), [1, 1, 0])
    }
}
