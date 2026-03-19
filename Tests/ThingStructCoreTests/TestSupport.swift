import Foundation
@testable import ThingStructCore

func makePlan(
    date: LocalDay = LocalDay(year: 2026, month: 3, day: 19),
    blocks: [TimeBlock]
) -> DayPlan {
    DayPlan(date: date, blocks: blocks)
}

func task(
    _ title: String,
    order: Int = 0,
    completed: Bool = false
) -> TaskItem {
    TaskItem(title: title, order: order, isCompleted: completed)
}

func baseBlock(
    id: UUID = UUID(),
    title: String,
    start: Int,
    requestedEnd: Int? = nil,
    tasks: [TaskItem] = []
) -> TimeBlock {
    TimeBlock(
        id: id,
        layerIndex: 0,
        title: title,
        tasks: tasks,
        timing: .absolute(
            startMinuteOfDay: start,
            requestedEndMinuteOfDay: requestedEnd
        )
    )
}

func overlayAbsolute(
    id: UUID = UUID(),
    parentID: UUID,
    layerIndex: Int,
    title: String,
    start: Int,
    requestedEnd: Int? = nil,
    tasks: [TaskItem] = []
) -> TimeBlock {
    TimeBlock(
        id: id,
        parentBlockID: parentID,
        layerIndex: layerIndex,
        title: title,
        tasks: tasks,
        timing: .absolute(
            startMinuteOfDay: start,
            requestedEndMinuteOfDay: requestedEnd
        )
    )
}

func overlayRelative(
    id: UUID = UUID(),
    parentID: UUID,
    layerIndex: Int,
    title: String,
    offset: Int,
    duration: Int? = nil,
    tasks: [TaskItem] = []
) -> TimeBlock {
    TimeBlock(
        id: id,
        parentBlockID: parentID,
        layerIndex: layerIndex,
        title: title,
        tasks: tasks,
        timing: .relative(
            startOffsetMinutes: offset,
            requestedDurationMinutes: duration
        )
    )
}

func templateBlock(
    id: UUID = UUID(),
    parentID: UUID? = nil,
    layerIndex: Int = 0,
    title: String,
    tasks: [TaskBlueprint] = [],
    timing: TimeBlockTiming
) -> BlockTemplate {
    BlockTemplate(
        id: id,
        parentTemplateBlockID: parentID,
        layerIndex: layerIndex,
        title: title,
        taskBlueprints: tasks,
        timing: timing
    )
}
