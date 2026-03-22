import AppIntents
import UIKit
import UserNotifications

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
