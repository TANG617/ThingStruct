#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct ThingStructCurrentBlockActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var timeRangeText: String
        var remainingMinutes: Int
        var remainingTaskCount: Int
        var topTaskTitle: String?
        var statusMessage: String?
    }

    var dateISO: String
    var blockID: String
    var deepLinkURL: String
}

@available(iOS 16.1, *)
enum ThingStructCurrentBlockLiveActivityController {
    static func start(
        using client: ThingStructSharedDocumentClient = .appLive,
        at date: Date = .now
    ) async throws -> Bool {
        try await sync(using: client, at: date)
    }

    static func sync(
        using client: ThingStructSharedDocumentClient = .appLive,
        at date: Date = .now
    ) async throws -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return false
        }

        let snapshot = try client.systemNowSnapshot(at: date)
        guard let payload = payload(from: snapshot, referenceDate: date) else {
            await endAll()
            return false
        }

        if let existing = Activity<ThingStructCurrentBlockActivityAttributes>.activities.first(
            where: { $0.attributes.blockID == payload.attributes.blockID && $0.attributes.dateISO == payload.attributes.dateISO }
        ) {
            await existing.update(payload.content)
            await endAll(excluding: existing.id)
            return true
        }

        await endAll()
        _ = try Activity.request(
            attributes: payload.attributes,
            content: payload.content,
            pushType: nil
        )
        return true
    }

    static func endAll() async {
        await endAll(excluding: nil)
    }

    static func endAll(excluding activityID: String?) async {
        for activity in Activity<ThingStructCurrentBlockActivityAttributes>.activities
        where activity.id != activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func payload(
        from snapshot: ThingStructSystemNowSnapshot,
        referenceDate: Date
    ) -> Payload? {
        guard
            let block = snapshot.currentBlock,
            !block.isBlank,
            block.endMinuteOfDay > snapshot.minuteOfDay,
            let deeplinkURL = ThingStructSystemRoute.today(
                date: block.date,
                blockID: block.blockID,
                taskID: snapshot.topTask?.taskID,
                source: .liveActivity
            ).url
        else {
            return nil
        }

        let remainingMinutes = max(0, block.endMinuteOfDay - snapshot.minuteOfDay)
        let staleDate = block.date.date(minuteOfDay: block.endMinuteOfDay) ?? referenceDate.addingTimeInterval(15 * 60)
        let attributes = ThingStructCurrentBlockActivityAttributes(
            dateISO: block.date.description,
            blockID: block.blockID.uuidString,
            deepLinkURL: deeplinkURL.absoluteString
        )
        let content = ActivityContent(
            state: ThingStructCurrentBlockActivityAttributes.ContentState(
                title: block.title,
                timeRangeText: block.timeRangeText,
                remainingMinutes: remainingMinutes,
                remainingTaskCount: snapshot.remainingTaskCount,
                topTaskTitle: snapshot.topTask?.title,
                statusMessage: snapshot.statusMessage
            ),
            staleDate: staleDate
        )

        return Payload(attributes: attributes, content: content)
    }
}

@available(iOS 16.1, *)
private struct Payload {
    let attributes: ThingStructCurrentBlockActivityAttributes
    let content: ActivityContent<ThingStructCurrentBlockActivityAttributes.ContentState>
}
#endif
