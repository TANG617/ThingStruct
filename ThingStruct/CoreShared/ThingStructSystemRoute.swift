import Foundation

enum ThingStructSharedConfig {
    static let appGroupID = "group.tang.ThingStruct"
    static let tintPresetDefaultsKey = "THINGSTRUCT_TINT_PRESET"
    static let widgetKind = "ThingStructNowWidget"
    static let currentBlockLiveActivityKind = "ThingStructCurrentBlockLiveActivity"
    static let openNowControlKind = "ThingStructOpenNowControl"
    static let completeCurrentTaskControlKind = "ThingStructCompleteCurrentTaskControl"
    static let openCurrentBlockControlKind = "ThingStructOpenCurrentBlockControl"
    static let startLiveActivityControlKind = "ThingStructStartLiveActivityControl"
    static let deepLinkScheme = "thingstruct"
    static let sharedDirectoryName = "ThingStruct"
    static let documentFileName = "document.json"
    static let notificationCategoryIdentifier = "THINGSTRUCT_REMINDER"
    static let notificationActionCompleteTopTask = "THINGSTRUCT_COMPLETE_TOP_TASK"
    static let notificationActionSnooze = "THINGSTRUCT_SNOOZE_10M"
    static let notificationUserInfoDateKey = "dateISO"
    static let notificationUserInfoBlockKey = "blockID"
    static let notificationUserInfoTaskKey = "taskID"
    static let quickActionNow = "tang.ThingStruct.quickaction.now"
    static let quickActionToday = "tang.ThingStruct.quickaction.today"
    static let quickActionTemplates = "tang.ThingStruct.quickaction.templates"
    static let quickActionCurrentBlock = "tang.ThingStruct.quickaction.currentBlock"
}

enum ThingStructSystemSource: String, Codable, Sendable {
    case app
    case widget
    case control
    case shortcut
    case notification
    case quickAction
    case liveActivity
}

enum ThingStructSystemRoute: Equatable, Sendable {
    case now(source: ThingStructSystemSource? = nil)
    case today(
        date: LocalDay? = nil,
        blockID: UUID? = nil,
        taskID: UUID? = nil,
        source: ThingStructSystemSource? = nil
    )
    case templates(source: ThingStructSystemSource? = nil)
    case startCurrentBlockLiveActivity(source: ThingStructSystemSource? = nil)
    case endCurrentBlockLiveActivity(source: ThingStructSystemSource? = nil)

    init?(url: URL) {
        guard
            url.scheme?.lowercased() == ThingStructSharedConfig.deepLinkScheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let host = url.host ?? ""
        let routeSource = host.isEmpty
            ? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : host
        let route = routeSource.lowercased()

        let source = components.queryItems?.thingStructValue(for: "source")
            .flatMap(ThingStructSystemSource.init(rawValue:))

        switch route {
        case "now":
            self = .now(source: source)

        case "today":
            self = .today(
                date: components.queryItems?.thingStructValue(for: "date").flatMap(LocalDay.init(isoDateString:)),
                blockID: components.queryItems?.thingStructValue(for: "block").flatMap(UUID.init(uuidString:)),
                taskID: components.queryItems?.thingStructValue(for: "task").flatMap(UUID.init(uuidString:)),
                source: source
            )

        case "templates":
            self = .templates(source: source)

        case "start-live-activity":
            self = .startCurrentBlockLiveActivity(source: source)

        case "end-live-activity":
            self = .endCurrentBlockLiveActivity(source: source)

        default:
            return nil
        }
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = ThingStructSharedConfig.deepLinkScheme

        switch self {
        case let .now(source):
            components.host = "now"
            components.queryItems = queryItems(source: source)

        case let .today(date, blockID, taskID, source):
            components.host = "today"
            components.queryItems = queryItems(
                date: date,
                blockID: blockID,
                taskID: taskID,
                source: source
            )

        case let .templates(source):
            components.host = "templates"
            components.queryItems = queryItems(source: source)

        case let .startCurrentBlockLiveActivity(source):
            components.host = "start-live-activity"
            components.queryItems = queryItems(source: source)

        case let .endCurrentBlockLiveActivity(source):
            components.host = "end-live-activity"
            components.queryItems = queryItems(source: source)
        }

        return components.url
    }

    private func queryItems(
        date: LocalDay? = nil,
        blockID: UUID? = nil,
        taskID: UUID? = nil,
        source: ThingStructSystemSource? = nil
    ) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []

        if let date {
            items.append(URLQueryItem(name: "date", value: date.description))
        }
        if let blockID {
            items.append(URLQueryItem(name: "block", value: blockID.uuidString))
        }
        if let taskID {
            items.append(URLQueryItem(name: "task", value: taskID.uuidString))
        }
        if let source {
            items.append(URLQueryItem(name: "source", value: source.rawValue))
        }

        return items.isEmpty ? nil : items
    }
}

extension [URLQueryItem] {
    func thingStructValue(for name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}

extension LocalDay {
    init?(isoDateString: String) {
        let parts = isoDateString.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        self.init(year: year, month: month, day: day)
    }

    func date(
        minuteOfDay: Int = 0,
        calendar: Calendar = .current
    ) -> Date? {
        guard let startOfDay = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return nil
        }

        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay)
    }
}

extension Date {
    var minuteOfDay: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
