/*
 * StateInputView.swift
 * 通用的状态/模板输入表单视图
 *
 * 这是一个可复用的输入表单组件，用于：
 * - 添加新状态（AddStateView使用）
 * - 编辑模板（TemplateEditView使用）
 *
 * 关键概念：
 * - @FocusState：键盘焦点管理
 * - @escaping闭包：逃逸闭包
 * - Form：表单布局
 * - async/await：异步编程
 */

import SwiftUI
import SwiftData

// MARK: - 状态输入视图

@MainActor
struct StateInputView: View {
    
    // MARK: - 环境属性
    
    @Environment(\.modelContext) private var modelContext
    
    /*
     * dismiss：关闭当前视图的动作
     *
     * 类型是 DismissAction，是一个可调用的结构体
     * 调用方式：dismiss() 或 dismiss.callAsFunction()
     */
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - 配置属性（外部传入）
    
    /*
     * let 属性：不可变的存储属性
     *
     * 这些属性在视图创建时设置，之后不能修改
     * 用于配置视图的外观和行为
     */
    
    /// 导航栏标题
    let navigationTitle: String
    
    /// 标题输入框的占位符文字
    let titlePlaceholder: String
    
    /// 确认按钮的文字
    let confirmButtonTitle: String
    
    /*
     * 闭包类型属性
     *
     * (String, [String]) -> Void 表示：
     * - 接受两个参数：String 和 [String]
     * - 无返回值（Void）
     *
     * C/C++对比：
     * void (*onSave)(const std::string&, const std::vector<std::string>&)
     * 或 std::function<void(string, vector<string>)>
     */
    let onSave: (String, [String]) -> Void
    
    /*
     * 可选类型属性
     *
     * String? 表示可能有值也可能是nil
     * 用于编辑模式时提供初始值
     */
    let initialTitle: String?
    let initialChecklistItems: [String]?
    
    // MARK: - 构造器
    
    /*
     * 自定义构造器
     *
     * Swift的struct如果有自定义init，默认的成员初始化器会消失
     * 这里自定义init是为了：
     * 1. 提供默认参数
     * 2. 标记onSave为@escaping
     */
    init(
        navigationTitle: String,
        titlePlaceholder: String,
        confirmButtonTitle: String,
        initialTitle: String? = nil,           // 默认值为nil
        initialChecklistItems: [String]? = nil,
        /*
         * @escaping：逃逸闭包标记
         *
         * 默认情况下，传入函数的闭包是"非逃逸"的，意味着：
         * - 闭包只在函数执行期间使用
         * - 函数返回后闭包不再存在
         *
         * @escaping 表示闭包会"逃逸"出函数：
         * - 闭包被存储起来，稍后调用
         * - 这里onSave被存储为属性，在用户点击保存时调用
         *
         * C/C++对比：
         * - 非逃逸闭包类似于栈上的lambda，函数结束后失效
         * - 逃逸闭包类似于堆上的std::function，可以长期持有
         *
         * 为什么需要标记：
         * - 编译器需要知道闭包的生命周期
         * - 逃逸闭包可能导致循环引用，需要开发者注意
         */
        onSave: @escaping (String, [String]) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.titlePlaceholder = titlePlaceholder
        self.confirmButtonTitle = confirmButtonTitle
        self.initialTitle = initialTitle
        self.initialChecklistItems = initialChecklistItems
        self.onSave = onSave
    }
    
    // MARK: - 本地状态
    
    /// 标题文字（双向绑定到输入框）
    @State private var title: String = ""
    
    /// 清单项数组（每个元素是一个输入框的内容）
    @State private var checklistItems: [String] = []
    
    /*
     * @FocusState：焦点状态管理
     *
     * SwiftUI的焦点管理系统：
     * - 控制哪个输入框获得键盘焦点
     * - 可以程序化地设置焦点
     *
     * Bool类型的@FocusState：是否获得焦点
     * 设置为true时，对应的输入框获得焦点，键盘弹出
     */
    @FocusState private var isTitleFocused: Bool
    
    /*
     * 可选类型的@FocusState
     *
     * Int? 表示：
     * - nil：没有清单项获得焦点
     * - 有值：该索引的清单项获得焦点
     *
     * 这允许我们追踪多个输入框中哪个获得了焦点
     */
    @FocusState private var focusedChecklistIndex: Int?
    
    // MARK: - 视图主体
    
    var body: some View {
        NavigationStack {
            /*
             * Form：表单容器
             *
             * iOS的标准表单布局，自动处理：
             * - 分组样式
             * - 键盘避让
             * - 滚动行为
             *
             * 类似于设置应用的界面风格
             */
            Form {
                // 标题输入区域
                Section {
                    /*
                     * TextField：文本输入框
                     *
                     * 参数：
                     * 1. 占位符文字（输入框为空时显示）
                     * 2. text: 绑定到的状态变量
                     *
                     * $title：获取Binding
                     * Binding是双向绑定：
                     * - 输入框显示title的值
                     * - 用户输入时自动更新title
                     */
                    TextField(titlePlaceholder, text: $title)
                        /*
                         * .focused()：绑定焦点状态
                         *
                         * $isTitleFocused：双向绑定
                         * - 当设置isTitleFocused = true，这个输入框获得焦点
                         * - 当用户点击其他地方，isTitleFocused自动变为false
                         */
                        .focused($isTitleFocused)
                        /*
                         * .submitLabel：键盘回车键显示的文字
                         *
                         * .done：显示"完成"（蓝色）
                         * .next：显示"下一项"
                         * .go：显示"前往"
                         */
                        .submitLabel(.done)
                        .font(.body)
                        /*
                         * .onSubmit：用户按回车键时触发
                         *
                         * 如果没有清单项，直接保存
                         * 如果有清单项，回车键不执行操作（用户可以继续编辑清单）
                         */
                        .onSubmit {
                            if checklistItems.isEmpty {
                                save()
                            }
                        }
                } header: {
                    Text("Title")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // 清单项输入区域
                Section {
                    /*
                     * ForEach + indices：遍历数组索引
                     *
                     * checklistItems.indices：数组的索引范围（0..<count）
                     * id: \.self：使用索引本身作为标识符
                     *
                     * 为什么用索引而不是元素：
                     * - 我们需要索引来绑定到数组元素
                     * - $checklistItems[index] 需要索引
                     */
                    ForEach(checklistItems.indices, id: \.self) { index in
                        /*
                         * $checklistItems[index]：绑定到数组的特定元素
                         *
                         * 这是Swift的下标绑定语法
                         * 允许修改数组中的特定元素
                         */
                        TextField("Checklist item", text: $checklistItems[index])
                            /*
                             * .focused($focusedChecklistIndex, equals: index)
                             *
                             * 条件焦点绑定：
                             * - 当focusedChecklistIndex == index时，此输入框获得焦点
                             * - 当此输入框获得焦点时，focusedChecklistIndex设为index
                             *
                             * 这样我们可以用一个变量管理多个输入框的焦点
                             */
                            .focused($focusedChecklistIndex, equals: index)
                            .submitLabel(.next)
                            /*
                             * .onChange：监听值变化
                             *
                             * 当checklistItems[index]改变时触发
                             * 用于检测用户是否清空了输入框
                             */
                            .onChange(of: checklistItems[index]) { newValue in
                                let oldValue = checklistItems[index]
                                /*
                                 * trimmingCharacters(in:)：去除首尾指定字符
                                 *
                                 * CharacterSet.whitespaces：空白字符集（空格、制表符）
                                 * 用于检查去除空白后是否为空字符串
                                 *
                                 * C/C++对比：类似于自己写的trim函数
                                 */
                                if newValue.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty && !oldValue.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                                    /*
                                     * Task + async/await：异步执行
                                     *
                                     * Task：Swift并发框架的Task类型
                                     *
                                     * @MainActor in：确保在主线程执行
                                     *
                                     * 为什么要延迟删除：
                                     * - 给用户一点时间撤销操作
                                     * - 避免在onChange中直接修改数组导致的问题
                                     */
                                    Task { @MainActor in
                                        /*
                                         * try? await：异步等待 + 忽略错误
                                         *
                                         * sleep(nanoseconds:)：暂停指定纳秒
                                         * 100_000_000纳秒 = 0.1秒
                                         *
                                         * _ 数字分隔符：提高可读性
                                         * 100_000_000 等于 100000000
                                         *
                                         * C/C++对比：类似于 std::this_thread::sleep_for
                                         */
                                        try? await Task.sleep(nanoseconds: 100_000_000)
                                        // 再次检查条件，因为用户可能已经输入了新内容
                                        if checklistItems.indices.contains(index) && checklistItems[index].trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
                                            deleteChecklistItem(at: index)
                                        }
                                    }
                                }
                            }
                            .onSubmit {
                                let trimmed = checklistItems[index].trimmingCharacters(in: CharacterSet.whitespaces)
                                if trimmed.isEmpty {
                                    // 空内容，删除此项
                                    deleteChecklistItem(at: index)
                                } else if index == checklistItems.count - 1 {
                                    // 最后一项，添加新项
                                    addChecklistItem()
                                } else {
                                    // 中间项，焦点移到下一项
                                    focusedChecklistIndex = index + 1
                                }
                            }
                    }
                    .onDelete(perform: deleteChecklistItems)
                    
                    // 添加新清单项按钮
                    Button {
                        addChecklistItem()
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text("Checklist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } footer: {
                    /*
                     * Section footer：分组底部说明文字
                     *
                     * 只有当清单为空时显示提示
                     */
                    if checklistItems.isEmpty {
                        Text("Add checklist items to create a structured state")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            /*
             * .formStyle(.grouped)：分组表单样式
             *
             * iOS标准的设置界面风格
             * 各个Section有明显的分组效果
             */
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            /*
             * .navigationBarTitleDisplayMode(.inline)：标题显示模式
             *
             * .inline：小标题，显示在导航栏中间
             * .large：大标题，显示在导航栏下方（可折叠）
             * .automatic：自动选择
             */
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                /*
                 * ToolbarItem placement 选项：
                 *
                 * .cancellationAction：取消操作（通常左侧）
                 * .confirmationAction：确认操作（通常右侧）
                 * .topBarLeading：导航栏左侧
                 * .topBarTrailing：导航栏右侧
                 */
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // 调用dismiss闭包关闭弹窗
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            /*
             * .task：视图出现时执行异步任务
             *
             * 类似于onAppear，但支持async/await
             * 视图消失时会自动取消任务
             *
             * 用途：
             * - 初始化数据
             * - 延迟设置焦点（等待视图渲染完成）
             */
            .task {
                // 如果有初始值，设置它们
                if let initialTitle = initialTitle {
                    title = initialTitle
                }
                if let initialItems = initialChecklistItems {
                    checklistItems = initialItems
                }
                
                // 等待0.1秒，确保视图已渲染
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                // 自动聚焦到标题输入框
                isTitleFocused = true
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 添加新的清单项
    private func addChecklistItem() {
        // 添加空字符串到数组
        checklistItems.append("")
        // 将焦点设置到新添加的项
        focusedChecklistIndex = checklistItems.count - 1
    }
    
    /// 删除指定索引的清单项
    private func deleteChecklistItem(at index: Int) {
        // 安全检查：确保索引有效
        guard index < checklistItems.count else { return }
        
        // 从数组中移除
        checklistItems.remove(at: index)
        
        // 更新焦点位置
        if focusedChecklistIndex == index {
            // 被删除的项有焦点，移动到相邻项
            if index < checklistItems.count {
                // 还有后续项，保持在当前位置（现在是原来的下一项）
                focusedChecklistIndex = index
            } else if index > 0 {
                // 没有后续项但有前面的项，移到上一项
                focusedChecklistIndex = index - 1
            } else {
                // 数组已空，清除焦点
                focusedChecklistIndex = nil
            }
        } else if let currentFocus = focusedChecklistIndex, currentFocus > index {
            // 焦点在被删除项之后，索引需要减1
            focusedChecklistIndex = currentFocus - 1
        }
    }
    
    /// 批量删除清单项（滑动删除）
    private func deleteChecklistItems(offsets: IndexSet) {
        /*
         * 从后往前删除，避免索引混乱
         *
         * sorted(by: >)：降序排列
         * 这样先删除大索引的项，不影响小索引
         *
         * C/C++对比：同样的问题，删除时需要从后往前
         */
        let sortedIndices = offsets.sorted(by: >)
        
        /*
         * for-where 语法：带条件的循环
         *
         * for x in collection where condition { }
         * 等价于：
         * for x in collection {
         *     if condition { ... }
         * }
         */
        for index in sortedIndices where index < checklistItems.count {
            checklistItems.remove(at: index)
        }
    }
    
    /// 保存数据
    private func save() {
        // 去除标题首尾空白
        let trimmedTitle = title.trimmingCharacters(in: CharacterSet.whitespaces)
        
        // 如果标题为空，直接关闭不保存
        guard !trimmedTitle.isEmpty else {
            dismiss()
            return
        }
        
        /*
         * compactMap：转换 + 过滤nil
         *
         * 类似于map + filter的组合：
         * 1. 对每个元素执行闭包
         * 2. 闭包返回Optional
         * 3. 自动过滤掉nil结果
         *
         * 这里用于过滤掉空的清单项
         *
         * C/C++对比：
         * 需要先transform再copy_if，或者手写循环
         */
        let validItems = checklistItems.compactMap { item in
            let trimmed = item.trimmingCharacters(in: CharacterSet.whitespaces)
            // 返回nil表示过滤掉这个元素
            return trimmed.isEmpty ? nil : trimmed
        }
        
        // 调用保存回调
        onSave(trimmedTitle, validItems)
        
        // 关闭弹窗
        dismiss()
    }
}
