/*
 * StateDetailView.swift
 * 状态详情页
 *
 * 这个视图展示单个状态的详细信息，允许用户：
 * - 查看和编辑状态标题
 * - 查看和管理清单子项
 * - 添加新的清单项
 *
 * 关键概念：
 * - 条件渲染：根据状态显示不同的UI
 * - 内联编辑：点击文本变成输入框
 * - Collection扩展：安全的数组下标访问
 */

import SwiftUI
import SwiftData

// MARK: - 状态详情视图

@MainActor
struct StateDetailView: View {
    
    // MARK: - 属性
    
    /// 数据库上下文，用于插入和删除数据
    @Environment(\.modelContext) private var modelContext
    
    /*
     * @Bindable：绑定SwiftData模型对象
     *
     * 与@State的区别：
     * - @State：视图自己拥有并管理的状态
     * - @Bindable：外部传入的@Model对象，视图观察其变化
     *
     * 当stateItem的属性改变时，视图自动刷新
     * 这是SwiftData的响应式数据绑定
     */
    @Bindable var stateItem: StateItem
    
    /// 是否正在编辑标题
    @State private var editingTitle = false
    
    /// 编辑中的新标题（临时存储，确认后才保存）
    @State private var newTitle: String = ""
    
    /// 标题输入框的焦点状态
    @FocusState private var isTitleFocused: Bool
    
    // MARK: - 视图主体
    
    var body: some View {
        List {
            /*
             * 标题区域
             *
             * 使用条件渲染显示：
             * - 编辑模式：显示TextField
             * - 查看模式：显示Text，点击进入编辑
             */
            Section {
                /*
                 * 条件渲染（Conditional Rendering）
                 *
                 * SwiftUI中if-else可以返回不同的视图
                 * 框架会根据条件显示对应的视图
                 *
                 * C/C++对比：
                 * 在Qt/MFC中需要手动隐藏/显示控件
                 * SwiftUI是声明式的，你只描述"应该显示什么"
                 */
                if editingTitle {
                    // 编辑模式：显示输入框
                    TextField("State Title", text: $newTitle)
                        .focused($isTitleFocused)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .onSubmit {
                            // 用户按回车，保存标题
                            saveTitle()
                        }
                        /*
                         * .task：视图出现时执行的异步任务
                         *
                         * 在这里用于：
                         * 1. 初始化newTitle为当前标题
                         * 2. 延迟设置焦点（等待视图渲染）
                         */
                        .task {
                            // 复制当前标题到编辑变量
                            newTitle = stateItem.title
                            // 等待0.1秒，确保TextField已渲染
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            // 设置焦点，弹出键盘
                            isTitleFocused = true
                        }
                } else {
                    // 查看模式：显示文本
                    HStack(spacing: 12) {
                        Text(stateItem.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    /*
                     * .contentShape：定义交互区域
                     *
                     * Rectangle()：整个矩形区域都可点击
                     * 没有这个修饰符，只有文字部分可点击
                     */
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    /*
                     * .onTapGesture：点击手势
                     *
                     * 点击时进入编辑模式
                     */
                    .onTapGesture {
                        editingTitle = true
                    }
                }
            } header: {
                /*
                 * Section header：分组标题
                 *
                 * 条件渲染：只有有清单项时才显示进度
                 */
                if !stateItem.checklistItems.isEmpty {
                    HStack(spacing: 8) {
                        Text("Checklist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // 进度显示：已完成/总数
                        HStack(spacing: 4) {
                            Text("\(stateItem.totalChecklistCount - stateItem.incompleteChecklistCount)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("/")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(stateItem.totalChecklistCount)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // 清单项列表
            if !stateItem.checklistItems.isEmpty {
                Section {
                    /*
                     * ForEach + sorted：排序后遍历
                     *
                     * stateItem.checklistItems.sorted(by:)：返回排序后的数组
                     * { $0.order < $1.order }：比较闭包，按order升序
                     *
                     * 注意：sorted返回新数组，不修改原数组
                     */
                    ForEach(stateItem.checklistItems.sorted(by: { $0.order < $1.order })) { item in
                        ChecklistItemRow(item: item, stateItem: stateItem)
                            /*
                             * .listRowInsets：列表行内边距
                             *
                             * EdgeInsets：四个方向的边距
                             * 自定义列表行的内边距
                             */
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onDelete(perform: deleteChecklistItems)
                }
            } else {
                // 空状态提示
                Section {
                    ContentUnavailableView {
                        Label("No Checklist Items", systemImage: "checklist")
                    } description: {
                        Text("Tap the + button to add checklist items")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 添加清单项按钮
                Button {
                    addChecklistItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 保存编辑后的标题
    private func saveTitle() {
        let trimmed = newTitle.trimmingCharacters(in: CharacterSet.whitespaces)
        if !trimmed.isEmpty {
            // 更新模型属性
            // SwiftData会自动保存更改
            stateItem.title = trimmed
        }
        // 退出编辑模式
        editingTitle = false
    }
    
    /// 添加新的清单项
    private func addChecklistItem() {
        // 创建新对象，order设为当前数量（添加到末尾）
        let newItem = ChecklistItem(title: "", order: stateItem.checklistItems.count)
        
        // 插入数据库
        modelContext.insert(newItem)
        
        // 建立关联关系
        stateItem.checklistItems.append(newItem)
        
        // 新项的title为空，会自动进入编辑模式（见ChecklistItemRow）
    }
    
    /// 删除清单项
    private func deleteChecklistItems(offsets: IndexSet) {
        // 获取排序后的数组（与ForEach中的顺序一致）
        let sortedItems = stateItem.checklistItems.sorted(by: { $0.order < $1.order })
        
        for index in offsets {
            /*
             * 安全下标访问
             *
             * sortedItems[safe: index]：使用下面定义的安全下标
             * 如果索引越界返回nil，而不是崩溃
             *
             * if let item = ...：可选绑定，nil时跳过
             */
            if let item = sortedItems[safe: index] {
                /*
                 * removeAll(where:)：移除所有满足条件的元素
                 *
                 * { $0.id == item.id }：匹配ID的闭包
                 * 通过ID匹配而不是对象引用，更可靠
                 */
                stateItem.checklistItems.removeAll { $0.id == item.id }
            }
        }
        
        // 重新编号所有剩余项
        for (index, item) in stateItem.checklistItems.enumerated() {
            item.order = index
        }
    }
}

// MARK: - 清单项行视图

/// 单个清单项的视图，支持编辑和完成状态切换
@MainActor
struct ChecklistItemRow: View {
    
    // MARK: - 属性
    
    /// 绑定的清单项对象
    @Bindable var item: ChecklistItem
    
    /// 父状态对象（用于更新完成状态）
    let stateItem: StateItem
    
    /// 数据库上下文（用于删除操作）
    @Environment(\.modelContext) private var modelContext
    
    /// 是否正在编辑标题
    @State private var editingTitle = false
    
    /// 编辑中的标题
    @State private var newTitle: String = ""
    
    /// 输入框焦点状态
    @FocusState private var isFocused: Bool
    
    // MARK: - 视图主体
    
    var body: some View {
        HStack(spacing: 14) {
            // 复选框按钮
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    // 切换完成状态
                    item.isCompleted.toggle()
                    // 更新父状态的整体完成状态
                    stateItem.updateCompletionStatus()
                }
            } label: {
                /*
                 * 条件图标
                 *
                 * 三元运算符选择不同的SF Symbol图标
                 * checkmark.square.fill：带勾的填充方框
                 * square：空方框
                 */
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                    /*
                     * .symbolEffect：SF Symbols动画
                     *
                     * .bounce：弹跳效果
                     * value：监听的值，变化时触发动画
                     *
                     * 这是iOS 17的新特性，让图标有生动的动画
                     */
                    .symbolEffect(.bounce, value: item.isCompleted)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            /*
             * 内联编辑模式
             *
             * 条件：正在编辑 或 标题为空（新建的项）
             * 新建的项自动进入编辑模式
             */
            if editingTitle || item.title.isEmpty {
                TextField("Checklist item", text: $newTitle)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .onSubmit {
                        saveTitle()
                    }
                    /*
                     * .onChange：监听值变化
                     *
                     * 用于检测用户清空输入后删除项
                     * iOS 17新语法：使用两参数闭包 { oldValue, newValue in ... }
                     */
                    .onChange(of: newTitle) { oldValue, newValue in
                        let trimmed = newValue.trimmingCharacters(in: CharacterSet.whitespaces)
                        // 如果新值为空（但不是初始空状态）
                        if trimmed.isEmpty && !oldValue.isEmpty {
                            // 延迟删除，给用户反悔的机会
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                                // 再次确认仍然是空的
                                if item.title.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                                    deleteItem()
                                }
                            }
                        }
                    }
                    .task {
                        // 初始化编辑内容
                        if item.title.isEmpty {
                            newTitle = ""
                        } else {
                            newTitle = item.title
                        }
                        editingTitle = true
                        // 延迟设置焦点
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        isFocused = true
                    }
            } else {
                // 查看模式：显示文本
                Text(item.title)
                    .font(.body)
                    /*
                     * .strikethrough：删除线效果
                     *
                     * 参数是布尔值，true时显示删除线
                     * 用于表示已完成的项目
                     */
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .onTapGesture {
                        // 点击进入编辑模式
                        editingTitle = true
                    }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        /*
         * 整行点击手势
         *
         * 如果不在编辑模式且有标题，点击切换完成状态
         */
        .onTapGesture {
            if !editingTitle && !item.title.isEmpty {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    item.isCompleted.toggle()
                    stateItem.updateCompletionStatus()
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 保存编辑后的标题
    private func saveTitle() {
        let trimmed = newTitle.trimmingCharacters(in: CharacterSet.whitespaces)
        if trimmed.isEmpty {
            // 空标题，删除此项
            deleteItem()
        } else {
            // 更新标题
            item.title = trimmed
            editingTitle = false
        }
    }
    
    /// 删除此清单项
    private func deleteItem() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            // 从父状态的数组中移除
            stateItem.checklistItems.removeAll { $0.id == item.id }
            
            // 从数据库删除
            modelContext.delete(item)
            
            // 重新编号剩余项
            for (index, remainingItem) in stateItem.checklistItems.enumerated() {
                remainingItem.order = index
            }
        }
    }
}

// MARK: - Collection 扩展

/*
 * extension：扩展现有类型
 *
 * Swift的扩展功能非常强大：
 * - 可以为任何类型添加新方法
 * - 包括系统类型和第三方类型
 * - 不需要访问源代码
 *
 * C/C++对比：
 * - C++没有直接等价物
 * - 最接近的是自由函数或继承
 * - Swift扩展更灵活，可以扩展协议、泛型等
 *
 * Collection：所有集合类型的协议（Array, Set, Dictionary等）
 * 这个扩展为所有集合类型添加安全下标访问
 */
extension Collection {
    /*
     * subscript：下标运算符重载
     *
     * collection[safe: index] 语法
     *
     * 参数标签 safe：调用时必须写 [safe: index]，增加代码可读性
     *
     * 返回类型 Element?：可选类型
     * - 索引有效时返回元素
     * - 索引无效时返回nil
     *
     * C/C++对比：
     * 类似于 std::map::at() vs operator[]
     * - at() 抛异常
     * - operator[] 可能产生未定义行为
     * Swift的方式更安全：返回Optional
     */
    subscript(safe index: Index) -> Element? {
        /*
         * 条件表达式
         *
         * indices：集合的有效索引范围
         * contains：检查索引是否在范围内
         *
         * 三元运算符返回：
         * - 有效索引：返回元素
         * - 无效索引：返回nil
         */
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 预览

#Preview {
    /*
     * NavigationStack包装
     *
     * StateDetailView通常通过导航进入
     * 预览时需要NavigationStack来显示导航栏
     */
    NavigationStack {
        StateDetailView(stateItem: StateItem(title: "Sample State"))
    }
    .modelContainer(for: [StateItem.self, ChecklistItem.self], inMemory: true)
}
