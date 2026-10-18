# 小组件模块 · 批A 按实例绑定与打卡试点（评估件落地批）

> **状态**：**待开工**（2026-10-17 · 产品令「把小组件落到下一步任务里，新会话开发」）
> **上游**：`docs/handoff/评估结论-20261017-小组件Glance裁定与内容对齐NFC分类评估.md`（活·**规格唯一来源**＝该件 §一~§五；本工单不复述评估，只写批次拆分与落地口径）
> ＋`docs/handoff/桌面模块-冻结版开发方案-20261013.md`（既有小组件基建：C1~C19/B 体系·四枚 provider＋配置页＋数据桥）
> ＋`docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md`（目标模型与五段大类·批1b 已落地）
> **前置门核对（开工时已验）**：桌面批1~3（`lh://` 底座＋四枚 provider＋数据桥＋待办勾圈闭环）＝**已在位**；
> 原型过门＝本批新增形态（打卡四格＋「先选后落」流程）**须先过门**（UI 铁律）。

## §0 本轮相对评估件的落地口径（实现决定 · 先看这节）

| # | 决定 | 理由 |
|---|---|---|
| 1 | **维持原生 AppWidget＋RemoteViews＋home_widget 栈，不引 Glance** | 评估件 §一裁定（含 §5.5 REA/JADX 字节级旁证：连用 Compose 做 UI 的一叶日记都在小组件上用 RemoteViews） |
| 2 | 目标选择器**复用 NFC「绑定目标」独立形态**，参数化 mode（nfc｜widget）；写卡专属分支（探卡/状态机/卡号）一律不进共享组件 | 评估件 §2.2/§2.3；NFC 批1b 已把五段大类做出现成形态 |
| 3 | 绑定存储＝**SharedPreferences 映射**（键带桌面实例 id）；不动 DB schema、不进备份 | 评估件 §2.3 层3；跨设备同步本轮不做 |
| 4 | 交互闭环＝**后台 isolate 跑 Dart 走仓库出口**（与 App 内同一出口）；本地回显三态＝乐观/收敛/回滚入队 | 评估件 §4.1 实证：打卡非单列写（流水 upsert＋连击重算＋子项），禁原生复刻 |
| 5 | 失效三态（无快照/无绑定/源失效）＋占位布局；命名改「功能-形态」口径 | 评估件 §5.3-3/4（一叶日记借鉴） |
| 6 | **「记一笔」弹窗＝版式同源记账页**（四类型 tab＋分类行＋子类 chips＋四则键盘），实现走**对话框 Activity 内嵌 Flutter 渲染同一份表单**（原生复刻降为备选） | 2026-10-18 产品令「复用记账页那种四种类型与子类样式」＋拍板件 §五对照表 |

## §1 · ⚙ 执行面板（六项）

- **受影响测试清单**＝新增常驻三件（预估）：`test/widget_binding_test.dart`（绑定读写／实例删除回收／**老实例回落全局默认**／失效三态判据·纯函数）、
  `test/widget_picker_test.dart`（共享选择器参数化：五段目标返回三件套／写卡分支隔离不泄漏／同一数据源）、
  `test/widget_checkin_echo_test.dart`（isolate 出口同源性守护／回显三态／待排空队列排空）。
  回归随收口＝`test/desktop_widget_test.dart`·`test/desktop_actions_test.dart`·`test/settings_page_test.dart`·`test/architecture_test.dart`·`test/size_budget_test.dart`·`test/nfc_linkage_test.dart`（选择器数据源同源不回归）。
  一律 `bash tools/ftest_waves.sh <批次名> <文件…>` **一文件一波**；**本批动 `android/**` ⇒ 收口必跑 `bash tools/kotlin_check.sh`**。
- **变异刀清单（≤3 刀 · md5 复原）**＝① 绑定层摘「老实例回落全局默认」→ 老实例读空全变占位的用例红；
  ② 交互出口改原生直写（绕 isolate）→ 同源性守护例红；③ 摘本地回显（执行后不写显示态）→ 回显收敛例红。
- **新增常驻用例**＝五件新文件（例数随落刀进度回填）：**① `test/widget_binding_test.dart` 已落（16 例全绿·2026-10-18）**；**② `test/widget_picker_test.dart` 已落（20 例全绿）**；**③ `test/widget_config_test.dart` 已落（15 例全绿·配置页先选后落）**；**④ `test/widget_render_test.dart` 已落（22 例全绿·渲染层六组）**；⑤ `test/widget_checkin_echo_test.dart`（待交互闭环）。
- **回灌成句**＝原型侧新增打卡四格形态＋「先选后落」流程样张（五段目标区沿用 NFC 弹层），过门后回灌 `prototype/index-desktop.html` 与本壳入口/角标；
  同步 `docs/UI组件规范.md` 登记小组件组件段与失效三态口径。
- **复测包编号**＝**6174 已出·已装机**（2026-10-18·arm64 单 ABI·versionCode 8174·md5 `cffb8d72`·无线装 `192.168.31.173:38151`·`install -r` 保数据·启动无 FATAL）。**下一枚＝攒 6175（未构建）**——实现批动 `android/**`（新 provider＋弹窗 Activity＋配置页改造＋清单），按攒批口径并入下一枚（产品令装机时一次钉版 `0.2.15+<编号+2000>`，形态以机上包为准）。
- **互斥面（写区）**＝`lib/core/platform/desktop_widget.dart`·`lib/features/widget/**`（新）·`lib/features/nfc/presentation/nfc_sheets.dart`（仅加参数·不挪既有逻辑）·`lib/shared/linkage/nfc_mounts.dart`（只读数据源）·`android/app/src/main/AndroidManifest.xml`·`android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt`·`WidgetConfigActivity.kt`＋新 provider/布局/信息 XML·`test/widget_*`·`prototype/index-desktop.html`·`docs/UI组件规范.md`。
  ⚠ **与在飞 NFC 线共用 `android/**`、清单、主活动、nfc 选择器 ⇒ 串行**：NFC 在飞线收口前，本批 android 刀与 nfc_sheets 参数化两处不动，先落 Dart 侧（绑定层/选择器参数化/回显逻辑）。

## §2 批A 范围（一条全链＋一枚试点）

| 层 | 交付 | 对应评估件 |
|---|---|---|
| 绑定层 | prefs 映射：绑定读写／实例删除回收／老实例回落全局默认／失效三态判据（纯函数可单测） | §2.3 层3 |
| 选择层 | NFC「绑定目标」形态参数化出 widget 模式（mode 只影响按钮文案与回调去向） | §2.3 层2 |
| 配置页 | 「本枚绑什么」＋预选绑定无感完成；全局四开关回归设置页（本就同份数据） | §2.3 层4 |
| 渲染层 | 打卡四格 provider：标题/副文案/主按钮/状态点共享模板＋深浅色映射＋失效三态布局 | §2.2/§5.3 |
| 交互闭环 | 点击打卡 → 本地回显 → 后台 isolate → 同源仓库出口；失败入待排空队列（App 启动排空） | §4.1/§4.2 |

## §3 开工前待产品拍板五项（源自评估件 §2.6·未勾定不动工）

① 读数型是否保留并列（建议保留）；② 首批范围（建议打卡/计时/快捷动作三枚，**本批先做打卡一枚**）；③ 配置页是否承载 Flutter（决定系统添加入口体验；本批先走 App 内「先选后 pin」序，桌面入口序留批C 复判）；④ 绑定存储进 SharedPreferences、不吃备份，是否可接受；⑤ 失效三态文案与点击去向。

> **2026-10-17 产品勾定（全按建议）**：① 读数型保留并列、不进五段表；② 首批＝打卡/计时/快捷动作三枚、本批先落打卡一枚；③ 本批走 App 内「先选后 pin」序、Flutter 配置页留批C 复判；④ SharedPreferences 按实例绑定可接受；⑤ 失效三态文案＝无快照「等待数据」／无绑定「未选择内容，点此设置」／源失效「内容已失效，点此重新选择」，点击起 App 开配置/管理页引导重绑。

## §4 本轮不做

NFC 五段其余条目 provider（计时/快捷动作/呵护宝宝）／读数型新 provider（今日打卡进度横条＝候选·留批B）／配置页 Flutter 承载／小组件内撤销改数（回 App 内）／跨设备同步绑定／锁屏类注册／小米官方审核通道／自定义 scheme 编辑页（借鉴项·留后续产品评估）。

## §5 开工检查单（新会话第一件事）

1. 读评估件 §一~§五＋本工单 §1 面板；2. 过 §3 拍板五项（产品勾定后回填面板「批内增量」对应项）；3. 与在飞 NFC 线确认 `android/**` 写面串行（先落 Dart 侧）；4. 原型样张先过门再动实现；5. 按 §2 五层顺序落刀，每刀编译＋测试＋doclint。

**新会话从这里接（2026-10-18 收尾态 · 五层全落）**：

- **已交付**：原型整改（4×1 三区／待办勾圈／**记一笔弹窗版式同源**·`widget_acheck` 38/38·样张**已过门**）；Dart 侧四层（绑定层 16 例／选择层 20 例／配置页 15 例）＋渲染层 22 例；**交互闭环层 14 例**（`test/widget_checkin_echo_test.dart`·回归八波 108 例全绿·kotlin 过）；复测包 **6174 已出已装机**（8174）。
- **下一站**：① **攒 6175 出包**（产品令装机时一枚打包——动过 `android/**`：新 provider＋闭环 receiver＋Manifest；届时设置页「添加小组件」才真能落桌面）；② §7.1 记一笔**对话框 Activity**（内嵌 Flutter 渲染记账页同一份表单·已登排期池 #20，过门后另起一刀）；③ 批B＝计时/快捷动作两枚 provider（规格见评估件 §2.5 批次建议）。
- **写区**：`android/**` 已随本批落地（NFC 线收口前曾只落 Dart 侧的串行纪律已解除——NFC 批3f 已装机待真机复测，不再写码）。
- **口径提醒**：`--target-platform android-arm64` **不**自动 +2000（偏移只在 `split-per-abi`）⇒ 装机号靠 `--build-number <编号+2000>`＋`local.properties` 同值钉版。

## §6 原型样张交付记录（2026-10-17 · **待产品过门**）

- **拍板五项**已回填 §3（全按建议勾定）。
- **样张落点**：`prototype/index-desktop.html` `#dt-widget` 新增四卡（打卡-单习惯双态双档四件套／计数型 ±N／失效三态／先选后落四步）＋`#dt-desk` 桌面落一枚打卡 widget＋`#dt-map` ③ 卡改「按实例绑定」口径；`prototype/index-settings.html` `#p-sub-desktop` 小部件卡加「打卡-单习惯（2×2）」行＋「添加小组件」改先选后落口径；壳入口副文案三处同步（`index.html` 按钮／注释／TITLES＋`index-settings.html` TITLES）。
- **新立常驻原型闸** `tools/widget_acheck.js`（**20/20**；变异两刀各红其位·md5 复原全等）＋存量 `tools/dtcheck.js` 35/35。
- **存量修正**：`index-settings.html` 哨兵块 24 字节先存漂移归位（govnav 重生成；快照实证与本批无关）。
- **闸链全绿**：protogate strict 0 违例（290 屏）·protostructcheck 6/6·REGISTRY CLEAN 294/294·CARDS CLEAN 15/15·doclint PASS。
- **过门材料**：三张截图（dt-widget 打卡四格／dt-desk 桌面落枚／p-sub-desktop 小部件卡）落仓库外 `tempWork/wa-shots`，随会话消息附上。
- **过门后**才动实现：Dart 侧先行（绑定层／选择器参数化／回显逻辑）；`android/**` 刀与 `nfc_sheets.dart` 参数化两处待 NFC 在飞线收口再动（§1 互斥面）。

## §7 实施记录（2026-10-18 · 增量推进中）

- **既有 widget 整改（产品反馈·原型侧已交付 `52d79315`）**：① 4×1 快捷记录两区→三区（记一笔｜今日支出｜本月结余·信息密度上调·8 处样张同版）；② 待办勾圈示意层可点（原 6 行只 1 行接 toast、其余死键——真机批3 已通，原型示意层没做全）。闸 `widget_acheck` 25/25（增钉两断言·变异一刀红·md5 复原全等）。
  ⚠ 4×1 三区的**原生实现**要动 `android/**`（与 NFC 在飞线串行），落排期池待排；真机勾圈无需实现（批3 已过真机门）。
- **绑定层已落（Dart 侧第一刀·纯函数＋prefs）**：`lib/features/widget/domain/widget_binding.dart`（目标三件套同构 `NfcTargetKind`·控制字符编解码·实例回收·老实例回落·失效三态判据）＋`lib/features/widget/data/widget_binding_store.dart`（一实例一键 `desktop.widget_bind.<id>`＋全局默认键·loadAll/prune/resolve）＋ `test/widget_binding_test.dart` **16 例全绿**·analyze 干净·变异一刀（回落打死）红后 md5 复原全等。
  - **架构纪律**：provider 未进 `core/providers.dart`（R2：core 禁依赖 features·组合根白名单只有 router）——store 构造注入自足，provider 留配置页那刀随 feature 侧 providers 文件一起加（免死代码）。
  - **存量红上报（非本批引入）**：`test/desktop_widget_test.dart` 1 例红＝守卫「activity 禁空 taskAffinity」（10-15 桌面批3 立）撞 `NfcRelayActivity` 空 affinity（10-17 NFC 批3c 故意为之·excludeFromRecents＋noHistory 的中转界面）。跨线冲突，按互斥纪律不动 NFC 线 Manifest/守卫，**待 NFC 在飞线收口时裁定**（守卫加白名单条目或收窄扫描面二选一）。
- **选择层已落（Dart 侧第二刀·2026-10-18 晚）**：`lib/features/widget/presentation/widget_target_picker.dart`——五段横向大类共享选择器，`WidgetPickerMode`（nfc｜widget）只改按钮文案与区标签（「保存」/「添加到桌面」·「贴卡后做什么」/「点击后做什么」），写卡专属分支不进组件；数据一律经 `nfc_mounts` linkage 出口（同库同函数·同一数据源）；返回 `WidgetTarget` 三件套由调用点决定去向（widget 侧绑实例键）。`test/widget_picker_test.dart` **20 例全绿**（五区各返三件套／切区不改变已选／再点子级退父级／进区默认选中／空习惯确认键置灰／同源守护≡NFC 侧 tab 表·ref 常量·care 子格式／写卡分支隔离源码扫描）。⚠ 与 NFC 侧两处登记（tab 表/ref 常量）靠测试守护防漂移，NFC 侧参数化时（R7）二选一销一份。变异一刀（habit/care 换序）⇒ 同源守护红其位·md5 复原全等。
- **配置页已落（Dart 侧第三刀·2026-10-18 夜）**：① 域层增「预选绑定」交接位——`kWidgetBindPendingKey`＝`desktop.widget_bind.pending`＋`WidgetPendingBind`（五段编码＝种类·kind·ref·sub·时刻；TTL 2min＋60s 回拨容忍）；② store 增 `setPendingTarget`／`pendingBindFor`／`clearPendingBind`，`loadAll` 明写跳过 `pending`/`default`（预选键**不得**被当成一枚实例列出来）；③ `widget_target_picker.dart` 增 `widgetTargetLabel`（`打卡 · 早起`／`快捷动作 · 记一笔`／呵护·计时·阅读只给大类——二级参数是机器码不上屏）；④ 新建 `lib/shared/linkage/widget_bind_mounts.dart`＝设置页唯一出口（R1：`features/settings` 禁 import `features/widget`），`addHabitWidgetFromSettings` 一键 ①②③（选择器打卡段预开 → 落预选 → 请系统 pin 打卡枚），**取消即什么都不落**（不写预选、不调 pin）；⑤ 设置页小组件卡增头部「添加小组件」＋末行「打卡-单习惯（2×2）／添加」（与原型 `p-sub-desktop` 同序），并加 `addWidgetFlow` 测试注入缝（生产不传＝走真流程）。
  `test/widget_config_test.dart` **15 例全绿**（预选编解码·脏值·有效期·交接位不进实例清单·标签·真链路三步·设置页接线两入口）。变异一刀（`pendingBindFor` 摘种类校验）⇒ 仅「种类不匹配取不到」转红·md5 `058c9a7a` 复原全等。闸：五文件五波 **ALL-GREEN 72 例**（config／desktop_settings／binding／picker／architecture）。
  - **为什么预选要带「种类」＋期限**：`requestPinAppWidget` 的 appWidgetId 由系统在落桌面那一刻才分配，App 侧拿不到 ⇒「先选」与「后落」之间必须有交接位；而用户在**系统**弹窗里点取消时没人消费它——不设期限、不校验种类，下次随手从部件库拖出的别的枚就会被误绑（「我没选过它，它自己绑上了」）。
  - **第④步（配置页读预选无感回写）未随本刀落**：它要在原生 `WidgetConfigActivity.onCreate` 里按 provider 类名认出「这是哪一枚」，而打卡枚 provider 属渲染层——两处各猜一个类名必漂移，故与 provider **同刀落**（同一次提交里定名，守护测试交叉核对键/格式/TTL）。
  - **测试工装口径（新坑）**：`AppDatabase.instance.open()` 走 sqflite 全局工厂，在 Windows 测试环境会**卡死**（实测 2 分钟超时零输出，`.timeout` 也救不了——ffi no-isolate 下同步阻塞）⇒ 一律用 picker 既有的 `db:` 注入缝，不在测试里初始化整库。
- **渲染层已落（第四刀·2026-10-18 深夜·动 `android/**`）**：打卡-单习惯 2×2 全链打通（Dart 快照 → 原生 RemoteViews → 配置页认领）。
  - **Dart 侧**：`LhWidgetKeys.habitItems`（白名单第 10 键）＋`WidgetHabitItem`／`encodeWidgetHabitItems`（唯一编码出口·条目 `\u001e`／字段 `\u001f`／序 name·streak·done）＋`LhWidgetNames.habitCheck`＋`pushDesktopWidgetSnapshot` 第五枚重绘；`buildSnapshot` 用 `habit.book`（＝**未归档**全量）出今日状态表——归档/删除的习惯不进表，绑着它的实例自然查不到行 ⇒ 桌面转「内容已失效」（不需要另设失效标记位）。
  - **原生侧**：`HabitCheckWidget`（四件套＝标题／习惯名／状态行／主按钮；失效三态**共用** `lh_wg_ph` 占位只换文案）＋`lh_widget_habit.xml`＋`lh_widget_habit_info.xml`（**全仓唯一**写 `android:configure` 的枚）＋drawable 四件（btn／btn_off／dot_on／dot_off）＋两档 `lh_wg_btn_off` 色值＋文案九条＋Manifest receiver＋`pinWidgetById` 的 `habit` 分支；`LhWidgetSupport` 增 `HabitRow`／`readHabitRows`／`boundHabitName`（实例键优先→回落 `…widget_bind.default`）／`consumePendingBind`／`notifyWidget`。
  - **第④步无感回写（同刀落的理由见上段）**：`WidgetConfigActivity.onCreate` 在 id 校验后按 `providerClassName()` 认领——类名是打卡枚、或取不到（配置阶段系统可能还没建好记录）⇒ `consumePendingBind` → 立刻 `RESULT_OK` 收摊，且**早于 `setContentView`**（晚一步用户会看到配置页闪一下）；其余四枚仍走四开关老路。
  - **三处坑（都属「看着对、真机错」）**：① `const val PREF_WIDGET_BIND_PREFIX = FLUTTER_KEY_PREFIX + …` 写在 `FLUTTER_KEY_PREFIX` 声明**之前** ⇒ Kotlin 报 `must be initialized`（`const val` 初始化按**声明次序**解析）→ 整块下移到该常量之后，原处留注记防搬回；② 布局里状态点与撑开器原用裸 `<View>` ⇒ 撞 RemoteViews 白名单（与 8150 装机实锤同一类 InflateException）→ 状态点改 `ImageView`、撑开器改空 `LinearLayout`；③ 「已打卡不可点」只换淡底色**不算**不可点——必须 `setOnClickPendingIntent(R.id.lh_wg_btn, null)` 撤掉意图，否则有点按反馈却毫无反应（比灰着更让人困惑）。
  - **闸**：`test/widget_render_test.dart` 新建 **22 例全绿**（编码四／跨语言同源三／失效三态文案＋判定次序二／渲染语句四／布局三／绑定与预选六）；`test/desktop_widget_test.dart` 同步五枚口径（**30 例全绿**，configure 断言改写为「**仅**打卡枚写」＋反向「只许它一枚」）；六文件六波 ALL-GREEN；`bash tools/kotlin_check.sh` `BUILD SUCCESSFUL`。变异三刀（摘 `habitNameOf` 的 ref 校验／摘 `consumePendingBind` 的种类校验／给编码加 24 字截断）各自对应例红，md5 逐刀复原全等。
  - **变异刀抓到的假绿**：「名字不截断」的样例原本**正好 24 字**，落在 `length > 24` 边界外 ⇒ 加截断后仍绿。样例加长到 33 字并补「须越过 24 字边界」自断言后该刀才真红——这类「样例没踩到边界」的假绿只有变异能现形。
  - **预览图**：`tools/gen_widget_previews.py` 增第五枚 `draw_habit`（浅/深两档；MIUI 只认 `previewImage`，缺图会回落应用图标、五枚长得一模一样）。
  - **本刀刻意未做**：未打卡按钮与占位态仍指 `lh://habit/check`（白名单既有段）——**广播直达**与「点占位去设置页」（需新增 `lh://settings/desktop` 段）留给交互闭环刀，避免跨线改 C19 白名单与路由解析。
- **下一步**：交互闭环（点击打卡 → 乐观回显 → 后台 isolate → 同源仓库出口；失败入待排空队列·App 启动排空；`test/widget_checkin_echo_test.dart`）→ 之后攒 6175 出包（产品要装机就提前，届时设置页「添加小组件」才真能落桌面）。
- **交互闭环层已落（第五刀·2026-10-18·动 `android/**`）**：点击 → 原生乐观回显 → 无头 Flutter 引擎跑 Dart → 同源仓库出口 → 收敛；失败/超时回滚入待排空队列，App 启动排空（幂等）。
  - **Dart 侧**：`lib/shared/linkage/widget_checkin_mounts.dart`（`widgetCheckinByName` 按名打卡复用 `habitCheckinWrite`——NFC/App/小组件三入口一个写实现；`runWidgetHabitCheckin` = 开库→写库→推快照；`pushWidgetHabitSnapshot` **只推习惯三键**重绘两枚，禁整包下发（会把待办/金额推成空值）；`drainPendingWidgetChecks` 逐名补写逐名清）＋`main.dart` 增 `@pragma('vm:entry-point') widgetBackgroundMain`（自定义入口点·不初始化 UI 依赖·B8）＋`habit_mounts` 抽出 `habitCheckinWrite` 写核。
  - **原生侧**：`HabitCheckReceiver`（起无头引擎＋等回执收摊＋销毁·**零 sqlite**——打卡不是单列写，禁复刻）＋`HabitCheckWidget.echoChecked`（`row.copy(done = true)` 借已打卡分支·只画自己一枚·查不到不猜）＋`LhWidget.habitCheckIntent`（广播直达·**requestCode 每实例一个**）＋Manifest 收编（exported=false）。
  - **四个坑**：① `FlutterLoader.ensureInitializationComplete` 带 Looper 检查（非主线程直接抛）⇒ 引擎只能在 **onReceive 主线程**建、worker 单线程等回执；② `DartExecutor.DartEntrypoint(bundlePath, "widgetBackgroundMain")` 两参构造＝「默认 bundle＋根库自定义入口」，native 侧 null bundle 不可靠故显式取 `findAppBundlePath()`；③ Kotlin 匿名实现 `MethodChannel.Result` 的 `error` 首参平台类型是**非空** `String`（写成 `String?` 编译红）；④ import 路径是 `io.flutter.embedding.engine.dart.DartExecutor`（带 `.dart` 子包）。
  - **闸**：新 `test/widget_checkin_echo_test.dart` **14 例全绿**（出口同源四／回显三态四／队列行为六）＋回归八波 108 例全绿（render 22／desktop_widget 30／snapshot_exec 6／actions 13／settings 10／architecture 11／size_budget 1／nfc_linkage 15）；`flutter analyze` 本批零 error；`kotlin_check.sh` `BUILD SUCCESSFUL`；变异两刀各自红其位（receiver 塞原生 SQL⇒「禁碰 sqlite」红；摘回显 `done = true`⇒「乐观回显」红）·md5 复原全等。
  - **存量红处理（非本刀净增）**：`feature_size_budget_test` 两处越档按实测同步登记（此后只许减）——settings +132＝NFC 批1b 管理屏入口（`b4e98058`·+49）＋批A 配置页刀（`ed834d9f`·设置页「添加小组件」＋打卡枚行·+93）；habit +9＝NFC 批3 贴卡触发链（`52bb9e1e`）。两刀均未跑过本闸，越档滚到本收口轮才发现。
  - **存量红处理二（文档域）**：交接文档 §5 超上限 54 字节（存量）⇒ 最旧块（2026-10-17 NFC 批3 系与推送 12 行）整段沉 `docs/archive/变更台账-20261017-NFC批3系与推送.md`，正文留指针；doclint 守护十二棘轮随之下调 25,600→24,289（只降不升）。排期池黄灯的不瘦理由沿用 §7.3。
  - **存量红处理三（代码域）**：`feature_size_budget_test` 第二道断言红＝nfc（4,723 行）与 widget（1,079 行）两个新 feature 目录**从未登记**（批1~批3f 与本批前四刀均未跑过本闸）⇒ 按现值登记（此后只许减）；连同 settings/habit 两处越档一并同步。修后该件 2 例全绿。

### §7.1 产品追加需求：记一笔「不打开 App 直接弹窗记账」（2026-10-18 拍板走 A 路）

- **依据**：`docs/handoff/拍板记录-20261018-记一笔弹窗记账与零输入口径改判.md`（三路对比＋口径改判＋真机门四项）。
- **调研结论**：widget 自身弹不出——RemoteViews 不输出弹窗/对话框 token，也不接受输入控件；唯一可行路＝**对话框主题的 Activity**（`Theme.DeviceDefault.Dialog`＋带包名前缀 taskAffinity＋`excludeFromRecents`），本仓已有两块先例（`WidgetConfigActivity`／`NfcRelayActivity`）。A 原生对话框（推荐·轻·任务栈干净）／B Flutter 对话框（视觉最好但小窗＋IME 风险）／C 悬浮窗（权限与生命周期脏·不推荐）。
- **口径改判**：覆盖 2026-10-17 评估件 Q3④「不采用」——**widget 自身不放输入控件这条不变**；仅「记账录入」允许对话框形态轻量 Activity 收集、交 Dart 侧写库（C15 唯一意图出口不变·C18 写入类仅预填不变）。
- **原型样张已交付（2026-10-18 二版·按产品「复用记账页版式」重做）**：`#qpDlg` 不再是「金额＋四个分类文字 chip」的粗糙版，改为**复刻记账页「记一笔」**——四类型 tab（支出/收入/转账/借贷）＋分类行（图标块·大类·子类·右侧金额）＋子类 chips 轨（大类 chip＋子类·单选中）＋四则键盘 15 键（保存跨两行·再记/算同列）；转账形态＝转出/转入两张账户卡、借贷形态＝借出/借入两段＋对方输入。`#dt-widget` 规格卡两档预览由**同一生成函数**出图（深浅各一档，浅色支出／深色收入）。
- **闸**：`tools/widget_acheck.js` **38/38**（弹窗相关增钉：四 tab／分类行／子类 chips 单选中／键盘 15 键／转账借贷表单切换／弹窗完整落在遮罩内／内容无横向溢出／两档预览同源·变异一刀摘「借贷」tab 后转红·md5 复原全等）。
- **待过门**：三张截图（`dt-desk-quickpopup-open`／`dt-desk-quickpopup-saved`／`dt-widget-quickpopup-card`·`WA_SHOTS=1` 可复现）落仓库外 `tempWork/wa-shots`；过门后才动 `android/**`（与 NFC 在飞线串行）·已登排期池 #20。
- **实现路选择（因版式同源而变）**：原定 A 路（原生复刻）降为备选，**首选改为对话框 Activity 内嵌 Flutter 渲染同一份表单**（视觉零差异·分类数据天然走 Dart）——详见拍板件 §五 对照表。

### §7.2 跨线存量红已按产品授权收口（2026-10-18）

`test/desktop_widget_test.dart` 那 1 例改为**有条件豁免**：`NfcRelayActivity` 允许空 `taskAffinity`，但必须同时带 `excludeFromRecents="true"` 与 `noHistory="true"`（二者缺一即红·变异验证＝抠 `noHistory` 后该例转红）；其余 activity 仍禁空 affinity。裁定依据与取证（守卫 10-15 立、`NfcRelayActivity` 10-17 加）见拍板件 §四。现该文件全绿。

### §7.3 体量黄灯不瘦的理由

`docs/交接文档.md` 100%、`docs/排期池.md` 90% 两处黄灯均属**存量累积**（本批只在排期池加 #20 一行＋一条注，净增 <400 字节）；瘦身须整件重排（跨多批变更日志归并），混在本批做会把「批A 增量」与「历史流水压缩」缠在一起、影响回溯——故本批不瘦，另立瘦身批处理（沿用 2026-10 前几批口径）。

### §7.4 记一笔弹窗已落（2026-10-18 · 两刀 · 排期池 #20）

- **路②落地**（拍板件 §五首选）：`LedgerAddPage` 加 `dialogMode`——**同一份表单换容器**，只差两处（无 AppBar、按内容收高 `shrinkWrap`）；四类型 tab／分类行／子类 chips／四则键盘仍走 `_body` 那一棵，全仓各只有一处（测试钉死）。离开出口 `_leave()`：弹窗形态 `SystemNavigator.pop()` 收 Activity，整页形态仍 `context.go('/ledger')`。
- **独立引擎**：`main.dart` 加 `@pragma('vm:entry-point') widgetQuickAddMain` → `runWidgetQuickAddApp()`（`lib/shared/linkage/widget_quick_add_mounts.dart`）——初始化只三件事（prefs／开库／主题令牌），**不跑 `main()` 其余初始化**（提醒重排/迁移/备份）。
- **原生**：`QuickAddActivity : FlutterActivity`（`getDartEntrypointFunctionName` → `widgetQuickAddMain`）＋ `QuickAddTheme`（`windowIsFloating=false` 才顶得动软键盘·透明底·无窗口动画）＋ Manifest（独立 affinity／`excludeFromRecents`／`noHistory`／`singleTask`／`exported=false`）。意图走 `LhWidget.quickAddIntent`（C15 唯一出口·**不派发 scheme**）。
- **4×1 三区原生同批落**（拍板件 §三「同批合并」）：`lh_widget_quick.xml` 记一笔｜今日支出｜本月结余（权重 3/3.5/3.5·分隔线用 `ImageView`，裸 `<View>` 撞 RemoteViews 白名单）；`QuickRecordWidget` 加 `readBalance` 读数、点击改走弹窗（不再 `lh://ledger/add` 起 App）。
- **快照只推记账三键**：新增 `pushWidgetLedgerSnapshot`（只 `amount_cell`／`month_amount_cell`／`balance_cell`，只重绘记账 2×2 与 4×1）——弹窗引擎拿不到待办/习惯域，整包下发会把那两张卡推成空（批A 同一坑）。三键口径抽成 `ledgerWidgetCells`，整包与弹窗共用（`mStat` 只在该函数里出现）。
- **闸**：新 `test/widget_quick_add_test.dart` **19 例全绿**（表单同源／容器两处／关闭出口／入口点 pragma／只推三键／口径唯一／渲染无 AppBar／原生八条）；回归 `desktop_widget` 30＋`widget_render` 22＋`architecture` 11＋`ledger_l2` 11＋`desktop_settings` 10＋`widget_config` 15＋`widget_checkin_echo` 14＋`size_budget` 1 全绿；`kotlin_check` BUILD SUCCESSFUL；变异三刀（摘 `shrinkWrap`／三键下发多推一枚／摘 Manifest `noHistory`）各红其位·md5 复原全等。
- **体量登记**：`feature_size_budget_test` ledger 18045→18132（本刀净 +87 行·同一份表单换容器，无第二套 UI），此后只许减。
- **待真机**（攒 6175）：软键盘不遮挡／返回即消／深色跟随／横竖屏（拍板件 §三 真机门四项）＋ 4×1 三区读数与隐藏金额遮蔽。
