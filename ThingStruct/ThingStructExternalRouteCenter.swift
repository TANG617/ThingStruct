import Foundation

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
