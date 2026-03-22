import AppIntents
import WidgetKit

private enum ThingStructControlIntentError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "Unable to build the requested ThingStruct route."
        }
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
        let executor = ThingStructSystemActionExecutor(client: .widgetLive)
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
        let executor = ThingStructSystemActionExecutor(client: .widgetLive)
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
