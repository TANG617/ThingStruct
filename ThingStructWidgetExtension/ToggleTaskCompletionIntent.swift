import AppIntents
import WidgetKit

struct ToggleTaskCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Task Completion"
    static let description = IntentDescription("Toggle a task directly from the ThingStruct widget.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Date ISO")
    var dateISO: String

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(dateISO: String, blockID: String, taskID: String) {
        self.dateISO = dateISO
        self.blockID = blockID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard
            let localDay = LocalDay(isoDateString: dateISO),
            let blockUUID = UUID(uuidString: blockID),
            let taskUUID = UUID(uuidString: taskID)
        else {
            return .result()
        }

        let client = ThingStructSharedDocumentClient.widgetLive
        _ = try client.toggleTask(
            on: localDay,
            blockID: blockUUID,
            taskID: taskUUID
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        return .result()
    }
}

struct CompleteLiveActivityTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Live Activity Task"
    static let description = IntentDescription("Complete the task currently shown in the ThingStruct Live Activity.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Date ISO")
    var dateISO: String

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(dateISO: String, blockID: String, taskID: String) {
        self.dateISO = dateISO
        self.blockID = blockID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard
            let localDay = LocalDay(isoDateString: dateISO),
            let blockUUID = UUID(uuidString: blockID),
            let taskUUID = UUID(uuidString: taskID)
        else {
            return .result()
        }

        let client = ThingStructSharedDocumentClient.widgetLive
        _ = try client.completeTask(
            on: localDay,
            blockID: blockUUID,
            taskID: taskUUID
        )

        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)

        if #available(iOS 16.1, *) {
            _ = try await ThingStructCurrentBlockLiveActivityController.sync(
                using: .widgetLive,
                at: .now
            )
        }

        return .result()
    }
}
