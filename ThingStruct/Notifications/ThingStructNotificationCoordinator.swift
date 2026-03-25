import Foundation
import UserNotifications
import WidgetKit

// 通知协调器负责把业务文档同步成“系统里实际挂起的本地通知”。
// 这层不做核心业务判断，而是做两件事：
// 1. 根据 document 推导应该有哪些通知
// 2. 把这些通知注册到 iOS 的 `UNUserNotificationCenter`
final class ThingStructNotificationCoordinator: NSObject {
    static let shared = ThingStructNotificationCoordinator()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "thingstruct.reminder."

    func configure() {
        // 注册 category/action 后，通知横幅上才能显示“完成任务”“10 分钟后提醒”这类按钮。
        center.delegate = self
        center.setNotificationCategories([notificationCategory])
    }

    func sync(with document: ThingStructDocument, referenceDate: Date = .now) {
        // 同步是异步执行的，因为：
        // - 读取待处理通知需要系统回调
        // - 请求权限 / 添加通知也都是异步 API
        Task {
            let requests = buildRequests(from: document, referenceDate: referenceDate)
            let pending = await pendingRequests()
            let pendingIdentifiers = Set(
                pending
                    .map(\.identifier)
                    // 只清理属于 ThingStruct 的通知，不影响用户设备上其他 app 的内容。
                    .filter { $0.hasPrefix(identifierPrefix) }
            )
            let desiredIdentifiers = Set(requests.map(\.identifier))

            let identifiersToRemove = Array(pendingIdentifiers.subtracting(desiredIdentifiers))
            if !identifiersToRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            }

            guard !requests.isEmpty else { return }
            guard await ensureAuthorizationIfNeeded() else { return }

            for request in requests {
                try? await add(request)
            }
        }
    }

    private var notificationCategory: UNNotificationCategory {
        // category 可以理解成“这一类通知有哪些交互按钮”。
        let completeAction = UNNotificationAction(
            identifier: ThingStructSharedConfig.notificationActionCompleteTopTask,
            title: "Complete task"
        )
        let snoozeAction = UNNotificationAction(
            identifier: ThingStructSharedConfig.notificationActionSnooze,
            title: "Remind in 10 min"
        )

        return UNNotificationCategory(
            identifier: ThingStructSharedConfig.notificationCategoryIdentifier,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
    }

    private func buildRequests(
        from document: ThingStructDocument,
        referenceDate: Date
    ) -> [UNNotificationRequest] {
        // 这里只看未来两周，避免系统里积累过多远期通知。
        let horizon = referenceDate.addingTimeInterval(14 * 24 * 60 * 60)

        return document.dayPlans
            .filter { $0.date >= LocalDay(date: referenceDate) }
            .compactMap { plan in
                try? DayPlanEngine.resolved(plan)
            }
            .flatMap { plan in
                plan.blocks.compactMap { block in
                    request(
                        for: block,
                        on: plan.date,
                        referenceDate: referenceDate,
                        horizon: horizon
                    )
                }
            }
    }

    private func request(
        for block: TimeBlock,
        on date: LocalDay,
        referenceDate: Date,
        horizon: Date
    ) -> UNNotificationRequest? {
        guard
            !block.isCancelled,
            let startMinuteOfDay = block.resolvedStartMinuteOfDay
        else {
            return nil
        }

        guard let reminder = block.reminders.sorted(by: reminderSort).first else {
            return nil
        }

        // 同一 block 可能配置多个 reminder，这里目前选择排序后的第一条作为实际通知。
        let triggerMinuteOfDay: Int
        switch reminder.triggerMode {
        case .atStart:
            triggerMinuteOfDay = startMinuteOfDay
        case .beforeStart:
            triggerMinuteOfDay = max(0, startMinuteOfDay - reminder.offsetMinutes)
        }

        guard
            let fireDate = date.date(minuteOfDay: triggerMinuteOfDay),
            fireDate > referenceDate,
            fireDate <= horizon
        else {
            return nil
        }

        let content = UNMutableNotificationContent()
        // `title/subtitle/body` 就是用户最终在系统通知里看到的文字。
        content.title = block.title
        content.subtitle = formattedTime(startMinuteOfDay)
        content.body = reminderBody(for: block)
        content.sound = .default
        content.categoryIdentifier = ThingStructSharedConfig.notificationCategoryIdentifier
        content.userInfo = [
            // `userInfo` 是通知跳回 app 时的上下文载荷。
            // 它的地位很像桌面开发里“消息参数”或“命令上下文”。
            ThingStructSharedConfig.notificationUserInfoDateKey: date.description,
            ThingStructSharedConfig.notificationUserInfoBlockKey: block.id.uuidString,
            ThingStructSharedConfig.notificationUserInfoTaskKey: block.tasks
                .sorted(by: taskSort)
                .first(where: { !$0.isCompleted })?.id.uuidString ?? ""
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(
            identifier: notificationIdentifier(for: date, blockID: block.id, reminderID: reminder.id),
            content: content,
            trigger: trigger
        )
    }

    private func reminderBody(for block: TimeBlock) -> String {
        // 通知正文优先提示“下一件要做的事”，比只显示 block 名称更具体。
        if let task = block.tasks.sorted(by: taskSort).first(where: { !$0.isCompleted }) {
            return "Next up: \(task.title)"
        }

        return "It's time for \(block.title)."
    }

    private func notificationIdentifier(
        for date: LocalDay,
        blockID: UUID,
        reminderID: UUID
    ) -> String {
        "\(identifierPrefix)\(date.description).\(blockID.uuidString).\(reminderID.uuidString)"
    }

    private func reminderSort(lhs: ReminderRule, rhs: ReminderRule) -> Bool {
        // 排序规则决定“多个 reminder 里谁优先成为真正发出的通知”。
        if lhs.triggerMode != rhs.triggerMode {
            return lhs.triggerMode == .beforeStart && rhs.triggerMode == .atStart
        }
        if lhs.offsetMinutes != rhs.offsetMinutes {
            return lhs.offsetMinutes < rhs.offsetMinutes
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func taskSort(lhs: TaskItem, rhs: TaskItem) -> Bool {
        // 任务排序遵循业务里的 `order`，再用 UUID 打破平局，确保结果稳定。
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func formattedTime(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func ensureAuthorizationIfNeeded() async -> Bool {
        // 通知权限是移动端开发里的一个高频概念：
        // 没授权时，代码逻辑没问题也不会真的弹通知。
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await requestAuthorization()) ?? false
        default:
            return false
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        // 这类 callback 风格 API 用 continuation 桥接到 async/await，
        // 是现代 Swift 并发里非常常见的写法。
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        // `center.add` 也是 callback API，这里同样做一次 async 封装。
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func scheduleSnooze(for response: UNNotificationResponse) async {
        // snooze 本质上就是复制原通知内容，再挂一个 10 分钟后的 time interval trigger。
        let original = response.notification.request.content
        let content = UNMutableNotificationContent()
        content.title = original.title
        content.subtitle = original.subtitle
        content.body = original.body
        content.sound = original.sound
        content.categoryIdentifier = original.categoryIdentifier
        content.userInfo = original.userInfo

        let request = UNNotificationRequest(
            identifier: response.notification.request.identifier + ".snooze",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        )

        try? await add(request)
    }

    private func routeURL(for response: UNNotificationResponse) -> URL? {
        // 用户点击通知本体时，不直接把响应对象丢给 UI，
        // 而是翻译成统一 deep link URL，这样 app 内部只需要处理一种入口格式。
        let userInfo = response.notification.request.content.userInfo
        let date = (userInfo[ThingStructSharedConfig.notificationUserInfoDateKey] as? String)
            .flatMap(LocalDay.init(isoDateString:))
        let blockID = (userInfo[ThingStructSharedConfig.notificationUserInfoBlockKey] as? String)
            .flatMap(UUID.init(uuidString:))
        let taskID = (userInfo[ThingStructSharedConfig.notificationUserInfoTaskKey] as? String)
            .flatMap(UUID.init(uuidString:))

        return ThingStructSystemRoute.today(
            date: date,
            blockID: blockID,
            taskID: taskID,
            source: .notification
        ).url
    }

    private func completeTopTask(for response: UNNotificationResponse) async {
        // 点击“完成任务”按钮时，通知层直接通过 repository 改文档，
        // 然后同步 widget / live activity / 通知本身。
        let userInfo = response.notification.request.content.userInfo
        guard
            let dateString = userInfo[ThingStructSharedConfig.notificationUserInfoDateKey] as? String,
            let date = LocalDay(isoDateString: dateString),
            let blockIDString = userInfo[ThingStructSharedConfig.notificationUserInfoBlockKey] as? String,
            let blockID = UUID(uuidString: blockIDString)
        else {
            return
        }

        let repository = ThingStructDocumentRepository.appLive
        _ = try? repository.completeTopTask(on: date, in: blockID)
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)

        if #available(iOS 16.1, *) {
            _ = try? await ThingStructCurrentBlockLiveActivityController.sync(using: .appLive, at: .now)
        }

        if let document = try? repository.load() {
            sync(with: document)
        }
    }
}

extension ThingStructNotificationCoordinator: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // app 在前台时，默认很多通知不会明显展示。
        // 这里显式要求仍然显示 banner 和声音。
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // 通知按钮点击、本体点击，最终都会汇聚到这里。
        switch response.actionIdentifier {
        case ThingStructSharedConfig.notificationActionCompleteTopTask:
            await completeTopTask(for: response)

        case ThingStructSharedConfig.notificationActionSnooze:
            await scheduleSnooze(for: response)

        case UNNotificationDefaultActionIdentifier:
            if let url = routeURL(for: response) {
                await MainActor.run {
                    // UI 路由中心是主线程对象，所以这里切回 MainActor。
                    ThingStructExternalRouteCenter.shared.enqueue(url)
                }
            }

        default:
            break
        }
    }
}
