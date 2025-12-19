/*
 * StateStreamManager.swift
 * 状态流管理器
 *
 * 管理 72 小时的 StateItem 滑动窗口
 * 负责自动生成和手动应用 RoutineTemplate
 */

import Foundation
import SwiftData
import Observation

// MARK: - StateStreamManager

/// 状态流管理器
///
/// 职责：
/// 1. 维护 72 小时（3 天）的 StateItem 流
/// 2. 自动从匹配的 RoutineTemplate 生成新一天的 states
/// 3. 支持手动应用 RoutineTemplate（插入到 currentState 之后）
@MainActor
@Observable
final class StateStreamManager {
    
    // MARK: - 配置
    
    /// 流的时间窗口大小（小时）
    static let streamWindowHours: Int = 72
    
    /// 每天的小时数
    private static let hoursPerDay: Int = 24
    
    // MARK: - 状态
    
    /// 流的起始时间（通常是 2 天前的零点）
    private(set) var streamStartTime: Date
    
    /// 上次刷新时间
    private(set) var lastRefreshTime: Date
    
    // MARK: - 初始化
    
    init() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // 流的起始时间：昨天零点（这样今天在中间位置）
        self.streamStartTime = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        self.lastRefreshTime = now
    }
    
    // MARK: - 时间窗口计算
    
    /// 流的结束时间
    var streamEndTime: Date {
        Calendar.current.date(
            byAdding: .hour,
            value: Self.streamWindowHours,
            to: streamStartTime
        ) ?? streamStartTime
    }
    
    /// 流覆盖的日期列表（通常是 3 天）
    var streamDates: [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var currentDate = streamStartTime
        
        while currentDate < streamEndTime {
            dates.append(calendar.startOfDay(for: currentDate))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? streamEndTime
        }
        
        return dates
    }
    
    // MARK: - 刷新逻辑
    
    /// 检查是否需要刷新流（新的一天开始了）
    /// - Returns: 是否需要刷新
    func needsRefresh() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // 检查是否跨天了
        let lastRefreshDay = calendar.startOfDay(for: lastRefreshTime)
        let today = calendar.startOfDay(for: now)
        
        return today > lastRefreshDay
    }
    
    /// 刷新流：滑动窗口并生成新一天的 states
    /// - Parameters:
    ///   - routineTemplates: 所有 RoutineTemplate
    ///   - existingStates: 已存在的 StateItem（用于避免重复生成）
    ///   - modelContext: 数据库上下文
    func refreshIfNeeded(
        routineTemplates: [RoutineTemplate],
        existingStates: [StateItem],
        modelContext: ModelContext
    ) {
        guard needsRefresh() else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        // 滑动窗口：更新起始时间到昨天
        streamStartTime = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        lastRefreshTime = now
        
        // 检查流中的每一天，为缺少 states 的日期生成
        for date in streamDates {
            generateStatesForDateIfNeeded(
                date: date,
                routineTemplates: routineTemplates,
                existingStates: existingStates,
                modelContext: modelContext
            )
        }
    }
    
    /// 为指定日期生成 states（如果该日期还没有 states 且有匹配的模板）
    private func generateStatesForDateIfNeeded(
        date: Date,
        routineTemplates: [RoutineTemplate],
        existingStates: [StateItem],
        modelContext: ModelContext
    ) {
        let calendar = Calendar.current
        
        // 检查该日期是否已有 states
        let hasStatesForDate = existingStates.contains { state in
            calendar.isDate(state.date, inSameDayAs: date)
        }
        
        guard !hasStatesForDate else { return }
        
        // 查找匹配该日期的 RoutineTemplate
        guard let matchingTemplate = routineTemplates.first(where: { $0.matchesDate(date) }) else {
            return
        }
        
        // 生成 states
        let maxOrder = existingStates
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map { $0.order }
            .max() ?? -1
        
        _ = matchingTemplate.createStates(
            for: date,
            startOrder: maxOrder + 1,
            modelContext: modelContext
        )
    }
    
    // MARK: - 手动应用
    
    /// 手动应用 RoutineTemplate
    /// 将模板中的 states 插入到 currentState 之后
    /// - Parameters:
    ///   - template: 要应用的模板
    ///   - currentState: 当前状态（新 states 会插入到其后）
    ///   - allStates: 所有现有状态（用于更新 order）
    ///   - modelContext: 数据库上下文
    /// - Returns: 新创建的 states
    @discardableResult
    func applyTemplate(
        _ template: RoutineTemplate,
        after currentState: StateItem?,
        allStates: [StateItem],
        modelContext: ModelContext
    ) -> [StateItem] {
        let today = Calendar.current.startOfDay(for: Date())
        
        // 确定插入位置的 order
        let insertOrder: Int
        if let current = currentState {
            insertOrder = current.order + 1
        } else {
            // 没有当前状态，插入到最后
            insertOrder = (allStates.map { $0.order }.max() ?? -1) + 1
        }
        
        // 更新后续 states 的 order（为新 states 腾出空间）
        let statesToShift = allStates.filter { $0.order >= insertOrder }
        let shiftAmount = template.stateTemplates.count
        
        for state in statesToShift {
            state.order += shiftAmount
        }
        
        // 创建新的 states
        let newStates = template.createStates(
            for: today,
            startOrder: insertOrder,
            modelContext: modelContext
        )
        
        return newStates
    }
    
    // MARK: - 初始化流
    
    /// 初始化流：确保流中的每一天都有 states（如果有匹配的模板）
    /// 通常在应用启动时调用
    func initializeStream(
        routineTemplates: [RoutineTemplate],
        existingStates: [StateItem],
        modelContext: ModelContext
    ) {
        for date in streamDates {
            generateStatesForDateIfNeeded(
                date: date,
                routineTemplates: routineTemplates,
                existingStates: existingStates,
                modelContext: modelContext
            )
        }
        
        lastRefreshTime = Date()
    }
}
