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
