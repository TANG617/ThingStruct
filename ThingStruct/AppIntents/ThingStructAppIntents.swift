import AppIntents
import WidgetKit

private enum ThingStructIntentError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "Unable to build the requested ThingStruct route."
        }
    }
}

struct OpenNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Now"
    static let description = IntentDescription("Open ThingStruct to the Now screen.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = ThingStructSystemRoute.now(source: .shortcut).url else {
            throw ThingStructIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today"
    static let description = IntentDescription("Open ThingStruct to today's timeline.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = ThingStructSystemRoute.today(
            date: .today(),
            blockID: nil,
            taskID: nil,
            source: .shortcut
        ).url else {
            throw ThingStructIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct OpenCurrentBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Current Block"
    static let description = IntentDescription("Open ThingStruct to the current active block.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let executor = ThingStructSystemActionExecutor()
        let url = try executor.openCurrentBlockURL(at: .now, source: .shortcut)
            ?? ThingStructSystemRoute.now(source: .shortcut).url

        guard let url else {
            throw ThingStructIntentError.missingRoute
        }

        return .result(
            opensIntent: OpenURLIntent(url),
            dialog: "Opening your current block."
        )
    }
}

struct CompleteCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Current Task"
    static let description = IntentDescription("Mark the highest-priority current task as completed.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let executor = ThingStructSystemActionExecutor()
        if let completedTask = try executor.completeCurrentTask(at: .now) {
            WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)

            if #available(iOS 16.1, *) {
                _ = try await ThingStructCurrentBlockLiveActivityController.sync(using: .appLive, at: .now)
            }

            return .result(
                dialog: IntentDialog("Completed \(completedTask.title).")
            )
        }

        return .result(
            dialog: IntentDialog("There isn't an incomplete task to complete right now.")
        )
    }
}

struct StartCurrentBlockLiveActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Activity"
    static let description = IntentDescription("Start a Live Activity for the current block.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard #available(iOS 16.1, *) else {
            return .result(dialog: "Live Activities aren't available on this device.")
        }

        let started = try await ThingStructCurrentBlockLiveActivityController.start(
            using: .appLive,
            at: .now
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)

        return .result(
            dialog: IntentDialog(
                started
                    ? "Started tracking the current block."
                    : "There isn't an active block to track right now."
            )
        )
    }
}

struct EndCurrentBlockLiveActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "End Live Activity"
    static let description = IntentDescription("End the current ThingStruct Live Activity.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard #available(iOS 16.1, *) else {
            return .result(dialog: "Live Activities aren't available on this device.")
        }

        await ThingStructCurrentBlockLiveActivityController.endAll()
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)
        return .result(dialog: "Ended the current Live Activity.")
    }
}

struct ThingStructShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenNowIntent(),
            phrases: [
                "Open now in \(.applicationName)",
                "Show my current focus in \(.applicationName)"
            ],
            shortTitle: "Open Now",
            systemImageName: "bolt.circle"
        )

        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: [
                "Open today in \(.applicationName)",
                "Show today's plan in \(.applicationName)"
            ],
            shortTitle: "Open Today",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: OpenCurrentBlockIntent(),
            phrases: [
                "Open my current block in \(.applicationName)",
                "Show the current block in \(.applicationName)"
            ],
            shortTitle: "Current Block",
            systemImageName: "scope"
        )

        AppShortcut(
            intent: CompleteCurrentTaskIntent(),
            phrases: [
                "Complete the current task in \(.applicationName)",
                "Check off the current task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: StartCurrentBlockLiveActivityIntent(),
            phrases: [
                "Start tracking this block in \(.applicationName)",
                "Start a live activity in \(.applicationName)"
            ],
            shortTitle: "Start Live",
            systemImageName: "waveform.path.ecg.rectangle"
        )

        AppShortcut(
            intent: EndCurrentBlockLiveActivityIntent(),
            phrases: [
                "End the live activity in \(.applicationName)",
                "Stop tracking this block in \(.applicationName)"
            ],
            shortTitle: "End Live",
            systemImageName: "xmark.circle"
        )
    }
}
