/*
 * RoutineTemplate.swift
 * 例程模板数据模型
 *
 * 例程模板是可复用的蓝图，用户可以从模板快速创建一天的例程
 * 层级结构：RoutineTemplate -> StateTemplate -> ChecklistItem（作为模板）
 */

import Foundation
import SwiftData

// MARK: - RoutineTemplate 数据模型

/// 例程模板：可复用的例程蓝图
/// 
/// 使用场景：
/// - 用户定义一个"工作日例程"模板，包含多个状态（如"晨间"、"工作"、"晚间"）
/// - 每天可以从模板快速创建当天的例程，无需重复输入
@Model
final class RoutineTemplate {
    
    // MARK: - 存储属性
    
    /// 唯一标识符
    var id: UUID
    
    /// 模板标题
    var title: String
    
    /// 重复日期（存储为 Int 数组，因为 SwiftData 不支持直接存储 Set<Enum>）
    /// 值对应 Weekday.rawValue：1=周日, 2=周一, ..., 7=周六
    /// 空数组表示不自动重复，只能手动应用
    var repeatDaysRaw: [Int]
    
    /// 模板包含的状态模板
    /// @Relationship: 一对多关系，一个例程模板可以有多个状态模板
    @Relationship(deleteRule: .cascade) var stateTemplates: [StateTemplate]
    
    // MARK: - 计算属性
    
    /// 重复日期的便捷访问（Set<Weekday> 形式）
    var repeatDays: Set<Weekday> {
        get { Set<Weekday>.from(intArray: repeatDaysRaw) }
        set { repeatDaysRaw = newValue.toIntArray }
    }
    
    /// 是否设置了自动重复
    var hasAutoRepeat: Bool {
        !repeatDaysRaw.isEmpty
    }
    
    /// 检查指定日期是否匹配此模板的重复规则
    /// - Parameter date: 要检查的日期
    /// - Returns: 是否匹配
    func matchesDate(_ date: Date) -> Bool {
        guard hasAutoRepeat else { return false }
        let weekday = Weekday.from(date: date)
        return repeatDays.contains(weekday)
    }
    
    // MARK: - 构造器
    
    /// 创建一个新的例程模板
    /// - Parameters:
    ///   - title: 模板标题
    ///   - repeatDays: 重复日期，默认为空（不自动重复）
    init(title: String, repeatDays: Set<Weekday> = []) {
        self.id = UUID()
        self.title = title
        self.repeatDaysRaw = repeatDays.toIntArray
        self.stateTemplates = []
    }
    
    // MARK: - 冲突检测
    
    /// 获取与其他模板冲突的日期
    /// - Parameters:
    ///   - days: 要检查的日期集合
    ///   - templates: 其他模板列表
    /// - Returns: 冲突的日期集合（已被其他模板占用）
    static func conflictingDays(
        for days: Set<Weekday>,
        with templates: [RoutineTemplate],
        excluding currentTemplate: RoutineTemplate? = nil
    ) -> Set<Weekday> {
        var occupied = Set<Weekday>()
        
        for template in templates {
            // 排除当前正在编辑的模板
            if let current = currentTemplate, template.id == current.id {
                continue
            }
            occupied.formUnion(template.repeatDays)
        }
        
        return days.intersection(occupied)
    }
    
    /// 获取所有已被其他模板占用的日期
    /// - Parameters:
    ///   - templates: 所有模板列表
    ///   - currentTemplate: 当前正在编辑的模板（会被排除）
    /// - Returns: 已被占用的日期集合
    static func occupiedDays(
        in templates: [RoutineTemplate],
        excluding currentTemplate: RoutineTemplate? = nil
    ) -> Set<Weekday> {
        var occupied = Set<Weekday>()
        
        for template in templates {
            if let current = currentTemplate, template.id == current.id {
                continue
            }
            occupied.formUnion(template.repeatDays)
        }
        
        return occupied
    }
    
    // MARK: - 工厂方法
    
    /// 从模板创建一个新的例程实例
    /// - Parameters:
    ///   - date: 例程所属日期
    ///   - modelContext: SwiftData 数据库上下文
    /// - Returns: 新创建的例程对象
    ///
    /// 注意：此方法会自动将新对象插入数据库
    func createRoutine(for date: Date, modelContext: ModelContext) -> RoutineItem {
        // 创建新的例程对象
        let routineItem = RoutineItem(title: title, date: date)
        
        // 将例程插入数据库
        modelContext.insert(routineItem)
        
        // 从每个状态模板创建状态实例
        for (index, stateTemplate) in stateTemplates.enumerated() {
            // 使用 StateTemplate 的工厂方法创建 StateItem
            let stateItem = stateTemplate.createState(for: date, order: index, modelContext: modelContext)
            
            // 建立关系：将状态添加到例程
            routineItem.stateItems.append(stateItem)
        }
        
        return routineItem
    }
    
    /// 从模板创建 StateItems（不创建 RoutineItem）
    /// 用于手动应用模板，将状态插入到现有列表中
    /// - Parameters:
    ///   - date: 状态所属日期
    ///   - startOrder: 起始排序值
    ///   - modelContext: SwiftData 数据库上下文
    /// - Returns: 新创建的状态数组
    func createStates(for date: Date, startOrder: Int, modelContext: ModelContext) -> [StateItem] {
        var states: [StateItem] = []
        
        for (index, stateTemplate) in stateTemplates.enumerated() {
            let stateItem = stateTemplate.createState(
                for: date,
                order: startOrder + index,
                modelContext: modelContext
            )
            states.append(stateItem)
        }
        
        return states
    }
}
