import Foundation

// 这一组常量是 app、widget、notification、shortcut 等系统表面共享的配置。
// 之所以放在一起，是因为它们大多都和“系统集成入口”有关。
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

// `ThingStructSystemSource` 用来标记“这次系统跳转/动作是从哪里来的”。
// 这既方便调试，也方便未来做埋点或差异化行为。
enum ThingStructSystemSource: String, Codable, Sendable {
    case app
    case widget
    case control
    case shortcut
    case notification
    case quickAction
    case liveActivity
}

// `ThingStructSystemRoute` 是项目内部统一的路由描述。
//
// 重点理解：
// - 外部世界看到的是 URL
// - app 内部真正流转的是这个 enum
//
// 这能把“字符串解析”限制在一个地方，避免整个项目到处手写 `if url.host == ...`。
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
        // 先做最外层过滤：scheme 不对，说明根本不是本 app 的路由。
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
        // 这里兼容两种 URL 形态：
        // - thingstruct://today?date=...
        // - thingstruct:///today?date=...
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
            // 无法识别的 host/path 直接返回 nil，让调用方决定是否忽略。
            return nil
        }
    }

    var url: URL? {
        // 与 `init?(url:)` 相反，这里负责把内部枚举重新序列化成 URL。
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
        // 只有非 nil 的参数才写进 URL，保持生成的 deep link 简洁。
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
    // 给 queryItems 数组补一个“按名称取值”的小 helper。
    func thingStructValue(for name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}

extension LocalDay {
    // 从 ISO 日期字符串（例如 "2026-03-25"）构造 `LocalDay`。
    // 这个 helper 主要服务 deep link / notification / widget 参数解析。
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
        // 把“某天 + 某分钟”重新还原成系统 `Date`。
        // 这常用于通知触发时间、边界计算等需要真实时间点的地方。
        guard let startOfDay = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return nil
        }

        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay)
    }
}

extension Date {
    // 把系统 Date 投影为“当天第几分钟”，是本项目里最常用的时间表示之一。
    var minuteOfDay: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
