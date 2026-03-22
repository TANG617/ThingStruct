# ThingStruct Widget (含交互式) 方案

本文档定义 ThingStruct 的 Widget 设计与实现方案，目标是在 iOS 桌面小组件中展示 `Now` 的关键信息，并支持在 Widget 内直接勾选任务（交互式 Widget）。

如果本文档与 [README.md](/Users/timli/workspace/ThingStruct/README.md) 或核心语义冲突，以核心层/规格为准；Widget 只消费核心层语义，不定义新的业务规则。

## 0. 背景与目标

现有 `Now` 页面由 [NowRootView.swift](/Users/timli/workspace/ThingStruct/ThingStruct/NowRootView.swift) 渲染，数据来自 `ThingStructStore.nowScreenModel(at:)`（见 [ThingStructStore.swift](/Users/timli/workspace/ThingStruct/ThingStruct/ThingStructStore.swift)），最终由 `ThingStructPresentation.nowScreenModel(...)`（见 [ScreenModels.swift](/Users/timli/workspace/ThingStruct/ThingStruct/CoreShared/ScreenModels.swift)）从 `ThingStructDocument` 推导得到 `NowScreenModel`。

Widget 的目标：

- 展示 “现在应该关注什么”：
  - 当前生效块（标题、时间范围）
  - 任务面板摘要（剩余任务数、前 N 条任务）
  - 空态提示（沿用 `statusMessage`）
- 支持交互：在 Widget 内对展示出来的任务进行“勾选/取消勾选”。
- 刷新可靠：时间推进（跨块/跨分钟）和用户交互（勾选）后都能及时刷新。
- 改动最小：尽量复用 `ThingStructCoreShared` 的推导逻辑与模型。

非目标（一期不做）：

- 在 Widget 内进行复杂结构编辑（新建块、改时间、编辑层级、编辑模板）。
- 在 Widget 内输入文字（系统限制）。
- 多 Widget 类型的复杂配置（可二期扩展）。

## 1. Widget 展示设计

### 1.1 Widget 家族（建议）

- `systemSmall`：强调 “当前块 + 剩余任务数 + 1-2 条任务”
- `systemMedium`：强调 “当前块 + 剩余任务数 + 3 条任务”
- `systemLarge`：二期可做（展示 active chain 的层叠卡片 + 更多任务/notes）

### 1.2 信息优先级（建议）

Widget 信息密度要比 App 低，因此采用固定优先级：

1. 当前块标题（来自 `NowScreenModel.activeChain` 中 `isCurrent` 的项；没有则用 `activeChain.first`）
2. 当前块时间范围（`startMinuteOfDay` - `endMinuteOfDay`）
3. 剩余任务数（`taskSections.flatMap(tasks).filter(!isCompleted).count`）
4. 可交互任务列表（取 “当前块优先”的任务；不足再从其他块补齐）
5. 空态文字（`statusMessage`）

### 1.3 交互区域原则

- 只对“任务勾选”提供交互，避免交互过多导致误触。
- 每条任务左侧提供一个可点按的勾选按钮（交互式 widget）。
- 卡片整体点击则跳转 App（深链），进入 `Now`。

## 2. 数据共享与工程结构

### 2.1 关键约束：Widget 不能读 App 私有沙盒

当前持久化实现 [ThingStructDocumentStore.swift](/Users/timli/workspace/ThingStruct/ThingStruct/ThingStructDocumentStore.swift) 将 `document.json` 存在 App 的 `Application Support/ThingStruct/document.json`，Widget Extension 无法直接访问。

因此必须引入 **App Group** 来共享数据文件。

### 2.2 App Group 持久化方案

1. 为 App Target 与 Widget Extension Target 均开启 `App Groups` capability。
2. 设定统一的 group id，例如：`group.com.yourteam.ThingStruct`（实际以你的 bundle/team 为准）。
3. 将 `document.json` 的存储路径改为：
   - `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)`
   - `.../ThingStruct/document.json`

建议新增一个共享的 DocumentStore（供 App 与 Widget 共用），并让原来的 `ThingStructDocumentStore.live` 变成对它的薄包装。

### 2.3 一次性迁移（重要）

为了不丢用户数据，需要在 App 启动时迁移旧文件：

- 若 App Group 路径下不存在 `document.json`，但旧路径存在，则复制旧文件到新路径（或移动）。
- 迁移完成后，App 与 Widget 都只使用 App Group 文件。

### 2.4 共享代码复用（CoreShared）

Widget 需要复用：

- `ThingStructDocument`、`DayPlanEngine`、`TemplateEngine`、`ThingStructPresentation`、`NowScreenModel` 等（位于 `/ThingStruct/CoreShared`）

落地方式二选一：

- 方案 A（最直接）：把 `ThingStruct/CoreShared` 目录下的 Swift 文件加入 Widget target 的 Target Membership。
- 方案 B（更干净）：把 CoreShared 抽成 Swift Package / 共享 Framework，让 App 与 Widget 共同依赖。

考虑当前仓库已经有 `Package.swift` 指向 `ThingStruct/CoreShared`，方案 B 的心智负担更低：确保 Widget Extension 也能依赖该 package（Xcode 里添加本地 package 依赖）。

## 3. Widget 时间线与刷新策略

### 3.1 Widget Entry 建议结构

`TimelineEntry` 只携带 Widget 渲染需要的最小字段，避免把整个 document 放进 entry：

- `date: Date`（系统要求）
- `now: NowScreenModel`（或再做一次瘦身，比如 `currentBlockTitle/timeRange/tasks[]`）
- `displayTasks: [WidgetTaskItem]`（供 UI 列表使用，包含 `title`, `isCompleted`, `blockID`, `taskID`, `localDay`）

### 3.2 TimelineProvider 计算流程

Provider 的 `getTimeline`：

1. 从 App Group 读取 `ThingStructDocument`
2. `ensureMaterialized`（可选但推荐：复用 App 的行为；若模板信息存在则自动生成当天 day plan）
3. 调用 `ThingStructPresentation.nowScreenModel(document:date:minuteOfDay:)`
4. 根据 `now.activeChain` 计算“下一次必须刷新”的时间点
5. 生成 1 个 entry（多数场景足够），设置 timeline policy 为 `.after(nextRefreshDate)`

### 3.3 刷新时间点（建议）

优先使用“跨块边界刷新”，兜底用周期刷新：

- 若能找到 current chain item：
  - `nextRefresh` = 当前块 `endMinuteOfDay` 对应的实际 `Date`（同一天）
- 否则：
  - `nextRefresh` = `Date.now + 15min`
- 兜底：
  - 即使算出了 endMinute，也建议取 `min(nextRefresh, now + 15min)`，避免系统因节能不触发导致长期不刷新。

### 3.4 用户交互后的即时刷新

在 `AppIntent.perform()` 完成写入后调用：

- `WidgetCenter.shared.reloadTimelines(ofKind: "...")`

这样勾选任务后，小组件 UI 会尽快重新拉取 timeline。

## 4. 交互式 Widget 方案（核心）

交互式 Widget 使用 `Button(intent:)` + `AppIntent`。

### 4.1 支持的交互（建议一期）

- `ToggleTaskCompletionIntent`：勾选/取消勾选某条 task（需要 `date + blockID + taskID`）

可选二期：

- `ToggleFirstTaskIntent`：快速勾选当前最重要任务（减少参数、降低 UI 占用）
- `SnoozeCurrentBlockIntent`：将当前块“标记为暂停/稍后”，需要业务语义支持（当前核心模型未定义，不建议一期开）

### 4.2 AppIntent 参数设计

出于兼容性与可控性考虑，建议所有参数都用 `String`（而不是 `UUID` / 自定义类型）：

- `dateISO`: `YYYY-MM-DD`（对应 `LocalDay.description`）
- `blockID`: `UUID.uuidString`
- `taskID`: `UUID.uuidString`

Widget UI 在渲染时就能从 `NowScreenModel` 拿到 `blockID/taskID`，并直接组装 intent 参数。

建议在共享代码中提供以下解析工具：

- `LocalDay` 的 `init?(iso: String)`：用 `split("-")` 解析 year/month/day
- `UUID?` 的 `init?(uuidString:)`：系统已有

### 4.3 ToggleTaskCompletionIntent 语义

Intent 的 `perform()` 需要做到：

1. **快速**：只做本地文件 I/O + 少量纯计算，避免长耗时（系统会限制 extension 的运行时间）。
2. **幂等/可失败**：找不到 document、day plan、block、task 时不崩溃；返回成功但不改变状态，或返回可诊断的 error（取决于你想不想在 Widget 上显示失败提示）。
3. **原子写入**：尽量避免与 App 并发写导致丢数据（见第 6 节）。
4. **写入后刷新**：保存成功后触发 `WidgetCenter.shared.reloadTimelines(ofKind:)`。

建议的最小执行步骤：

1. 读取 App Group 的 `document.json`（不存在则当作空 document）
2. `ensureMaterialized`（可选但建议保持与 App 一致）
3. 找到对应 day plan 的 block 与 task
4. `task.isCompleted.toggle()` 并更新 `completedAt`
5. 保存回 App Group
6. 触发 widget reload

### 4.4 Intent 结果与“是否拉起 App”

建议：

- intent 执行成功时 **不要拉起 App**，让交互保持“就地完成”。
- 若参数非法或数据缺失，通常也不拉起 App；Widget 上只是不生效即可。

在一些极端场景（比如旧版本数据迁移未完成）可以考虑让 intent 打开 App 以完成初始化，但这会牺牲交互体验，建议仅作为 fallback（比如返回一个提示并引导用户点开 App）。

### 4.5 Widget UI 如何绑定 Intent

渲染任务列表时，每条任务用 `Button(intent:)` 触发：

```swift
Button(intent: ToggleTaskCompletionIntent(
    dateISO: item.dateISO,
    blockID: item.blockID,
    taskID: item.taskID
)) {
    HStack {
        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
        Text(item.title)
        Spacer()
    }
}
```

注意点：

- Widget 的按钮区域要尽量大，避免误触（尤其是 small size）。
- `Text` 建议 `lineLimit(1)` 或 `lineLimit(2)`，任务标题过长会影响可点按区域。

## 5. 共享“读写 + 推导”客户端（建议抽出）

### 5.1 为什么需要一个 Shared Client

交互式 widget 不只是展示，它还要写入 `ThingStructDocument`。如果 App 与 Widget 各自实现一份读写逻辑，后续很容易：

- 路径不一致（读写不同文件）
- 迁移逻辑缺失（Widget 读不到数据）
- 并发写不一致（丢更新）
- ensureMaterialized 行为不一致（Now 展示不一致）

因此建议引入一个共享的轻量客户端，例如：

- `ThingStructSharedDocumentClient`

并在 App 与 Widget 都复用它。

### 5.2 建议的 API（示意）

- `load() throws -> ThingStructDocument`
- `save(_ document: ThingStructDocument) throws`
- `mutate(_ body: (inout ThingStructDocument) throws -> Void) throws`
- `nowModel(at date: Date) throws -> NowScreenModel`
- `toggleTask(date: LocalDay, blockID: UUID, taskID: UUID) throws`

其中 `mutate` 负责：

1. 读取最新 document
2. 在内存里执行变更
3. 原子写回

这样 App 与 Widget 的“写”都走同一路径，减少并发问题。

## 6. 并发与一致性（交互式 Widget 必须考虑）

### 6.1 主要风险

Widget 与 App 可能同时写入 `document.json`：

- App 前台编辑/勾选任务并保存
- Widget 后台 intent 勾选任务并保存

若双方都采用“读 -> 改 -> 写”且没有协调，可能出现 **后写覆盖先写**，导致丢失更新。

### 6.2 建议：NSFileCoordinator 协调读写

推荐在 Shared Client 内部对 `document.json` 使用 `NSFileCoordinator`：

- `coordinate(readingItemAt:)` 读取
- `coordinate(writingItemAt:options:)` 写入

这样系统会在 App 与 Extension 之间做文件访问协调，避免同时写导致的竞态。

### 6.3 写入策略：在协调区内重新加载再写

更稳妥的策略是：写入时在“写协调区”内重新加载 document，再应用变更并写回，确保写入基于最新版本。

如果未来要进一步增强一致性，可以给 `ThingStructDocument` 增加一个 `revision`（自增 Int）或 `lastModifiedAt`，用于：

- App 前台检测“外部文件已更新”时提醒/刷新
- 调试并发问题

## 7. App 侧配套改动（交互式 widget 的闭环）

### 7.1 App 保存后触发 Widget 刷新

在 App 里，任何导致 `persistDocument()` 的写操作后，建议补一行：

- `WidgetCenter.shared.reloadTimelines(ofKind: ...)`

这样 App 内的编辑也能尽快同步到 Widget。

参考位置：`ThingStructStore.persistDocument()`（见 [ThingStructStore.swift](/Users/timli/workspace/ThingStruct/ThingStruct/ThingStructStore.swift)）。

### 7.2 App 被 Widget 修改后的“刷新策略”

Widget 的 intent 写入会改变磁盘文件，但 App 内存中的 `store.document` 不会自动更新。

一期建议的低成本策略：

- 在 `scenePhase == .active` 时检查并 reload document（或直接 reload）
- 或在 App 响应深链打开时 `reload()` 一次，确保从 Widget 进入 App 时数据一致

更强但更复杂的策略（二期）：

- 使用 `NSFilePresenter` 监听 App Group 文件变更并增量刷新 store

## 8. 深链跳转（Widget -> App）

建议定义 URL scheme，例如 `thingstruct://`：

- `thingstruct://now`：打开 Now tab
- `thingstruct://today?date=YYYY-MM-DD&block=<uuid>`：打开 Today，并定位到 block

Widget 侧：

- 整个 widget 用 `.widgetURL(URL(string: "thingstruct://now"))`

App 侧：

- 在 `ContentView` 或 `AppShellView` 加 `.onOpenURL`，解析后设置：
  - `store.selectedTab = .now/.today/...`
  - 需要时调用 `store.selectDate(...)` / `store.selectBlock(...)`

## 9. 落地步骤（建议顺序）

1. 新建 Widget Extension target（WidgetKit + SwiftUI）。
2. 为 App 与 Widget 都开启 App Groups，并确定 group id。
3. 抽出 Shared Client：
   - 统一 App Group 路径
   - 实现迁移：旧路径 -> App Group
   - 读写使用 `NSFileCoordinator`（推荐）
4. 让 App 的 `ThingStructDocumentStore.live` 改为使用 Shared Client 的路径/实现。
5. Widget 实现：
   - Provider：`load -> nowModel -> timeline`
   - View：small/medium 布局
6. 交互式 intent：
   - `ToggleTaskCompletionIntent`：调用 Shared Client 的 `toggleTask`
   - `perform()` 后 reload timelines
7. App 侧配套：
   - 保存后 reload widget timelines
   - onOpenURL 深链切 tab
   - 在激活时 reload（一期建议）
8. 补齐测试与 QA：
   - 共享存储读写测试
   - toggle 行为测试（包含 `completedAt`）
   - 手动验证并发与刷新

## 10. QA 清单（手动验证）

- 首次安装（无文件）：Widget 能显示 placeholder/空态，不崩溃。
- 打开 App 初始化后：Widget 能在 1-2 次刷新内展示正确的当前块与任务。
- Widget 勾选任务：
  - 立即在 Widget 中反映剩余数变化
  - 打开 App 后状态一致
- App 内勾选/编辑后：Widget 能刷新反映变化。
- 跨块边界：到达 `endMinuteOfDay` 附近能自动刷新显示新块。
- 并发场景（App 前台 + Widget 勾选）：无崩溃，数据不丢失（或至少不出现明显回滚）。
