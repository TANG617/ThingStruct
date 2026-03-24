import XCTest
@testable import ThingStructCore

final class SystemSupportTests: XCTestCase {
    func testLiveActivitySnapshotUsesTopLayerNoteAndTaskWhenTopLayerHasIncompleteTask() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let baseID = UUID()
        let overlayID = UUID()
        let overlayTaskID = UUID()

        var base = baseBlock(
            id: baseID,
            title: "Morning",
            start: 540,
            requestedEnd: 720,
            tasks: [task("Base task")]
        )
        base.note = "Base note"

        var overlay = overlayRelative(
            id: overlayID,
            parentID: baseID,
            layerIndex: 1,
            title: "Focus Sprint",
            offset: 30,
            duration: 90,
            tasks: [TaskItem(id: overlayTaskID, title: "Top task")]
        )
        overlay.note = "Top note"

        let document = ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(makePlan(date: day, blocks: [base, overlay]))])
        let snapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)

        XCTAssertEqual(snapshot.currentBlock?.blockID, overlayID)
        XCTAssertEqual(snapshot.displayBlock?.blockID, overlayID)
        XCTAssertEqual(snapshot.displayTask?.taskID, overlayTaskID)
        XCTAssertEqual(snapshot.displayNote, "Top note")
        XCTAssertNil(snapshot.displaySourceBlockTitle)
    }

    func testLiveActivitySnapshotFallsBackAsBoundNoteAndTaskGroup() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let baseID = UUID()
        let baseTaskID = UUID()
        let overlayID = UUID()

        var base = baseBlock(
            id: baseID,
            title: "Morning",
            start: 540,
            requestedEnd: 720,
            tasks: [TaskItem(id: baseTaskID, title: "Base task")]
        )
        base.note = "Base note"

        var overlay = overlayRelative(
            id: overlayID,
            parentID: baseID,
            layerIndex: 1,
            title: "Focus Sprint",
            offset: 30,
            duration: 90,
            tasks: [task("Done first", completed: true)]
        )
        overlay.note = "Top note should not stay visible"

        let document = ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(makePlan(date: day, blocks: [base, overlay]))])
        let snapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)

        XCTAssertEqual(snapshot.currentBlock?.blockID, overlayID)
        XCTAssertEqual(snapshot.displayBlock?.blockID, baseID)
        XCTAssertEqual(snapshot.displayTask?.taskID, baseTaskID)
        XCTAssertEqual(snapshot.displayNote, "Base note")
        XCTAssertEqual(snapshot.displaySourceBlockTitle, "Morning")
        XCTAssertEqual(
            ThingStructSystemRoute(url: try XCTUnwrap(snapshot.deepLinkURL())),
            .today(date: day, blockID: baseID, taskID: baseTaskID, source: .liveActivity)
        )
    }

    func testLiveActivitySnapshotDoesNotBorrowNoteFromLowerLayerWhenDisplayBlockHasNoNote() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let baseID = UUID()
        let overlayID = UUID()
        let overlayTaskID = UUID()

        var base = baseBlock(
            id: baseID,
            title: "Morning",
            start: 540,
            requestedEnd: 720,
            tasks: [task("Base task")]
        )
        base.note = "Base note that should stay hidden"

        let overlay = overlayRelative(
            id: overlayID,
            parentID: baseID,
            layerIndex: 1,
            title: "Focus Sprint",
            offset: 30,
            duration: 90,
            tasks: [TaskItem(id: overlayTaskID, title: "Top task")]
        )

        let document = ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(makePlan(date: day, blocks: [base, overlay]))])
        let snapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)

        XCTAssertEqual(snapshot.displayBlock?.blockID, overlayID)
        XCTAssertEqual(snapshot.displayTask?.taskID, overlayTaskID)
        XCTAssertNil(snapshot.displayNote)
    }

    func testLiveActivitySnapshotShowsCompletionStateWhenChainHasNoIncompleteTasks() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let baseID = UUID()
        let overlayID = UUID()

        var base = baseBlock(
            id: baseID,
            title: "Morning",
            start: 540,
            requestedEnd: 720,
            tasks: [task("Base task", completed: true)]
        )
        base.note = "Base note"

        var overlay = overlayRelative(
            id: overlayID,
            parentID: baseID,
            layerIndex: 1,
            title: "Focus Sprint",
            offset: 30,
            duration: 90,
            tasks: [task("Overlay task", completed: true)]
        )
        overlay.note = "Top note"

        let document = ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(makePlan(date: day, blocks: [base, overlay]))])
        let snapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)

        XCTAssertEqual(snapshot.currentBlock?.blockID, overlayID)
        XCTAssertNil(snapshot.displayBlock)
        XCTAssertNil(snapshot.displayTask)
        XCTAssertNil(snapshot.displayNote)
        XCTAssertEqual(snapshot.statusMessage, "No incomplete tasks in this chain.")
        XCTAssertEqual(
            ThingStructSystemRoute(url: try XCTUnwrap(snapshot.deepLinkURL())),
            .today(date: day, blockID: overlayID, taskID: nil, source: .liveActivity)
        )
    }

    func testCompleteTaskIsIdempotentAndLiveActivityAdvancesToNextVisibleTask() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let baseID = UUID()
        let baseTaskID = UUID()
        let overlayID = UUID()
        let overlayTaskAID = UUID()
        let overlayTaskBID = UUID()

        var base = baseBlock(
            id: baseID,
            title: "Morning",
            start: 540,
            requestedEnd: 720,
            tasks: [TaskItem(id: baseTaskID, title: "Base task")]
        )
        base.note = "Base note"

        var overlay = overlayRelative(
            id: overlayID,
            parentID: baseID,
            layerIndex: 1,
            title: "Focus Sprint",
            offset: 30,
            duration: 90,
            tasks: [
                TaskItem(id: overlayTaskAID, title: "Top task"),
                TaskItem(id: overlayTaskBID, title: "Next task", order: 1)
            ]
        )
        overlay.note = "Top note"

        let client = ThingStructSharedDocumentClient()
        var document = ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(makePlan(date: day, blocks: [base, overlay]))])
        let referenceDate = try date(day, minuteOfDay: 600)

        let firstSnapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)
        XCTAssertEqual(firstSnapshot.displayTask?.taskID, overlayTaskAID)

        XCTAssertTrue(try client.completeTask(on: day, blockID: overlayID, taskID: overlayTaskAID, completedAt: referenceDate, in: &document))

        let secondSnapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)
        XCTAssertEqual(secondSnapshot.displayTask?.taskID, overlayTaskBID)
        XCTAssertEqual(secondSnapshot.displayBlock?.blockID, overlayID)

        XCTAssertTrue(try client.completeTask(on: day, blockID: overlayID, taskID: overlayTaskBID, completedAt: referenceDate, in: &document))

        let thirdSnapshot = try makeLiveActivitySnapshot(document: document, day: day, minuteOfDay: 600)
        XCTAssertEqual(thirdSnapshot.displayTask?.taskID, baseTaskID)
        XCTAssertEqual(thirdSnapshot.displayBlock?.blockID, baseID)
        XCTAssertEqual(thirdSnapshot.displayNote, "Base note")

        XCTAssertFalse(try client.completeTask(on: day, blockID: overlayID, taskID: overlayTaskBID, completedAt: referenceDate, in: &document))

        let persistedOverlay = try XCTUnwrap(
            document.dayPlan(for: day)?.blocks.first(where: { $0.id == overlayID })
        )
        let completedTask = try XCTUnwrap(persistedOverlay.tasks.first(where: { $0.id == overlayTaskBID }))
        XCTAssertTrue(completedTask.isCompleted)
        XCTAssertEqual(completedTask.completedAt, referenceDate)
    }

    private func makeLiveActivitySnapshot(
        document: ThingStructDocument,
        day: LocalDay,
        minuteOfDay: Int
    ) throws -> ThingStructSystemLiveActivitySnapshot {
        let client = ThingStructSharedDocumentClient()
        let now = try ThingStructPresentation.nowScreenModel(
            document: document,
            date: day,
            minuteOfDay: minuteOfDay
        )
        return client.liveActivitySnapshot(from: now)
    }

    private func date(_ day: LocalDay, minuteOfDay: Int) throws -> Date {
        try XCTUnwrap(day.date(minuteOfDay: minuteOfDay))
    }
}
