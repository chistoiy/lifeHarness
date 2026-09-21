# LifeHarness UI 组件规范（组件词典 · V1.0 · 2026-09-21）

> **用途**：建立产品负责人 ↔ 开发（含 AI agent）的 UI 共同语言。微调指令直接引用「编号+中文名」（如「LH-S01 事件详情弹层 标题字号+1」「LH-K03 胶囊筛选 选中态换成描边」），即可精准定位到原型 CSS 与 Flutter 代码，无需描述性猜测。
> **三源同步铁律**：原型 `prototype/index.html` 仍是 UI 唯一事实源；本规范是其**索引**。**改原型必须同步更新对应规格卡；新 UI 组件先登记规格卡（编号+锚点）再进入开发**（并入交接文档铁律）。
> 锚点格式：`文件:行` 为 2026-09-21 快照，行号漂移时以类名/函数名检索为准。

## 〇、指令用语（术语表）

| 中文术语 | 英文/代号 | 含义（禁止用其他叫法指代） |
|---|---|---|
| 卡片 | card | 描边圆角白底容器（LH-C01） |
| 渐变主卡 | hero card | 主题渐变大卡（LH-C02） |
| 弹层 | sheet | 底部滑出面板 showModalBottomSheet |
| 胶囊 | pill / chip | 全圆角小标签，含筛选态（LH-K03） |
| 色点 | dot | 5px 状态圆点（LH-K05） |
| 把手 | grip | 编排 ⠿ 拖动钮（LH-K04 变体） |
| 圆钮 | mv-btn | ↑↓ 微调圆钮（LH-K04） |
| 速记列 | rail | 块视图右侧分类列（LH-K10） |
| 分节卡 | section card | 模板结构化正文卡（LH-C04） |
| 空态行 | empty row | 虚线补录占位行（LH-L04） |
| 心情行 | mood row | 7 表情点选行（LH-K06） |
| 顶栏行 | header row | 页首日期+工具行（LH-K08 宿主） |
| 胶囊提示 | toast | 全局深色胶囊 SnackBar（LH-T01） |
| 滚轮 | wheel | 就地内嵌/弹层式数值滚轮（LH-K07） |

## 一、LH-T 提示类

### LH-T01 胶囊提示 AppToast
| 项 | 值 |
|---|---|
| 原型锚点 | `#toast`（index.html L2000 · toast() L2137） |
| 代码锚点 | `core/theme/app_theme.dart` snackBarTheme（L74 附近）；调用统一走 `shared/widgets/ui_kit.dart` `AppToast.show` |
| 规格 | 底 0xE60F172A · 白字 12.5 w600 · 圆角 28 · 宽 320 · floating · 默认 1.5~2.2s |
| 可调旋钮 | 底色/圆角/宽度/字号/时长（改一处全局生效，禁止页面私调样式） |
| 现状 | 主题层已统一；调用点 40 处/19 文件，后续批次路过逐步替换为 AppToast.show |

## 二、LH-C 卡片类

### LH-C01 描边卡 card
- 原型 `.card`；代码 `context.cardDecoration`（app_theme.dart:85）
- 规格：tokens.card 底 · 圆角 tokens.cardRadius · 描边 tokens.cardBorder
- 用法：所有内容卡基线；变体=内 padding 12/16

### LH-C02 渐变主卡 hero card
- 原型：问候卡/心情月历卡渐变头卡；代码：`_HeroCard`（dashboard_page.dart:350 附近）、journal 心情月历卡
- 规格：tokens.gradient · r24 · tokens.cardShadow · 白字
- 可调旋钮：圆角/阴影/内距；**渐变色本身属主题令牌，改动=换主题层，不走微调**

### LH-C03 玻璃子卡 mini glass
- 原型：渐变卡内半透明小格；代码 `_MiniGlass`（dashboard_page.dart:500）
- 规格：white12 · r16 · 标题 white70 11px

### LH-C04 分节卡 section card（V1.28 新增）
- 原型：日记结构化分节；代码 `diary_edit_page.dart` 分节渲染（sec-$i key）
- 规格：LH-C01 底 + 节标题 w800 + 独立 TextField（hint=占位语）
- ui_kit 已抽 `SectionCard` 原语，新页面分节一律复用

### LH-C05 INS 卡片 ins card
- 原型：INS 风日记分享卡；代码 `journal/presentation/widgets/ins_card.dart:9`
- 变体：DiaryCard（❤️⭐回望数）

## 三、LH-S 弹层类（sheet 家族）

**公共骨架**：showModalBottomSheet · isScrollControlled · 内边距 LTRB(16,14,16,24) · 标题 15 w900 · 行卡=LH-C01+选中描边 accent 2px+✓

| 编号 | 名称 | 原型 | 代码锚点 |
|---|---|---|---|
| LH-S01 | 事件详情弹层 | sheetEventDetail | event_detail_sheet.dart:14 `showEventDetailSheet`（查看/开始/结束/✎编辑/删除） |
| LH-S02 | 标记块详情弹层 | sheetBlockDetail | event_detail_sheet.dart:201 `showBlockDetailSheet`（取消标记） |
| LH-S03 | 统一添加弹层 | sheetTimePick | time_pick_sheet.dart:19 `showTimePickSheet`（日期+时分滚轮+时长 chips+分类+备注·四视图共用） |
| LH-S04 | 待办新建/编辑弹层 | sheetAddTask / sheetTask | todo_edit_sheet.dart:14/:24（两型·提醒·番茄·关联分类） |
| LH-S05 | 日期滚轮弹层 | sheetDatePick | wheel_date.dart:15 `showWheelDatePick`（年月日三列） |
| LH-S06 | 日记模板管理弹层 | sheetDiaryTpl | diary_edit_page `_openTplSheet`（行 key tpl-row-*，删除 tpl-del-*，新建 tpl-new） |
| LH-S07 | 新建模板弹层 | sheetDiaryTplEdit | diary_edit_page `_openTplCreateSheet`（tpl-name / tpl-sec-* / tpl-save） |
| LH-S08 | 上级分组选择弹层 | sheetCatParent | category/settings 内 |

- 可调旋钮：标题字号、行卡高度、选中描边色——**弹层内字段结构变更走原型确认门**。

## 四、LH-K 控件类

| 编号 | 名称 | 原型 | 代码锚点 | 规格要点 / 可调旋钮 |
|---|---|---|---|---|
| LH-K01 | 渐变悬浮钮 FAB | .fab | core/widgets/grad_fab.dart:9 GradFab | 渐变+白＋；尺寸/位置 |
| LH-K02 | FAB 行卡 | fabGo 行 | grad_fab.dart:66 FabActionCard | 快捷记录展开项（首页/待办共用） |
| LH-K03 | 胶囊筛选 chip | .chip/.chip-on | ui_kit `PillChip`（journal 全部/列表/INS、待办筛选同源化） | 选中=accent 底白字；未选=卡底描边；字号/圆角/间距 |
| LH-K04 | 编排圆钮 mv-btn | .mv-btn | dashboard_page.dart:318 `_ArrowBtn` | 28 圆底+描边；↑/↓/⠿(grip 变体)；尺寸/间距 |
| LH-K05 | 状态色点 dot | 三色点 | calendar 三色（完成 34D399/计划 6366F1/进行中 F43F5E）+ 待办象限色点 + ui_kit `DotLegend` | 4~5px；配色属语义色，改动需全局检索 |
| LH-K06 | 心情表情行 | moodRow | ui_kit `MoodRow`（dashboard `_MoodCard` / diary 同源） | 7 emoji 23~24px · 选中 AnimatedScale 1.25 未选 45% 透明 |
| LH-K07 | 滚轮选择器 | WHEELS | wheel_time.dart:8 InlineWheelTime · wheel_date.dart | 就地内嵌铁律（禁两段式）；中心行 19px 主题色 |
| LH-K08 | 视图切换钮 | 顶栏单钮 | calendar_page `_TimeHeader` PopupMenuButton | 36 圆角 12 accent12 底；字=当前视图「轴/块/日/周」 |
| LH-K09 | 「今」回今天钮 | .today-btn | `_TimeHeader` isToday 分支 | 非今天才显；36 accent12 底 |
| LH-K10 | 分类速记列 | rail 列 | grid_day_view.dart 右列（64 宽） | 选中=标记/未选=记到此刻；行高 34 r12 |
| LH-K11 | 时长快捷 chips | 添加弹层 | time_pick_sheet 内 | 0/15/30/1h/2h |
| LH-K12 | 待办勾选框 | .chk | todo_list_view `_TodoTile` | 20 方角 6 · 完成=accent 底白✓ |

## 五、LH-L 列表条目类

| 编号 | 名称 | 原型 | 代码锚点 | 规格要点 |
|---|---|---|---|---|
| LH-L01 | 待办条目 | .task-row | todo_list_view `_TodoTile` | chk+标题+⏰/#tag/🔁 信息行+象限色点 |
| LH-L02 | 日程条目卡 | dashEvents | dashboard `_TodayScheduleCard` | 左 4px 色条+标题+等宽起止时间 |
| LH-L03 | 日记条目卡 | p-records 列表 | journal_page 条目卡 | 日期+周几+内容预览+标签（一天多篇=同日多卡·第 N 篇） |
| LH-L04 | 空态补录行 | 虚线行 | ui_kit `EmptyDashRow`（轴视图/日视图/记录页同源化） | 描边 outlineVariant · r16 · 居中灰字 · 点击=补录 |
| LH-L05 | 时间轴行 | 轴视图行 | calendar_page `_AxisView.rail` | 左 42 时间列+9 圆点+竖线（46 位）+内容卡 |
| LH-L06 | 功能宫格块 | 宫格 | dashboard `_AllModulesCard` | 44 emoji 底块 r14+名 11px+版本角标 7px · 未建 45% 透明 |

## 六、微调指令写法（示例）

- 「**LH-T01** 时长统一 2s」→ 只改 ui_kit/theme 一处。
- 「**LH-S03** 添加弹层备注框加高」→ 定位 time_pick_sheet.dart。
- 「**LH-K03** 和 **LH-L04** 的圆角统一 20」→ 两处原语一次改完，全 app 生效。
- 「所有**渐变主卡**阴影减轻」→ 只动 LH-C02（tokens.cardShadow 引用点核查）。
- 未登记的新样式需求 → 我先补规格卡编号（含原型修改）再开发。

## 七、ui_kit 原语清单（本批已抽 · lib/shared/widgets/ui_kit.dart）

`AppToast.show` / `PillChip` / `DotLegend` / `MoodRow` / `SectionCard` / `EmptyDashRow`
——新代码必须优先复用；存量调用点按两档流程「路过替换」，不做专项重构批。
