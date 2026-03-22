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
