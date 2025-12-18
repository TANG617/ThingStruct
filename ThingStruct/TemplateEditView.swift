/*
 * TemplateEditView.swift
 * 模板编辑视图
 *
 * 这个视图用于创建新模板或编辑现有模板
 * 复用了StateInputView组件，展示了视图组合的强大之处
 *
 * 关键概念：
 * - 可选参数区分创建/编辑模式
 * - 视图组合和复用
 * - map高阶函数
 */

import SwiftUI
import SwiftData

// MARK: - 模板编辑视图

@MainActor
struct TemplateEditView: View {
    
    // MARK: - 环境属性
    
    /// 数据库上下文
    @Environment(\.modelContext) private var modelContext
    
    /// 关闭弹窗的动作
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - 配置属性
    
    /*
     * 可选类型参数：区分创建和编辑模式
     *
     * StateTemplate?：
     * - nil：创建新模板
     * - 有值：编辑现有模板
     *
     * 这是一种常见的设计模式：
     * 用同一个视图处理创建和编辑，通过参数区分
     */
    let template: StateTemplate?
    
    // MARK: - 构造器
    
    /*
     * 带默认参数的构造器
     *
     * template: StateTemplate? = nil：默认为nil（创建模式）
     *
     * 调用方式：
     * - TemplateEditView()：创建新模板
     * - TemplateEditView(template: someTemplate)：编辑模板
     */
    init(template: StateTemplate? = nil) {
        self.template = template
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        /*
         * if let：可选绑定 + 条件渲染
         *
         * 如果template不是nil，解包并渲染编辑模式
         * 否则渲染创建模式
         *
         * 两种模式都复用StateInputView，只是配置不同
         */
        if let existingTemplate = template {
            // ===== 编辑模式 =====
            StateInputView(
                navigationTitle: "Edit Template",
                titlePlaceholder: "Template Title",
                confirmButtonTitle: "Save",
                // 提供初始值
                initialTitle: existingTemplate.title,
                /*
                 * 提取清单项标题
                 *
                 * existingTemplate.checklistItems：ChecklistItem数组
                 * .sorted(by:)：按order排序
                 * .map { $0.title }：提取每个项的title
                 *
                 * map 高阶函数：
                 * - 将数组中的每个元素转换为另一种形式
                 * - 返回转换后的新数组
                 *
                 * C/C++对比：
                 * std::vector<string> titles;
                 * std::transform(items.begin(), items.end(), back_inserter(titles),
                 *     [](const auto& item) { return item.title; });
                 *
                 * Swift的map更简洁：
                 * items.map { $0.title }
                 */
                initialChecklistItems: existingTemplate.checklistItems.sorted(by: { $0.order < $1.order }).map { $0.title }
            ) { title, checklistItems in
                // ===== 保存回调：更新现有模板 =====
                
                // 更新标题
                existingTemplate.title = title
                
                /*
                 * 删除旧的清单项
                 *
                 * 策略：先删除所有旧项，再创建新项
                 * 这比尝试"智能合并"更简单可靠
                 *
                 * for-in 循环：遍历数组
                 */
                for oldItem in existingTemplate.checklistItems {
                    // 从数据库删除
                    modelContext.delete(oldItem)
                }
                // 清空关系数组
                existingTemplate.checklistItems.removeAll()
                
                // 创建新的清单项
                for (index, itemTitle) in checklistItems.enumerated() {
                    let checklistItem = ChecklistItem(title: itemTitle, order: index)
                    // 插入数据库
                    modelContext.insert(checklistItem)
                    // 建立关系
                    existingTemplate.checklistItems.append(checklistItem)
                }
                
                // 注意：不需要手动保存
                // SwiftData会自动追踪变化并保存
            }
        } else {
            // ===== 创建模式 =====
            StateInputView(
                navigationTitle: "New Template",
                titlePlaceholder: "Template Title",
                confirmButtonTitle: "Save"
                // 不提供初始值，使用默认的空值
            ) { title, checklistItems in
                // ===== 保存回调：创建新模板 =====
                
                // 创建模板对象
                let template = StateTemplate(title: title)
                
                // 插入数据库
                modelContext.insert(template)
                
                // 创建清单项并建立关系
                for (index, itemTitle) in checklistItems.enumerated() {
                    let checklistItem = ChecklistItem(title: itemTitle, order: index)
                    modelContext.insert(checklistItem)
                    template.checklistItems.append(checklistItem)
                }
            }
        }
    }
}

// MARK: - 预览

#Preview {
    // 预览创建模式（无参数）
    TemplateEditView()
        .modelContainer(for: [StateTemplate.self, ChecklistItem.self], inMemory: true)
}

/*
 * 设计总结
 *
 * 这个文件展示了SwiftUI的几个重要设计原则：
 *
 * 1. 视图复用（View Reuse）
 *    - StateInputView 被多处复用：AddStateView、TemplateEditView
 *    - 通过参数配置不同的行为
 *    - 减少代码重复，保持UI一致性
 *
 * 2. 组合优于继承（Composition over Inheritance）
 *    - SwiftUI视图是struct，不能继承
 *    - 通过组合（包含其他视图）实现复用
 *    - 这是SwiftUI的设计哲学
 *
 * 3. 闭包回调（Callback Closure）
 *    - onSave闭包让调用者定义保存逻辑
 *    - 视图只负责UI，业务逻辑外部提供
 *    - 实现了UI和业务逻辑的分离
 *
 * 4. 可选类型区分模式
 *    - template参数为nil或有值区分创建/编辑
 *    - 避免了创建两个几乎相同的视图
 *    - 常见于CRUD应用
 *
 * C/C++开发者注意：
 * - Swift的视图是值类型（struct），不是引用类型
 * - 不要尝试在视图中存储大量状态
 * - 数据应该存储在@Model对象或外部状态管理中
 */
