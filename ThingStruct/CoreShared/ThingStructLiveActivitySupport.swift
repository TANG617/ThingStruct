#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation

// Live Activity 的“属性”和“内容状态”需要是独立的可编码类型，
// 因为它们会被系统拿去在锁屏、Dynamic Island 等系统 UI 中展示。
// 这里和普通 SwiftUI View State 不同，它更像一个跨进程展示载荷。
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

// 这个控制器统一管理当前 block 的 Live Activity 生命周期。
// 责任包括：
// - 根据 repository 生成快照
// - 决定应该启动、更新还是结束 activity
// - 保证同一时刻不会残留多份重复 activity
@available(iOS 16.1, *)
enum ThingStructCurrentBlockLiveActivityController {
    static func start(
        using repository: ThingStructDocumentRepository = .appLive,
        at date: Date = .now
    ) async throws -> Bool {
        // 当前实现把“start”统一复用成一次 `sync`：
        // 有活动就更新，没有就新建，不该显示时就结束。
        try await sync(using: repository, at: date)
    }

    static func sync(
        using repository: ThingStructDocumentRepository = .appLive,
        at date: Date = .now
    ) async throws -> Bool {
        // 如果系统层面禁用了 Live Activity，就立即清理所有现有 activity。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return false
        }

        let snapshot = try repository.liveActivitySnapshot(at: date)
        guard let payload = payload(from: snapshot, referenceDate: date) else {
            // 没有可展示的当前 block 时，结束 activity 比保留旧内容更安全。
            await endAll()
            return false
        }

        // 如果已经存在同一个日期、同一个 block 的 activity，就原地更新。
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

        // 否则先清空旧 activity，再请求创建新的。
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
        // `Activity.activities` 给出当前 app 仍活着的所有 activity 实例。
        for activity in Activity<ThingStructCurrentBlockActivityAttributes>.activities
        where activity.id != activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func payload(
        from snapshot: ThingStructSystemLiveActivitySnapshot,
        referenceDate: Date
    ) -> Payload? {
        // 只有在“存在非空白当前块，且还没结束，且能构造跳转 URL”时才值得展示。
        guard
            let currentBlock = snapshot.currentBlock,
            !currentBlock.isBlank,
            currentBlock.endMinuteOfDay > snapshot.minuteOfDay,
            let tapURL = snapshot.tapURL()
        else {
            return nil
        }

        // `staleDate` 告诉系统：这份内容在什么时候之后应该被视为过期。
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
    // 只是一个内部打包结构，避免函数返回超长元组。
    let attributes: ThingStructCurrentBlockActivityAttributes
    let content: ActivityContent<ThingStructCurrentBlockActivityAttributes.ContentState>
}
#endif
