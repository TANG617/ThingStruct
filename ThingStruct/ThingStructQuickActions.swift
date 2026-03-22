import UIKit

private enum ThingStructQuickActionRouteKey {
    static let routeURL = "routeURL"
}

@MainActor
enum ThingStructQuickActionManager {
    static func refresh(referenceDate: Date = .now) {
        var items: [UIApplicationShortcutItem] = [
            shortcutItem(
                type: ThingStructSharedConfig.quickActionNow,
                title: "Now",
                subtitle: "Open the current focus",
                systemImageName: "bolt.circle",
                route: .now(source: .quickAction)
            ),
            shortcutItem(
                type: ThingStructSharedConfig.quickActionToday,
                title: "Today",
                subtitle: "Open today's timeline",
                systemImageName: "calendar",
                route: .today(date: .today(), blockID: nil, taskID: nil, source: .quickAction)
            ),
            shortcutItem(
                type: ThingStructSharedConfig.quickActionTemplates,
                title: "Templates",
                subtitle: "Open your saved templates",
                systemImageName: "square.stack.3d.up",
                route: .templates(source: .quickAction)
            )
        ]

        let executor = ThingStructSystemActionExecutor()
        if
            let snapshot = try? executor.currentSnapshot(at: referenceDate),
            let currentBlock = snapshot.currentBlock,
            let routeURL = ThingStructSystemRoute.today(
                date: currentBlock.date,
                blockID: currentBlock.blockID,
                taskID: snapshot.topTask?.taskID,
                source: .quickAction
            ).url
        {
            items.insert(
                UIApplicationShortcutItem(
                    type: ThingStructSharedConfig.quickActionCurrentBlock,
                    localizedTitle: currentBlock.title,
                    localizedSubtitle: currentBlock.timeRangeText,
                    icon: UIApplicationShortcutIcon(systemImageName: "scope"),
                    userInfo: [
                        ThingStructQuickActionRouteKey.routeURL: routeURL.absoluteString as NSString
                    ]
                ),
                at: 1
            )
        }

        UIApplication.shared.shortcutItems = items
    }

    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let routeURL = routeURL(for: shortcutItem) else {
            return false
        }

        ThingStructExternalRouteCenter.shared.enqueue(routeURL)
        return true
    }

    private static func shortcutItem(
        type: String,
        title: String,
        subtitle: String,
        systemImageName: String,
        route: ThingStructSystemRoute
    ) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: type,
            localizedTitle: title,
            localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: systemImageName),
            userInfo: [
                ThingStructQuickActionRouteKey.routeURL: (route.url?.absoluteString ?? "") as NSString
            ]
        )
    }

    private static func routeURL(for shortcutItem: UIApplicationShortcutItem) -> URL? {
        if
            let routeString = shortcutItem.userInfo?[ThingStructQuickActionRouteKey.routeURL] as? String,
            let url = URL(string: routeString)
        {
            return url
        }

        switch shortcutItem.type {
        case ThingStructSharedConfig.quickActionNow:
            return ThingStructSystemRoute.now(source: .quickAction).url
        case ThingStructSharedConfig.quickActionToday:
            return ThingStructSystemRoute.today(date: .today(), blockID: nil, taskID: nil, source: .quickAction).url
        case ThingStructSharedConfig.quickActionTemplates:
            return ThingStructSystemRoute.templates(source: .quickAction).url
        default:
            return nil
        }
    }
}
