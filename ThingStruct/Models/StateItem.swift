/*
 * StateItem.swift
 * 状态（任务）数据模型
 *
 * 这是应用的核心数据模型，代表一个待办状态/任务
 * 包含了更多Swift特性：计算属性、关系映射、闭包等
 *
 * 注意：类名使用 StateItem 而不是 State，
 * 因为 State 会与 SwiftUI 的 @State 属性包装器冲突
 */

import Foundation
import SwiftData

// MARK: - StateItem 数据模型

/// 状态模型：代表一个待办任务，可以包含多个清单子项
/// 
/// SwiftData: @Model 宏将这个类映射到数据库表
/// 数据库会自动创建一个名为 "StateItem" 的表来存储数据
@Model
final class StateItem {
    
    // MARK: - 存储属性
    
    /// 唯一标识符（数据库主键）
    var id: UUID
    
    /// 状态标题
    var title: String
    
    /// 排序顺序（数字越小越靠前）
    var order: Int
    
    /// 是否已完成
    var isCompleted: Bool
    
    /// 所属日期（用于按天分组显示）
    var date: Date
    
    // MARK: - 关系属性（Relationship）
    
    /*
     * @Relationship 属性包装器：定义数据模型之间的关系
     * 
     * SwiftData: 类似于关系型数据库的外键关系
     * C/C++对比：类似于 C++ 中一个对象持有另一个对象的指针/引用
     *
     * deleteRule 参数指定删除行为：
     * - .cascade（级联删除）：删除StateItem时，自动删除所有关联的ChecklistItem
     * - .nullify：删除时只断开关系，不删除关联对象
     * - .deny：如果有关联对象，阻止删除
     *
     * 数据库层面：这会创建一个外键关系
     * StateItem表 <--一对多--> ChecklistItem表
     */
    @Relationship(deleteRule: .cascade) var checklistItems: [ChecklistItem]
    
    // MARK: - 构造器
    
    /// 创建一个新的状态
    /// - Parameters:
    ///   - title: 状态标题
    ///   - date: 所属日期，默认为当前日期
    ///   - order: 排序顺序，默认为0
    init(title: String, date: Date = Date.now, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.isCompleted = false
        /*
         * Calendar.current.startOfDay(for:) 获取某一天的开始时间（00:00:00）
         * 这样可以忽略具体时分秒，只比较日期
         * 
         * Calendar.current：获取用户当前日历设置
         * C/C++对比：类似于使用 time.h 中的 localtime() 然后清零时分秒
         */
        self.date = Calendar.current.startOfDay(for: date)
        self.checklistItems = []  // 空数组，后续可以添加子项
    }
    
    // MARK: - 计算属性（Computed Properties）
    
    /*
     * 计算属性：不存储数据，每次访问时动态计算
     * 
     * C/C++对比：类似于 C++ 的 getter 方法，但语法更简洁
     * 看起来像访问变量，实际上是调用函数
     *
     * 优点：
     * 1. 数据始终是最新的（不会过期）
     * 2. 不占用存储空间
     * 3. 调用者使用起来像普通属性一样简单
     *
     * 语法：var 属性名: 类型 { 计算代码 }
     * 没有 = 号，用花括号包裹计算逻辑
     */
    
    /// 未完成的清单项数量
    var incompleteChecklistCount: Int {
        /*
         * 这里展示了 Swift 的函数式编程特性
         *
         * checklistItems.lazy：创建一个惰性序列
         *   - lazy：延迟计算，不会创建中间数组，节省内存
         *   - C/C++对比：类似于 C++20 的 ranges::views
         *
         * .filter { ... }：过滤操作，保留满足条件的元素
         *   - { !$0.isCompleted } 是一个闭包（匿名函数）
         *   - $0 是闭包的第一个参数（自动命名）
         *   - C/C++对比：类似于 std::count_if 配合 lambda
         *
         * .count：计算元素数量
         *
         * 等价的 C++ 代码：
         * int count = std::count_if(checklistItems.begin(), checklistItems.end(),
         *     [](const auto& item) { return !item.isCompleted; });
         */
        checklistItems.lazy.filter { !$0.isCompleted }.count
    }
    
    /// 清单项总数
    var totalChecklistCount: Int {
        checklistItems.count
    }
    
    // MARK: - 实例方法
    
    /// 根据子项完成状态，更新整体完成状态
    /// 当所有子项都完成时，自动将状态标记为已完成
    func updateCompletionStatus() {
        /*
         * guard 语句：提前返回的条件检查
         * 
         * C/C++对比：类似于在函数开头的 if 检查然后 return
         * 但 guard 语法更清晰地表达"前置条件"的意图
         *
         * guard 条件 else { return }
         * 意思是：如果条件不满足，就执行 else 块（通常是 return）
         * 
         * 等价C++：if (checklistItems.empty()) return;
         */
        guard !checklistItems.isEmpty else { return }
        
        /*
         * allSatisfy：检查是否所有元素都满足条件
         *
         * \.isCompleted 是"键路径"(Key Path)语法
         * C/C++对比：类似于成员指针，但更安全和强类型
         * 
         * \.isCompleted 等价于 { $0.isCompleted }
         * 即访问每个元素的 isCompleted 属性
         *
         * 等价的 C++ 代码：
         * bool allCompleted = std::all_of(checklistItems.begin(), checklistItems.end(),
         *     [](const auto& item) { return item.isCompleted; });
         */
        let allCompleted = checklistItems.allSatisfy(\.isCompleted)
        
        // 只有状态真正改变时才更新，避免不必要的数据库写入
        if allCompleted != isCompleted {
            isCompleted = allCompleted
        }
    }
}
