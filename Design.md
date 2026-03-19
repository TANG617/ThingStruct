# ThingStruct UI Design

本文档定义 ThingStruct 的 iOS UI 实现方案。

如果本文档与 [README.md](/Users/timli/workspace/ThingStruct/README.md) 冲突，以 [README.md](/Users/timli/workspace/ThingStruct/README.md) 中的数据模型、算法和约束为准。UI 只能消费核心层语义，不能反向定义核心规则。

## 1. 设计目标

UI 的目标不是做“效率工具风格”的自定义界面，而是尽量接近 Apple 官方 iOS App 的体验。

目标包括：

- 使用 iOS 26 最原生的导航结构、页面层级与系统组件
- 尽量依赖 SwiftUI 标准容器和系统材质，而不是手工绘制大量自定义装饰
- 让信息密度、留白、交互节奏、编辑流都接近 Apple 官方 App
- 让 `ThingStructCore` 成为唯一业务真相来源

不追求：

- 自定义 tab bar
- 常驻浮动按钮
- 大量渐变、发光、玻璃叠玻璃
- 用页面层逻辑替代核心层算法

## 2. 总体原则

### 2.1 原生优先

优先使用以下标准能力：

- `TabView`
- `NavigationStack`
- toolbar
- `sheet`
- `List`
- `ScrollView`
- 系统分组样式和材质
- SF Symbols
- 动态字体

只有在系统容器无法表达需求时，才构建定制视图。

### 2.2 核心层优先

UI 不自行计算以下结果：

- `resolvedStart` / `resolvedEnd`
- `BlankBaseBlock`
- `activeChain`
- `activeBlock`
- `taskSourceBlock`
- 模板选择结果
- 候选模板窗口

这些结果都必须来自 `ThingStructCore`。

### 2.3 内容优先于装饰

视觉层面以内容清晰、层级明确、触达路径短为第一优先级。

推荐风格：

- 使用系统背景层次
- 使用系统默认字重和字号层级
- 使用有限、稳定的强调色
- 用间距、分组、材质和字级建立层次

不推荐：

- 大面积品牌色铺底
- 每张卡片都加复杂阴影
- 手工模拟系统玻璃效果

## 3. 根导航结构

根界面使用 `TabView`，固定包含三个一级页面：

1. `Now`
2. `Today`
3. `Templates`

每个 tab 内部都使用独立的 `NavigationStack`。

导航行为建议：

- `Now` 默认使用大标题
- `Today` 默认使用 inline 标题，以便把垂直空间留给时间轴
- `Templates` 可根据内容密度选择大标题或 inline，但同一版本内应保持稳定
- tab 切换时保留各自导航栈状态
- 默认启动进入 `Now`

推荐顺序：

1. `Now`
2. `Today`
3. `Templates`

推荐图标：

- `Now`: `play.circle` 或 `bolt.circle`
- `Today`: `calendar`
- `Templates`: `square.stack.3d.up`

语义分工：

- `Now`
  - 回答“现在应该关注什么”
- `Today`
  - 回答“今天整天的结构是什么，以及怎么编辑”
- `Templates`
  - 回答“模板是什么、明天将采用什么模板、如何调整规则”

## 4. 页面级信息架构

### 4.1 `Now`

`Now` 是首页，也是默认 tab。

页面自上而下包含：

1. 当前日期和时间摘要
2. 当前生效块主卡片
3. `activeChain` 可视化
4. 当前任务面板
5. 快速跳转入口

#### 4.1.1 视觉风格

- 用滚动页面承载内容
- 顶部主卡片突出当前 `activeBlock`
- `activeChain` 采用纵向层叠卡片或层级列表
- checklist 使用系统 row 样式，避免过度装饰

#### 4.1.2 交互

允许：

- 勾选任务
- 查看当前链条详情
- 跳转到 `Today` 并定位当前块
- 跳转到 `Templates` 查看明天模板

不允许：

- 在 `Now` 直接做复杂结构编辑
- 在 `Now` 创建或取消块

#### 4.1.3 空态与异常态

- 如果当前时刻命中 `BlankBaseBlock`，主卡片明确显示“当前为空白时段”
- 如果 `taskSourceBlock == nil` 且当前链条存在，任务区域显示“当前链条没有未完成任务”
- 如果今日 `DayPlan` 尚未成功加载，则使用系统原生 loading 占位
- 如果核心层返回错误，则展示可恢复错误界面，并允许用户重试

### 4.2 `Today`

`Today` 是主编辑页面。

页面结构：

1. 顶部日期导航和辅助操作
2. 全天时间轴
3. 当前时间指示线
4. 选中块详情区
5. 新建和编辑入口

#### 4.2.1 时间轴表现

时间轴采用“原生感较强的自定义布局”：

- 纵向滚动
- 左侧为时间刻度
- 主轨道展示 `BaseBlock`
- `OverlayBlock` 在父块内部显示
- 空白时段由 `BlankBaseBlock` 低权重显示

#### 4.2.2 编辑方式

`Today` 负责发起以下结构操作：

- 新建 `BaseBlock`
- 在选中块上方新建 `OverlayBlock`
- 编辑块属性
- 取消块

不支持：

- 自由拖拽 reparent
- 在 blank 上直接创建 overlay
- 在当前阶段做任意图形化时间拖拽编辑

#### 4.2.3 面板组织

推荐：

- 主体使用时间轴
- 详情使用底部 sheet 或底部 inspector 面板
- 编辑表单使用 sheet

原因：

- 接近 Apple 官方“浏览 + 轻量编辑器”的结构
- 比多层 push 更适合频繁编辑对象

#### 4.2.4 首屏定位与滚动行为

- 打开 `Today` 时，时间轴默认优先定位到“当前时间线”附近
- 如果查看的不是今天，而是其他日期，则默认定位到当天第一个用户定义块附近
- 时间轴滚动位置只在当前会话内保留，不需要长期持久化
- “回到当前时间”按钮应始终可用

### 4.3 `Templates`

`Templates` 管理候选模板、正式模板和模板分配规则。

页面可以采用分段控件或单页分区，但信息架构必须稳定包含三部分：

1. `Suggested`
2. `Saved`
3. `Schedule`

#### 4.3.1 `Suggested`

展示最近三天候选模板窗口：

- `today-2`
- `today-1`
- `today`

每张卡片显示：

- 来源日期
- 块数量
- 任务蓝图数量
- 结构摘要
- 保存为正式模板入口

#### 4.3.2 `Saved`

展示所有正式模板，支持：

- 查看预览
- 编辑标题
- 编辑模板结构
- 编辑任务蓝图
- 编辑提醒规则

#### 4.3.3 `Schedule`

展示并编辑：

- `WeekdayTemplateRule`
- `DateTemplateOverride`

重点强调“明天采用哪个模板”：

- 明天日期
- 明天 weekday
- weekday 自动推导结果
- override 状态
- 最终生效模板

#### 4.3.4 空态与异常态

- 没有候选模板时，`Suggested` 明确说明原因，例如“最近三天没有可导出的有效计划”
- 没有正式模板时，`Saved` 明确引导用户先从候选模板保存
- `Schedule` 在没有可分配模板时，应展示只读解释态，而不是空白页

## 5. 视觉系统

### 5.1 色彩

采用系统色为主：

- 主背景：系统背景
- 分组背景：系统 grouped background
- 主强调色：仅保留一个全局 accent
- 危险操作：系统红色
- 成功完成：系统绿色或默认完成态样式

原则：

- 不依赖品牌色制造层次
- 不让颜色承担全部结构语义
- 层次主要由位置、字级、材质、边界和分组提供

### 5.2 字体

使用系统字体和动态字体。

推荐层级：

- 页面标题：`.largeTitle` 或系统导航标题
- 区块标题：`.title3` / `.headline`
- 正文：`.body`
- 次要信息：`.subheadline` / `.footnote`

不使用自定义字体。

### 5.3 材质与容器

使用系统材质时遵守以下原则：

- 导航和系统容器的玻璃感优先交给系统
- 内容卡片只在少数关键区域使用材质
- 不让所有卡片都变成玻璃

推荐使用场景：

- `Now` 顶部当前块主卡片
- 极少数主操作按钮
- 层级链视觉强调区域

### 5.4 图标

统一使用 SF Symbols。

建议：

- tab 图标使用标准语义图标
- toolbar 动作使用一阶语义图标
- checklist 完成态采用系统勾选语义

## 6. 关键组件方案

### 6.1 `AppShellView`

职责：

- 承载 `TabView`
- 管理 tab 选择
- 注入全局环境对象和轻量 UI 状态

### 6.2 `NowScreen`

职责：

- 渲染 `Now` 页面的静态结构
- 接收已解析 `NowScreenModel`
- 响应勾选任务、跳转等用户意图

### 6.3 `TodayTimelineView`

职责：

- 绘制全天时间轴
- 呈现 base/overlay/blank 三类块
- 响应点击选中
- 呈现“当前时间”指示线

这是 UI 中最主要的定制视图，但依然应保持系统风格，避免过多视觉表演。

### 6.4 `BlockDetailPanel`

职责：

- 展示当前选中块的核心信息
- 提供编辑、取消、新建 overlay 等操作入口

### 6.5 `BlockEditorSheet`

职责：

- 创建或编辑 `TimeBlock`
- 编辑标题、备注、提醒、任务
- 编辑时间模式和时间参数

### 6.6 `TemplateEditorSheet`

职责：

- 编辑正式模板
- 不允许从空白开始创建模板

### 6.7 `TemplateAssignmentView`

职责：

- 呈现 weekday 规则
- 呈现 date override
- 管理明天 override

### 6.8 呈现规则

页面级呈现统一遵守以下规则：

- 轻量详情优先使用 push
- 表单编辑优先使用 sheet
- 危险操作确认优先使用 confirmation dialog
- 非阻塞反馈优先使用系统 toast 风格或轻量 banner

sheet 建议：

- `BlockEditorSheet` 使用中到大尺寸 detent
- `TemplateEditorSheet` 使用大尺寸 detent 或全屏 sheet
- 不在一个操作流中连续堆叠多个 sheet

## 7. 数据流与状态管理

### 7.1 分层

推荐分为四层：

1. SwiftData 持久化层
2. Core 适配层
3. Screen ViewModel 层
4. SwiftUI View 层

### 7.2 Core 适配层

Core 适配层负责：

- 从 SwiftData 读取旧数据和新数据
- 组装为 `ThingStructCore` 输入
- 调用核心算法
- 把用户编辑意图翻译回持久化写入

它不负责自定义 UI 逻辑。

### 7.3 Screen Model

建议为每个一级页面准备稳定的只读展示模型：

- `NowScreenModel`
- `TodayScreenModel`
- `TemplatesScreenModel`

这样可以让视图代码保持干净，也便于预览和测试。

### 7.4 SwiftUI 本地状态

UI 本地状态只保留：

- 当前选中 tab
- 当前选中日期
- 当前选中 block
- 当前打开的 sheet
- 表单草稿
- toast / alert / confirmation dialog 状态

UI 不长期缓存：

- 解析结果
- 活动链
- blank 补齐结果
- 模板最终选择结果

但可以短暂保留：

- 当前滚动位置
- 当前输入草稿
- 当前 sheet 的局部表单状态

## 8. 交互细节

### 8.1 新建入口

当前阶段不使用自定义 FAB。

推荐入口：

- `Today` 页面 toolbar 中的 `+`
- 选中块后的上下文操作
- 详情面板中的“Add Overlay”

### 8.2 删除与取消

当前只允许取消，不允许直接删除业务块。

推荐交互：

- 在详情面板或菜单中提供 `Cancel Block`
- 使用系统确认对话框
- 文案明确提示会触发层级塌缩

### 8.3 任务勾选

任务勾选必须立即回流核心层，重新拉取 `taskSourceBlock`。

不在页面本地做“假完成态缓存”。

### 8.4 Blank 时段

blank 时段应可见，但不抢主视觉。

推荐表现：

- 低对比度
- 明确标注为空白时段
- 点击 blank 时段时，进入“创建真实 `BaseBlock`”流程

### 8.5 空态、错态和加载态

每个一级页面都必须有明确的三种状态设计：

- loading
- empty
- error

要求：

- 不允许用纯空白页面代表 empty
- 不允许用 debug 文本直接暴露底层错误
- error 状态必须提供明确的恢复动作，例如 retry
- empty 状态应带有下一步引导

## 9. 可访问性

必须支持：

- Dynamic Type
- VoiceOver 可读块标题、时间范围、层级和任务状态
- 足够的点按热区
- 深浅色系统外观
- 减少动态效果

时间轴中的块卡片必须具备清晰的 accessibility label，例如：

- 标题
- 开始和结束时间
- 当前层级
- 是否为当前块
- 未完成任务数

## 10. 实现顺序

推荐按以下顺序实现：

1. `AppShellView` 和新的根 `TabView`
2. Core 适配层和 screen model
3. `Now` 的只读实现
4. `Today` 的只读时间轴
5. `Today` 的选中与编辑 sheet
6. `Templates` 的只读实现
7. `Templates` 的保存、编辑和 schedule
8. 删除旧页面和旧交互

每个阶段都应同时补齐：

- SwiftUI preview
- 基础 UI 测试或快照验证
- 可访问性自检

## 11. 与当前仓库的关系

当前仓库仍然保留旧页面结构，例如：

- [ContentView.swift](/Users/timli/workspace/ThingStruct/ThingStruct/ContentView.swift)
- [AddStateView.swift](/Users/timli/workspace/ThingStruct/ThingStruct/AddStateView.swift)
- [StateDetailView.swift](/Users/timli/workspace/ThingStruct/ThingStruct/StateDetailView.swift)
- [FloatingActionButton.swift](/Users/timli/workspace/ThingStruct/ThingStruct/FloatingActionButton.swift)

这些页面和组件不应继续作为最终 UI 架构的中心。

迁移目标是：

- 用新的三 tab 壳层替换旧单页入口
- 用 core screen model 替换旧页面内部计算逻辑
- 用统一的 editor sheet 替换分散的旧编辑页
- 移除自定义 FAB 方案

## 12. 当前文档的实现约束

本文档描述的是 UI 方案，不等于立刻全部实现。

在正式编码时仍需遵守：

- 以核心层规则为准
- 先搭结构，再接编辑
- 先保证原生体验，再做少量增强
- 不为了“好看”而破坏信息架构和系统一致性
