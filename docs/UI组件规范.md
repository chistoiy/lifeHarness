# LifeHarness UI 组件规范（组件词典 · V1.0 · 2026-09-21）

> **用途**：建立产品负责人 ↔ 开发（含 AI agent）的 UI 共同语言。微调指令直接引用「编号+中文名」（如「LH-S01 事件详情弹层 标题字号+1」「LH-K03 胶囊筛选 选中态换成描边」），即可精准定位到原型 CSS 与 Flutter 代码，无需描述性猜测。
> **三源同步铁律（2026-10-03 改口径）**：UI 事实源按**屏单一归属**——壳与跨模块屏在 `prototype/index.html`，模块细节屏在该模块专版，一张屏只有一个家（治理规格见 docs/archive/交棒话术-20261003-原型瘦身与屏单一归属治理.md）。本规范是其**索引**：改原型必须同步更新对应规格卡；新 UI 组件先登记规格卡（编号＋锚点）再进入开发（并入交接文档铁律）。
> **别名要求**：每个 LH 组件与每张屏都要挂「人话别名」（如「记账那页」「日历格子」「阅读外观面板」），与模块注册表同源维护——开发者的自然语言与截图靠它定位，词典里没有的说法就当场补进去。
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
| 字体角色 | type role | 正文衬线 / UI 无衬线 / 代码等宽三档，全局按角色取字体（LH-F01） |

## 〇A、LH-F01 字体角色（2026-10-02 产品定 · 全局规范 · **2026-10-03 Flutter 侧已接**）

> **口径**：长文正文用**衬线**（阅读舒适、笔画有粗细），标题与一切 UI 标签用**无衬线**（密排清晰），
> 数字/代码用**等宽**。全部走**系统回落字体链**——**不随包字体文件**（思源宋体一字重全量约 8–20MB，
> 与《APK包体压缩可行性》「无无损压缩空间」直接冲突，已否决）。
>
> **落地进度（2026-10-05 批五）**：三档角色里「数字用等宽」分两档实现——**字段级**用 `--f-code` 字族（计时/日志/代码），**读数级**用 OpenType `tnum`（金额/计数列，Flutter＝LH-K33 作用域、原型＝壳与记账专版 `body{font-variant-numeric:tabular-nums}`）。前者已接，后者本批两侧各落一处。

| 角色 | CSS 变量 | 字体链（原型与实现同一串） | 用在 |
|---|---|---|---|
| 正文 body | `--f-body` | `'Noto Serif SC','Source Han Serif SC','Songti SC','STSong','SimSun',Georgia,serif` | 阅读器正文与引文、日记/笔记正文、书摘正文、X-Ray 摘录卡正文 |
| UI ui | `--f-ui` | `Inter,'Noto Sans SC','Source Han Sans SC','PingFang SC','Microsoft YaHei',system-ui,sans-serif` | 页面与卡片标题、**书名**、底栏与顶栏文字、按钮/标签/表单、阅读器内的标题行（`.brp-h`） |
| 代码 code | `--f-code` | `ui-monospace,'JetBrains Mono',Consolas,Menlo,monospace` | 数值/计时/日志/代码块与等宽字段 |

**平台事实（别再按 Windows 观感做决定）**：`Microsoft YaHei` 只存在于 Windows，安卓真机上取不到，
它在这条链里只作开发期 Windows 预览兜底；安卓/鸿蒙的衬线回落到 `Noto Serif CJK`（即思源宋体同源），
无衬线回落到 `Noto Sans CJK`（思源黑体同源）——所以**真机观感与你在 Windows 上看到的接近，
但各家 ROM 的衬线实现可能不完全一致**（部分 ROM 无衬线字体缺失时会回落成黑体＝衬线效果消失）。
需要跨机型绝对一致时再议随包子集（体积代价由产品拍板）。

**锚点**：原型 `prototype/index.html` / `prototype/index-bookshelf.html` 的 `:root{--f-ui/--f-body/--f-code}`
与 `.f-body/.f-code` 工具类；阅读器字体目录 `BR_FONTS`（九款全带 CJK 回落链）、正文默认族 `BR_DEF.font='serif'`；
校验脚本 `tools/f01typecheck.js`（三角色断言 + `prototype/shots/f01_shared_dash.png · f01_reader_serif.png`）。
**Flutter 侧已接（2026-10-03·批一）**：三串链的唯一来源＝`lib/core/theme/app_typography.dart`
（`kFontBody/kFontUi/kFontCode`＋`lhFontRoleOfReaderFont`，链内容与上表逐字符一致，`TextStyle.fontFamily`
吃链首、`fontFamilyFallback` 吃其余）；全局默认字族在 `AppTheme.build` 里＝UI 链，主题设了 `--app-font`
则整档跟随主题；阅读器 `ReaderCfg.fontFamily` 与 `ReaderLayout.fontFamily/base` **调同一函数**（测量与渲染同源），
默认族已改 `'serif'`，白名单保留 `system`（老用户落库值原样读回）；分页表 `PagStore.tableVersion` 2→3
（枚举值没变而映射串变了，不升版本旧分页表会继续命中）。**遗留**：本表 body 角色列的「日记/笔记正文、
书摘正文、X-Ray 摘录卡正文」四个面还没接（`F01 工单 §1 落点表`未列，需逐屏改样式并经真机观感确认）。
回归钉子＝`test/reader_f01_font_test.dart`（11 例：同串/默认族/老值读回/同源/主题覆盖/表版本）。

**已定**：角色划分与「不随包字体」已定；阅读器正文默认族「系统默认」→**衬线**由产品 2026-10-02 拍板
（见《需求清单》V1.59 段；已手动选过字体的老用户保持其选择，白名单里的 `system` 保留）；
7 套主题 json 的 `--app-font`（复古/秋日暖调走衬线）与三档角色链的关系＝**角色链作默认、主题字体令牌作整档覆盖**
（产品 2026-10-03 拍板，落点见 `docs/handoff/交棒话术-20261002-下一版实现批-F01-批C-R32精修.md` §1）。


## 一、LH-T 提示类

### LH-T01 胶囊提示 AppToast
| 项 | 值 |
|---|---|
| 原型锚点 | `#toast`（index.html L2000 · toast() L2137） |
| 代码锚点 | `core/theme/app_theme.dart` snackBarTheme（L74 附近）；调用统一走 `shared/widgets/ui_kit.dart` `AppToast.show` |
| 规格 | 底 0xE60F172A · 白字 12.5 w600 · 圆角 28 · 宽 320 · floating · 默认 1.5~2.2s |
| 可调旋钮 | 底色/圆角/宽度/字号/时长（改一处全局生效，禁止页面私调样式） |
| 现状 | 主题层已统一；调用点 40 处/19 文件，后续批次路过逐步替换为 AppToast.show |
| ⚠️ 带按钮必写 `persist: false` | 框架 `SnackBar` 构造里 `persist = persist ?? action != null`——**带 `SnackBarAction` 的条默认永挂**，直到点按钮或再挂一条。撤销类条子一律显式 `persist: false` + 明确 `duration`（V1.52.1 真机反馈②）。 |
| ⚠️ 模态弹层内不要挂 | 条子由**页面 Scaffold** 渲染，弹层浮着时既被压在弹层与遮罩后头看不见、又不会退场。弹层内的校验反馈走弹层自带提示行（见 LH-S03 的 `_hint`），落库成功的反馈＝先 pop 再下一帧挂。 |

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
- 原型：`prototype/archive/index-kits.html`（V1.58 下架后移入 archive 留档） `#kitHero`（小工具首页顶部主卡，复用 LH-C02 渐变皮肤）
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

### LH-C13 分类胶囊 CatPill（V1.52.1 新增）
- 原型：`index.html` `.tag-chip`（L156）+ `.tp-catgrid .tag-chip`（L73·6 列窄格）；代码：`time_pick_sheet.dart` `CatPill`
- 规格：高 26 · 圆角 999 · 内边距横 5 · 色点 7×7 圆角 3 + 3dp 间距 · 名称 10 w600 `Flexible`+省略号
  · 未选=onSurface 6% 底/onSurfaceVariant 字 · 选中=accent 实底白字（**色点不换 ✓**）· 子分组色点沿用父级 60% 透明
- ⚠️ 不用 `ChoiceChip` 的两条硬理由：① 6 列窄格（约 48dp）下它的 label 会被 avatar+内边距挤到 0 宽，屏幕上只剩一个色点（真机反馈⑤）；② 选中时它把 avatar 替换成 ✓，把分类色点顶掉，与原型不符
- 用法：定宽列（一级分类 6 列等分）传 `width`，内容自适应列（子分组）不传；一级格外层最多 3 行、超出可滚（对齐 `.tp-catgrid` max-height 82px）

## 三、LH-S 弹层类（sheet 家族）

**公共骨架**：showModalBottomSheet · isScrollControlled · 内边距 LTRB(16,14,16,24) · 标题 15 w900 · 行卡=LH-C01+选中描边 accent 2px+✓

| 编号 | 名称 | 原型 | 代码锚点 |
|---|---|---|---|
| LH-S01 | 事件详情弹层 ~~sheetEventDetail~~ | **V1.52 退役**：并入 LH-S03 统一弹层（点已有事件=与新增同一个弹层） | 原 `event_detail_sheet.dart` 已删除 |
| LH-S02 | 标记块详情弹层 ~~sheetBlockDetail~~ | **V1.52 退役**：「取消标记」独立层撤销，删除动作进 LH-S03 底部「删除」+ SnackBar 撤销 | 同上 |
| LH-S03 | **统一添加 / 编辑弹层**（V1.52 · V1.52.1 修口） | sheetTimePick | `showTimePickSheet(context, ref, {day, startMin, block, event})`：日/时/**分（1 分一档 · CupertinoPicker looping · `squeeze: 1.0` 才等于「高度÷行高」的真行数，默认 1.45 会多挤进行数）**三列滚轮 ×2 组（起止 · 结束含日轮支持跨天）· 一级分类**每行 6 个**（LH-C13 CatPill）+子分组自适应 · 备注 · 底部按形态=「继续添加+添加」/「删除+保存修改」· 计时中额外「■ 结束计时」· 已结束额外「✂ 对半拆分 / ⇧ 与上一个合并 / ⇩ 与下一个合并」（间隙>30 分置灰 · **合并存活段=较早那段，删的是另一段**）· 破坏性操作 SnackBar 带撤销（`persist: false` · 先关弹层再下一帧挂）· 标签与「管理 ›」并入一级分组标题行 · **弹层内校验反馈走标题下提示行 `_hint`（✕ 红 / ✔ 主题色），不借道页面 SnackBar** |
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
| LH-S29 | **服务商添加/编辑弹层**（V1.53.1） | `sheetAiProv` | `ai_page.dart` `_AiProviderFormSheet` | 名称 · Base URL（等宽，允许任意 `http(s)` 前缀与自定义后缀）· 模型名 · 协议二选（复用 LH-K03 胶囊）· 独立 Key（LH-K30 掩码+眼睛）· http 明文二次确认行（仅当地址以 `http://` 开头才出现）· 测试结果框（**浅色描边**，禁深色面板）· 「测试连接 / 删除（非当前才给）/ 保存服务商」。**校验失败一律弹层内行内红字**（模态弹层里挂页面 SnackBar 会被遮罩挡住看不见——既定坑）；新增即选用；改动即刻生效，业务模块零感知 |
| LH-S30 | **AI 记录设置弹层**（V1.53） | `sheetAiUsageCfg` | `ai_usage_page.dart` `_CfgSheet` | 记正文开关（关闭后新调用只记用量，**已存正文不被自动删**，要单独按「清除已存正文」）· 保留天数 chips（7/15/30/90/不限，选中即刻按超期裁剪并 toast 丢弃条数）· 当前占用 MB（正文+原因字节实算）· 清除正文（保留用量）与清空全部两个破坏性动作各走二次确认 · 底部隐私说明 |
| LH-S31 | **破坏性操作二次确认**（批六 T3 · 由日子 `daysConfirm` 提升） | 原型侧 `confirm('…')` 定式（书架删摘录同式；呵护专版疫苗/里程碑已补） | `shared/widgets/confirm_dialog.dart` `lhConfirm` | 取消在左、destructive 动作在右并着玫红 `#F43F5E`（与就地错误同族色），两者视觉上分得开；点遮罩/返回＝取消，**绝不默认执行**。文案由调用方给一句人话（说清删的是什么、能不能回来），本原语不拼句子。key 沿用日子侧 `d-confirm-ok`/`d-confirm-cancel`（既有用例与真机走查锚点不拆）；日子侧 `daysConfirm` 改为委托本原语——**确认版式全仓只许一份实现**（守护钉死） |
- 可调旋钮：标题字号、行卡高度、选中描边色——**弹层内字段结构变更走原型确认门**。

## 四、LH-K 控件类

| 编号 | 名称 | 原型 | 代码锚点 | 规格要点 / 可调旋钮 |
|---|---|---|---|---|
| LH-K00 | 按压反馈原语（批二 T5） | 无独立屏（全 app 通用态） | ui_kit `Pressable` | `Listener` 只观察指针不进手势竞技场；按下 `AnimatedScale(.96)`、抬起/取消复原；选 scale 不选 splash（要能安全套进横滑列表与卡片，splash 需 Material 祖先且在滚动面留残影）；`enabled=false` 时零开销直通 |
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
| LH-K30 | **掩码密钥输入 + 眼睛切换**（V1.53.1） | `#apKey`/`#gkKey` + `apPeek()` | `ai_page.dart` Key 卡与服务商表单 | **默认掩码**（HTML `type=password` / Flutter `obscureText: true`），右侧线性 SVG 眼睛点切明文、再点回掩码，**禁 emoji 眼睛**；编辑已有条目时把已存 Key 掩码预填并在下方给状态提示「已存 Key（末 4 位 xxxx）· 覆盖即改，清空后保存＝删除该 Key」；明文只在本机显示，绝不进日志/备份/同步 |
| LH-K31 | **服务商条目行**（V1.53.1） | `#aiProvList`（`aiProvRender()`） | `ai_page.dart` `_ProviderRow` | 一行两条信息带：上行＝名称（+「预置」徽）＋动作区（当前＝绿点「● 当前」文字，非当前＝「选用」；一律给「编辑」，非当前再加红字「删」）；下行＝Base URL 等宽省略号 ＋「模型 · 协议 · Key 已单独保存/沿用旧全局 Key/未填」，`http://` 端点追加黄字「http 明文（局域网）」。**当前端点不给删除入口**（数据层同样拒删，双保险） |
| LH-K32 | **表单就地错误行**（批三 T9 · 批四已回灌原型） | `index-ledger.html` saveTx／recAddSave／catSheetSave ＋ 壳 `index.html` addTask／aiQuad（`.fld-err` 红字行＋`.fld-bad` 描边，2026-10-05 回灌） | ui_kit `FieldError` | 校验失败写**在字段旁**，不借道提示条（模态弹层里页面 SnackBar 会被遮罩压住看不见＝既定坑）。文案＝原短句一字不动（只换呈现位置），必填类按字段拆开各写各的（「请填写名称与目标金额」→「请填写心愿名称」＋「请填写目标金额」）。样式＝LH-S03 `_hint` 定式：10.5 / w700 / 玫红 `F43F5E`；`message` 为 null 或空串时不占位。**输入框优先走框架 `InputDecoration.errorText`**（自带红字与描边联动），滚轮/选择卡这类「点开回填」的控件没有失焦语义，才用本原语在其下方补一行；失焦只**复核已亮错的那枚**，不在用户第一次离开空字段时提前催 |
| LH-K33 | **等宽数字作用域**（批四 T12 · 原型侧批五补落） | 壳 `index.html` ＋ 记账 `index-ledger.html` 的 `body{font-variant-numeric:tabular-nums}`（其余专版待点头同法） | ui_kit `TabularNums` + `kTabularNumFeatures` | 子树里的**数字按等宽字形排**（OpenType `tnum`），金额/预算/报表列逐行对齐不抖。**只挂字形特性、不换字族**——〇A 的 `--f-code` 字族是给数值/计时/日志「字段」的独立档，切字族属视觉变更（要走原型门）；本原语管「同一句里数字宽度」，两者不冲突。用法＝在含数字列的页面/卡片外**包一层**（记账线＝各页 `data:` 分支返回处），不必逐处写样式：`TextStyle.merge` 对 `fontFeatures` 是「子级没写就沿袭上级」，页内自带 `TextStyle(fontSize:…)` 的读数照样吃到；已自写 `fontFeatures` 的存量点（阅读器 chrome/计时）不受影响。**能力边界**＝字族本身没有 `tnum` 时该特性为空操作（观感不变、宽度仍可能微抖），这是〇A「不随包字体文件」的已知代价；`inherit:false` 的样式不吃作用域（调用方自理）。**原型侧实测这条不是空写**（内置浏览器量 `#p-finance`）：Inter 已加载时 `1111.11` 与 `8888.88` 在等宽档同宽 107.69px，切回比例档为 75.64 / 111.44px |
| LH-K34 | **底栏角标**（批六 T11 · 原型已出待过门） | 壳 `index.html` `renderNav()`＋`.navbadge` ＋数据源表 `NAV_BADGE_SRC` | 规划 `app_router.dart` `_NavTab` 包 `Badge` | 数字胶囊挂在该枚图标右上（`top:2px; left:calc(50%+7px)`，15px 高 · 9px/800 白字 · 玫红 `#f43f5e` 底，深色档 `#fb7185`），**>99 收敛成 99+，纯数字禁 emoji**；有计数才出现，**进入该栏目即清**（本次会话内），下次产生新数据再亮。数据源集中在一张表里按栏目页取（待办枚＝未完成且逾期条数，实算不写死）；阅读侧 X-Ray 徽标数据在书架专版本模块，壳不代管——挂哪枚等产品定，接法同表 |
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
| LH-L14 | **AI 使用记录行**（V1.53） | `#auBox .ailine` | `ai_usage_page.dart` `_row`/`_detail` | 收拢一行＝时刻(HH:MM 等宽)+状态徽(成功绿/失败红/取消黄/未启用灰·纯文字)+「模块 · 能力名」+「入x/出y · 耗时」；**点行内联展开**（不平铺、不跳页）System/User/输出 三段全文（`SelectableText`，被截断的 User 末尾标「…已截断（上限 8000 字）」），失败行多一段「原因」（停记正文时原因仍在）；展开区四个小按钮＝复制输入/复制输出/复制全部/删除本条；**长按整行＝复制该行摘要**（与日志页同交互）；无正文时展开区给「本条未存正文」一句 |
| LH-L15 | **加载失败态卡**（批六 T8 · 原型已出待过门） | `index-ledger.html` L1 顶部 `#finErr`（演示开关：控制台 `setErrDemo(1)`，或地址带 `?errdemo=1`） | 规划 `lib/shared/widgets/err_state.dart`（先接 ledger/care/todo 三线 data 分支） | **失败不许渲染成「暂无数据」**：标题一句人话（如「这个账本没加载出来」）＋原因小字（真实取 `humanizeError` 短句，技术细节进日志页）＋主按钮「重试」（就地重取）＋次按钮「查看详情」（跳运行日志）。图标一律线性 SVG 禁 emoji；区块级失败只顶掉该区块，整页级失败顶掉整屏数据区。与空态（LH-L04）分得开 |
## 六、微调指令写法（示例）

- 「**LH-T01** 时长统一 2s」→ 只改 ui_kit/theme 一处。
- 「**LH-S03** 添加弹层备注框加高」→ 定位 time_pick_sheet.dart。
- 「**LH-K03** 和 **LH-L04** 的圆角统一 20」→ 两处原语一次改完，全 app 生效。
- 「所有**渐变主卡**阴影减轻」→ 只动 LH-C02（tokens.cardShadow 引用点核查）。
- 未登记的新样式需求 → 我先补规格卡编号（含原型修改）再开发。

## 七、ui_kit 原语清单（本批已抽 · lib/shared/widgets/ui_kit.dart）

`AppToast.show` / `PillChip` / `DotLegend` / `MoodRow` / `SectionCard` / `EmptyDashRow`
——新代码必须优先复用；存量调用点按两档流程「路过替换」，不做专项重构批。
