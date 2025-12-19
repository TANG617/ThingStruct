/*
 * ContentView.swift
 * 应用主界面
 *
 * 这是应用启动后显示的主界面，展示了SwiftUI的核心概念：
 * - 声明式UI构建
 * - 状态管理（@State, @Environment, @Query）
 * - 列表和导航
 * - 动画和手势
 *
 * 对于C/C++开发者：
 * SwiftUI与Qt/MFC等命令式框架有本质区别
 * 你不需要手动更新UI，只需要修改数据，UI会自动刷新
 */

import SwiftUI
import SwiftData

// MARK: - 显示配置（可调试）

/// 控制 ContentView 显示多少条目
/// 调试时可以设置 maxPendingCount = nil 来显示全部 pending
private enum DisplayConfig {
    /// 最多显示多少个 pending states，nil = 显示全部
    static let maxPendingCount: Int? = nil  // 调试模式：显示全部
    
    /// 最多显示多少个已完成的 states
    static let maxCompletedCount: Int = 3
}

// MARK: - 主内容视图

/*
 * @MainActor：确保此类型的所有代码在主线程执行
 *
 * 为什么需要：
 * - UI操作必须在主线程
 * - SwiftData操作可能触发UI更新
 * - @MainActor编译时保证线程安全
 */
@MainActor
struct ContentView: View {
    /*
     * View 协议：所有SwiftUI视图必须遵循的协议
     *
     * C/C++对比：
     * - C++/Qt: 继承 QWidget 或 QObject
     * - SwiftUI: 遵循 View 协议
     *
     * View协议只要求一个属性：var body: some View
     * 即描述"这个视图长什么样"
     */
    
    // MARK: - 属性包装器（Property Wrappers）
    
    /*
     * 属性包装器是Swift的重要特性，用 @ 符号标记
     * 它们为属性添加额外的行为，类似于装饰器模式
     *
     * C/C++对比：
     * - C++没有直接等价物
     * - 最接近的是包装类或CRTP模式
     * - 属性包装器更简洁，编译器自动处理
     */
    
    /*
     * @Environment：从SwiftUI环境中读取值
     *
     * SwiftUI的"环境"是一个依赖注入系统：
     * - 父视图可以向环境注入值
     * - 子视图可以从环境读取值
     * - 不需要显式传递参数
     *
     * \.modelContext：键路径，指向环境中的数据库上下文
     * 这个值是在 ThingStructApp.swift 中通过 .modelContainer() 注入的
     *
     * C/C++对比：
     * - 类似于依赖注入容器
     * - 避免了全局变量或单例的问题
     * - 比手动传递参数更方便
     *
     * private：访问控制，只在当前文件内可见
     */
    @Environment(\.modelContext) private var modelContext
    
    /*
     * @Query：SwiftData的数据查询属性包装器
     *
     * SwiftData: 自动从数据库查询数据，并监听变化
     * - 当数据库数据改变时，自动刷新UI
     * - sort: 指定排序方式
     *
     * \StateItem.order：键路径语法，表示按StateItem的order属性排序
     * C/C++对比：类似于 SQL 的 ORDER BY order
     *
     * 等价SQL: SELECT * FROM StateItem ORDER BY order
     *
     * 类型 [StateItem]：StateItem对象的数组
     * [] 是 Array<StateItem> 的语法糖
     */
    @Query(sort: \StateItem.order) private var allStates: [StateItem]
    
    /// 查询所有 RoutineTemplate（用于自动生成和手动应用）
    @Query private var routineTemplates: [RoutineTemplate]
    
    /// 状态流管理器
    @State private var streamManager = StateStreamManager()
    
    /*
     * @State：本地状态管理
     *
     * SwiftUI的核心概念：状态驱动UI
     * - @State 创建视图拥有的可变状态
     * - 当状态改变时，SwiftUI自动重新渲染视图
     *
     * C/C++对比：
     * - 类似于有观察者的成员变量
     * - 但不需要手动实现观察者模式
     * - 框架自动处理UI更新
     *
     * showingAddState = false：
     * - 控制"添加状态"弹窗是否显示
     * - false表示初始时隐藏
     * - 当设置为true时，弹窗自动显示
     */
    @State private var showingStateTemplateLibrary = false
    @State private var showingRoutineTemplateLibrary = false
    
    /*
     * StateItem?：可选类型（Optional）
     *
     * C/C++对比：
     * - 类似于可能为null的指针
     * - 但更安全：编译器强制处理nil情况
     * - ? 是 Optional<StateItem> 的语法糖
     *
     * nil：表示"没有值"，类似于 C++ 的 nullptr
     * 
     * 用途：selectedState 记录当前选中的状态
     * - nil表示没有选中任何状态
     * - 有值时可以导航到详情页
     */
    @State private var selectedState: StateItem?
    
    // MARK: - 计算属性
    
    /*
     * 计算属性：每次访问时动态计算
     * 不存储值，只提供计算逻辑
     */
    
    /// 今天的日期（零点时刻）
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    /// 今天的所有状态
    /// 从数据库查询结果中过滤出今天的数据
    private var todayStates: [StateItem] {
        /*
         * filter 高阶函数：过滤数组
         *
         * { ... } 是闭包（匿名函数）
         * $0 是闭包的第一个参数（数组元素）
         *
         * Calendar.current.isDate(_:inSameDayAs:)：
         * 比较两个日期是否在同一天（忽略时分秒）
         *
         * C/C++对比：
         * std::copy_if(allStates.begin(), allStates.end(), back_inserter(result),
         *     [this](const auto& s) { return isSameDay(s.date, today); });
         */
        allStates.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    /// 当前正在进行的状态（第一个未完成的）
    private var currentState: StateItem? {
        /*
         * first(where:)：找到第一个满足条件的元素
         * 返回 Optional，找不到时返回 nil
         *
         * C/C++对比：类似于 std::find_if
         */
        todayStates.first { !$0.isCompleted }
    }
    
    /// 待处理的状态（排除当前状态）
    private var pendingStates: [StateItem] {
        /*
         * guard let：可选绑定 + 提前返回
         *
         * 语法：guard let 变量名 = 可选值 else { return }
         * 作用：如果可选值是nil，执行else块；否则解包并继续
         *
         * C/C++对比：
         * auto* current = currentState;
         * if (current == nullptr) {
         *     return todayStates.filter(...);
         * }
         * // 使用 current
         */
        guard let current = currentState else {
            return todayStates.filter { !$0.isCompleted }
        }
        // 排除当前状态，返回其他未完成的状态
        return todayStates.filter { !$0.isCompleted && $0.id != current.id }
    }
    
    /// 已完成的状态
    private var completedStates: [StateItem] {
        todayStates.filter { $0.isCompleted }
    }
    
    // MARK: - 显示窗口（可配置数量）
    
    /// 可见的 pending states（根据配置限制数量）
    private var visiblePendingStates: [StateItem] {
        if let max = DisplayConfig.maxPendingCount {
            return Array(pendingStates.prefix(max))
        }
        return pendingStates  // 显示全部
    }
    
    /// 可见的 completed states（根据配置限制数量）
    private var visibleCompletedStates: [StateItem] {
        // 显示最近完成的 N 个
        Array(completedStates.suffix(DisplayConfig.maxCompletedCount))
    }
    
    /// 今天的标题（如 "Dec 18, Thu"）
    private var todayTitle: String {
        /*
         * DateFormatter：日期格式化工具
         * C/C++对比：类似于 strftime，但更面向对象
         */
        let formatter = DateFormatter()
        formatter.locale = Locale.current  // 使用用户的地区设置
        formatter.dateFormat = "MMM d"     // 格式：月份缩写 + 日期
        let dateString = formatter.string(from: Date())
        
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.current
        weekdayFormatter.dateFormat = "EEE"  // 星期缩写
        let weekday = weekdayFormatter.string(from: Date())
        
        // 字符串插值：\(变量) 将变量值嵌入字符串
        return "\(dateString), \(weekday)"
    }
    
    // MARK: - 视图主体
    
    /*
     * body 属性：描述视图的UI结构
     *
     * some View：不透明返回类型
     * - 表示返回某个遵循View协议的类型
     * - 编译器知道具体类型，调用者不需要知道
     *
     * SwiftUI的声明式语法：
     * - 你描述"UI应该是什么样"
     * - 框架负责渲染和更新
     * - 数据改变时，框架自动比较差异并更新
     */
    var body: some View {
        /*
         * NavigationStack：导航容器
         *
         * iOS导航模式：堆栈式导航
         * - 类似于网页的浏览历史
         * - push进入新页面，pop返回上一页
         *
         * C/C++对比：类似于 UINavigationController (UIKit)
         */
        NavigationStack {
            /*
             * List：列表视图
             *
             * SwiftUI的List非常强大：
             * - 自动处理滚动
             * - 自动复用cell（性能优化）
             * - 支持分组、滑动操作等
             *
             * C/C++对比：类似于 QListView，但更简洁
             */
            List {
                /*
                 * if let：可选绑定
                 *
                 * 在SwiftUI中，if语句可以用于条件渲染
                 * if let current = currentState：
                 * - 如果currentState不是nil，解包赋值给current，渲染内容
                 * - 如果是nil，跳过整个块
                 *
                 * C/C++对比：if (auto* current = currentState) { ... }
                 */
                if let current = currentState {
                    /*
                     * Section：列表分组
                     *
                     * header：分组标题
                     * 使用尾随闭包语法：
                     * Section { 内容 } header: { 标题 }
                     */
                    Section {
                        /*
                         * ForEach：循环渲染视图
                         *
                         * 与普通for循环不同：
                         * - ForEach是一个视图构建器
                         * - 为每个元素创建一个视图
                         *
                         * [current]：创建只包含一个元素的数组
                         * 这样可以使用ForEach的删除功能
                         *
                         * { stateItem in ... }：闭包参数
                         * stateItem是当前迭代的元素
                         */
                        ForEach([current]) { stateItem in
                            /*
                             * CurrentStateCardView：自定义视图组件
                             *
                             * 参数传递：
                             * - stateItem: 要显示的状态数据
                             * - onTap: 点击时的回调闭包
                             *
                             * { selectedState = stateItem }：尾随闭包
                             * 当用户点击时，设置选中的状态
                             */
                            CurrentStateCardView(stateItem: stateItem, onTap: {
                                selectedState = stateItem
                            })
                        }
                        /*
                         * .onDelete：添加滑动删除功能
                         *
                         * IndexSet：被删除项的索引集合
                         * _ 表示忽略参数（因为我们知道只有一个元素）
                         *
                         * SwiftUI自动处理滑动手势和删除按钮
                         */
                        .onDelete { _ in
                            if let stateItem = currentState {
                                /*
                                 * withAnimation：包装动画
                                 *
                                 * 将状态变化包装在动画中
                                 * SwiftUI自动为UI变化添加动画效果
                                 *
                                 * .spring()：弹簧动画
                                 * - response: 动画持续时间（秒）
                                 * - dampingFraction: 阻尼系数（0-1）
                                 *   0=无阻尼持续震荡，1=无弹性
                                 */
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    // 从数据库删除
                                    modelContext.delete(stateItem)
                                }
                            }
                        }
                    } header: {
                        /*
                         * Text：文本视图
                         *
                         * SwiftUI的基础视图之一
                         * 类似于 UILabel (UIKit) 或 QLabel (Qt)
                         */
                        Text("Current")
                            /*
                             * 修饰符（Modifiers）
                             *
                             * SwiftUI使用链式调用来配置视图
                             * 每个修饰符返回一个新的视图
                             *
                             * .font()：设置字体
                             * .foregroundStyle()：设置前景色
                             * .secondary：系统定义的次要颜色
                             */
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 待处理状态列表
                if !visiblePendingStates.isEmpty {
                    Section {
                        ForEach(visiblePendingStates) { stateItem in
                            CompactStateRowView(stateItem: stateItem, onTap: {
                                selectedState = stateItem
                            })
                            /*
                             * .swipeActions：自定义滑动操作
                             *
                             * edge: .leading 表示从左边滑动
                             * allowsFullSwipe: true 允许完全滑动触发
                             *
                             * C/C++对比：
                             * 在UIKit需要实现委托方法
                             * SwiftUI用声明式语法，更简洁
                             */
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                /*
                                 * Button：按钮视图
                                 *
                                 * 两个参数（都是闭包）：
                                 * 1. action: 点击时执行的代码
                                 * 2. label: 按钮的外观
                                 */
                                Button {
                                    selectedState = stateItem
                                } label: {
                                    /*
                                     * Label：带图标的标签
                                     *
                                     * systemImage：SF Symbols图标名
                                     * SF Symbols是Apple的图标库，包含数千个图标
                                     */
                                    Label("Details", systemImage: "info.circle.fill")
                                }
                                .tint(.accentColor)  // 设置按钮颜色
                            }
                        }
                        /*
                         * .onMove：添加拖拽排序功能
                         *
                         * perform: 拖拽完成后调用的函数
                         * SwiftUI自动处理拖拽UI
                         */
                        .onMove(perform: movePendingStates)
                        .onDelete(perform: deletePendingStates)
                    } header: {
                        HStack {
                            Text("Pending")
                            if pendingStates.count > visiblePendingStates.count {
                                Text("(\(pendingStates.count) total)")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                
                // 已完成状态列表
                if !visibleCompletedStates.isEmpty {
                    Section {
                        ForEach(visibleCompletedStates) { stateItem in
                            CompactStateRowView(stateItem: stateItem, onTap: {
                                selectedState = stateItem
                            })
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    selectedState = stateItem
                                } label: {
                                    Label("Details", systemImage: "info.circle.fill")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .onDelete(perform: deleteVisibleCompletedStates)
                    } header: {
                        HStack {
                            Text("Completed")
                            if completedStates.count > visibleCompletedStates.count {
                                Text("(\(completedStates.count) total)")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                
                // 空状态视图
                if todayStates.isEmpty {
                    Section {
                        /*
                         * ContentUnavailableView：空状态视图
                         *
                         * iOS 17新增的系统组件
                         * 用于显示"没有内容"的友好提示
                         */
                        ContentUnavailableView {
                            Label("No States Today", systemImage: "checklist")
                        } description: {
                            Text("Tap the + button to add a new state")
                        }
                    }
                }
            }
            /*
             * 列表样式修饰符
             *
             * .listStyle(.insetGrouped)：
             * 分组缩进样式，iOS设置应用的风格
             *
             * 其他样式：.plain, .grouped, .sidebar等
             */
            .listStyle(.insetGrouped)
            // 设置导航栏标题
            .navigationTitle(todayTitle)
            /*
             * .navigationDestination：声明导航目的地
             *
             * item: $selectedState：绑定到可选状态
             * - 当selectedState从nil变为有值，自动导航
             * - 当返回时，自动设回nil
             *
             * $：获取Binding（双向绑定）
             * Binding允许子视图修改父视图的@State
             *
             * { stateItem in ... }：目的地视图构建器
             * stateItem是解包后的selectedState值
             */
            .navigationDestination(item: $selectedState) { stateItem in
                StateDetailView(stateItem: stateItem)
            }
            /*
             * .toolbar：配置工具栏
             *
             * 工具栏可以在导航栏显示按钮
             */
            .toolbar {
                /*
                 * ToolbarItem：工具栏项
                 *
                 * placement：位置
                 * - .topBarTrailing：导航栏右侧
                 * - .topBarLeading：导航栏左侧
                 * - .bottomBar：底部工具栏
                 */
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingStateTemplateLibrary = true
                        } label: {
                            Label("State Templates", systemImage: "doc.on.doc")
                        }
                        
                        Button {
                            showingRoutineTemplateLibrary = true
                        } label: {
                            Label("Routine Templates", systemImage: "calendar.day.timeline.left")
                        }
                    } label: {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .fontWeight(.medium)
                    }
                    .tint(.accentColor)
                }
            }
            /*
             * .sheet：模态弹窗
             *
             * isPresented: 绑定到布尔状态
             * - 当状态为true时显示弹窗
             * - 关闭弹窗时自动设为false
             *
             * 这是SwiftUI的声明式方式：
             * 你不需要调用 present() 方法
             * 只需要改变状态，UI自动响应
             */
            .sheet(isPresented: $showingStateTemplateLibrary) {
                StateTemplateLibraryView()
            }
            .sheet(isPresented: $showingRoutineTemplateLibrary) {
                RoutineTemplateLibraryView()
            }
            /*
             * .overlay：覆盖层
             *
             * 在视图上方叠加另一个视图
             * 这里用于显示浮动操作按钮(FAB)
             *
             * alignment: .bottomTrailing：定位到右下角
             */
            .overlay(alignment: .bottomTrailing) {
                FloatingActionButton()
            }
            .onAppear {
                // 初始化/刷新状态流
                streamManager.refreshIfNeeded(
                    routineTemplates: routineTemplates,
                    existingStates: allStates,
                    modelContext: modelContext
                )
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /*
     * 处理拖拽排序
     *
     * IndexSet：被移动项的索引集合
     * destination：目标位置
     *
     * C/C++对比：类似于处理 QAbstractItemModel 的 moveRows
     */
    private func movePendingStates(from source: IndexSet, to destination: Int) {
        // 复制数组（值类型，自动复制）
        var states = visiblePendingStates
        
        // Array.move：移动元素位置
        states.move(fromOffsets: source, toOffset: destination)
        
        /*
         * ?? 空合运算符（Nil-Coalescing）
         *
         * currentState?.order ?? -1：
         * - 如果currentState不是nil，使用其order值
         * - 如果是nil，使用默认值-1
         *
         * C/C++对比：currentState ? currentState->order : -1
         */
        let currentOrder = currentState?.order ?? -1
        
        // 更新所有状态的排序值
        for (index, stateItem) in states.enumerated() {
            stateItem.order = currentOrder + 1 + index
        }
    }
    
    /// 删除待处理状态
    private func deletePendingStates(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                modelContext.delete(visiblePendingStates[index])
            }
        }
    }
    
    /// 删除可见的已完成状态
    private func deleteVisibleCompletedStates(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                modelContext.delete(visibleCompletedStates[index])
            }
        }
    }
}

// MARK: - 当前状态卡片视图

/*
 * 自定义视图组件
 *
 * SwiftUI鼓励将UI拆分为小的可复用组件
 * 类似于React组件或Vue组件的概念
 */
@MainActor
struct CurrentStateCardView: View {
    /*
     * @Bindable：SwiftData对象的绑定
     *
     * SwiftData: 允许视图监听@Model对象的变化
     * 当对象属性改变时，视图自动刷新
     *
     * 区别：
     * - @State：视图自己拥有的状态
     * - @Bindable：外部传入的可观察对象
     */
    @Bindable var stateItem: StateItem
    
    /*
     * 闭包类型属性
     *
     * () -> Void：无参数、无返回值的函数类型
     *
     * C/C++对比：
     * - C: void (*onTap)(void)
     * - C++: std::function<void()> onTap
     *
     * 用途：让父视图定义点击行为，实现组件解耦
     */
    let onTap: () -> Void
    
    var body: some View {
        /*
         * VStack：垂直堆叠布局
         *
         * SwiftUI的布局容器：
         * - VStack：垂直排列（类似CSS flex-direction: column）
         * - HStack：水平排列（类似CSS flex-direction: row）
         * - ZStack：层叠排列（类似CSS position: absolute）
         *
         * alignment: .leading：子视图左对齐
         * spacing: 16：子视图间距16点
         */
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stateItem.title)
                        /*
                         * 字体修饰符
                         *
                         * .font(.title3)：使用系统标题3字体
                         * 系统字体会自动适应用户的辅助功能设置
                         *
                         * .fontWeight(.semibold)：半粗体
                         * .foregroundStyle(.primary)：主要前景色（自动适应深色模式）
                         */
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    // 条件渲染：只有有子项时才显示进度
                    if stateItem.totalChecklistCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            /*
                             * 字符串插值中的计算
                             *
                             * \(表达式)：在字符串中嵌入任何Swift表达式
                             */
                            Text("\(stateItem.totalChecklistCount - stateItem.incompleteChecklistCount)/\(stateItem.totalChecklistCount) completed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                /*
                 * Spacer：弹性空间
                 *
                 * 在HStack/VStack中占据所有可用空间
                 * 类似于CSS的flex-grow: 1
                 *
                 * 这里用于将左侧内容推到左边
                 */
                Spacer()
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    onTap()
                } label: {
                    Label("Details", systemImage: "info.circle.fill")
                }
                .tint(.accentColor)
            }
            
            // 显示清单子项列表
            if !stateItem.checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    /*
                     * sorted(by:)：排序
                     *
                     * { $0.order < $1.order }：比较闭包
                     * $0是第一个元素，$1是第二个元素
                     *
                     * C/C++对比：
                     * std::sort(items.begin(), items.end(),
                     *     [](const auto& a, const auto& b) { return a.order < b.order; });
                     */
                    ForEach(stateItem.checklistItems.sorted(by: { $0.order < $1.order })) { item in
                        ChecklistItemCompactRow(item: item, stateItem: stateItem)
                    }
                }
                .padding(.top, 4)
            }
        }
        /*
         * .padding：内边距
         *
         * .padding(.vertical, 12)：只设置垂直方向的内边距
         * 等同于CSS的 padding-top: 12px; padding-bottom: 12px;
         */
        .padding(.vertical, 12)
    }
}

// MARK: - 清单项紧凑行视图

/// 清单子项的单行显示，带有复选框
@MainActor
struct ChecklistItemCompactRow: View {
    @Bindable var item: ChecklistItem
    let stateItem: StateItem
    
    var body: some View {
        HStack(spacing: 14) {
            /*
             * Button 的两种语法：
             *
             * 1. Button(action: { }, label: { })
             * 2. Button { action } label: { view }（尾随闭包语法）
             *
             * 当最后一个参数是闭包时，可以放在括号外面
             * 当有多个尾随闭包时，用标签区分
             */
            Button {
                // action：点击时执行
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    /*
                     * toggle()：布尔值取反
                     *
                     * 等价于 item.isCompleted = !item.isCompleted
                     * Swift的语法糖，更简洁
                     */
                    item.isCompleted.toggle()
                    // 更新父状态的完成状态
                    stateItem.updateCompletionStatus()
                }
            } label: {
                // label：按钮的外观
                /*
                 * 三元运算符：条件 ? 真值 : 假值
                 *
                 * 根据完成状态显示不同图标
                 */
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                    .font(.title3)
                    /*
                     * .symbolEffect：SF Symbols动画效果
                     *
                     * .bounce：弹跳效果
                     * value：当此值变化时触发动画
                     *
                     * 这是iOS 17的新特性
                     */
                    .symbolEffect(.bounce, value: item.isCompleted)
                    /*
                     * .frame：设置尺寸
                     *
                     * minWidth/minHeight：最小尺寸
                     * 确保点击区域足够大（44pt是Apple推荐的最小触摸目标）
                     */
                    .frame(minWidth: 32, minHeight: 32)
                    /*
                     * .contentShape：定义点击区域形状
                     *
                     * Rectangle()：矩形区域
                     * 没有这个，只有图标本身可点击
                     */
                    .contentShape(Rectangle())
            }
            /*
             * .buttonStyle(.plain)：移除按钮默认样式
             *
             * 默认按钮会有高亮效果
             * .plain 让按钮看起来像普通视图
             */
            .buttonStyle(.plain)
            
            Text(item.title)
                .font(.body)
                /*
                 * .strikethrough：删除线
                 *
                 * 参数是布尔值，true时显示删除线
                 * 已完成的项目显示删除线效果
                 */
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                /*
                 * .frame：设置布局约束
                 *
                 * maxWidth: .infinity：占据所有可用宽度
                 * alignment: .leading：内容左对齐
                 */
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        /*
         * .onTapGesture：添加点击手势
         *
         * 整行都可以点击来切换完成状态
         *
         * C/C++对比：
         * UIKit需要实现 UIGestureRecognizer
         * SwiftUI只需要一个修饰符
         */
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                item.isCompleted.toggle()
                stateItem.updateCompletionStatus()
            }
        }
    }
}

// MARK: - 紧凑状态行视图

/// 状态的紧凑单行显示（用于待处理和已完成列表）
@MainActor
struct CompactStateRowView: View {
    @Bindable var stateItem: StateItem
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(stateItem.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                if stateItem.totalChecklistCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(stateItem.totalChecklistCount - stateItem.incompleteChecklistCount)/\(stateItem.totalChecklistCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
    }
}

// MARK: - 预览

/*
 * #Preview 宏：Xcode预览
 *
 * 允许在不运行应用的情况下预览UI
 * 在Xcode右侧的Canvas面板中实时显示
 *
 * 这是开发SwiftUI应用的重要工具：
 * - 即时看到UI效果
 * - 无需编译运行整个应用
 * - 支持多种配置（深色模式、不同设备等）
 */
#Preview {
    ContentView()
        /*
         * .modelContainer(for:inMemory:)：为预览配置内存数据库
         *
         * inMemory: true 表示数据只在内存中
         * 预览结束后数据消失，不影响真实数据
         */
        .modelContainer(for: [StateItem.self, ChecklistItem.self, StateTemplate.self, RoutineItem.self, RoutineTemplate.self], inMemory: true)
}
