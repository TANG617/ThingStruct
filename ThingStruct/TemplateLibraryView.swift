/*
 * TemplateLibraryView.swift
 * 模板库视图
 *
 * 这个视图展示所有保存的状态模板，用户可以：
 * - 点击模板快速创建新状态
 * - 左滑编辑模板
 * - 右滑删除模板
 * - 添加新模板
 *
 * 关键概念：
 * - sheet(item:)：带数据的模态弹窗
 * - 自定义ButtonStyle：自定义按钮外观和动画
 * - 工厂方法模式：从模板创建状态
 */

import SwiftUI
import SwiftData

// MARK: - 模板库视图

@MainActor
struct TemplateLibraryView: View {
    
    // MARK: - 环境和查询属性
    
    /// 数据库上下文
    @Environment(\.modelContext) private var modelContext
    
    /// 关闭弹窗的动作
    @Environment(\.dismiss) private var dismiss
    
    /*
     * @Query：数据库查询
     *
     * sort: \StateTemplate.title 按标题字母顺序排序
     * 查询结果会自动响应数据库变化
     */
    @Query(sort: \StateTemplate.title) private var templates: [StateTemplate]
    
    /// 查询所有状态（用于确定新状态的排序位置）
    @Query(sort: \StateItem.order) private var allStates: [StateItem]
    
    /// 是否显示添加模板弹窗
    @State private var showingAddTemplate = false
    
    /*
     * 可选类型状态：用于编辑模板
     *
     * StateTemplate?：
     * - nil：不显示编辑弹窗
     * - 有值：显示编辑弹窗，编辑该模板
     *
     * 配合 sheet(item:) 使用
     */
    @State private var editingTemplate: StateTemplate?
    
    // MARK: - 计算属性
    
    /// 今天的日期
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    /// 今天的状态列表
    private var todayStates: [StateItem] {
        allStates.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(templates) { template in
                    /*
                     * TemplateRowView：自定义行视图
                     *
                     * onTap闭包：点击时从模板创建状态
                     */
                    TemplateRowView(template: template, onTap: {
                        createStateFromTemplate(template)
                    })
                    /*
                     * .swipeActions：滑动操作
                     *
                     * edge: .leading：从左边滑动
                     * 左滑显示编辑按钮
                     */
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            // 设置要编辑的模板，触发sheet显示
                            editingTemplate = template
                        } label: {
                            Label("Edit", systemImage: "pencil.circle.fill")
                        }
                        .tint(.accentColor)
                    }
                }
                // 右滑删除（系统默认行为）
                .onDelete(perform: deleteTemplates)
                
                // 空状态视图
                if templates.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Templates", systemImage: "list.bullet.rectangle.portrait")
                        } description: {
                            Text("Tap the + button to create a template")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Template Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 完成按钮（关闭弹窗）
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
                // 添加模板按钮
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTemplate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .fontWeight(.medium)
                    }
                }
            }
            /*
             * .sheet(isPresented:)：布尔值控制的模态弹窗
             *
             * showingAddTemplate为true时显示
             * 用于添加新模板
             */
            .sheet(isPresented: $showingAddTemplate) {
                TemplateEditView()  // 无参数表示新建模式
            }
            /*
             * .sheet(item:)：带数据的模态弹窗
             *
             * 与 sheet(isPresented:) 的区别：
             * - isPresented：只控制显示/隐藏
             * - item：绑定到可选值，有值时显示，并传递该值
             *
             * $editingTemplate：绑定到可选的StateTemplate
             * - 当设置 editingTemplate = someTemplate 时，弹窗显示
             * - 当弹窗关闭时，自动设置 editingTemplate = nil
             *
             * { template in ... }：闭包接收解包后的值
             * 用于构建弹窗内容
             */
            .sheet(item: $editingTemplate) { template in
                TemplateEditView(template: template)  // 传入模板表示编辑模式
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 从模板创建新状态
    private func createStateFromTemplate(_ template: StateTemplate) {
        /*
         * 调用模板的工厂方法
         *
         * _ = ：忽略返回值
         * 我们不需要使用创建的状态对象
         * 它已经被插入数据库并关联到模板
         *
         * 参数：
         * - date: 当前日期
         * - order: 排在今天所有状态之后
         * - modelContext: 数据库上下文
         */
        _ = template.createState(for: Date(), order: todayStates.count, modelContext: modelContext)
        
        // 关闭模板库弹窗，返回主界面
        dismiss()
    }
    
    /// 删除模板
    private func deleteTemplates(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                // 从数据库删除
                // @Relationship(deleteRule: .cascade) 会自动删除关联的清单项
                modelContext.delete(templates[index])
            }
        }
    }
}

// MARK: - 模板行视图

/// 单个模板的行视图
@MainActor
struct TemplateRowView: View {
    
    /// 要显示的模板
    let template: StateTemplate
    
    /// 点击时的回调
    let onTap: () -> Void
    
    var body: some View {
        /*
         * Button包装整行
         *
         * 让整行都可点击，而不只是文字部分
         */
        Button {
            onTap()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    // 模板标题
                    Text(template.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    // 清单项数量（如果有）
                    if !template.checklistItems.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(template.checklistItems.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        /*
         * .buttonStyle：应用自定义按钮样式
         *
         * TemplateRowButtonStyle：下面定义的自定义样式
         * 提供按下时的视觉反馈
         */
        .buttonStyle(TemplateRowButtonStyle())
    }
}

// MARK: - 自定义按钮样式

/*
 * ButtonStyle 协议：自定义按钮外观
 *
 * SwiftUI提供了几种内置样式：
 * - .plain：无样式
 * - .bordered：带边框
 * - .borderedProminent：带填充背景
 *
 * 自定义ButtonStyle可以完全控制按钮外观
 *
 * C/C++对比：
 * 在UIKit/Qt中需要子类化或设置多个属性
 * SwiftUI用协议和组合更灵活
 */
@MainActor
struct TemplateRowButtonStyle: ButtonStyle {
    /*
     * makeBody：ButtonStyle协议的必需方法
     *
     * configuration：包含按钮的配置信息
     * - configuration.label：按钮的内容（label闭包中定义的视图）
     * - configuration.isPressed：是否被按下
     *
     * 返回值：修改后的视图
     */
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            /*
             * 按下时的背景变化
             *
             * 三元运算符：
             * - 按下时：使用主题色，15%透明度
             * - 未按下：透明
             */
            .background(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
            /*
             * 按下时的缩放效果
             *
             * scaleEffect：缩放变换
             * - 按下时：缩小到98%
             * - 未按下：100%
             *
             * 这是一个微妙的视觉反馈
             */
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            /*
             * 动画修饰符
             *
             * .animation(_:value:)：当value变化时应用动画
             * 
             * .spring()：弹簧动画
             * - response: 0.2：动画持续时间
             * - dampingFraction: 0.7：阻尼系数
             *
             * 让按下/松开的过渡更平滑自然
             */
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 预览

#Preview {
    TemplateLibraryView()
        .modelContainer(for: [StateTemplate.self, ChecklistItem.self], inMemory: true)
}
