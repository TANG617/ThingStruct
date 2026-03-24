import AppIntents
import SwiftUI
import UIKit
import UserNotifications

@main
struct ThingStructApp: App {
    @UIApplicationDelegateAdaptor(ThingStructAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Root Views

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: ThingStructStore

    @MainActor
    init(store: ThingStructStore? = nil) {
        _store = State(initialValue: store ?? ThingStructStore())
    }

    var body: some View {
        AppShellView()
            .environment(store)
            .task {
                store.loadIfNeeded()
                consumePendingExternalRoute()
                ThingStructQuickActionManager.refresh()
            }
            .onOpenURL(perform: applyExternalURL)
            .onReceive(NotificationCenter.default.publisher(for: .thingStructExternalRouteDidChange)) { notification in
                guard let url = notification.object as? URL else { return }
                applyExternalURL(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, store.isLoaded else { return }
                store.reload()
                store.syncCurrentBlockLiveActivity()
                ThingStructQuickActionManager.refresh()
                consumePendingExternalRoute()
            }
    }

    private func consumePendingExternalRoute() {
        guard let pendingURL = ThingStructExternalRouteCenter.shared.consumePendingURL() else {
            return
        }

        applyExternalURL(pendingURL)
    }

    private func applyExternalURL(_ url: URL) {
        guard let route = ThingStructSystemRoute(url: url) else {
            return
        }

        switch route {
        case .now:
            store.showNow()

        case let .today(date, blockID, _, _):
            store.showToday(date: date, blockID: blockID)

        case .templates:
            store.showTemplates()

        case .startCurrentBlockLiveActivity:
            store.startCurrentBlockLiveActivity()

        case .endCurrentBlockLiveActivity:
            store.endCurrentBlockLiveActivity()
        }
    }
}

struct AppShellView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        @Bindable var store = store

        TabView(selection: $store.selectedTab) {
            NowRootView()
                .tabItem {
                    Label("Now", systemImage: "bolt.circle")
                }
                .tag(RootTab.now)

            TodayRootView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(RootTab.today)

            LibraryRootView()
                .tabItem {
                    Label("Library", systemImage: "square.stack.3d.up")
                }
                .tag(RootTab.library)
        }
        .tint(store.tintPreset.tintColor)
        .environment(\.thingStructTintPreset, store.tintPreset)
        .alert(
            "Unable to Complete Action",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("OK") {
                store.dismissError()
            }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }
}

// MARK: - App Lifecycle

final class ThingStructAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ThingStructSceneDelegate.self

        if let shortcutItem = options.shortcutItem {
            _ = ThingStructQuickActionManager.handle(shortcutItem)
        }

        return configuration
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ThingStructShortcutsProvider.updateAppShortcutParameters()
        ThingStructNotificationCoordinator.shared.configure()
        return true
    }
}

final class ThingStructSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(ThingStructQuickActionManager.handle(shortcutItem))
    }
}

// MARK: - External Routing

extension Notification.Name {
    static let thingStructExternalRouteDidChange = Notification.Name("ThingStructExternalRouteDidChange")
}

@MainActor
final class ThingStructExternalRouteCenter {
    static let shared = ThingStructExternalRouteCenter()

    private(set) var pendingURL: URL?

    func enqueue(_ url: URL) {
        pendingURL = url
        NotificationCenter.default.post(name: .thingStructExternalRouteDidChange, object: url)
    }

    func consumePendingURL() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }
}

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
            return ThingStructSystemRoute.today(
                date: .today(),
                blockID: nil,
                taskID: nil,
                source: .quickAction
            ).url
        case ThingStructSharedConfig.quickActionTemplates:
            return ThingStructSystemRoute.templates(source: .quickAction).url
        default:
            return nil
        }
    }
}

// MARK: - Previews

#Preview("Content - Now") {
    ContentView(store: PreviewSupport.store(tab: .now))
}

#Preview("Content - Today") {
    ContentView(store: PreviewSupport.store(tab: .today))
}

#Preview("Content - Library Tab") {
    ContentView(store: PreviewSupport.store(tab: .library))
}

#Preview("Content - Templates in Library") {
    ContentView(
        store: PreviewSupport.store(
            tab: .library,
            libraryNavigationPath: [.templates]
        )
    )
}

#Preview("App Shell - Now") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .now))
}

#Preview("App Shell - Today") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .today))
}

#Preview("App Shell - Library") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .library))
}

#Preview("App Shell - Templates in Library") {
    AppShellView()
        .environment(
            PreviewSupport.store(
                tab: .library,
                libraryNavigationPath: [.templates]
            )
        )
}

#Preview("App Shell - Error Alert") {
    AppShellView()
        .environment(
            PreviewSupport.store(
                tab: .now,
                lastErrorMessage: "This is a preview alert message."
            )
        )
}
