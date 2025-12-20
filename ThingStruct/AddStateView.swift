/*
 * AddStateView.swift
 * 添加新状态的视图
 *
 * 这个文件展示了SwiftUI的视图组合模式：
 * - 一个视图可以复用另一个视图（StateInputView）
 * - 通过闭包传递数据保存逻辑
 *
 * 设计思想：
 * - AddStateView 负责业务逻辑（如何保存数据）
 * - StateInputView 负责UI展示（输入表单）
 * 这种分离让 StateInputView 可以在多处复用
 */

import SwiftUI
import SwiftData

// MARK: - 添加状态视图

@MainActor
struct AddStateView: View {
    
    // MARK: - 环境属性
    
    /*
     * @Environment(\.modelContext)：获取数据库上下文
     *
     * modelContext用于：
     * - 插入新记录（insert）
     * - 删除记录（delete）
     * - SwiftData自动处理保存
     */
    @Environment(\.modelContext) private var modelContext
    
    /*
     * @Environment(\.dismiss)：获取关闭视图的动作
     *
     * dismiss是一个闭包，调用它可以关闭当前视图
     * 用于关闭模态弹窗（sheet）
     *
     * C/C++对比：类似于对话框的close()方法
     * 但这里是声明式的：你获取一个"关闭动作"，在需要时调用它
     *
     * 注意：虽然在这个文件中没有直接使用dismiss，
     * 但StateInputView内部会使用它来关闭弹窗
     */
    @Environment(\.dismiss) private var dismiss
    
    /*
     * @Query：自动查询数据库中的所有状态
     *
     * sort: \StateItem.order 按order属性排序
     * 我们需要知道今天有多少状态，以便设置新状态的排序顺序
     */
    @Query(sort: \StateItem.order) private var allStates: [StateItem]
    
    // MARK: - 计算属性
    
    /// 今天的日期（零点时刻）
    private var today: Date {
        Calendar.current.startOfDay(for: Date.now)
    }
    
    /// 今天的状态数量（用于确定新状态的排序位置）
    private var todayStates: [StateItem] {
        allStates.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        /*
         * 视图组合（View Composition）
         *
         * 这里直接使用 StateInputView 作为主体
         * 通过参数配置其外观和行为
         *
         * 这是SwiftUI推荐的模式：
         * - 创建小的、可复用的视图组件
         * - 通过组合构建复杂界面
         *
         * C/C++对比：
         * 类似于组合模式（Composite Pattern）
         * 一个组件包含其他组件
         */
        StateInputView(
            navigationTitle: "New State",       // 导航栏标题
            titlePlaceholder: "State Title",    // 输入框占位符
            confirmButtonTitle: "Done"          // 确认按钮文字
        ) { title, checklistItems in
            /*
             * 尾随闭包（Trailing Closure）
             *
             * 这是Swift的语法糖：
             * - 当函数最后一个参数是闭包时
             * - 可以把闭包写在括号外面
             *
             * 完整写法：
             * StateInputView(..., onSave: { title, checklistItems in ... })
             *
             * 这个闭包定义了保存数据的逻辑
             * StateInputView会在用户点击保存时调用它
             */
            
            // 创建新的状态对象
            let newState = StateItem(
                title: title,
                date: Date.now,                    // 当前日期
                order: todayStates.count         // 排在今天所有状态之后
            )
            
            // 插入到数据库
            modelContext.insert(newState)
            
            /*
             * enumerated()：同时获取索引和值
             *
             * for (index, itemTitle) in array.enumerated()
             * 等价于：
             * for i in 0..<array.count {
             *     let index = i
             *     let itemTitle = array[i]
             * }
             *
             * C/C++对比：
             * for (size_t i = 0; i < items.size(); i++) {
             *     int index = i;
             *     auto& itemTitle = items[i];
             * }
             */
            for (index, itemTitle) in checklistItems.enumerated() {
                // 为每个清单项创建对象
                let checklistItem = ChecklistItem(title: itemTitle, order: index)
                
                // 插入数据库
                modelContext.insert(checklistItem)
                
                // 建立关联关系
                // SwiftData会自动维护数据库中的外键关系
                newState.checklistItems.append(checklistItem)
            }
            
            // 注意：不需要手动调用save()
            // SwiftData会自动保存更改
        }
    }
}

// MARK: - 预览

#Preview {
    AddStateView()
        // 使用内存数据库进行预览
        .modelContainer(for: [StateItem.self], inMemory: true)
}
