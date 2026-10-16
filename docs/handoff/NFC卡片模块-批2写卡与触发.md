# NFC 卡片模块 · 批2 写卡与触发（写卡层 ＋ 贴卡触发链）

> **状态**：**开工中**（2026-10-17 · 产品令「开工 NFC 批2」）· 子批 2a/2b/2c 顺序执行
> **上游**：`docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md`（V3 冻结档·C/B 条目体系）——**本工单不复述规格，只写批次拆分与本轮落地口径**
> ＋`docs/archive/NFC卡片模块-批1数据层与管理屏.md`（批1 已收口 `b4e98058`）
> ＋`docs/archive/NFC卡片模块-批1b管理屏交互改造.md`（批1b 已收口 · DB v49）
> **可执行规格**：冻结档 §2.2（F2-1~F2-13）／§4.3（写卡状态机）／§4.4（贴卡两制）／§6.1~§6.5；
> 原型侧 `prototype/index.html` 的 `sheetNfcWrite` 段与 `tools/nfc_proto_check.js` 断言。
> **前置门核对（开工时已验）**：冻结档 §6.5 第 1 条（桌面模块批1 的 `lh://` 底座）＝**已在位**
> （`lib/core/platform/launch_route.dart`＋`desktop_actions.dart`＋`app.dart` 消费点）；第 2 条原型过门＝已过。

## §0 本轮相对冻结档的四处落地口径（实现决定 · 先看这节）

| # | 决定 | 理由 |
|---|---|---|
| 1 | 依赖钉 **`nfc_manager: ^4.1.1`**（非 latest 4.2.x） | 4.2.x 要 Dart `^3.11.4`，本机 Dart 3.10.8 装不上；4.1.1 的 SDK 约束 `^3.9.2` 可用。冻结档 §6.2「只此一套插件」不变 |
| 2 | 失败五档判定＝**系统报错类别**：`PlatformException.code`（插件 Pigeon 用 `exception.javaClass.simpleName` 当 code）＋写前主动探针（`NdefAndroid.from == null`＝非 NDEF／`isWritable == false`＝只读／`byteLength > maxSize`＝容量） | F2-2 原文「以系统报错类别为准，不靠字符串匹配」——`code` 就是类别本身，message 不进判定 |
| 3 | 原生改动**多一处**（第 4 处）：`lh/nfc` 通道 ＋ `openSettings` 方法（`ACTION_NFC_SETTINGS`，回落 `ACTION_WIRELESS_SETTINGS`） | §4.9 降级矩阵「系统 NFC 关闭 → 去设置入口」是需求硬项，而 `url_launcher` 打不开系统 NFC 设置页。先例＝`MainActivity.requestOverlayPermission` 已在做同类系统设置页跳转。Manifest 改动面仍严格＝三处 |
| 4 | 触发链的 ref/host **自取**（`ProviderScope.containerOf(rootContext)` ＋ 根 `NavigatorState.context`，须首帧后），`context.mounted` 假 ⇒ **只落库、放弃 toast 与弹层**（B31） | C32/B31 原文；先例＝`lib/shared/linkage/sys_pill_sync.dart` 的 `drainPillEvents` |

## §1 · ⚙ 执行面板（六项）

- **受影响测试清单**＝新增常驻三件：`test/nfc_write_state_test.dart`（写卡状态机纯逻辑：五档失败分派／占用二态／30s 超时分支／写中断回「未写入」／文案表逐字）、
  `test/nfc_trigger_test.dart`（总闸优先静默／去抖 3 秒窗口与反馈分级 B43／确认开关两态／id 格式校验静默丢弃 B35／未命中禁落 `unknownRouteFallback`／写卡后 3 秒内同卡只更新写入态 B39／只读卡显示「只读卡」）、
  `test/nfc_target_test.dart`（四类目标解析／toggle 判据三分支／同名分类按 catId 区分／目标已删走失效分支）。
  回归随收口＝`test/nfc_card_dao_test.dart`·`test/nfc_linkage_test.dart`·`test/nfc_privacy_test.dart`（批1/批1b 常驻不回归）·
  `test/journal_test.dart`（S6/S7）·`test/architecture_test.dart`（R1）·`test/desktop_actions_test.dart`·`test/settings_page_test.dart`·`test/size_budget_test.dart`。
  一律 `bash tools/ftest_waves.sh <批次名> <文件…>` **一文件一波**；**本批动 `android/**` ⇒ 收口必跑 `bash tools/kotlin_check.sh`**。
- **变异刀清单（≤3 刀 · md5 复原）**＝① 摘掉去抖窗口判定（`nfc_trigger` 恒执行）→ `nfc_trigger_test` 红；
  ② 把 toggle 判据改成恒「开始」（摘「进行中则结束」分支）→ `nfc_target_test` 红；
  ③ 摘掉 `nfc.enabled` 总闸判定（关着也能触发）→ `nfc_trigger_test` 红。
- **新增常驻用例**＝三件新文件（例数随 2a/2b/2c 逐批落定后回填），攒到下轮发版独占全量归位。
- **回灌成句**＝原型侧**本轮预期零结构改动**（`sheetNfcWrite` 已过门）；实现若发现原型缺项，按「需求 > 原型」补并**回灌原型**，
  同步 `docs/UI组件规范.md` 登记写卡层组件（LH-S42 段）与贴卡回执口径。
- **下一复测包编号**＝**攒 6157（未构建）**——本批动 `android/**`（Manifest 权限＋intent-filter＋`lh/nfc` 通道）＋引新插件，
  按攒批口径**并入下一枚**（产品令装机时一次钉版 `0.2.15+4157`，universal 或 arm64 以机上包形态为准）。
- **互斥面（写区）**＝`lib/features/nfc/**`·`lib/shared/linkage/nfc_mounts.dart`·`test/nfc_*`·
  `android/app/src/main/AndroidManifest.xml`·`android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt`·
  `pubspec.yaml`＋`pubspec.lock`·`lib/app.dart`（仅 `nfc:` 分支）·`prototype/index.html` 的 nfc 段（如需回灌）。

## §2 子批拆分与顺序（每子批各自可编译、可测、可回滚）

| 子批 | 范围 | 关键交付 |
|---|---|---|
| **2a 写卡层** | F2-1/F2-2/F2-3 ＋ §4.3 状态机 ＋ §4.5/§4.6 反馈 | 域层状态机＋文案表；`data/nfc_tag_io.dart`（唯一接触插件的文件）；写卡层 UI；编辑层「写入卡片」行接入；Manifest 权限＋`uses-feature`；`pubspec` 插件 |
| **2b 触发链** | F2-4~F2-9 ＋ §4.4 通用段 | 原生 `ACTION_NDEF_DISCOVERED` filter＋`handle()` 分支；`data/nfc_trigger.dart`（总闸／去抖／确认／未绑定／失效／nav 执行）；`app.dart` 的 `nfc:` 分支接链 |
| **2c 有状态 toggle 与回执** | F2-10~F2-13 | `nfc_mounts` 两个 toggle 转发口（自取 ref/host）＋进行中判据；阅读结束**复用 `endReadPillTimer`**（单源）；管理屏「● 计时中」同源回显 |

## §3 批2a · 写卡层（可执行要点）

- **域层**（`lib/features/nfc/domain/nfc_write_state.dart`·零 Flutter 依赖）：`NfcWriteState` 十二态
  （`idle/waiting/reading/writing/done/occupied/occupiedOwn/errReadonly/errNonNdef/errCapacity/errBroken/errNfcOff`）＋
  文案表（**逐字照原型 `NFC_STATE_TEXT`**：主文案＋副文案两行）＋纯判定函数：
  `nfcWriteStateAfterRead(...)`（只读／非 NDEF／空白→writing／有内容→occupied／本机另一张→occupiedOwn）／
  `nfcWriteFailureOf(String? errorCode)`（`TagLostException`→中断／`IOException`→容量／`FormatException`→非 NDEF／其余→中断）／
  `nfcWriteLabelForState(...)`（重试钮文案：只读＝「换卡」，其余＝「重试」）。
- **通道层**（`lib/features/nfc/data/nfc_tag_io.dart`）：`NfcTagIo` 抽象＋`NfcManagerTagIo` 实现（唯一 import `package:nfc_manager/**` 处），
  暴露 `availability()`／`startRead(...)`／`stop()`／`openSettings()`／`writeUri(tag, uri)`。
  写卡＝**单条 NDEF URI 记录**（TNF `absoluteUri`·type 空·payload＝`utf8('lh://nfc/<id>')`），
  `ndef_record` 无 `createUri` 工厂 ⇒ 手构 `NdefRecord`（这是本批唯一的"照规格手写 NDEF"点）。
- **表现层**（`lib/features/nfc/presentation/nfc_write_sheet.dart`）：呼吸圆环（1.6s 循环·本模块唯一循环动画·离开层即停）／
  成功对勾（200ms）＋1.2s 自动关层／失败就地红字替换（200ms 淡入）／占用确认块（普通占用＝「取消」＋「覆盖写入」，
  本机另一张＝**仅取消**）／30s 无卡自动关层（B7·不 toast）／写中取消＝中断写入并关层（卡保持未写入）。
  **层内文案只出当前状态，不堆历史**。
- **接入**：新建态保存后进写卡层（C16）；编辑态「写入卡片」行进写卡层；写完**不跳列表不关弹层**（B39），
  只把写入态置「已写入」并写 `written_at`（C31）；写卡成功后 3 秒内同卡贴卡**只更新写入态不执行**（B39·判定在 2b 的触发链）。

## §4 批2b · 触发链（可执行要点）

- **原生**：Manifest 加 `ACTION_NDEF_DISCOVERED` filter（`<data android:scheme="lh" android:host="nfc"/>`）；
  `MainActivity.handle()` **仅加 `lh://nfc/*` 分支**（取 path 末段·**12 位 base62 校验·非法静默丢弃不回显 B35**），
  投给既有 `lh/launch` 队列（与 `ACTION_VIEW` 共用同一解析分支·C36/C37）。既有 5 组 filter 与 `lh/intents` 一字不改。
- **Dart 分派**（`lib/features/nfc/data/nfc_trigger.dart`）：`nfcHandleLaunch(LaunchRoute)` 由 `app.dart` 的 `route.isNfc` 分支调用。
  判定顺序＝**总闸 `nfc.enabled` 先于一切**（关⇒完全静默：不报错不弹提示不震动不计次·C42）→ 去抖 3 秒窗口（内存窗口·不落盘不查库；
  第二次出 `AppToast`「刚刚触发过，等一下」、第三次起静默·B43）→ 卡号查表（未命中走 B8 绑定引导、**禁落 `unknownRouteFallback`**）→
  目标失效（`AppToast` ＋回 `/`·C24）→ 确认开关（`lhConfirm` 标题＝卡名·正文＝目标名）→ 执行。
- **执行两制**：`nav.*`＝`go(动作路由)`（无回执）；有状态卡＝toggle（2c）。计数只在成功后 `markUsed`（B16：窗口内被吞不计次）。

## §5 批2c · 有状态 toggle 与回执（可执行要点）

- `nfc_mounts.dart` 新增两转发口 `nfcToggleTimer(catId, catName)`／`nfcToggleRead(bookId)`：**内部自取 ref/host**，不接受外部 context（C32）。
  时间侧判据＝`activeTiming()?.catId == target_ref`；阅读侧＝`runningSession()?.bookId == target_ref`。
  结束阅读**必须复用 `endReadPillTimer`**（toast ＋ 按 `read.autoAsk` 弹记进度），**不自造结束路径、不为对齐文案改该函数**（单源红线·C22-V3）。
- 回执四文案（C22）＝「开始「学习」计时」／「已结束「学习」· 42 分钟」／「开始阅读《书名》」／「《书名》已结束 · 23 分钟」；
  **触发后不跳屏不弹层**（阅读结束的 autoAsk 记进度弹层除外）。
- 管理屏「● 计时中」＝同源判据回显（`nfc_page.dart` 的 `_runningOf` 注入点接真值源）；**卡片表不存计时态**（B30）。

## §6 不做的事

- 不做批3 范围：UID 轨（`enableReaderMode`）／定时长卡／带参卡／排序／触觉锚。
- 不引第二个 NFC 插件；不加常驻服务、后台巡检、定时器（§6.3 功耗）。
- 不重开 `flutter_deeplinking_enabled`；不改既有 5 组 intent-filter；`ACTION_PILL_*` 一字不改。
- 不动批1/批1b 已收口的数据层与两向写语义；不改「标签只存编号」`written_at` 判据 `id` 格式三条铁律。

## §7 执行记录（逐子批回填）

- **2026-10-17 开工**：前置门核对通过；`pubspec` 加 `nfc_manager: ^4.1.1`（`pubspec.lock` 归一：镜像 URL 回写 `pub.dev`，
  真实变化仅 `nfc_manager 4.1.1`＋`ndef_record 1.4.0→1.4.1`＋`vm_service 15.3.0→15.4.0`）。
- **2026-10-17 批2a 写卡层·落地**：新增四件＝`domain/nfc_write_state.dart`（零 Flutter 依赖·状态机＋文案表唯一源·30s 超时＋1.2s done 停留）、`domain/nfc_card.dart` 追加 `nfcTagUriOf`/`nfcCardIdOfTagUri`、`data/nfc_tag_io.dart`（**全仓唯一** import `package:nfc_manager/**`·`NfcTagIo` 抽象＋`NfcManagerTagIo` 实现）、`presentation/nfc_write_sheet.dart`（写卡层 UI）。接入＝`nfc_sheets.dart` 加 `onCreated` 回调＋写入行接写卡层、`nfc_page.dart` 新建保存后自动进写卡层（C16）。平台侧＝`AndroidManifest.xml` 加 NFC 权限/feature、`MainActivity.kt` 加 `lh/nfc` 通道（只 `openSettings` 一法·`ACTION_NFC_SETTINGS` 回落无线设置）。
- **2026-10-17 批2a 门禁读数**：`test/nfc_write_state_test.dart` 新增 27 例**全绿**（文案表逐字／读到标签后分派／五档失败分派／容量预判与超时／URI 口径与读回解析／tnf 映射与异常码）。回归波 7 文件 **ALL-GREEN** ＝`nfc_card_dao_test`(32)／`nfc_linkage_test`(15)／`nfc_privacy_test`(4)／`architecture_test`(11)／`size_budget_test`(1)／`desktop_ns_registry_test`(6)／`desktop_scheme_parse_test`(15)。`kotlin_check.sh`＝KT-OK（`:app:compileReleaseKotlin` BUILD SUCCESSFUL 4m1s）。`flutter analyze`＝641 issues，**`lib/` 命中 11 条全在未触碰的既有文件且全为 info/warning、零 error**；顺手清掉批1 存量 `test/nfc_privacy_test.dart` 一条 unused import。`doclint.py`＝PASS strict 全绿（REGISTRY CLEAN／CARDS CLEAN／断链 0／守护全绿）。
- **2026-10-17 批2b 触发链·落地**：新增 `data/nfc_trigger.dart`（总闸→去抖→id 校验→查表→失效→确认→执行，判定顺序即代码顺序；去抖窗口＝进程级内存表，B43 第二次 toast 第三次起静默）。原生＝`AndroidManifest.xml` 加 `ACTION_NDEF_DISCOVERED` filter（`scheme=lh host=nfc`）、`MainActivity.handle()` 加 NDEF 分支（**与 `ACTION_VIEW lh://` 共用 `enqueueLaunch` 同一出口**·C36/C37）；常量 `ACTION_NDEF_DISCOVERED` 取值 `android.nfc.action.NDEF_DISCOVERED`（用字面量避引 nfc 包）。`app.dart` 的 `route.isNfc` 分支由「只不吞不炸」改为接 `nfcHandleLaunch(route, nfcTriggerDepsOf(ref, navCtx))`。`confirm_dialog.dart` 加两个可选参（`title`／`destructive`），**默认值与原行为逐位相同**（既有 30 处删除确认版式不动），NFC 执行类确认传 `title=卡名`＋`destructive=false`（不把「执行」染成删除红）。
- **2026-10-17 批2b 门禁读数**：`test/nfc_trigger_test.dart` 新增 **23 例全绿**（形态/总闸优先静默／id 格式校验静默不回显／去抖三级反馈／未命中禁落 `unknownRouteFallback`／目标失效回 `/`／确认开关两态＋host 不可用降级 B31／执行两制 go-push-toggle）。回归波＝`architecture_test`(11)／`desktop_scheme_parse_test`(15)／`desktop_ns_registry_test`(6)／`haptic_confirm_test`(2)／`item_delete_ui_test`(7)／`days_ui_test`(7) 等 **ALL-GREEN**。`kotlin_check.sh`＝**先红后绿**：`Intent.ACTION_NDEF_DISCOVERED` 不存在（该常量在 `NfcAdapter`）⇒ 改字面量常量后 KT-OK（BUILD SUCCESSFUL 1m34s）。
- **2026-10-17 批2c 有状态 toggle·落地**：`nfc_mounts.dart` 新增两转发口 `nfcToggleTimer`／`nfcToggleRead`（**内部自取 ref/host**·C32）＋纯判据 `nfcTimerToggleAction`／`nfcReadToggleAction`（三分支：同 id 结束／异 id 开始／无跑开始）＋`nfcRunningTargets()`（读回计时分类/在读书·B30）。结束阅读**复用 `endReadPillTimer`**（单源红线 C22-V3，未改该函数）。回执四文案逐字（C22）。`nfc_page.dart` 的 `_runningOf` 由恒 false 接真值源（`nfcRunningTargets()` 与列表同一次 `_load` 读回，卡表不存计时态 B30）。`nfc_trigger` 的 `toggle` 出口接入两转发口。
- **2026-10-17 批2c 门禁读数**：`test/nfc_target_test.dart` 新增 **19 例全绿**（四类目标解析／同名分类按 catId 区分 B23／书软删＝失效 B24／存在性判据／二级参数拆解／toggle 判据三分支）。
- **2026-10-17 变异三刀（各红其位·md5 复原）**：① 摘去抖窗口判定（`if (false && …)`）→ `nfc_trigger_test` 去抖两例红；② toggle 判据恒「开始」（`nfcTimerToggleAction` 恒 start）→ `nfc_target_test` 「目标正在计时⇒结束」红；③ 摘总闸（`if (false && !loadNfcEnabled())`）→ `nfc_trigger_test` 「总闸关⇒静默」红。复原后全绿。
- **2026-10-17 批2 收口门禁**：全量 `flutter analyze`＝640 issues（比开工前少 1＝清掉批1 存量 unused import），**`lib/` 命中 3 条 warning 全在未触碰的 settings 文件、error 0、NFC 零命中**；`kotlin_check.sh`＝KT-OK；`doclint.py`＝PASS strict 全绿（REGISTRY CLEAN／CARDS CLEAN／断链 0）。`docs/UI组件规范.md`：LH-S42 代码锚点由「批2 才实现」改为已交付；新增 **LH-L18 贴卡回执行**（C22 四文案／有状态卡才回执／单源结束／去抖分级／总闸静默）。
