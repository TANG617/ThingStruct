/*
 * Weekday.swift
 * 星期枚举
 *
 * 用于 RoutineTemplate 的重复日期选择
 * rawValue 使用 Calendar 标准：1=周日, 2=周一, ..., 7=周六
 */

import Foundation

// MARK: - Weekday 枚举

/// 星期枚举，用于设置 RoutineTemplate 的重复日期
///
/// rawValue 遵循 Calendar.Component.weekday 标准：
/// - 1 = 周日 (Sunday)
/// - 2 = 周一 (Monday)
/// - ...
/// - 7 = 周六 (Saturday)
enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    // MARK: - Identifiable
    
    var id: Int { rawValue }
    
    // MARK: - 显示名称
    
    /// 短名称（用于 UI 按钮显示）
    /// 例如："Mon", "Tue", "Wed"
    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
    
    /// 完整名称
    /// 例如："Sunday", "Monday"
    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
    
    /// 中文名称
    var chineseName: String {
        switch self {
        case .sunday: return "周日"
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        }
    }
    
    // MARK: - 工厂方法
    
    /// 从 Date 获取对应的 Weekday
    /// - Parameter date: 日期
    /// - Returns: 对应的星期枚举值
    static func from(date: Date) -> Weekday {
        let weekdayComponent = Calendar.current.component(.weekday, from: date)
        return Weekday(rawValue: weekdayComponent) ?? .sunday
    }
    
    /// 获取今天的星期
    static var today: Weekday {
        from(date: Date.now)
    }
    
    // MARK: - 排序后的列表（周一开始）
    
    /// 按周一到周日排序的列表（更符合中国习惯）
    static var mondayFirst: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}

// MARK: - Set<Weekday> 扩展

extension Set where Element == Weekday {
    /// 转换为 [Int] 用于 SwiftData 存储
    var toIntArray: [Int] {
        self.map { $0.rawValue }.sorted()
    }
    
    /// 从 [Int] 创建 Set<Weekday>
    static func from(intArray: [Int]) -> Set<Weekday> {
        Set(intArray.compactMap { Weekday(rawValue: $0) })
    }
}
