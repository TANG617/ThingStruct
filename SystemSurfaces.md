# ThingStruct System Surfaces

本文档定义 ThingStruct 的 iOS 系统级入口与控件方案，包括 Widget、Live Activities、Controls、App Shortcuts、Spotlight、Home Screen Quick Actions 和通知动作。

如果本文档与 [README.md](/Users/timli/workspace/ThingStruct/README.md) 或核心层语义冲突，以核心层为准。系统级入口只能消费核心层语义，或执行受控的有限动作，不能反向定义业务规则。

当前方案按 Apple 现行 WidgetKit、ActivityKit 与 App Intents 能力编写。具体 API availability 与部署目标，以当前 Xcode SDK 和项目的 iOS deployment target 为准。

## 0. 背景与目标

ThingStruct 的核心价值是回答三个问题：

1. 现在应该关注什么。
2. 今天的结构是什么。
3. 模板如何驱动未来几天。

主 App 已经承载了完整编辑体验，但这类产品天然需要大量“在 App 之外”的触达能力。用户往往不是想“打开一个规划工具”，而是想在系统界面里快速完成以下动作：

- 抬手看一眼当前 block。
- 在锁屏或桌面上确认还剩几件任务。
- 一键把当前任务勾掉。
- 不打开 App 就进入“当前这件事”的持续跟踪状态。
- 用 Siri、Shortcuts、Spotlight、Action Button 或控制中心直接触发最常用动作。

因此，ThingStruct 的系统级入口方案需要满足以下目标：

- 信息分层明确：不同系统入口只承载适合它的信息密度。
- 动作边界清晰：系统入口只做轻量、确定、可回退或可容错的操作。
- 复用现有架构：尽量复用共享文档客户端、既有 deep link 和 `Now` 推导逻辑。
- 先做高回报入口：优先建设用户最常用、实现复用度最高的系统入口。
- 控制复杂度：复杂结构编辑、文本输入、模板编排仍保留在主 App 内完成。

非目标：

- 在 Widget、Control 或 Live Activity 中做复杂结构编辑。
- 在系统入口中输入任意文本。
- 为每一种系统位置都单独发明一套业务规则。
- 一期就做远程推送驱动的服务端编排。
- 一期就做 watchOS 独立 App、CarPlay 独立 UI 或 macOS 独立产品化适配。

## 1. 当前基线

结合现有工程，ThingStruct 已具备以下基础：

- 主 App 已有三个一级入口：`Now`、`Today`、`Templates`。
- 现有 deep link 已支持 `thingstruct://now`、`thingstruct://today`、`thingstruct://templates`。
- App 与 Widget Extension 已共享 App Group 容器。
- 已经存在共享文档客户端 [ThingStructSharedDocumentClient.swift](/Users/timli/workspace/ThingStruct/ThingStruct/CoreShared/ThingStructSharedDocumentClient.swift)。
- 已经存在 `Now` Widget 和一个内部交互 intent [ToggleTaskCompletionIntent.swift](/Users/timli/workspace/ThingStruct/ThingStructWidgetExtension/ToggleTaskCompletionIntent.swift)。
- 当前 Widget 方案文档已写明桌面小组件与交互式勾选方向，见 [weiget.md](/Users/timli/workspace/ThingStruct/weiget.md)。

当前仍缺少或尚未抽象清晰的部分：

- 没有统一的“系统动作层”，导致 Widget、Controls、Shortcuts、通知动作还不能共享同一套命令抽象。
- 没有面向系统公开的 discoverable intents；当前只有一个内部的、以 raw ID 为参数的 intent。
- 还没有 Live Activities 接入。
- 还没有 Controls。
- 还没有 Home Screen Quick Actions。
- 还没有通知动作与提醒闭环。
- deep link 还不够细，只能跳 tab，不能稳定表达“打开某天某个 block 某个任务来源”的上下文。

## 2. 入口全景图

下表给出 ThingStruct 在 iOS 上应考虑的系统入口全景：

| 类别 | 系统位置 | 主要价值 | 是否适合写操作 | ThingStruct 定位 |
| --- | --- | --- | --- | --- |
| Home Screen Widget | 桌面 / Today View / StandBy | glanceable 的 `Now` 概览 | 适合极少量写操作 | 必做 |
| Lock Screen Accessory Widget | 锁屏时间附近 | 极简 glanceable 信息 | 只适合极轻写操作 | 必做 |
| Live Activities | 锁屏、Dynamic Island、派生系统位置 | 持续展示当前 block 的进度与状态 | 适合 1-2 个轻交互 | 必做 |
| Controls | Control Center、锁屏底部、Action Button 等系统位置 | 单一、确定的一键动作 | 非常适合 | 必做 |
| App Shortcuts / Siri / Spotlight | Siri、Shortcuts、Spotlight、系统建议 | 提升可发现性与自动化能力 | 适合 | 必做 |
| Home Screen Quick Actions | 长按 App 图标 | 极低成本的高频入口 | 适合跳转，不适合复杂写入 | 建议做 |
| Notification Actions | 本地通知上的 action buttons | 与提醒闭环、时机触达 | 适合 1-2 个轻操作 | 建议做 |
| 派生覆盖面 | Apple Watch Smart Stack、配对 Mac、CarPlay、StandBy | 来自 WidgetKit / ActivityKit 的自然扩展 | 以只读或轻交互为主 | 作为测试矩阵，不单独立项 |

结论上，ThingStruct 不应该把这些入口视为彼此独立的“功能堆叠”，而应该把它们都建立在一套统一的“系统级查询 + 系统级命令”模型上。

## 3. 产品结论与优先级

如果只给一个产品结论：

- Widget 和 Live Activities 解决“看”。
- Controls、Shortcuts 和通知动作解决“做”。
- 所有系统入口都应先依赖同一层 App Intent / Action Executor，再往不同系统位置投放。

建议优先级如下：

1. 先抽统一动作层与更细粒度的路由层。
2. 在现有 Widget 基础上补齐锁屏 accessory widgets。
3. 做 Controls，因为它是“一键动作”最自然的系统位置。
4. 做公开的 App Shortcuts / Siri / Spotlight 能力。
5. 做 Live Activities，但先做本地更新版，不引入服务端。
6. 做 Home Screen Quick Actions。
7. 做通知动作，把提醒闭环补全。

这个顺序的原因：

- Widget、Controls、Shortcuts、通知动作都可以共享同一批 AppIntent 和共享文档读写逻辑。
- Controls 与公开 Shortcuts 的研发回报通常高于单独追求 Live Activity 的复杂动画。
- Live Activities 适合“当前 block 持续进行中”的场景，但它对生命周期、更新策略和平台限制要求更高，适合放在动作层稳定之后做。

## 4. 统一交互模型

### 4.1 系统入口只暴露两类能力

所有系统入口都只应该做两类事：

- 查询：返回 glanceable 的系统视图模型。
- 命令：执行轻量、确定、可容错的受控动作。

系统入口不应该直接暴露以下能力：

- 任意新建 block。
- 任意编辑 block 时间。
- 任意编辑模板结构。
- 任何需要文本输入的流程。
- 任何会明显改变整天结构、且难以在系统入口中确认后果的操作。

### 4.2 建议的公共系统动作

ThingStruct 适合面向系统公开的动作，建议限制在以下集合：

| 动作 ID | 用户语义 | 是否改写数据 | 推荐投放位置 | 备注 |
| --- | --- | --- | --- | --- |
| `openNow` | 打开 `Now` | 否 | Widget、Shortcut、Quick Action、Control | 最基础入口 |
| `openToday` | 打开今天 | 否 | Shortcut、Quick Action、Control | 可带日期参数 |
| `openCurrentBlock` | 打开当前 block 所在位置 | 否 | Widget、Shortcut、Control、通知 | 依赖更细粒度 route |
| `toggleTaskByID` | 切换某个任务完成状态 | 是 | Widget、Live Activity | 保持内部命令，不对用户公开 |
| `completeTopTask` | 完成当前最优先未完成任务 | 是 | Control、Shortcut、通知 | 公开命令 |
| `startCurrentBlockLiveActivity` | 启动当前 block 的 Live Activity | 否或轻写 | App、Shortcut、Control | 可以记录当前 activity metadata |
| `endCurrentBlockLiveActivity` | 结束当前 Live Activity | 否或轻写 | App、Shortcut、Control | 用于手动结束 |
| `snoozeReminder` | 稍后提醒 | 是 | 通知动作 | 仅在提醒闭环里出现 |

这里要刻意区分两类 intent：

- 内部 intent：参数是 raw ID，主要给 Widget 或 Live Activity 绑定按钮使用，不用于 Siri/Spotlight discoverability。
- 公开 intent：参数是人类可理解的语义，例如“打开今天”“完成当前任务”“开始当前状态追踪”，用于 App Shortcuts、Siri、Spotlight、Controls。

当前已有的 [ToggleTaskCompletionIntent.swift](/Users/timli/workspace/ThingStruct/ThingStructWidgetExtension/ToggleTaskCompletionIntent.swift) 属于前者，不应该直接拿来作为用户可发现的公开动作。

## 5. 统一架构方案

### 5.1 核心原则

- `CoreShared` 继续作为唯一业务真相来源。
- 任何系统入口都不能自己计算另一套 `activeChain`、当前 block 或模板决策。
- 所有系统入口的读写都走共享文档客户端，避免 App 与 Extension 各写一套逻辑。
- 所有“打开到哪里”的能力都走统一路由模型，不再散落在各处拼接 URL。
- 所有面向系统公开的动作都先抽成命令，再决定放到 Widget、Control、Shortcut 还是通知上。

### 5.2 推荐的分层

建议把系统级能力拆成三层：

#### A. CoreShared 层

这一层保持平台无关，负责稳定语义与轻量 DTO：

- `ThingStructSystemRoute`
  - 定义系统级路由，如 `now`、`today(date)`、`todayBlock(date, blockID)`、`templates`。
- `ThingStructSystemAction`
  - 定义可序列化的动作标识，而不是直接承载 `AppIntent`。
- `ThingStructSystemNowQuery`
  - 为 Widget、Controls、Live Activity 提供统一的“当前状态快照”。

这一层不直接依赖 `WidgetKit`、`ActivityKit`、`ControlWidget` 等 UI 框架。

#### B. App / Extension Shared 层

这一层由 iOS target 共享，承接系统框架：

- `ThingStructSystemActionExecutor`
  - 接受一个系统动作，调用共享文档客户端执行。
- `ThingStructSystemRouteBuilder`
  - 负责把 route 编码成 deep link。
- `ThingStructShortcutCatalog`
  - 注册公开的 App Shortcuts 与推荐短语。
- `ThingStructLiveActivityCoordinator`
  - 负责启动、更新、结束 Live Activity。

如果后续文件增多，可以单独做一个被 App 与 Widget Extension 共享的本地 target；在当前工程规模下，也可以先用一组共享源文件解决。

#### C. Surface 层

这一层只负责“投放”：

- Widget 视图与 timeline provider。
- Live Activity 视图。
- Controls 定义。
- 公共 AppIntents。
- Quick Actions 入口处理。
- 通知 category 与 action handler。

Surface 层不应自己写业务规则。

### 5.3 路由方案扩展

当前已有路由：

- `thingstruct://now`
- `thingstruct://today?date=YYYY-MM-DD&block=<uuid>`
- `thingstruct://templates`

建议补充并规范以下能力：

- `thingstruct://today?date=YYYY-MM-DD&block=<uuid>&source=widget`
- `thingstruct://now?source=control`
- `thingstruct://today?date=YYYY-MM-DD&block=<uuid>&task=<uuid>&source=notification`
- `thingstruct://templates?source=shortcut`

其中：

- `source` 只用于埋点与调试，不参与核心业务判断。
- `task` 仅用于 App 打开后高亮或滚动定位，不能成为新的业务真相。
- deep link parser 对未知参数保持宽容，避免旧入口失效。

### 5.4 公共 intent 与内部 intent 的边界

建议把 intent 分成两组：

#### 内部 intent

特点：

- 参数直接使用 UUID、ISO 日期等机器字段。
- 不 discoverable。
- 面向 Widget / Live Activity 的按钮绑定。
- 失败时静默容错即可。

已有的 `ToggleTaskCompletionIntent` 应继续保留在这组。

#### 公共 intent

特点：

- 参数必须是用户能理解的概念。
- 适合 Siri、Shortcuts、Spotlight。
- 有清晰的 `title`、`description` 和建议短语。
- 执行失败时需要给出更清晰的结果反馈。

例如：

- `OpenNowIntent`
- `OpenTodayIntent`
- `CompleteCurrentTaskIntent`
- `StartCurrentBlockLiveActivityIntent`
- `EndCurrentBlockLiveActivityIntent`

## 6. 各系统入口详细方案

### 6.1 Widgets

#### 6.1.1 目标

Widget 负责在不打开 App 的情况下，回答“现在应该关注什么”。

#### 6.1.2 推荐家族

在现有 `systemSmall` / `systemMedium` 基础上，建议补齐以下家族：

1. `systemSmall`
2. `systemMedium`
3. `accessoryInline`
4. `accessoryRectangular`
5. `accessoryCircular`

其中：

- `systemSmall`
  - 展示当前 block、剩余任务数、1 条高优先级任务。
- `systemMedium`
  - 展示当前 block、时间范围、剩余任务数、2-3 条任务。
- `accessoryInline`
  - 展示一句极简状态，如“Deep Work until 10:30”或“剩余 2 项”。
- `accessoryRectangular`
  - 展示当前 block + 剩余任务数 + 倒计时/结束时间。
- `accessoryCircular`
  - 优先展示一个单值指标，例如剩余任务数或完成进度。

#### 6.1.3 交互范围

Widget 上只保留以下交互：

- 切换当前展示任务的完成状态。
- 点击整体打开 App 到 `Now` 或指定 block。

不建议在 Widget 上做：

- 模板切换。
- 任意 block 创建。
- 复杂多按钮布局。

#### 6.1.4 配置能力

二期可引入可配置 widget，但不建议一期就把配置做重。

建议的可配置方向只有两类：

- 聚焦模式
  - `当前 block`
  - `剩余任务`
  - `明日模板摘要`
- 日期模式
  - `今天`
  - `明天`

如果做配置，必须用 `AppIntent` 配置，并保证默认配置无需任何设置也能成立。

#### 6.1.5 数据管线

建议继续复用现有 [ThingStructWidgetSupport.swift](/Users/timli/workspace/ThingStruct/ThingStruct/CoreShared/ThingStructWidgetSupport.swift) 的快照生成思路，但拆成两类模型：

- 通用 `Now` 查询快照。
- 按 family 裁切后的 Widget 视图模型。

这样 Live Activity、Control 与 Widget 可以共享同一份底层查询结果，而不是各自从 document 再推导一次。

### 6.2 Live Activities

#### 6.2.1 定位

Live Activity 不是“另一个 Widget”，而是“当前 block 正在进行中”的持续状态展示。

ThingStruct 最适合的 Live Activity 只有一种：

- 当前正在生效的 block 的 Live Activity。

不建议一期支持：

- 同时追踪多个 block。
- 用 Live Activity 展示整天时间线。
- 用 Live Activity 做复杂任务列表浏览。

#### 6.2.2 启动条件

建议只在以下情况下允许启动：

- 当前存在非空白的 active block。
- 当前 block 有明确的结束时间，且结束时间晚于现在。
- 用户明确从 App、Shortcut 或 Control 触发启动。

不建议自动为每个 block 默认启动 Live Activity，否则系统噪音会过大。

#### 6.2.3 展示内容

锁屏与 Dynamic Island 的内容建议固定为：

- block 标题。
- 时间范围。
- 剩余分钟数或相对结束时间。
- 当前未完成任务数。
- 1 条最重要任务的摘要。
- 一个轻交互按钮。

可用轻交互仅建议保留以下两种之一：

- 完成当前最优先任务。
- 打开 App。

#### 6.2.4 生命周期策略

一期建议采用“本地更新版”：

- 在 App 前台或用户显式触发时启动。
- 在任务完成、App 回到前台、或用户显式结束时更新。
- 到 block 结束时间自动结束，或在下次有机会同步时结束。

对于跨 block 自动切换，要明确接受一个现实限制：

- 如果不引入服务端 ActivityKit push，Live Activity 在 App 长时间不活跃时，很难保证像服务端时序产品那样无缝跨 block 滚动更新。

因此一期产品语义应保持保守：

- Live Activity 表示“当前这件事的持续追踪”。
- 它不是“永不间断的全天自动流水线”。

#### 6.2.5 数据与实现建议

建议增加一个专门的协调器：

- `ThingStructLiveActivityCoordinator`

职责：

- 根据当前 `Now` 查询结果决定是否可启动。
- 维护当前 activity ID 与对应 block ID。
- 封装 start / update / end。
- 当当前 block 已失效时，结束对应 activity。

Widget Extension 中的 `WidgetBundle` 后续可以同时承载：

- 现有 Widget。
- Lock Screen accessory widgets。
- Live Activity。
- Controls。

### 6.3 Controls

#### 6.3.1 定位

Controls 是 ThingStruct 最值得补上的“另一类控件”。

它们的职责是：

- 只做一个动作。
- 反馈尽量即时。
- 不要求用户先打开 App。

Controls 非常适合进入这些位置：

- Control Center
- 锁屏底部
- Action Button
- 其他由系统衍生的控制入口

#### 6.3.2 推荐控件集合

ThingStruct 一期建议只做 4 个 controls：

| 控件名 | 动作 | 是否改写数据 | 是否默认拉起 App | 说明 |
| --- | --- | --- | --- | --- |
| Open Now | 打开 `Now` | 否 | 是 | 最安全、最基础 |
| Complete Current Task | 完成当前最优先任务 | 是 | 否 | 最高价值写操作 |
| Open Current Block | 打开当前 block | 否 | 是 | 精准定位 |
| Start Live Activity | 启动当前 block Live Activity | 否或轻写 | 否 | 把持续追踪入口暴露到系统层 |

二期可评估是否追加：

- End Live Activity
- Open Today

不建议做的 controls：

- 直接切换模板。
- 直接新建 block。
- 直接编辑时间。
- 直接在 control 中浏览任务列表。

#### 6.3.3 设计原则

- 每个 control 必须具有单一、确定、无歧义的结果。
- 写操作尽量选择可重复点击且副作用可控的动作。
- 没有足够上下文时宁可失败返回，不要猜测用户意图。
- 控件标题与图标必须稳定，不依赖大量动态布局。

#### 6.3.4 实现策略

Controls 应直接复用公开 AppIntents，而不是重新造一套命令。

例如：

- `CompleteCurrentTaskIntent`
- `OpenNowIntent`
- `OpenCurrentBlockIntent`
- `StartCurrentBlockLiveActivityIntent`

如果项目 deployment target 低于 Controls 所需系统版本，应通过 availability gate 条件编译，而不是把整个系统动作层与 Controls 强绑定。

### 6.4 App Shortcuts / Siri / Spotlight

#### 6.4.1 定位

这部分不一定被用户称为“控件”，但对 ThingStruct 价值很高，因为它把 App 的高频动作变成系统可发现能力。

建议公开的 shortcuts：

1. 打开现在
2. 打开今天
3. 打开当前 block
4. 完成当前最优先任务
5. 开始当前 block 的实时活动
6. 结束当前实时活动

#### 6.4.2 公开策略

公开 shortcut 的条件：

- 参数可被人类理解。
- 执行结果容易预期。
- 不需要复杂确认页。

因此，不建议公开以下能力：

- 按 UUID 切换任务完成。
- 任意 block 编辑。
- 任意模板结构修改。

#### 6.4.3 实体建模建议

如果后续想把模板、日期或 block 暴露为 Shortcut 参数，再引入 `AppEntity`：

- `TemplateEntity`
- `DayEntity`
- `CurrentBlockEntity`

但一期完全可以只做“无参数”或“极少参数”的高频快捷动作，避免过早引入复杂实体查询。

#### 6.4.4 Donation 与发现性

建议：

- 在用户常用主路径上 donation 高价值动作。
- 不 donation 内部 ID 型 intents。
- 使用稳定、自然语言化的短语描述。

### 6.5 Home Screen Quick Actions

#### 6.5.1 定位

Quick Actions 成本低、收益高，特别适合 ThingStruct 这类“每天会频繁打开”的 App。

#### 6.5.2 推荐配置

静态 quick actions 建议：

1. `Now`
2. `Today`
3. `Templates`

动态 quick actions 建议最多保留 1-2 个：

- 当前 block
- 当前最优先未完成任务

动态项不宜太多，否则系统本身也不会全部展示。

#### 6.5.3 路由处理

Quick Action 触发后不应自己实现一套新导航，而应立即映射为统一 route，再交给现有的 [ThingStructStore+DeepLink.swift](/Users/timli/workspace/ThingStruct/ThingStruct/ThingStructStore+DeepLink.swift) 或其等价路由入口消费。

### 6.6 Notification Actions

#### 6.6.1 定位

ThingStruct 的数据模型里已经有 `ReminderRule` 语义，因此通知动作不应被视为“锦上添花”，而应是提醒体系的自然组成部分。

#### 6.6.2 推荐动作

每条提醒通知建议最多提供两个动作：

1. 完成当前最优先任务
2. 稍后提醒 10 分钟

点击通知主体则打开对应 block。

#### 6.6.3 设计原则

- 通知动作必须极少且清晰。
- “稍后提醒”需要有统一时长，不做复杂菜单。
- 如果目标 block 或任务已失效，动作应静默失败或打开 App，而不是误写其他内容。

### 6.7 派生覆盖面

以下位置不建议作为独立产品需求单独设计，但应纳入验收矩阵：

- StandBy
- 锁屏 accessory widget 展示
- Dynamic Island 各种尺寸
- 配对 Apple Watch / Mac 的派生 Live Activity 展示
- CarPlay 中 Live Activity 的基础展示

对这些位置的原则是：

- 一期只要求内容不失真、不崩溃、信息层级成立。
- 不为它们额外发明独立信息架构。

## 7. 分阶段实施方案

### Phase 0: 统一底层

目标：

- 抽出统一 route builder。
- 抽出统一 action executor。
- 定义内部 intent 与公开 intent 的分层。

交付：

- 系统动作枚举或等价命令抽象。
- 更细粒度 deep link。
- 公开 intents 的命名与目录结构。

验收标准：

- Widget、Quick Action、Shortcut 最终都能映射到同一路由层。
- 所有写操作都能经由共享文档客户端执行。

### Phase 1: Widget 2.0

目标：

- 维持现有桌面 Widget。
- 新增锁屏 accessory widgets。
- 保持交互式勾选能力。

交付：

- `systemSmall`
- `systemMedium`
- `accessoryInline`
- `accessoryRectangular`
- `accessoryCircular`

验收标准：

- `Now` 核心信息在桌面和锁屏都能成立。
- 锁屏小组件在超低信息密度下仍保持可读。

### Phase 2: Controls + Public Shortcuts

目标：

- 建立公开可发现的系统动作入口。

交付：

- 4 个 controls
- 4-6 个公开 shortcuts
- Siri / Spotlight 可发现性

验收标准：

- 用户无需打开 App，即可完成最常用轻动作。
- 每个 control 和 shortcut 的语义都稳定可预期。

### Phase 3: Live Activities

目标：

- 为“当前 block 正在进行中”提供持续显示能力。

交付：

- 单一类型 Live Activity
- Dynamic Island minimal / compact / expanded
- 锁屏展示

验收标准：

- 当前 block 开始后，用户可从 App 或系统动作启动 Live Activity。
- 当前 block 结束或失效后，Activity 能结束，不留下错误状态。

### Phase 4: Quick Actions + Notifications

目标：

- 补齐启动入口与提醒闭环。

交付：

- App 图标 quick actions
- 通知 actions

验收标准：

- 长按图标可直达高频页面。
- 到点提醒可以直接完成任务或稍后提醒。

## 8. 建议的文件落点

以下是建议的工程落点，不要求一次性全部建立，但路径应尽量稳定：

- `ThingStruct/CoreShared/ThingStructSystemRoute.swift`
  - 定义可序列化的系统路由。
- `ThingStruct/CoreShared/ThingStructSystemNowQuery.swift`
  - 定义系统入口共用的 `Now` 查询快照。
- `ThingStruct/SystemActions/ThingStructSystemActionExecutor.swift`
  - 统一执行系统动作。
- `ThingStruct/SystemActions/ThingStructSystemRouteBuilder.swift`
  - 统一拼接 deep links。
- `ThingStruct/AppIntents/OpenNowIntent.swift`
- `ThingStruct/AppIntents/OpenTodayIntent.swift`
- `ThingStruct/AppIntents/OpenCurrentBlockIntent.swift`
- `ThingStruct/AppIntents/CompleteCurrentTaskIntent.swift`
- `ThingStruct/AppIntents/StartCurrentBlockLiveActivityIntent.swift`
- `ThingStruct/AppIntents/EndCurrentBlockLiveActivityIntent.swift`
- `ThingStruct/AppIntents/ThingStructShortcutCatalog.swift`
  - 注册公开 shortcuts。
- `ThingStruct/ThingStructStore+QuickActions.swift`
  - Quick Actions 到统一 route 的映射。
- `ThingStruct/Notifications/ThingStructReminderCoordinator.swift`
  - 本地通知调度与 action 处理。
- `ThingStructWidgetExtension/ThingStructAccessoryWidgets.swift`
  - 锁屏 accessory widgets。
- `ThingStructWidgetExtension/ThingStructControls.swift`
  - Controls 定义。
- `ThingStructWidgetExtension/ThingStructCurrentBlockLiveActivity.swift`
  - Live Activity 视图与配置。

如果后续 source files 继续增多，可以把 `SystemActions` 与 `AppIntents` 进一步抽到一个共享 target 中；但在当前阶段，不应为了“结构完美”过早引入额外 target 复杂度。

## 9. 测试与验收矩阵

### 9.1 必要单元测试

- 当前 `Now` 查询在不同分钟点返回的当前 block 是否正确。
- `completeTopTask` 在没有未完成任务时是否安全失败。
- `toggleTaskByID` 是否只影响目标任务。
- 更细粒度 deep link 是否能稳定解析。
- 当前 block 消失后，Live Activity 是否会结束。

### 9.2 必要手工测试

- 桌面 widget 在 small / medium 下的排版。
- 锁屏 accessory widgets 的可读性。
- Widget 内交互后是否及时刷新。
- Control Center 控件点击后的成功率与反馈。
- App Shortcut 是否能通过 Siri / Spotlight 被发现与执行。
- Quick Action 是否能正确路由。
- 提醒通知动作是否会误写过期 block。

### 9.3 关键风险

- Controls 依赖较新系统版本，需要 availability gate。
- Live Activities 如果不接入服务端 push，就不适合承诺“全天自动无缝切换”。
- 系统入口写操作越多，越需要严格控制动作边界，避免用户在系统界面里误改整天计划。
- 公开 shortcuts 如果参数设计过重，会让发现性和可用性一起下降。
- 多入口并发写入仍要依赖共享文档协调，不能绕开现有文件协调逻辑。

## 10. 建议的一期最终范围

综合产品价值与实现成本，ThingStruct 的一期系统入口建议范围如下：

1. 保留并打磨现有 `Now` Widget。
2. 新增 3 个锁屏 accessory widgets。
3. 新增 4 个 controls。
4. 新增 4-6 个公开 App Shortcuts。
5. 新增 1 个“当前 block”Live Activity。
6. 新增 3 个 Home Screen Quick Actions。
7. 新增 2 个通知动作。

这个范围已经足以让 ThingStruct 从“一个有 Widget 的 App”，升级成“一个真正融入 iOS 系统层的时间结构工具”。

更重要的是，这个范围仍然能保持清晰边界：

- 所有复杂编辑继续留在 App 内。
- 所有系统入口共享同一套动作层。
- 所有系统位置都围绕 `Now` 这一核心价值展开，而不是各做各的。
