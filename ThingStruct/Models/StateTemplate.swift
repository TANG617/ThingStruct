/*
 * StateTemplate.swift
 * 状态模板数据模型
 *
 * 模板是可复用的状态蓝图，用户可以从模板快速创建新的状态
 * 这个文件展示了工厂方法模式和 SwiftData 的数据操作
 */

import Foundation
import SwiftData

// MARK: - StateTemplate 数据模型

/// 状态模板：可复用的状态蓝图
/// 
/// 使用场景：
/// - 用户定义一个"晨间例程"模板，包含"刷牙"、"洗脸"等固定子项
/// - 每天可以从模板快速创建当天的任务，无需重复输入
@Model
final class StateTemplate {
    
    // MARK: - 存储属性
    
    /// 唯一标识符
    var id: UUID
    
    /// 模板标题
    var title: String
    
    /// 模板包含的清单项
    /// @Relationship: 一对多关系，一个模板可以有多个子项
    @Relationship(deleteRule: .cascade) var checklistItems: [ChecklistItem]
    
    // MARK: - 构造器
    
    /// 创建一个新的状态模板
    /// - Parameter title: 模板标题
    init(title: String) {
        self.id = UUID()
        self.title = title
        self.checklistItems = []
    }
    
    // MARK: - 工厂方法
    
    /*
     * 工厂方法模式（Factory Method Pattern）
     *
     * 设计模式：创建对象的方法，封装了复杂的创建逻辑
     * C/C++对比：类似于 C++ 的静态工厂方法或工厂类
     *
     * 为什么用工厂方法而不是直接 new/init：
     * 1. 创建过程复杂（需要同时创建多个关联对象）
     * 2. 需要访问数据库上下文
     * 3. 封装创建细节，调用者无需了解内部实现
     */
    
    /// 从模板创建一个新的状态实例
    /// - Parameters:
    ///   - date: 状态所属日期
    ///   - order: 排序顺序
    ///   - modelContext: SwiftData 数据库上下文
    /// - Returns: 新创建的状态对象
    ///
    /// 注意：此方法会自动将新对象插入数据库
    func createState(for date: Date, order: Int, modelContext: ModelContext) -> StateItem {
        /*
         * ModelContext 是 SwiftData 的核心类
         *
         * SwiftData: 类似于数据库连接 + 事务管理器
         * C/C++对比：类似于数据库的 Connection 对象
         *
         * 主要功能：
         * 1. insert(): 插入新记录
         * 2. delete(): 删除记录
         * 3. save(): 保存所有更改（通常自动调用）
         * 4. 追踪对象变化
         */
        
        // 创建新的状态对象（基于模板的标题）
        let stateItem = StateItem(title: title, date: date, order: order)
        
        // 将状态插入数据库
        // SwiftData: insert() 类似于 SQL 的 INSERT INTO
        modelContext.insert(stateItem)
        
        /*
         * enumerated() 方法：同时获取索引和元素
         *
         * C/C++对比：
         * - C++: for (size_t i = 0; i < items.size(); i++) { auto& item = items[i]; }
         * - Swift: for (index, item) in items.enumerated() { }
         *
         * 返回的是 (Int, Element) 元组序列
         * 比手动维护计数器更安全，不会越界
         */
        for (index, item) in checklistItems.enumerated() {
            /*
             * 这里创建的是新的 ChecklistItem 实例
             * 不是复制原来的对象，因为：
             * 1. 每个状态应该有独立的清单项（完成状态独立）
             * 2. 原来的清单项属于模板，新的属于状态
             */
            let newItem = ChecklistItem(title: item.title, order: index)
            
            // 插入数据库
            modelContext.insert(newItem)
            
            // 建立关系：将清单项添加到状态的 checklistItems 数组
            // SwiftData 会自动维护数据库中的外键关系
            stateItem.checklistItems.append(newItem)
        }
        
        return stateItem
    }
}
