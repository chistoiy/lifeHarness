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

### LH-C06 书籍封面卡 book cover card（V1.30 新增）
- 原型：`prototype/index-bookshelf.html` `.bk-cov` + `.bk-pbar.has-pct`（书架四视图 / 工作台轨道 / 书单详情共用）
- 规格：色板封面（书脊渐变 + 左上高光 + 底部作者名）· 状态角标见 LH-K17 · **百分比写在进度条右端**（填充 ≥62% 用白字，否则灰字）· **不显示页数与「笔记 N 条」**
- 列数：封面墙 3/4/5 列可调（`read.wallCols`），轨道固定 106px（LH-L07）

### LH-C07 沉浸头图卡 immersive hero（V1.30 新增）
- 原型：书籍详情页 `.bd-bg`（封面模糊 26px + saturate 1.5 作背景，内容浮于其上）
- 规格：书名 19px / 作者·译者 / 出版社·出版日期 / 四枚信息芯片（LH-K15）· 右侧 92×132 封面点进资料页 · 页内**不放动作行**（动作在 LH-K13）

### LH-C08 完成度方块卡 habit tile（V1.31 新增）
- 原型：`prototype/index_habitcheck.html` `hbTile()`（习惯主页第三视图「方块 · 完成度」）
- 规格：卡内=完成度环（12px 描边环 + 中心百分比或达成数）+ **7 日点阵**（合格格可点就地打卡，非计划日渲染 `span` 不给假可用性）+ 待打卡时刻行 + 补记角标（`ring-amber`）；**不放大号打卡按钮**，点卡本体进详情
- 与 LH-L09（紧凑行）、LH-L01（待办条目）同属「一行/一格多态」家族，尺寸与圆角对齐 LH-C01

### LH-C09 月历打卡格 habit day cell（V1.31 新增）
- 原型：`hbMonthHtml()`（详情页近 30 天 / 补卡弹层 / 日期速览弹层**三处共用同一函数**）
- 规格：`h-[38px]` 圆角格 = **日期数字（必显）** + 状态圆点（达成/带数值时显数值短码）+ 选中 `ring-2`；补记日加 `ring-amber`；翻月 ‹ › 与「回本月」钮在格区上方一行
- 规则：任何「看某天有没有打卡」的场景一律用本组件，**禁止再用无日期的 30 格矩阵**（用户反馈「看不到日期，不直观」）

### LH-C10 工具控制盘 hero（V1.47 新增）
- 原型：`prototype/index-kits.html` `#kitHero`（小工具首页顶部主卡，复用 LH-C02 渐变皮肤）
- 规格：上排 **4 枚数据位**（累计使用 / 近 7 天 / 收藏 / 已装插件）· 点数据位直达对应屏 · 中排 4 枚功能入口（收藏 / 最近 / 插件 / 统计，线性 SVG）· 下排「数据位 ⇄」换防 +「清空足迹」（二次确认 HG-D2）
- 规则：**卡内数字一律 `KIT_METRICS` 从足迹流水实算，禁写死**（HG-E1）；数据位取值与顺序可配（LH-S24），偏好落本机 `lh_kits_v1` 随备份导出

### LH-C11 工具卡 tool tile（V1.47 新增）
- 原型：`kitRenderHome()` 首页四列网格 + `#kitRecentStrip` 最近使用行
- 规格：圆角卡 = 图标 + 名 + **使用次数角标**（0 次显示「未用过」）；收藏项左上 ★；单击进详情、**长按切收藏**
- 图标：**一律线性 SVG**（`kitSvg(key)` 从 `KIT_ICOS` 取，尺寸 `1em` 随容器字号）；`TOOLS[k].ic` 的 emoji 仅作历史字段，不再参与渲染（用户拍板 2026-09-27）

### LH-C12 时间账本卡族 time stats cards（V1.52 新增）
- 原型：`index.html` `p-timeStats`（`renderTimeStats` / `tsClock` / `tsHeat` / `tsStack`）；
  代码：`time_stats_page.dart`（`/time-stats` · 时间页顶栏柱状图标 + 仪表盘分布卡双入口）
- 组成：四档分段（日/周/月/年）+ `‹ 期间 ›` 翻页 · 渐变 hero（总时长/日均/覆盖率/段数/计时中/未记录）·
  时钟盘面（24h 极坐标扇区=每段块 · 红线=当前时刻）· 单日/单月时长对比面积图 · 满高底轨堆叠柱 ·
  热力图（按日深浅 · 少→多图例）· 总时长环形（含「未记录」灰弧 · 分母=天数×1440）· 分类排行（次数/占比/进度条/环比）
- 规格：每卡标题行右侧 ∧/∨ 可折叠（`_fold` 内存态）· 全部 CustomPainter 自绘零图表依赖 · 聚合一律走 `block_ops`（`minutesByCat`/`totalMinutes`/`deltaPct`）

## 三、LH-S 弹层类（sheet 家族）

**公共骨架**：showModalBottomSheet · isScrollControlled · 内边距 LTRB(16,14,16,24) · 标题 15 w900 · 行卡=LH-C01+选中描边 accent 2px+✓

| 编号 | 名称 | 原型 | 代码锚点 |
|---|---|---|---|
| LH-S01 | 事件详情弹层 ~~sheetEventDetail~~ | **V1.52 退役**：并入 LH-S03 统一弹层（点已有事件=与新增同一个弹层） | 原 `event_detail_sheet.dart` 已删除 |
| LH-S02 | 标记块详情弹层 ~~sheetBlockDetail~~ | **V1.52 退役**：「取消标记」独立层撤销，删除动作进 LH-S03 底部「删除」+ SnackBar 撤销 | 同上 |
| LH-S03 | **统一添加 / 编辑弹层**（V1.52） | sheetTimePick | `showTimePickSheet(context, ref, {day, startMin, block, event})`：日/时/**分（1 分一档 · CupertinoPicker looping）**三列滚轮 ×2 组（起止 · 结束含日轮支持跨天）· 一级分类**每行 6 个**+子分组自适应 · 备注 · 底部按形态=「继续添加+添加」/「删除+保存修改」· 计时中额外「■ 结束计时」· 已结束额外「✂ 对半拆分 / ⇧ 与上一个合并 / ⇩ 与下一个合并」（间隙>30 分置灰）· 破坏性操作 SnackBar 带撤销 · 标签与「管理 ›」并入一级分组标题行 |
| LH-S04 | 待办新建/编辑弹层 | sheetAddTask / sheetTask | todo_edit_sheet.dart:14/:24（两型·提醒·番茄·关联分类） |
| LH-S05 | 日期滚轮弹层 | sheetDatePick | wheel_date.dart:15 `showWheelDatePick`（年月日三列） |
| LH-S06 | 日记模板管理弹层 | sheetDiaryTpl | diary_edit_page `_openTplSheet`（行 key tpl-row-*，删除 tpl-del-*，新建 tpl-new） |
| LH-S07 | 新建模板弹层 | sheetDiaryTplEdit | diary_edit_page `_openTplCreateSheet`（tpl-name / tpl-sec-* / tpl-save） |
| LH-S08 | 上级分组选择弹层 | sheetCatParent | category/settings 内 |
| LH-S09 | 书籍操作弹层 | sheetBookOps（index-bookshelf.html） | 批3 规划 `features/reading/widgets/book_ops_sheet.dart`；标题=书名，行=线性图标+文字，动作集见计划 §3.4 |
| LH-S10 | 摘录操作弹层 | sheetQuoteOps | 收藏/编辑/转日记/转待办/转笔记/复制/删除七行 |
| LH-S11 | 摘录录入表单（**全模块唯一一张**） | sheetQuoteEdit | 书→章节下拉（取该书目录）+页码→创建时间→原文→想法→识图/加图/剪贴板→颜色分类→标签多选；换书三处联动 |
| LH-S12 | 计时明细弹层 | sheetSess | 逐条 日期/时长/起始页→结束页 行内可改+删除+补记；改动回算聚合与轨迹 |
| LH-S13 | 阅读轨迹弹层 | sheetTrack | 复用 bsTrack（柱状+时段分布+里程碑），顶部「改明细」跳 LH-S12 |
| LH-S14 | 目录导入弹层 | sheetTocImport | 文件解析（演示）+ **粘贴文本实时解析**→预览「N 部分/M 节」→确认替换 |
| LH-S15 | 书架维度 / 排序二级面板 | sheetShelfDim / sheetShelfSort | 触发条点开；8 维度 / 6 排序 |
| LH-S16 | **习惯记量弹层**（V1.31） | sheetHabitLog | 打卡并记量；组习惯展开**逐子项一行**（名 + 单位 + 目标 + 步进 + 数值滚轮）；今日已打卡时标题=「修改今日记录量」；含「清空 / 撤销今日」；时刻用**就地内嵌滚轮**（LH-K07） |
| LH-S17 | **补卡弹层**（V1.31） | sheetHabitBackfill | 上半=共用月历（LH-C09，日期 + 达成圆点，**可跨月多选**）；中部=习惯 chips 多选；下部=子项数值行 + 补记时刻滚轮 + 「补卡计入连续天数」开关；底部=**补卡记录列表**（每行 日期·习惯·量 + 删除钮，删除即撤销该次补卡并回退连续与统计） |
| LH-S18 | **日期速览弹层**（V1.31） | sheetHabitDay | 顶栏日期点开；共用月历切日 + 当日「已达成 / 待打卡 / 补记」明细 + 「去补卡」跳 LH-S17 并预选该日 |
| LH-S19 | **自动达成待确认弹层**（V1.31） | sheetHabitPend | 逐条 来源 / 时间 / 值 + 「确认」「驳回」；顶部「全部确认」（id=hpAll）；驳回不写流水只留状态 |
| LH-S20 | **字典管理弹层**（V1.31） | sheetHabitMgr（cat / unit） | 分类与记录量单位**同一套组件两种 kind**：行内改名 + ↑↓ 排序 + 删除前引用守卫（>0 引用拒绝并弹「迁移到…」）+ 新增行；**替代原生 `<select>` 死枚举** |
| LH-S21 | **习惯模板库弹层**（V1.31） | sheetHabitTpl | 12 张模板卡（含 1 张组模板）· 点「使用」= 预填新建表单，**不直接落库** |
| LH-S22 | **习惯分享长图弹层**（V1.31） | sheetHabitShare | 月度成就 + 热力图 + 记录量长图预览 · 复制 / 保存（与阅读书单长图共用导出通道） |

| LH-S23 | **插件安装向导弹层**（V1.47） | sheetKitInstall（index-kits） | 六步 渠道→来源→下载→校验→权限→完成；校验步含 **SHA-256 + minisign 双验失败** 拒绝分支与黑名单提示；「重来」回第一步 |
| LH-S24 | **数据位配置弹层**（V1.47） | sheetKitCfg | **固定预览 + 草稿保存制**（HG-D3）：未点「保存」不写 `KITS.hero`；候选指标 chips 单选 + ↑↓ 调序 |
| LH-S25 | **沙箱运行弹层**（V1.47） | sheetKitSandbox | 标题带插件名；私有目录 / 堆隔离 / `plugin_<id>` 表空间说明 + 就地运行演示页 + 权限逐条授予状态 |
| LH-S26 | **自绘选色弹层**（V1.47 真机轮） | sheetKitColor（index-kits） | 规划 `features/tools/widgets/color_sheet.dart` | 替代 `<input type=color>`：当前色预览 + 16 色板 + **色相/饱和/明度三滑杆**（色相条为渐变轨）+ HEX/rgb/hsl 解析框 + 取消/确定；**从预设或解析进入时保留精确 HEX**（`KCC.exact`），仅拖动滑杆才由 HSL 回算，避免 ±1 色偏 |
| LH-S27 | **专版日期滚轮弹层**（V1.47 真机轮） | sheetKitDate（index-kits） | 复用 LH-S05 三列滚轮基础设施 | 替代 `<input type=date>`：年 1970~2040 / 月 12 / 日**按年月自动收放天数**；顶部实时「YYYY 年 M 月 D 日 · 周 X」；确定后回填并触发所属工具重算 |
| LH-S28 | **抽签选项与数据弹层**（V1.47 真机轮） | sheetWheelCfg（index-kits） | 规划 `features/tools/widgets/wheel_cfg_sheet.dart` | 工具主屏只留轮盘与结果，**数据管理整体收进设置弹层**：套 chips（≤8）+ 改名/新建/删除 + 批量粘贴 + 选项权重行（−/＋/↑↓/删）+ 恢复默认；弹层可滚动、右上「完成」关闭 |

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
| LH-K13 | **顶栏页内动作图标钮**（V1.30） | `#hdrActs`（index-bookshelf） | 二级页顶栏右侧·36 圆·线性图标 19px·**只用图标不用文字**·带 title/tooltip；计时中该钮转 grad 高亮。规则：二级页高频动作上此钮，低频动作仍进 LH-S09 操作弹层 |
| LH-K14 | **图标入口条**（V1.30） | `#recHub` 五枚 / `#shTools` | 36 高·圆角 12·bg-white/15·图标 17px 居中·**无文字标签**；书架=书脊架(shelf)、设置=齿轮(cog)、书单=列表(list)，禁用形似太阳的旧 gear |
| LH-K15 | **可点信息芯片**（V1.30） | 详情页「4h32m」「62%」 | 12px 线性图标+数值+虚线下划线+title；点=开对应弹层（LH-S12 / 记进度）。规则：可改的数值不做成纯文本 |
| LH-K16 | **就地编辑行**（V1.30） | 目录编辑态 `.toc-ed` / 计时明细行 | input 直接嵌在行内改（不跳二级页）；行右侧 24×24 圆钮 ↑ ↓ ⠿ 与删除；退出编辑自动清理空条目 |
| LH-K17 | **可点状态角标**（V1.30） | 封面右上 `${b.st}` 角标 | 点=按 在读→想读→已读→弃读 循环（`stopPropagation` 不误触父级跳转）；切已读补 100% 与 `end` |
| LH-K18 | **下拉筛选条（成对）**（V1.31） | 习惯主页 `#hbFilterBar`（状态 / 分类） | 两个**等宽窄下拉**（非平铺 chips）；选项来自字典表（分类=habit_dict）；选中值显示在钮面；与 LH-K03 胶囊互斥使用 |
| LH-K19 | **视图三态循环钮**（V1.31） | `HB_VIEWS` + `hbViewT()` | 列表 · 明细与操作 → 紧凑 · 一行一个 → 方块 · 完成度；钮面=当前视图短名；复用 LH-K08 外形，**多态时循环而非弹菜单**；偏好本地记忆 |
| LH-K20 | **热力图（三模式）**（V1.31） | `hbHeatRender` + `hbHeatPick` | 17 周 × 7 格、格 11px 圆角 3px；模式=达成数（emerald 五档）/ 记录量（按当期最大值归一）/ 主要时段（四色 violet→sky→amber→indigo）；**图例与说明文字随模式切换**；`title` 与点按 toast 给出当日明细与补记次数 |
| LH-K21 | **时段分布柱**（V1.31） | `hbTimeAgg` + `HB_BKS` | 四段（凌晨 0-5 / 上午 6-11 / 下午 12-17 / 晚上 18-23）柱 + 最常时段文案；数据源=`check_at`，补记时刻同权 |
| LH-K22 | **顶栏「设置 + 搜索」双图标对**（V1.31） | `hbHdrBtn()` | 习惯主页顶栏=设置齿轮 + 搜索；**添加动作不占顶栏**（走 FAB 与列表尾虚线行）；沿用 LH-K13 尺寸与线性图标 |
| LH-K23 | **里程碑条**（V1.31） | 详情页 `#hdRoot` 内里程碑卡 | 7/21/66/100 天节点横滑，已过点亮、未到灰；点已过节点 toast 达成日期 |
| LH-K24 | **权重扇区轮盘**（V1.47） | `wheelDraw()`（index-kits） | 规划 `features/tools/widgets/weighted_wheel.dart` | `conic-gradient` 按权重累计角铺色 + SVG 文字层；**下半区标签自动 +180°** 保持可读；权重 1–9 步进、扇区标占比%；多套数据（≤8 套）各带历史 |
| LH-K25 | **色相环配色盘**（V1.47） | `cmpWheel()` | 规划 `hue_ring.dart` | 6° 一段的 SVG 色相环（饱和/明度随主色）+ 方案扇区白/黑描边 + 外圈可点圆点（点=复制该色）；中心写方案名与主色 HEX；底部「一键复制全套」 |
| LH-K26 | **图片取色舞台**（V1.47） | `#cpkStage>canvas` | 规划 `image_color_picker.dart` | canvas 真实像素读取（`getImageData`）· 100–400% 缩放滑杆 · 十字准星开关 · 结果芯片（HEX/RGB/HSL 可复制、可存配色笔记）；最近取色去重、长按移除 |
| LH-K27 | **全量程滚动尺面**（V1.47） | `#rulerBox`（52vh 滚动卡） | 规划 `ruler_scale.dart` | 默认取 `max(screen.w,screen.h)` 的**长边**并铺满整条量程（短边可切）；主刻度横贯细线；倍率校准以银行卡 8.50cm 为基准，持久化 |
| LH-K28 | **提词舞台层**（V1.47） | `#tpStage` | 规划 `teleprompter_stage.dart` | 全屏覆盖层：rAF 按 px/s 滚动、首尾回绕；横向=整体 rotate 90° 并交换宽高；LED 模式=点阵遮罩 + 扫描线 + 发光字；**默认 `display:none`，仅去 `.hidden` 时显形**（截图曾暴露常驻遮罩） |
| LH-K29 | **线性图标原语 kit-ico**（V1.47） | `KIT_ICOS` + `kitSvg()`（index-kits） | 规划 `lib/shared/widgets/lh_icons.dart` 图标表 | `svg.kit-ico{width:1em;height:1em;fill:none;stroke:currentColor;stroke-width:1.7;round}`；**新增工具/分类只往表里加键**，不在 UI 处内联画路径；缺键回落 `_def` 而非 emoji；分类名与图标解耦（`cat-网络` 这类键查表，名字本身保持纯词）；**齿轮用标准齿形路径，禁用形似太阳的辐条式画法**（沿用 LH-K14 旧口径） |

| 编号 | 名称 | 原型 | 代码锚点 | 规格要点 |
|---|---|---|---|---|
| LH-L01 | 待办条目 | .task-row | todo_list_view `_TodoTile` | chk+标题+⏰/#tag/🔁 信息行+象限色点 |
| LH-L02 | 日程条目卡 | dashEvents | dashboard `_TodayScheduleCard` | 左 4px 色条+标题+等宽起止时间 |
| LH-L03 | 日记条目卡 | p-records 列表 | journal_page 条目卡 | 日期+周几+内容预览+标签（一天多篇=同日多卡·第 N 篇） |
| LH-L04 | 空态补录行 | 虚线行 | ui_kit `EmptyDashRow`（轴视图/日视图/记录页同源化） | 描边 outlineVariant · r16 · 居中灰字 · 点击=补录 |
| LH-L05 | 时间轴行 | 轴视图行 | calendar_page `_AxisView.rail` | 左 42 时间列+9 圆点+竖线（46 位）+内容卡 |
| LH-L06 | 功能宫格块 | 宫格 | dashboard `_AllModulesCard` | 44 emoji 底块 r14+名 11px+版本角标 7px · 未建 45% 透明 |
| LH-L07 | 封面横向滑动轨道 | `.bk-rail`（index-bookshelf） | 批3 规划 reading 工作台 | `grid-auto-flow:column`·列宽 106·`scroll-snap-type:x proximity`·左右各 20 出血（露半张作滑动暗示）·按**最近一次阅读**倒序·卡内复用 LH-C06 |
| LH-L08 | 计时明细行 | `#ssList .card` | 批3 规划 LH-S12 内 | 上行=序号+日期+删除圆钮；下行=时长(分钟)+起始页→结束页；行内 input 直接改（LH-K16） |
| LH-L09 | **习惯紧凑行**（V1.31） | `hbCardMini()` | 批1 规划 `features/habit/widgets/habit_tile_row.dart` | 一行一个：图标+名+迷你 7 日点阵+完成度百分比+打卡小钮；高度 ≤46；无记录量摘要（信息密度优先给完成度） |
| LH-L10 | **打卡流水行**（V1.31） | `hbFlowHtml()` | 详情页流水卡 | 日期 + **时刻**（HH:MM 等宽）+ 值与单位 + 来源标签（手动/番茄/阅读计时/日程/待办/补记）+ 心得预览；右垃圾桶=撤销该日；补记日 `ring-amber` 角标 |
| LH-L11 | **补卡记录行**（V1.31） | `#bfLogList` | LH-S17 底部 | 日期 · 习惯名 · 值 · 「补记」标签 + 删除圆钮；**删除=撤销该次补卡**（含子项与时刻），列表空时整卡隐藏 |
| LH-L12 | **插件条目行**（V1.47） | `plgRenderCenter()`（index-kits） | 图标 + 名 + 来源标签（本地 / GitHub）+ 版本 · minHost · 体积 · 权限 n/m + 已用次数；右箭头进详情；启停联动首页「拓展」分组 |
| LH-L13 | **工具足迹行**（V1.47） | `renderKitsStats()` 明细 | 日期 + 工具名 + 分类；与 17×7 热力格点选联动；清空走二次确认（HG-D2），清空后全部指标归零重算 |

## 六、微调指令写法（示例）

- 「**LH-T01** 时长统一 2s」→ 只改 ui_kit/theme 一处。
- 「**LH-S03** 添加弹层备注框加高」→ 定位 time_pick_sheet.dart。
- 「**LH-K03** 和 **LH-L04** 的圆角统一 20」→ 两处原语一次改完，全 app 生效。
- 「所有**渐变主卡**阴影减轻」→ 只动 LH-C02（tokens.cardShadow 引用点核查）。
- 未登记的新样式需求 → 我先补规格卡编号（含原型修改）再开发。

## 七、ui_kit 原语清单（本批已抽 · lib/shared/widgets/ui_kit.dart）

`AppToast.show` / `PillChip` / `DotLegend` / `MoodRow` / `SectionCard` / `EmptyDashRow`
——新代码必须优先复用；存量调用点按两档流程「路过替换」，不做专项重构批。
