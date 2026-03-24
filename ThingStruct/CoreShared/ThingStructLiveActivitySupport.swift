#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct ThingStructCurrentBlockActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var timeRangeText: String
        var remainingTaskCount: Int
        var tapURL: String
        var displayNote: String?
        var actionableTaskTitle: String?
        var actionableTaskDateISO: String?
        var actionableTaskBlockID: String?
        var actionableTaskID: String?
        var displaySourceBlockTitle: String?
        var statusMessage: String?
    }

    var dateISO: String
    var currentBlockID: String
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

        let snapshot = try client.liveActivitySnapshot(at: date)
        guard let payload = payload(from: snapshot, referenceDate: date) else {
            await endAll()
            return false
        }

        if let existing = Activity<ThingStructCurrentBlockActivityAttributes>.activities.first(
            where: {
                $0.attributes.currentBlockID == payload.attributes.currentBlockID &&
                    $0.attributes.dateISO == payload.attributes.dateISO
            }
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
        from snapshot: ThingStructSystemLiveActivitySnapshot,
        referenceDate: Date
    ) -> Payload? {
        guard
            let currentBlock = snapshot.currentBlock,
            !currentBlock.isBlank,
            currentBlock.endMinuteOfDay > snapshot.minuteOfDay,
            let tapURL = snapshot.tapURL()
        else {
            return nil
        }

        let staleDate = currentBlock.date.date(minuteOfDay: currentBlock.endMinuteOfDay) ?? referenceDate.addingTimeInterval(15 * 60)
        let attributes = ThingStructCurrentBlockActivityAttributes(
            dateISO: currentBlock.date.description,
            currentBlockID: currentBlock.blockID.uuidString
        )
        let content = ActivityContent(
            state: ThingStructCurrentBlockActivityAttributes.ContentState(
                title: currentBlock.title,
                timeRangeText: currentBlock.timeRangeText,
                remainingTaskCount: snapshot.remainingTaskCount,
                tapURL: tapURL.absoluteString,
                displayNote: snapshot.displayNote,
                actionableTaskTitle: snapshot.displayTask?.title,
                actionableTaskDateISO: snapshot.displayTask?.date.description,
                actionableTaskBlockID: snapshot.displayTask?.blockID.uuidString,
                actionableTaskID: snapshot.displayTask?.taskID.uuidString,
                displaySourceBlockTitle: snapshot.displaySourceBlockTitle,
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
