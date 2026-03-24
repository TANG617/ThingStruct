import AppIntents
import SwiftUI
import WidgetKit

@main
struct ThingStructWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ThingStructNowWidget()

        if #available(iOS 16.1, *) {
            ThingStructCurrentBlockLiveActivity()
        }

        if #available(iOS 18.0, *) {
            ThingStructOpenNowControl()
            ThingStructCompleteCurrentTaskControl()
            ThingStructOpenCurrentBlockControl()
            ThingStructStartLiveActivityControl()
        }
    }
}

private enum ThingStructControlIntentError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "Unable to build the requested ThingStruct route."
        }
    }
}

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

        let repository = ThingStructDocumentRepository.widgetLive
        _ = try repository.toggleTask(
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

        let repository = ThingStructDocumentRepository.widgetLive
        _ = try repository.completeTask(
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

struct OpenNowControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Now"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = ThingStructSystemRoute.now(source: .control).url else {
            throw ThingStructControlIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenCurrentBlockControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Current Block"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        let executor = ThingStructSystemActionExecutor(repository: .widgetLive)
        let url = try executor.openCurrentBlockURL(at: .now, source: .control)
            ?? ThingStructSystemRoute.now(source: .control).url

        guard let url else {
            throw ThingStructControlIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct CompleteCurrentTaskControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Current Task"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let executor = ThingStructSystemActionExecutor(repository: .widgetLive)
        _ = try executor.completeCurrentTask(at: .now)
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

struct StartCurrentBlockLiveActivityControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Activity"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        guard #available(iOS 16.1, *) else {
            return .result()
        }

        _ = try await ThingStructCurrentBlockLiveActivityController.start(
            using: .widgetLive,
            at: .now
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ThingStructOpenNowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.openNowControlKind) {
            ControlWidgetButton(action: OpenNowControlIntent()) {
                Label("Now", systemImage: "bolt.circle")
            }
        }
        .displayName("Open Now")
        .description("Jump straight into the Now screen.")
    }
}

@available(iOS 18.0, *)
struct ThingStructCompleteCurrentTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.completeCurrentTaskControlKind) {
            ControlWidgetButton(action: CompleteCurrentTaskControlIntent()) {
                Label("Complete Current Task", systemImage: "checkmark.circle")
            }
        }
        .displayName("Complete Task")
        .description("Check off the highest-priority current task.")
    }
}

@available(iOS 18.0, *)
struct ThingStructOpenCurrentBlockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.openCurrentBlockControlKind) {
            ControlWidgetButton(action: OpenCurrentBlockControlIntent()) {
                Label("Open Current Block", systemImage: "scope")
            }
        }
        .displayName("Open Current Block")
        .description("Open ThingStruct to the active block.")
    }
}

@available(iOS 18.0, *)
struct ThingStructStartLiveActivityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.startLiveActivityControlKind) {
            ControlWidgetButton(action: StartCurrentBlockLiveActivityControlIntent()) {
                Label("Start Live Activity", systemImage: "waveform.path.ecg.rectangle")
            }
        }
        .displayName("Start Live Activity")
        .description("Start tracking the active block as a Live Activity.")
    }
}
