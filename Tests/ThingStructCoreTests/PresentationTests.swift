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

        XCTAssertEqual(model.statusMessage, "You're in open time right now.")
        XCTAssertEqual(model.activeChain.count, 1)
        XCTAssertTrue(model.activeChain.first?.isBlank == true)
    }

    func testTodayScreenModelHidesRuntimeBlankBlocksButExposesOpenSlots() throws {
        let morning = baseBlock(title: "Morning", start: 60, requestedEnd: 120)
        let document = ThingStructDocument(
            dayPlans: [makePlan(blocks: [morning])]
        )

        let model = try ThingStructPresentation.todayScreenModel(
            document: document,
            date: LocalDay(year: 2026, month: 3, day: 19),
            selectedBlockID: nil,
            currentMinute: nil
        )

        XCTAssertEqual(model.blocks.map(\.title), ["Morning"])
        XCTAssertFalse(model.blocks.contains(where: \.isBlank))
        XCTAssertEqual(model.openSlots.map(\.startMinuteOfDay), [0, 120])
        XCTAssertEqual(model.openSlots.map(\.endMinuteOfDay), [60, 1440])
    }

    func testNowScreenModelKeepsCompletedUpperTaskSectionVisible() throws {
        let baseID = UUID()
        let overlayID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: baseID,
                title: "Morning",
                start: 540,
                requestedEnd: 720,
                tasks: [task("Plan work")]
            ),
            overlayRelative(
                id: overlayID,
                parentID: baseID,
                layerIndex: 1,
                title: "Focus Sprint",
                offset: 0,
                duration: 120,
                tasks: [task("Finish draft", completed: true)]
            )
        ])

        let model = try ThingStructPresentation.nowScreenModel(
            document: ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(plan)]),
            date: LocalDay(year: 2026, month: 3, day: 19),
            minuteOfDay: 600
        )

        XCTAssertEqual(model.taskSections.map(\.id), [overlayID, baseID])
        XCTAssertEqual(model.taskSections.map(\.title), ["Focus Sprint", "Morning"])
        XCTAssertTrue(model.taskSections[0].isCurrent)
        XCTAssertTrue(model.taskSections[0].isComplete)
        XCTAssertFalse(model.taskSections[1].isCurrent)
        XCTAssertFalse(model.taskSections[1].isComplete)
    }

    func testTodayScreenModelRoundsBlockTimesToNearestFiveMinutes() throws {
        let blockID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(
                id: blockID,
                title: "Morning",
                start: 543,
                requestedEnd: 607
            )
        ])

        let model = try ThingStructPresentation.todayScreenModel(
            document: ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(plan)]),
            date: LocalDay(year: 2026, month: 3, day: 19),
            selectedBlockID: blockID,
            currentMinute: nil
        )

        XCTAssertEqual(model.blocks.first(where: { $0.id == blockID })?.startMinuteOfDay, 545)
        XCTAssertEqual(model.blocks.first(where: { $0.id == blockID })?.endMinuteOfDay, 605)
        XCTAssertEqual(model.selectedBlock?.startMinuteOfDay, 545)
        XCTAssertEqual(model.selectedBlock?.endMinuteOfDay, 605)
    }

    func testNowScreenModelGroupsNotesAndTasksByHighestLayerFirst() throws {
        let baseID = UUID()
        let overlayID = UUID()
        let topID = UUID()
        let plan = DayPlan(
            date: LocalDay(year: 2026, month: 3, day: 19),
            blocks: [
                TimeBlock(
                    id: baseID,
                    layerIndex: 0,
                    title: "Morning",
                    note: "Base note",
                    tasks: [task("Base task")],
                    timing: .absolute(
                        startMinuteOfDay: 540,
                        requestedEndMinuteOfDay: 720
                    )
                ),
                TimeBlock(
                    id: overlayID,
                    parentBlockID: baseID,
                    layerIndex: 1,
                    title: "Focus Sprint",
                    note: "Overlay note",
                    tasks: [task("Overlay task")],
                    timing: .relative(
                        startOffsetMinutes: 0,
                        requestedDurationMinutes: 180
                    )
                ),
                TimeBlock(
                    id: topID,
                    parentBlockID: overlayID,
                    layerIndex: 2,
                    title: "Launch Window",
                    note: "Top note",
                    tasks: [task("Top task", completed: true)],
                    timing: .relative(
                        startOffsetMinutes: 0,
                        requestedDurationMinutes: 180
                    )
                )
            ]
        )

        let model = try ThingStructPresentation.nowScreenModel(
            document: ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(plan)]),
            date: LocalDay(year: 2026, month: 3, day: 19),
            minuteOfDay: 600
        )

        XCTAssertEqual(model.noteSections.map(\.id), [topID, overlayID, baseID])
        XCTAssertEqual(model.noteSections.map(\.note), ["Top note", "Overlay note", "Base note"])
        XCTAssertEqual(model.taskSections.map(\.id), [topID, overlayID, baseID])
        XCTAssertEqual(model.activeChain.map(\.layerIndex), [2, 1, 0])
        XCTAssertTrue(model.noteSections[0].isCurrent)
        XCTAssertTrue(model.taskSections[0].isCurrent)
    }

    func testTodayScreenModelFocusesCurrentActiveBlockWhenNothingSelected() throws {
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
                title: "Focus Sprint",
                offset: 30,
                duration: 60
            )
        ])

        let model = try ThingStructPresentation.todayScreenModel(
            document: ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(plan)]),
            date: LocalDay(year: 2026, month: 3, day: 19),
            selectedBlockID: nil,
            currentMinute: 585
        )

        XCTAssertEqual(model.initialFocusBlockID, overlayID)
        XCTAssertEqual(model.selectedBlock?.id, overlayID)
        XCTAssertEqual(model.initialScrollMinute, 570)
    }

    func testTodayScreenModelDoesNotFocusBlankWhenCurrentMinuteIsInGap() throws {
        let morning = baseBlock(title: "Morning", start: 540, requestedEnd: 600)
        let evening = baseBlock(title: "Evening", start: 660, requestedEnd: 720)

        let model = try ThingStructPresentation.todayScreenModel(
            document: ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(makePlan(blocks: [morning, evening]))]),
            date: LocalDay(year: 2026, month: 3, day: 19),
            selectedBlockID: nil,
            currentMinute: 630
        )

        XCTAssertNil(model.initialFocusBlockID)
        XCTAssertNil(model.selectedBlock)
        XCTAssertEqual(model.initialScrollMinute, 630)
        XCTAssertEqual(model.openSlots.map(\.startMinuteOfDay), [0, 600, 720])
        XCTAssertEqual(model.openSlots.map(\.endMinuteOfDay), [540, 660, 1440])
    }

    func testTodayScreenModelIncludesParentTitleForOverlayDetail() throws {
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
                title: "Focus Sprint",
                offset: 30,
                duration: 60
            )
        ])

        let model = try ThingStructPresentation.todayScreenModel(
            document: ThingStructDocument(dayPlans: [try DayPlanEngine.resolved(plan)]),
            date: LocalDay(year: 2026, month: 3, day: 19),
            selectedBlockID: overlayID,
            currentMinute: nil
        )

        XCTAssertEqual(model.selectedBlock?.id, overlayID)
        XCTAssertEqual(model.selectedBlock?.parentBlockID, baseID)
        XCTAssertEqual(model.selectedBlock?.parentBlockTitle, "Morning")
    }

    func testTemplatesScreenModelBuildsTodayAndTomorrowSummaries() throws {
        let referenceDay = LocalDay(year: 2026, month: 3, day: 19)
        let tomorrow = referenceDay.adding(days: 1)
        let todayTemplate = SavedDayTemplate(
            title: "Today Override",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
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
                savedTemplates: [todayTemplate, weekdayTemplate, overrideTemplate],
                weekdayRules: [WeekdayTemplateRule(weekday: tomorrow.weekday, savedTemplateID: weekdayTemplate.id)],
                overrides: [
                    DateTemplateOverride(date: referenceDay, savedTemplateID: todayTemplate.id),
                    DateTemplateOverride(date: tomorrow, savedTemplateID: overrideTemplate.id)
                ]
            ),
            referenceDay: referenceDay
        )

        XCTAssertEqual(model.todaySchedule.date, referenceDay)
        XCTAssertEqual(model.todaySchedule.overrideTemplateTitle, "Today Override")
        XCTAssertEqual(model.todaySchedule.finalTemplateTitle, "Today Override")
        XCTAssertEqual(model.tomorrowSchedule.weekdayTemplateTitle, "Weekday")
        XCTAssertEqual(model.tomorrowSchedule.overrideTemplateTitle, "Override")
        XCTAssertEqual(model.tomorrowSchedule.finalTemplateTitle, "Override")
    }
}
