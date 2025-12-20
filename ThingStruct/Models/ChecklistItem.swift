/*
 * ChecklistItem.swift
 * 清单项数据模型
 *
 * 这是最简单的数据模型，适合作为Swift和SwiftData入门学习
 */

// MARK: - 导入框架
/*
 * import 语句类似于 C/C++ 的 #include，但更智能：
 * - 不需要头文件/源文件分离
 * - 自动处理循环依赖
 * - 只导入需要的符号
 */
import Foundation  // 基础框架：提供 UUID、Date 等基础类型（类似 C 的 stdlib）
import SwiftData   // Apple的数据持久化框架：自动将对象保存到数据库（类似ORM）

// MARK: - 数据模型定义

/*
 * @Model 是一个"宏"(Macro)，Swift 5.9 新特性
 * 
 * C/C++对比：类似于预处理宏，但更强大和类型安全
 * - C宏：#define，简单的文本替换
 * - Swift宏：在编译时生成额外代码，有完整的类型检查
 *
 * @Model 宏的作用：
 * 1. 自动生成数据库表结构（将类映射到SQLite表）
 * 2. 自动追踪属性变化（类似观察者模式）
 * 3. 自动处理数据持久化（保存/加载）
 * 
 * 生成的效果类似于：
 * - 为每个属性添加 getter/setter 拦截
 * - 添加数据库序列化/反序列化代码
 * - 注册到 SwiftData 的模型管理系统
 */
@Model
final class ChecklistItem {
    /*
     * final 关键字：
     * C/C++对比：类似于 C++11 的 final，表示此类不能被继承
     * 作用：
     * 1. 语义上明确这是一个"叶子类"
     * 2. 允许编译器优化（静态派发而非动态派发）
     *
     * class vs struct：
     * - class 是引用类型（类似 C++ 的指针/引用语义）
     *   两个变量可以指向同一个对象，修改会互相影响
     * - struct 是值类型（类似 C 的 struct）
     *   赋值时会复制，各自独立
     * 
     * SwiftData 的 @Model 只能用于 class，因为需要引用语义来追踪变化
     */
    
    // MARK: - 存储属性（Stored Properties）
    /*
     * 存储属性：实际占用内存存储数据的属性
     * C/C++对比：类似于 C++ 类的成员变量
     *
     * var vs let：
     * - var：可变变量（类似普通变量）
     * - let：不可变常量（类似 const）
     */
    
    /// 唯一标识符
    /// UUID: 通用唯一标识符，128位随机数，几乎不可能重复
    /// C/C++对比：类似于生成一个全局唯一的ID，常用于数据库主键
    var id: UUID
    
    /// 清单项的标题文字
    /// String: Swift的字符串类型，自动管理内存，支持Unicode
    /// C/C++对比：类似 std::string，但更安全（不会有空指针）
    var title: String
    
    /// 是否已完成
    /// Bool: 布尔类型，只有 true 和 false 两个值
    var isCompleted: Bool
    var completedDate: Date?
    
    /// 排序顺序（用于列表中的显示顺序）
    /// Int: 整数类型，在64位系统上是64位有符号整数
    var order: Int

    
    
    // MARK: - 构造器（Initializer）
    /*
     * init 是 Swift 的构造器，类似于 C++ 的构造函数
     * 
     * Swift 构造器的特点：
     * 1. 必须初始化所有存储属性（编译器强制检查）
     * 2. 支持默认参数值（order: Int = 0）
     * 3. 不需要写返回类型
     *
     * C/C++对比：
     * - C++ 构造函数可以不初始化成员（会是未定义值）
     * - Swift 强制要求所有属性必须有值，更安全
     */
    
    /// 创建一个新的清单项
    /// - Parameters:
    ///   - title: 清单项的标题
    ///   - order: 排序顺序，默认为0
    init(title: String, order: Int = 0) {
        /*
         * self 关键字：
         * C/C++对比：完全等同于 C++ 的 this 指针
         * 用于区分参数名和属性名（当它们同名时）
         */
        self.id = UUID()           // UUID() 生成一个新的随机UUID
        self.title = title
        self.isCompleted = false   // 新创建的项默认未完成
        self.completedDate = nil
        self.order = order
    }
}
