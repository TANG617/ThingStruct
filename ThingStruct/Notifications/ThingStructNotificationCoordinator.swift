import Foundation
import UserNotifications
import WidgetKit

final class ThingStructNotificationCoordinator: NSObject {
    static let shared = ThingStructNotificationCoordinator()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "thingstruct.reminder."

    func configure() {
        center.delegate = self
        center.setNotificationCategories([notificationCategory])
    }

    func sync(with document: ThingStructDocument, referenceDate: Date = .now) {
        Task {
            let requests = buildRequests(from: document, referenceDate: referenceDate)
            let pending = await pendingRequests()
            let pendingIdentifiers = Set(
                pending
                    .map(\.identifier)
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
        content.title = block.title
        content.subtitle = formattedTime(startMinuteOfDay)
        content.body = reminderBody(for: block)
        content.sound = .default
        content.categoryIdentifier = ThingStructSharedConfig.notificationCategoryIdentifier
        content.userInfo = [
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
        if lhs.triggerMode != rhs.triggerMode {
            return lhs.triggerMode == .beforeStart && rhs.triggerMode == .atStart
        }
        if lhs.offsetMinutes != rhs.offsetMinutes {
            return lhs.offsetMinutes < rhs.offsetMinutes
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func taskSort(lhs: TaskItem, rhs: TaskItem) -> Bool {
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
        let userInfo = response.notification.request.content.userInfo
        guard
            let dateString = userInfo[ThingStructSharedConfig.notificationUserInfoDateKey] as? String,
            let date = LocalDay(isoDateString: dateString),
            let blockIDString = userInfo[ThingStructSharedConfig.notificationUserInfoBlockKey] as? String,
            let blockID = UUID(uuidString: blockIDString)
        else {
            return
        }

        let client = ThingStructSharedDocumentClient.appLive
        _ = try? client.completeTopTask(on: date, in: blockID)
        WidgetCenter.shared.reloadTimelines(ofKind: ThingStructSharedConfig.widgetKind)

        if #available(iOS 16.1, *) {
            _ = try? await ThingStructCurrentBlockLiveActivityController.sync(using: .appLive, at: .now)
        }

        if let document = try? client.load() {
            sync(with: document)
        }
    }
}

extension ThingStructNotificationCoordinator: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case ThingStructSharedConfig.notificationActionCompleteTopTask:
            await completeTopTask(for: response)

        case ThingStructSharedConfig.notificationActionSnooze:
            await scheduleSnooze(for: response)

        case UNNotificationDefaultActionIdentifier:
            if let url = routeURL(for: response) {
                await MainActor.run {
                    ThingStructExternalRouteCenter.shared.enqueue(url)
                }
            }

        default:
            break
        }
    }
}
