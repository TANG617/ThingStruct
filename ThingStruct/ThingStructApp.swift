/*
 * ThingStructApp.swift
 * 应用程序入口点
 *
 * 这是整个iOS应用的起点，类似于C/C++的 main() 函数
 * 负责：
 * 1. 应用生命周期管理
 * 2. 数据库初始化
 * 3. 根视图设置
 */

// MARK: - 框架导入

/*
 * SwiftUI：Apple的声明式UI框架
 * 
 * C/C++对比：
 * - C++ Qt/MFC 需要手动创建窗口、处理消息循环
 * - SwiftUI 是声明式的：你描述"UI应该是什么样"，框架自动处理渲染和更新
 *
 * 声明式 vs 命令式：
 * - 命令式（C++/Qt）：创建按钮 -> 设置文字 -> 添加到父视图 -> 绑定点击事件
 * - 声明式（SwiftUI）：Button("点击我") { 处理逻辑 }
 */
import SwiftUI

/*
 * SwiftData：Apple的数据持久化框架（2023年发布）
 * 
 * 类似于：
 * - C++: SQLite + ORM库
 * - 其他语言: Hibernate (Java), Entity Framework (C#)
 *
 * 功能：自动将Swift对象保存到SQLite数据库
 */
import SwiftData

// MARK: - 应用入口

/*
 * @main 宏：标记应用程序入口点
 *
 * C/C++对比：
 * - C/C++ 使用 main() 函数作为入口
 * - Swift 使用 @main 标记的类型作为入口
 *
 * 编译器会自动生成启动代码，调用这个结构体的初始化
 * 等价于 C++ 中 WinMain 或 main 的作用
 */
@main
struct ThingStructApp: App {
    /*
     * struct 遵循 App 协议
     *
     * 协议（Protocol）：
     * C/C++对比：类似于 C++ 的纯虚基类（接口）
     * - C++: class IApp { virtual Scene body() = 0; };
     * - Swift: protocol App { var body: some Scene { get } }
     *
     * App 协议要求：
     * 1. 必须提供 body 属性，返回应用的场景结构
     * 2. 处理应用生命周期（启动、进入后台、恢复等）
     *
     * struct vs class 选择：
     * - SwiftUI 视图使用 struct（值类型），更轻量、无引用计数开销
     * - 数据模型使用 class（引用类型），因为需要共享和追踪变化
     */
    
    // MARK: - 数据库容器
    
    /*
     * @MainActor 属性包装器：保证在主线程执行
     *
     * C/C++对比：
     * - C++/Qt 中 UI 操作必须在主线程，通常用 QMetaObject::invokeMethod
     * - Swift 用 @MainActor 编译器自动保证线程安全
     *
     * Actor 是 Swift 的并发模型：
     * - 确保数据访问的线程安全
     * - MainActor 特指 UI 主线程
     *
     * 为什么需要：
     * - 数据库操作可能触发UI更新
     * - UI更新必须在主线程
     * - @MainActor 确保这一点
     */
    @MainActor
    var sharedModelContainer: ModelContainer = {
        /*
         * 这是一个"闭包初始化"语法
         *
         * 语法解析：var 变量名: 类型 = { 初始化代码 }()
         *
         * { ... } 是一个闭包（匿名函数）
         * 末尾的 () 立即调用这个闭包
         *
         * C/C++对比：类似于立即执行的 lambda
         * auto container = []() {
         *     // 初始化代码
         *     return ModelContainer(...);
         * }();
         *
         * 为什么这样写：
         * 1. 初始化逻辑复杂，不适合写在一行
         * 2. 可以在初始化中使用 do-catch 错误处理
         * 3. 保持代码组织清晰
         */
        
        /*
         * Schema：数据库模式定义
         *
         * C/C++对比：类似于 SQL 的 CREATE TABLE 语句集合
         * 定义了数据库中有哪些表（模型类）
         *
         * StateItem.self, ChecklistItem.self：
         * .self 获取类型本身（元类型）
         * C/C++对比：类似于 typeid(StateItem) 或模板中的类型参数
         */
        let schema = Schema([
            StateItem.self,       // 状态表
            ChecklistItem.self,   // 清单项表
            StateTemplate.self,   // 模板表
        ])
        
        /*
         * ModelConfiguration：数据库配置
         *
         * 参数说明：
         * - schema: 使用的数据库模式
         * - isStoredInMemoryOnly: false 表示持久化到磁盘
         *   如果是 true，数据只在内存中，应用关闭后丢失（用于测试）
         *
         * 数据存储位置：
         * iOS 会自动存储在应用的沙盒目录中
         * 通常是 ~/Library/Application Support/YourApp/default.store
         */
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        /*
         * do-catch：Swift 的错误处理机制
         *
         * C/C++对比：
         * - C++ 使用 try-catch 捕获异常
         * - Swift 的 do-catch 类似，但更严格
         *
         * Swift 错误处理特点：
         * 1. 必须用 try 标记可能抛出错误的调用
         * 2. 错误类型是明确的（不像 C++ 可以抛任何东西）
         * 3. 编译器强制处理错误（不能忽略）
         *
         * try 关键字：
         * - try: 在 do-catch 中使用，错误会被 catch 捕获
         * - try?: 错误时返回 nil（可选类型）
         * - try!: 强制执行，错误时崩溃（类似断言）
         */
        do {
            /*
             * ModelContainer：数据库容器
             *
             * SwiftData: 管理整个数据库生命周期
             * - 创建/打开数据库文件
             * - 管理数据库连接
             * - 提供 ModelContext 给各个视图使用
             *
             * C/C++对比：类似于数据库连接池
             */
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            /*
             * fatalError：终止程序执行
             *
             * C/C++对比：类似于 abort() 或 assert(false)
             * 会立即终止程序，输出错误信息
             *
             * 字符串插值 \(error)：
             * 在字符串中嵌入变量值
             * C/C++对比：类似于 printf("%s", error.what()) 或 std::format
             *
             * 这里用 fatalError 因为：
             * 数据库创建失败是致命错误，应用无法正常运行
             */
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // MARK: - 应用界面
    
    /*
     * body 属性：定义应用的界面结构
     *
     * some Scene：不透明返回类型（Opaque Return Type）
     *
     * C/C++对比：
     * - C++ 通常返回具体类型或用模板
     * - Swift 的 some 表示"返回某个遵循 Scene 协议的类型，但调用者不需要知道具体是什么"
     *
     * 好处：
     * 1. 编译器知道具体类型，可以优化
     * 2. 调用者只需要知道是 Scene，无需关心细节
     * 3. 允许返回复杂的泛型类型而不暴露实现细节
     *
     * Scene 协议：
     * 表示应用的一个"场景"，可以是窗口、菜单等
     * iOS 上通常只有一个全屏场景
     * macOS/iPadOS 可以有多窗口
     */
    var body: some Scene {
        /*
         * WindowGroup：窗口组
         *
         * SwiftUI: 管理应用的窗口
         * - iOS: 一个全屏窗口
         * - macOS: 可以有多个窗口
         * - iPadOS: 支持多窗口/分屏
         *
         * 花括号内的内容是窗口的根视图
         */
        WindowGroup {
            /*
             * ContentView()：创建主内容视图
             *
             * 这是应用启动后显示的第一个界面
             * 类似于 Web 的 index.html 或 Android 的 MainActivity
             */
            ContentView()
        }
        /*
         * .modelContainer()：将数据库容器注入到视图层级
         *
         * SwiftUI: 这是"环境修饰符"
         * 将 sharedModelContainer 放入 SwiftUI 的环境系统
         * 所有子视图都可以通过 @Environment 访问
         *
         * C/C++对比：类似于依赖注入（Dependency Injection）
         * 而不是全局变量或单例模式
         *
         * 好处：
         * 1. 解耦：视图不直接依赖具体的数据库实例
         * 2. 测试：可以注入内存数据库进行单元测试
         * 3. 作用域：可以在不同视图层级使用不同的容器
         */
        .modelContainer(sharedModelContainer)
    }
}
