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

1. `Notes`
2. `Tasks`

#### 4.1.1 视觉风格

- 用滚动页面承载内容
- 顶部导航标题使用当前日期的短格式，而不是固定写 `Now`
  - 推荐样式：`Fri Mar 20`
- 页面重心应明确落在 `Tasks`，而不是时间摘要或当前块摘要
- 不显示顶部当前时间、大块 `Current Block` 卡片或页内快速跳转按钮
- `Notes` 与 `Tasks` 都按 block 分组，但分别聚合成两个独立区域
- `Notes` 与 `Tasks` 的区块标题应使用同一套字号与字重，保持同级 section heading 的一致性
- `Tasks` 的视觉权重高于 `Notes`
- 不再单独展示 `activeChain` 上下文区；如果 `Notes` 和 `Tasks` 已经表达了链条信息，就不重复渲染 `Context`
- `Notes` 应明显轻于 `Tasks`：
  - 更小的内边距
  - 更浅的底色
  - 更弱或可省略的描边
  - 不应做成与任务主卡同级的“行动面板”
- `Tasks` 中真正未完成的任务应优先占据首屏空间
- 已完成任务的信息仍可保留，但必须弱于未完成任务，不能与行动内容争抢视觉中心
- 顶部标题与首个 section 之间的留白应适度收紧，避免首页出现过多无效空白

#### 4.1.2 信息排序与分组

- `Notes` 显示当前 `activeChain` 中所有有 note 的 block
- `Tasks` 显示当前 `activeChain` 中所有有 tasks 的 block
- 两个区域都必须按 `layerIndex` 从高到低排序
- 如果同一时刻存在多层叠加，必须先展示最上层 block，再展示更下层 block
- `Notes` 放在一起，`Tasks` 放在一起，不能按 block 交替穿插
- 每个 note/task 分组仍需保留其来源 block 的标题，不能打平成没有来源的纯文本列表
- 某个 block 在对应区域没有内容时直接跳过：
  - 没有 note，不出现在 `Notes`
  - 没有 tasks，不出现在 `Tasks`
- 任务区的展示优先级应进一步细分：
  - 有未完成任务的 block 使用展开态任务卡
  - 全部任务已完成的 block 仍按 layer 顺序保留，但使用更紧凑的完成态卡片
  - 完成态卡片默认不展开完整任务列表，避免首屏被“已经做完”的内容占满
  - 完成摘要文案应弱于未完成任务标题与任务项
- 如果某个 block 同时存在已完成和未完成任务：
  - 优先展示未完成任务
  - 已完成部分仅做摘要，或放在明显低权重的位置
- 不应为了暴露内部实现而在主卡片中突出 `L0` / `L1` 一类开发者术语；层级关系主要由顺序和颜色表达

#### 4.1.3 Layer 颜色系统

- block 颜色是全局设计语言，不是 `Now` 页局部样式
- 同一个 `layerIndex` 在不同页面中应使用一致的颜色映射
- 所有 layer 使用同一色系，只通过深浅变化表达层级
- `layerIndex` 越高，颜色越深
- 颜色映射应使用稳定的预设色阶，而不是仅靠透明度临时叠加
- 色阶差异必须足够清晰，用户即使不看层号，也能通过颜色直接感知哪个 block 更上层
- `BlankBaseBlock` 继续使用明显低权重的中性色，不参与彩色 layer 色阶
- 在 `Notes`、`Tasks`、时间轴等 block 相关视图里，应复用同一套 layer 颜色规则
- 同一 layer 的 badge、描边、卡片底色也应属于同一色阶系统，而不是各自独立取色

#### 4.1.4 交互

允许：

- 勾选任务

不允许：

- 在 `Now` 直接做复杂结构编辑
- 在 `Now` 创建或取消块
- 在 `Now` 增加只为补充说明而存在的重复信息区块

#### 4.1.5 空态与异常态

- 如果当前时刻命中 `BlankBaseBlock`，页面应在内容区明确表达“当前为空白时段”
- 如果当前链条存在但没有任何 note，可省略 `Notes` 区域
- 如果当前链条存在但没有任何任务，`Tasks` 区域显示“当前链条没有未完成任务”或等价空态
- 如果当前链条里的上层 block 已全部完成，但下层仍有未完成任务：
  - 上层 block 继续显示为完成态摘要
  - 下层未完成任务仍应清晰可见，并承担主要视觉焦点
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
- `OverlayBlock` 不应像独立平面卡片那样简单叠放，而应在父块容器内部呈现为嵌套结构
- 父块应像容器而不是底板：
  - 标题、时间、摘要留在父块 header
  - 子 overlay 在容器内部以 inset 子卡形式呈现
  - 父块正文不能继续铺到 overlay 背后，避免出现“内容重叠但关系不清”的视觉效果
- 多层 overlay 继续递归嵌套，层级关系优先通过结构与色阶表达，而不是单纯依赖 `L0` / `L1` 文本
- 空白时段由 `BlankBaseBlock` 低权重显示
- 当前选中块及其祖先链条都应有清晰但不同等级的选中反馈：
  - 当前选中块最强
  - 祖先块次强
  - 非选中块保持正常权重

#### 4.2.2 编辑方式

`Today` 负责发起以下结构操作：

- 新建 `BaseBlock`
- 在选中块上方新建 `OverlayBlock`
- 编辑块属性
- 取消块
- 通过直接操纵时间轴调整 block 长度

不支持：

- 自由拖拽 reparent
- 在 blank 上直接创建 overlay
- 在当前阶段拖拽 block 的起点位置
- 在当前阶段整体平移 block 所在时间段

#### 4.2.3 面板组织

推荐：

- 主体使用时间轴
- 详情使用原生底部 sheet
- 编辑表单使用 sheet

原因：

- 接近 Apple 官方“浏览 + 轻量编辑器”的结构
- 比多层 push 更适合频繁编辑对象

详情 sheet 应满足：

- 使用 iOS 原生 sheet 呈现，而不是自绘浮动卡片
- 明确表达当前面板对应的是哪一个 block
- 如果选中的是 overlay，应清楚显示其父块关系，例如“Inside 某个父块”
- 使用与选中 block 相同色系的轻量强调，建立与时间轴中选中项的视觉关联
- 主区域只保留两个按钮：
  - `Edit`
  - `Add Overlay`
- `Cancel Block` 不在主区域出现，而是在 `Edit Block` 页末尾以 destructive 入口呈现
- 收起和隐藏只能通过用户下滑手势完成，不提供单独的关闭按钮
- 允许在原生 sheet detent 之间自然收缩，视觉上接近 iOS 系统 sheet 的液态过渡
- 详情内容应像 inspector，而不是一组大按钮堆在底部

顶部工具栏应满足：

- 中间稳定显示当前日期
- 左右箭头负责切天
- `Today` 按钮只在当前查看的不是今天时出现
- “回到当前时间”入口在查看今天时可用，但不应遮挡时间轴中的 block 内容
- 新建按钮仍保留在顶栏，且不应与日期导航形成割裂的视觉分组

#### 4.2.4 首屏定位与滚动行为

- 打开 `Today` 时，时间轴默认优先定位到“当前时间线”附近
- 如果查看的是今天：
  - 默认将当前时间线放在视口中部附近，而不是贴近顶部
  - 默认选中当前 `activeBlock`
- 如果查看的不是今天，而是其他日期，则默认定位到当天第一个用户定义块附近
- 自动定位只应发生在页面首次进入或切换日期时，用户手动滚动或手动选中后不应反复抢焦点
- 时间轴滚动位置只在当前会话内保留，不需要长期持久化
- “回到当前时间”按钮应始终可用
- 触发“回到当前时间”时，应该优先滚动并选中当前正在进行的 `activeBlock`

#### 4.2.5 时间精度

- `Today` 中所有 block 相关时间都使用 5 分钟精度
- 包括：
  - 时间轴中展示的 block 起止时间
  - 编辑页中的 absolute start/end
  - 编辑页中的 relative offset/duration
  - `Today` 中通过拖拽调整长度后的结果
- 对用户输入与拖拽结果采用“就近吸附到 5 分钟”的规则
- 当前时间指示线保持真实分钟，不需要强制吸附到 5 分钟

#### 4.2.6 时间轴直接操纵

- 支持在 `Today` 中通过长按 block 后拖动其底边来调整 block 长度
- 第一阶段只允许调整长度，不允许拖动起点，不允许整体平移
- 进入 resize 模式后，应提供清晰但克制的视觉反馈，例如：
  - 当前 block 高亮
  - 底边出现可拖拽手柄
  - 拖动过程中显示结束时间预览
- 约束规则：
  - `BlankBaseBlock` 不可调整
  - block 最短长度为 5 分钟
  - `BaseBlock` 的结束时间不能越过下一个同层兄弟 block，也不能越过午夜
  - `OverlayBlock` 的结束时间不能越过父 block 的结束时间
  - `OverlayBlock` 的结束时间不能越过下一个同层兄弟 overlay
- 写回规则：
  - absolute block 写回 `requestedEndMinuteOfDay`
  - relative overlay 写回 `requestedDurationMinutes`
  - 如果 overlay 原本是开放结束，用户拖拽后应转为显式 duration

### 4.3 `Templates`

`Templates` 管理候选模板、正式模板和模板分配规则。

页面可以采用分段控件或单页分区，但信息架构必须稳定包含三部分：

1. `Suggested`
2. `Saved`
3. `Schedule`

页面层级应满足：

- `Templates` 更适合使用紧凑页头，而不是过高的大标题首屏
- 分段控件应作为页面级切换容器出现，而不是像普通列表行那样嵌在内容区里
- 分段控件与首个内容区之间的距离应较短，避免首屏出现“标题很大但内容很远”的空白
- 三个分段的切换应尽量稳定，不因内容多少而导致整体布局显得忽上忽下
- 页面语言需要统一：
  - 如果产品主语言是中文，页内 chrome 与按钮文案应优先中文化
  - 如果保留英文导航，则关键文案的英文也应保持完整一致，不混用半技术化缩写和自然语言

#### 4.3.1 `Suggested`

展示最近三天候选模板窗口：

- `today-2`
- `today-1`
- `today`

这三天窗口应稳定出现，不应因为某一天没有候选模板就把该日期整段省略。

推荐表现：

- 按日期稳定展示三张卡片或三个位点
- 有候选模板的日期显示完整候选卡片
- 没有候选模板的日期显示低权重解释态，例如：
  - `No exportable plan`
  - `No structured day to suggest`
- 候选为空时，页面仍然要让用户感知“最近三天都检查过了”，而不是像只加载出一张卡

每张卡片显示：

- 来源日期
- 块数量
- 任务蓝图数量
- 结构摘要
- 保存为正式模板入口

候选卡片的视觉组织应满足：

- 卡片首先表现“这是一个什么模板”，其次才是“可以保存”
- `Save as Template` 不应做成一条占整卡宽度、压过内容本体的主视觉按钮
- 更推荐将保存入口做成 trailing 主按钮或紧凑按钮，而不是整卡最醒目的大色块
- 日期与结构摘要应承担主阅读重心
- 数量信息应清楚但不技术化：
  - `5 blocks`
  - `9 tasks`
  - `5 base blocks` 可保留，但应弱于总块数与任务数
- 结构摘要应比普通副标题更像 preview：
  - 展示前 2 到 3 个 block 标题
  - 超出时显示 `+N more`
  - 可使用 tag、chip 或紧凑分隔方式提升可扫描性

#### 4.3.2 `Saved`

展示所有正式模板，支持：

- 查看预览
- 编辑标题
- 编辑模板结构
- 编辑任务蓝图

正式模板列表不应只剩下标题和统计数字。

每张卡片推荐显示：

- 模板标题
- 轻量结构 preview
- 块数量与任务数量
- 已分配 weekday
- 当前是否用于明天的状态
- `Edit`
- `Use for Tomorrow`

Saved 卡片应满足：

- 用户不进入编辑页，也能快速区分两个模板的结构差异
- `Use for Tomorrow` 可以是主要动作，但不应遮盖模板本身的信息
- 如果某模板当前就是明天最终生效模板，应给出清晰但克制的 badge 或状态说明
- weekday 分配信息更适合以紧凑 badge / chip 展示，而不是一整串弱文本

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

`Schedule` 的页面结构应优先回答“明天最终用哪个模板”，然后才是“规则如何编辑”。

推荐顺序：

1. 顶部结果卡
2. `Weekday Rules`
3. `Tomorrow Override`

结果卡应满足：

- 明确突出最终模板名称
- 明确提示当前是否处于 override 状态
- weekday rule、override、final 的关系要一眼可读
- `Regenerate Tomorrow Plan` 是次级维护动作，不应与最终结果争夺视觉中心

规则编辑区应满足：

- 看起来像设置区，而不是一整屏重复 picker
- 同类设置尽量收纳在稳定容器中，减少视觉噪音
- 当没有任何可分配模板时，应展示只读解释态，而不是让用户面对一组几乎无意义的空 picker

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
- 提供 `Edit` 和 `Add Overlay` 两个主操作入口
- 依附于原生底部 sheet，而不是独立悬浮卡片

### 6.5 `BlockEditorSheet`

职责：

- 创建或编辑 `TimeBlock`
- 编辑标题、备注、任务
- 编辑时间模式和时间参数
- 在编辑页末尾提供 `Cancel Block` destructive 操作

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
- `Today` 的 block detail 使用原生 sheet detent，而不是 `safeAreaInset` 自绘面板
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

- 在 `Edit Block` 页最末尾提供 `Cancel Block`
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
