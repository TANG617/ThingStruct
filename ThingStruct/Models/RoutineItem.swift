/*
 * RoutineItem.swift
 * 例程数据模型
 *
 * Routine 是一天的全部状态集合
 * 层级结构：Routine -> State -> Checklist/Remarks
 */

import Foundation
import SwiftData

// MARK: - RoutineItem 数据模型

/// 例程：代表一天的全部状态
/// 
/// 每天只有一个 RoutineItem，包含当天所有的 StateItem
@Model
final class RoutineItem {
    
    // MARK: - 存储属性
    
    /// 唯一标识符
    var id: UUID
    
    /// 例程标题（可选，如"今日例程"）
    var title: String
    
    /// 所属日期（一天只有一个例程）
    var date: Date
    
    /// 例程包含的状态项
    /// @Relationship: 一对多关系，删除例程时自动删除所有状态
    @Relationship(deleteRule: .cascade) var stateItems: [StateItem]
    
    // MARK: - 构造器
    
    /// 创建一个新的例程
    /// - Parameters:
    ///   - title: 例程标题
    ///   - date: 所属日期，默认为当前日期
    init(title: String = "", date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.date = Calendar.current.startOfDay(for: date)
        self.stateItems = []
    }
    
    // MARK: - 计算属性
    
    /// 已完成的状态数量
    var completedStateCount: Int {
        stateItems.lazy.filter { $0.isCompleted }.count
    }
    
    /// 状态总数
    var totalStateCount: Int {
        stateItems.count
    }
    
    /// 是否所有状态都已完成
    var isCompleted: Bool {
        !stateItems.isEmpty && stateItems.allSatisfy(\.isCompleted)
    }
}
