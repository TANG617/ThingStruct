import AppIntents
import WidgetKit

// AppIntents 是 iOS 暴露给系统能力中心的一套入口协议。
// 可以把它理解成：
// - app 内部已经有一套命令/路由
// - 系统（Siri、快捷指令、Spotlight、控制中心）需要一个统一桥接层来调用它们
// 这个文件就是那层桥接。

private enum ThingStructIntentError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "Unable to build the requested ThingStruct route."
        }
    }
}

// 打开 Now 页的快捷指令。
// 注意这里不直接操作 UI，而是构造一个路由 URL 交给系统打开。
struct OpenNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Now"
    static let description = IntentDescription("Open ThingStruct to the Now screen.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent {
        // `OpensIntent` 表示这个 intent 的结果是“让系统继续执行一个打开动作”。
        guard let url = ThingStructSystemRoute.now(source: .shortcut).url else {
            throw ThingStructIntentError.missingRoute
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

// 打开 Today 页。
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

// 打开当前激活 block。
// 和简单路由不同，这里需要先问业务层“当前块是谁”，所以借助执行器。
struct OpenCurrentBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Current Block"
    static let description = IntentDescription("Open ThingStruct to the current active block.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        // `ThingStructSystemActionExecutor` 是“系统表面上的动作执行器”：
        // 它负责在 widget / shortcut / live activity 这类入口里重用相同的业务动作。
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

// 直接完成当前最高优先级任务。
// 这是一个典型的“系统命令 -> 业务动作 -> 系统副作用同步”的例子。
struct CompleteCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Current Task"
    static let description = IntentDescription("Mark the highest-priority current task as completed.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let executor = ThingStructSystemActionExecutor()
        if let completedTask = try executor.completeCurrentTask(at: .now) {
            // Intent 直接写入数据后，需要手动同步依赖这个数据的系统表面。
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

// 从快捷指令中启动 Live Activity。
struct StartCurrentBlockLiveActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Activity"
    static let description = IntentDescription("Start a Live Activity for the current block.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // `#available` 是 Swift 常见的运行时平台可用性检查。
        // iOS API 经常按系统版本逐步开放，所以你会在项目里频繁看到它。
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

// 结束当前 Live Activity。
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

// `AppShortcutsProvider` 把多个 intent 组织成可被系统发现的一组快捷操作。
// phrases 里的 `\(.applicationName)` 是系统提供的占位符，运行时会替换成 app 名称。
struct ThingStructShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        // 这里返回的数组就是最终暴露给系统的快捷动作清单。
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
