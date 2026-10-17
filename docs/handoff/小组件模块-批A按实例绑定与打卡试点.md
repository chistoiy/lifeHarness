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

## §1 · ⚙ 执行面板（六项）

- **受影响测试清单**＝新增常驻三件（预估）：`test/widget_binding_test.dart`（绑定读写／实例删除回收／**老实例回落全局默认**／失效三态判据·纯函数）、
  `test/widget_picker_test.dart`（共享选择器参数化：五段目标返回三件套／写卡分支隔离不泄漏／同一数据源）、
  `test/widget_checkin_echo_test.dart`（isolate 出口同源性守护／回显三态／待排空队列排空）。
  回归随收口＝`test/desktop_widget_test.dart`·`test/desktop_actions_test.dart`·`test/settings_page_test.dart`·`test/architecture_test.dart`·`test/size_budget_test.dart`·`test/nfc_linkage_test.dart`（选择器数据源同源不回归）。
  一律 `bash tools/ftest_waves.sh <批次名> <文件…>` **一文件一波**；**本批动 `android/**` ⇒ 收口必跑 `bash tools/kotlin_check.sh`**。
- **变异刀清单（≤3 刀 · md5 复原）**＝① 绑定层摘「老实例回落全局默认」→ 老实例读空全变占位的用例红；
  ② 交互出口改原生直写（绕 isolate）→ 同源性守护例红；③ 摘本地回显（执行后不写显示态）→ 回显收敛例红。
- **新增常驻用例**＝三件新文件（例数随落刀进度回填），攒到下轮发版独占全量归位。
- **回灌成句**＝原型侧新增打卡四格形态＋「先选后落」流程样张（五段目标区沿用 NFC 弹层），过门后回灌 `prototype/index-desktop.html` 与本壳入口/角标；
  同步 `docs/UI组件规范.md` 登记小组件组件段与失效三态口径。
- **下一复测包编号**＝**攒 6174（未构建）**——本批动 `android/**`（新 provider＋配置页改造＋清单），按攒批口径并入下一枚（产品令装机时一次钉版 `0.2.15+4174`，形态以机上包为准）。
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

## §6 原型样张交付记录（2026-10-17 · **待产品过门**）

- **拍板五项**已回填 §3（全按建议勾定）。
- **样张落点**：`prototype/index-desktop.html` `#dt-widget` 新增四卡（打卡-单习惯双态双档四件套／计数型 ±N／失效三态／先选后落四步）＋`#dt-desk` 桌面落一枚打卡 widget＋`#dt-map` ③ 卡改「按实例绑定」口径；`prototype/index-settings.html` `#p-sub-desktop` 小部件卡加「打卡-单习惯（2×2）」行＋「添加小组件」改先选后落口径；壳入口副文案三处同步（`index.html` 按钮／注释／TITLES＋`index-settings.html` TITLES）。
- **新立常驻原型闸** `tools/widget_acheck.js`（**20/20**；变异两刀各红其位·md5 复原全等）＋存量 `tools/dtcheck.js` 35/35。
- **存量修正**：`index-settings.html` 哨兵块 24 字节先存漂移归位（govnav 重生成；快照实证与本批无关）。
- **闸链全绿**：protogate strict 0 违例（290 屏）·protostructcheck 6/6·REGISTRY CLEAN 294/294·CARDS CLEAN 15/15·doclint PASS。
- **过门材料**：三张截图（dt-widget 打卡四格／dt-desk 桌面落枚／p-sub-desktop 小部件卡）落仓库外 `tempWork/wa-shots`，随会话消息附上。
- **过门后**才动实现：Dart 侧先行（绑定层／选择器参数化／回显逻辑）；`android/**` 刀与 `nfc_sheets.dart` 参数化两处待 NFC 在飞线收口再动（§1 互斥面）。
