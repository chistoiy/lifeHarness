# LifeHarness 日志系统 · 本地备份 · 双云同步 实施计划（批0~批5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地纯本地 App 的日志系统（内存+落盘+查看导出）、`.lhbak` 本地备份导出/导入恢复、坚果云 WebDAV + 缤纷云 S3 双服务备份目录差异同步（含控流与切换）。

**Architecture:** 新增三个宿主内核目录 `lib/core/logging/`、`lib/core/backup/`、`lib/core/sync/`；协议层以 `RemoteStore` 抽象挡在业务之外，所有云端请求经唯一出口 `HttpGate`；同步对象是快照目录里的 `.lhbak` + 日志文件，差异引擎只消费 `FileEntry` 清单。

**Tech Stack:** Flutter + Riverpod + go_router + sqflite；新增 `http`、`archive`、`cryptography`、`flutter_secure_storage`、`file_picker`；手写 S3 SigV4；AES-GCM(PBKDF2) 口令加密。

**Spec:** `docs/superpowers/specs/2026-09-24-sync-log-backup-design.md`（本计划逐条对应其 §1~§9）

**权威实现参考（零上下文工程师必读）：**
- `d:/dev_workplace/jiucaihezi/developSummary/protocol/cloud-storage-webdav-s3.md` —— 双协议接入规则 R1~R14、D1~D5、P1~P6、§8 骨架（下称【云盘】）
- `d:/dev_workplace/developSummary/engineering/app-log-and-error-reporting.md` —— 日志 R1~R13 与 AppLog 骨架（下称【日志】）
- `d:/dev_workplace/developSummary/mobile/single-channel-request-scheduler.md` —— 串行调度 R1~R9（下称【调度】）

## Global Constraints

每个任务的隐含要求，逐条来自设计稿 §7 与项目既定规范：

- 凭据**不进仓库/提交/日志/备份导出**：坚果云应用密码、缤纷云 AK/SK、注册邮箱、桶名的**完整值一律不落本档与任何仓库文件**（本文与代码注释均不写片段）。每个 commit 前做暂存区扫描：`git diff --cached | grep -iE "dav\.jianguoyun|s3\.bitiful|@qq\.com|accesskey|secretkey|applicationpassword"` 命中即人工复核上下文——端点域名/邮箱后缀/字段名出现属实现必需可放行，**凭据值本体出现即否决该提交**；push 一律先征得产品负责人同意（Gitee/GitHub 双通道）。真机联调凭据由产品负责人手动填入 App，助手经手零接触。
- UI：无教学性文案、无 emoji 图标（线性 SVG/纯文字）、时间/数值选择用就地滚轮；新屏一律先对照 `prototype/index-sync.html`。
- 业务层零协议分支：`isS3` 判断只允许出现在 `ServiceConfig`、`RemoteStore.forConfig` 与表单字段联动三处。
- 同一时刻只允许一个同步任务；云端请求只能经 `HttpGate.send` 发出；重发必须用工厂重建请求对象。
- 测试规范：新用例一律拆分独立文件（防 isolate 污染挂死）；`testWidgets` 用 sqflite 必须 `databaseFactoryFfiNoIsolate`；secure storage/导出目录在测试注入 fake；SnackBar 退场用 `helpers.clearToasts` 小步 pump；禁真实异步 I/O（HttpClient/createTemp）。
- 构建环境：pub 走 tsinghua 镜像可达；`flutter test` 的 sqlite3 由 `hooks.user_defines` 读本地库；`flutter build` 必须 PowerShell `Remove-Item Env:FLUTTER_STORAGE_BASE_URL` 后执行；`| tail` 管道会吞失败——判定看输出正文。
- 两档提速：批内增量只跑受影响测试组；收口批全套 `flutter test` + `flutter analyze`（0 error，warning 不新增）。
- 提交信息 Conventional Commit 中文描述；本计划所有提交仅本地，不 push。

---

## 批0 · 文档升版与专版原型

### Task 1: 需求清单 V1.41 升版 + 计划书/交接文档登记

**Files:**
- Modify: `docs/需求清单.md`（功能清单加 V1.41 段；第十节修订记录追加；§运行模式行「同步=本地备份+WebDAV」改为「WebDAV/S3 双服务可切换」；隐私红线行「除 WebDAV 外无网络请求」改为「除用户配置的 WebDAV/S3 同步外无网络请求」）
- Modify: `docs/开发计划书.md`（技术选型表加「S3：手写 SigV4 轻量客户端（http 包）」「加密存储：flutter_secure_storage(Keystore)」；M2 同步子系统节标注「提前至 V1.41 实施，口径见设计稿」）
- Modify: `docs/交接文档.md`（进展表加行：V1.41 批次启动，设计稿+实施计划落档）
- 只读参照: `docs/superpowers/specs/2026-09-24-sync-log-backup-design.md`

**Interfaces:**
- Produces: 文档口径基线，后续批次「需求 V1.41-a/b/c…」落地条引用。

- [ ] **Step 1:** 通读设计稿 §0 四项拍板口径与 §8 文档要求，按 Files 所列三处升版；需求清单条目编号沿用其现行格式（追加「模块：日志系统 / 本地备份 / 云同步（V1.41）」小节，含【云盘】R8/R9/R10 口径的面向需求表述）。
- [ ] **Step 2:** 全文搜索设计稿是否已被引用一致（计划书/交接文档中的相对路径 `docs/superpowers/specs/2026-09-24-sync-log-backup-design.md`）。
- [ ] **Step 3:** `git diff` 自查无凭据特征串后提交：`git add docs/需求清单.md docs/开发计划书.md docs/交接文档.md && git commit -m "docs(v1.41): 需求升版·日志/本地备份/双云同步(坚果云WebDAV+缤纷云S3)——设计稿口径落档"`。

### Task 2: 专版原型 `prototype/index-sync.html`

**Files:**
- Create: `prototype/index-sync.html`
- 参照: `prototype/index-health.html`（同构单文件 SPA 模式：切屏函数、弹层组件、设计令牌内联）

**Interfaces:**
- Produces: 屏 id 约定（Flutter 路由/组件命名以此为准）：`p-sync`（主页）、`p-log`（日志查看）、`p-synchist`（同步历史）、`s-svc-edit`、`s-svc-verify`、`s-diff`、`s-syncprog`、`s-backup`、`s-throttle`。

- [ ] **Step 1:** 复制 `index-health.html` 为骨架底，按设计稿 §5 表逐屏实现 9 屏/弹层。硬性内容：P1 服务卡展示协议徽标（WebDAV/S3 文字）+ 容量三态（有配额进度条 / 仅「已用 xx」 / 全 null 隐藏容量行）+「切换服务」列表 +「立即同步」「差异对比」「备份导出/导入」「控流」「日志」入口行；S1 表单 provider 切换时字段联动（地址/账户/应用密码 ↔ endpoint/region/bucket/AK/SK），凭据行有「仅存本机加密区」状态点；S3 差异四态分组+逐条勾选+底部合计「上传 n · 下载 m · 共 xx MB」；S4 进度行含「被限流，等待 8s」示例态与取消钮；P-log 显示窗口 120 条示意 + 「复制全部（300）」钮 + 级别过滤 chip + 保留天数滚轮；S6 节流三档 150/300/800ms 单选 + 快照份数 N 滚轮 + 仅 Wi-Fi 开关。
- [ ] **Step 2:** 无头校验（沿用 `tools/` 现有 v2check 思路）：每屏 DOM 断言关键文案存在、切换 provider 后字段标签变化、无教学文案泄漏（搜索「提示：」「你可以」「首先」类句式 0 命中）。
- [ ] **Step 3:** 内置浏览器逐屏走查：切屏→断言→截图到 `docs/acceptance-20260924-sync/`→控制台 0 报错。
- [ ] **Step 4:** 提交：`git commit -m "proto(sync): index-sync.html 专版原型——数据与同步9屏/弹层高保真"`（本地，不 push），**停下等产品负责人逐屏验收**；验收意见按 V 修订登记（原型原位改）。

---

## 批1 · 日志系统

### Task 3: `AppLog` 内存核心

**Files:**
- Create: `lib/core/logging/app_log.dart`
- Test: `test/log_app_log_test.dart`（新独立文件，全局规范适用）

**Interfaces:**
- Produces（后续任务依赖的精确签名）:
  - `enum LhLevel { info, warn, error }`
  - `class AppLog { static final List<LhLogLine> lines; static final ValueNotifier<int> version; static const int displayWindow = 120; static void Function(LhLogLine)? onReport; static void add(String text, {LhLevel level = LhLevel.info}); static void addStack(String stack); static void addKey(String text); static void reportError(String text); static String allText(); static String windowText(int width); static void reset(); }`
  - `class LhLogLine { final DateTime time; final LhLevel level; final String text; String get formatted; }` → `HH:mm:ss.SSS [级别] 文本`

- [ ] **Step 1: 写失败测试** `test/log_app_log_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';

void main() {
  setUp(AppLog.reset);

  test('环形缓冲上限300，丢最旧', () {
    for (var i = 0; i < 350; i++) {
      AppLog.add('line$i');
    }
    expect(AppLog.lines.length, 300);
    expect(AppLog.lines.first.text, 'line50');
    expect(AppLog.lines.last.text, 'line349');
  });

  test('formatted 含毫秒时间戳与级别', () {
    AppLog.add('boom', level: LhLevel.error);
    final f = AppLog.lines.single.formatted;
    expect(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3} \[E\] boom$').hasMatch(f), isTrue);
  });

  test('reportError 防递归：重入直接吞掉', () {
    AppLog.onReport = (l) => AppLog.reportError('re-enter'); // 模拟记录时再触发
    AppLog.reportError('first');
    expect(AppLog.lines.any((l) => l.text == 'first'), isTrue); // 不栈溢出、不死循环
    AppLog.onReport = null;
  });

  test('reportError 500ms 内合并限频', () {
    AppLog.reportError('a');
    AppLog.reportError('b');
    expect(AppLog.lines.where((l) => l.text == 'b').length, 0);
  });

  test('堆栈截断：前14行压单行', () {
    final st = List.generate(40, (i) => '#$i frame').join('\n');
    AppLog.addStack(st);
    final t = AppLog.lines.last.text;
    expect(t.split(' | ').length, 14);
    expect(t, isNot(contains('\n')));
  });

  test('allText 全量300行，displayWindow 只给120', () {
    for (var i = 0; i < 300; i++) {
      AppLog.add('l$i');
    }
    expect(AppLog.allText().split('\n').length, 300);
    expect(AppLog.windowText(1000).split('\n').length, AppLog.displayWindow);
  });
}
```

- [ ] **Step 2:** `flutter test test/log_app_log_test.dart` → 编译失败（未定义）。
- [ ] **Step 3: 实现** `app_log.dart`，照【日志】§3 骨架 + 上述接口；`addKey` 本期只进缓冲并打 `key=true` 标记（logcat 转发留 `// R13 接 NativeLog 的挂点`，Android EventChannel 在 Task 5 一并接 file sink 时不做全量镜像）；`onReport` 为测试钩子 `static void Function(LhLogLine)? onReport;`；`windowText(int width)` 取最近 width 条再截 displayWindow；`version` 通知走 300ms `Timer` 节流合并（测试里用 `fakeAsync` 或直接容忍）。
- [ ] **Step 4:** 跑测试全绿。若节流 Timer 导致 version 断言不稳定，不断言 version 值本身（既定坑：禁单次大 pump）。
- [ ] **Step 5:** 提交 `feat(logging): AppLog 环形缓冲/节流/防递归/截断（需求V1.41-a）`。

### Task 4: 全局三处错误捕获接入 `main.dart`

**Files:**
- Modify: `lib/main.dart`（`main()` 最前，`WidgetsFlutterBinding.ensureInitialized()` 之后立刻挂三处，**先于** `SharedPreferences.getInstance()`——R1 启动即记）
- Test: `test/log_error_capture_test.dart`

**Interfaces:**
- Consumes: `AppLog.reportError` / `AppLog.addStack`
- Produces: `void installGlobalErrorLogging()`（从 main.dart 提取到 `lib/core/logging/error_capture.dart`，供测试直接调用）

- [ ] **Step 1: 写失败测试：**

```dart
testWidgets('FlutterError 构建错误进日志', (tester) async {
  installGlobalErrorLogging();
  final err = FlutterErrorDetails(exception: StateError('x'), library: 'test');
  FlutterError.reportError(err);
  expect(AppLog.lines.any((l) => l.text.contains('FlutterError') && l.text.contains('x')), isTrue);
});
```

外加一条：`ErrorWidget.builder` 被调用后缓冲含 `WidgetError`；一条：`PlatformDispatcher.instance.onError` 返回 true 且记 `未捕获异常`。测试结束 `tearDown` 还原三处原值（保存 old 引用）。

- [ ] **Step 2:** 跑红。
- [ ] **Step 3:** 实现 `error_capture.dart`：三处赋值照【日志】§3（presentError 保留、占位 Widget 文案「页面局部错误（详情见日志）」——符合 R12 且无教学句）；`main()` 首行调用。
- [ ] **Step 4:** 跑绿 + 快速跑 `flutter test test/log_app_log_test.dart` 确认互不污染。
- [ ] **Step 5:** 提交 `feat(logging): 三处全局错误捕获接入组合根`。

### Task 5: `FileLogSink` 按天滚动落盘

**Files:**
- Create: `lib/core/logging/file_log_sink.dart`
- Modify: `lib/main.dart`（初始化顺序：打开目录 → FileLogSink.init → 把启动至今的缓冲行补写一次）
- Test: `test/log_file_sink_test.dart`

**Interfaces:**
- Produces: `class FileLogSink { static Future<void> init(String dirPath, {int retentionDays = 14}); static void write(LhLogLine line); static Future<void> flush(); static Future<List<String>> dayFiles(); }`；文件命名 `lh-YYYYMMDD.log`；单文件超 5MB 追加 `.1`、`.2` 分卷。
- AppLog 侧新增：`static void Function(LhLogLine)? onLine;`（FileLogSink 挂载；替换原 addKey 的 logcat 挂点说明）。

- [ ] **Step 1: 写失败测试**（纯 `test()` + 注入临时目录，用 `flutter_test` 的 `addTearDown` 删目录；生产目录才走 path_provider，测试不碰）：init 后 `write` 三行 → `flush` → 断言当天文件存在且含 3 行、格式同 `formatted`；`retentionDays: 0` 时先手造 `lh-20000101.log` → init 后该文件被删；5MB 分卷用写入小阈值参数（`maxBytes` 注入，测试传 200）验证滚出 `.1`。
- [ ] **Step 2:** 跑红。
- [ ] **Step 3:** 实现：内部 `Timer.periodic(3s)` 批量 append（`File.writeAsString(mode: append)`），`write` 只进待刷队列（环形、超 500 行即刷），绝不同步写；错误/关键行 `write` 后立即刷。**凭据脱敏在此层统一做**：`sanitize(String)` 把 `Authorization:`、`X-Amz-Signature`、`credential=`、口令字段值替换为 `***(…尾4位)***`（正则见实现），AppLog 所有入口先过 sanitize——Global Constraints 的代码化落点。
- [ ] **Step 4:** 跑绿。
- [ ] **Step 5:** 提交 `feat(logging): FileLogSink 按天滚动落盘+保留天数+凭据脱敏`。

### Task 6: 日志查看页 + 设置页接入口

**Files:**
- Create: `lib/features/settings/presentation/log_page.dart`
- Modify: `lib/core/router/app_router.dart`（加 `GoRoute(path: '/log', …)`）
- Modify: `lib/features/settings/presentation/settings_page.dart`（占位行区加「运行日志」行 → `context.go('/log')`）
- Test: `test/log_page_test.dart`

**Interfaces:**
- Consumes: `AppLog.lines/version/allText/windowText`、`FileLogSink.dayFiles`
- Produces: 路由 `/log`；页面用 `ValueListenableBuilder<int>(valueListenable: AppLog.version)` 仅局部件订阅（R7）。

- [ ] **Step 1: 写失败 widget 测试：** `helpers.wrapWithApp(...)` 打开 `/log` → ①注入 350 条后窗口列表渲染 ≤120 行（用 find.byType 计数）；②级别 chip「全部/警告+/错误」过滤生效；③点「复制全部」→ 剪贴板 mock（`MockClipboard` 覆盖 `ServicesBinding.defaultBinaryMessenger` 的 `flutter/platform` channel）收到的文本行数 == `AppLog.lines.length`；④保留天数滚轮出现且当前值回显。禁真实异步 I/O：FileLogSink 一律经 `init(dirPath)` 参数注入临时目录，页面不直接调 path_provider。
- [ ] **Step 2:** 跑红。
- [ ] **Step 3:** 实现页面：ListView.builder 渲染 `windowText`（key 用行号+时间防重建风暴）、顶部工具行（过滤 chip / 复制钮 / 保留天数入口→就地滚轮 CWheel 组件复用）、底部显示「文件日志：最近 3 天文件名列表」。样式对照原型 `p-log`，遵循 LH 组件规范（`docs/UI组件规范.md`）。
- [ ] **Step 4:** 跑绿，增量跑 `flutter test test/settings_controller_test.dart`（设置页行未破坏）。
- [ ] **Step 5:** 提交 `feat(logging): 日志查看页/复制全量/级别过滤/保留天数设置`。

---

## 批2 · 本地备份 `.lhbak`

### Task 7: 依赖引入与环境验证

**Files:**
- Modify: `pubspec.yaml`（`http: ^1.2.0`、`archive: ^3.6.1`、`cryptography: ^2.7.0`、`flutter_secure_storage: ^9.2.2`、`file_picker: ^8.1.3`，版本以 pub 镜像可解析的最新兼容为准）
- Modify: `android/app/src/main/AndroidManifest.xml`（`<uses-permission android:name="android.permission.INTERNET"/>` 仅 release+debug 需要；离线策略记忆：除同步外无网络请求，权限注释写明）

- [ ] **Step 1:** `flutter pub get`（tsinghua 镜像），失败则按解析器提示微调版本约束；**不许**为绕版本冲突升级既有依赖大版本。
- [ ] **Step 2:** `flutter analyze` 0 新错误；`flutter test test/database_schema_test.dart` 冒烟确认工程仍绿。
- [ ] **Step 3:** 提交 `chore(deps): 引入 http/archive/cryptography/secure_storage/file_picker + INTERNET 权限（V1.41）`。

### Task 8: `LhBak` 容器（manifest/打包/解包/校验）

**Files:**
- Create: `lib/core/backup/lh_bak.dart`
- Test: `test/backup_lh_bak_test.dart`

**Interfaces:**
- Produces:
  - `class LhBakManifest { int dbVersion; String appVersion; DateTime createdAt; Map<String, TableStat> tables; List<String> excludedTables; bool encrypted; List<String> members; }`，`class TableStat { int rows; String checksum; }`（checksum = 逐行拼接 `name=值;…` 的 MD5 hex，空表为 `'-'`）
  - `static Future<LhBakCreateResult> create({required Database db, required String outDirPath, List<String> attachDirs = const [], List<String> logFiles = const [], List<String> excludeTables = const [], DateTime? now})` → 返回 `File file; LhBakManifest manifest;`
  - `static Future<LhBakManifest> verify(String filePath)` — 抛 `LhBakException(code)`，code ∈ {`badZip`,`badManifest`,`versionMismatch`,`checksumMismatch`}
  - `static Future<LhBakManifest> unpack({required String filePath, required Database targetDb})` — 解出 db.sqlite 覆盖恢复到 target 连接（内部：删旧表重建→ATTACH 快照文件→逐表 INSERT；`excludeTables` 生成的包在恢复报告中列缺失表）

- [ ] **Step 1: 写失败测试**（ffi 内存库 + 注入临时导出目录，遵守 testWidgets 规范；这里是纯 `test()` 可用 `databaseFactoryFfi`）：
  - create→verify 往返通过；manifest 表数 == `DbSchema.createStatements` 里实表数（排除 `plugin_` 前缀预留空表可选入 `excludedTables`——**默认全量含 plugin_ 表**，因为备份要「整包备份随到随走」既定规范）；
  - 改 1 行后再 create，旧包 verify 报 `checksumMismatch`；
  - zip 字节尾部截断 → `badZip`；manifest 里 `dbVersion` 改成 9999 → `versionMismatch`（App 版本 > 包版本才拒；包版本 ≤ App 历史版本允许，按 `dbVersion > DbSchema.version` 判）；
  - `excludeTables: ['care_events_x']`（造一个 care 表名）→ manifest.excludedTables 含之、db 快照无该表数据行。
- [ ] **Step 2:** 跑红。
- [ ] **Step 3:** 实现：`VACUUM INTO` 得快照文件 → `archive` 打包 zip（成员：`manifest.json`、`db.sqlite`、`attachments/<原相对路径>`、`logs/<文件名>`）；文件命名 `lifeharness_YYYYMMDD_HHmmss.lhbak`；checksum 计算放独立纯函数 `String tableChecksum(List<Map<String,Object?>> rows)` 便于单测。
- [ ] **Step 4:** 跑绿。
- [ ] **Step 5:** 提交 `feat(backup): .lhbak 容器——manifest校验/VACUUM INTO快照/打包解包`。

### Task 9: AES-GCM 口令加密档

**Files:**
- Modify: `lib/core/backup/lh_bak.dart`（create/verify/unpack 加 `{String? passphrase}` 参数；manifest.encrypted=true 时 zip 成员 `db.sqlite.enc`、`attachments/**.enc` 为密文 blob：`salt(16B)|nonce(12B)|密文`）
- Test: `test/backup_crypto_test.dart`

**Interfaces:**
- Produces: `LhBak.create(..., passphrase)`、`LhBak.verify(path, passphrase: )`；`LhBakException.code == 'needPassphrase' | 'wrongPassphrase'`。

- [ ] **Step 1: 写失败测试：** 口令包不带口令 verify → `needPassphrase`；错口令 → `wrongPassphrase`；对口令 → create→verify→unpack 往返后逐表 checksum 与明文包一致；`cryptography` 的 AES-GCM + PBKDF2(SHA256, 100k 轮, c 参数进 manifest) 直接可用（非 flutter 绑定），ffi 纯 Dart 测试无平台通道问题。
- [ ] **Step 2~4:** 红→实现→绿。
- [ ] **Step 5:** 提交 `feat(backup): .lhbak 可选口令加密（PBKDF2+AES-GCM）`。

### Task 10: `BackupService` 导出/导入恢复 + 备份半屏（S5）

**Files:**
- Create: `lib/core/backup/backup_service.dart`
- Create: `lib/features/settings/presentation/sync_backup_sheet.dart`（S5/S 弹层组件）
- Modify: `lib/core/router/app_router.dart` + `settings_page.dart`（「数据与同步」占位行改真实路由 `/sync`——本批先建 `/sync` 空壳页占住路由，批5 完成主页；「备份导出/导入」从空壳行进弹层）
- Test: `test/backup_restore_test.dart`, `test/backup_sheet_ui_test.dart`

**Interfaces:**
- Consumes: `LhBak.create/verify/unpack`、`FileLogSink.dayFiles`、`AppDatabase`
- Produces:
  - `class BackupService({required String Function() exportDir, required Future<Database> Function() db})`（目录与库注入可测；`exportDir` 在同步快照场景由调用方覆盖）
  - `Future<LhBakCreateResult> exportBackup({bool withLogs = false, bool withAttachments = true, String? passphrase, List<String> excludeTables = const [], String? outDirOverride, String? nameTag})` — `nameTag:'auto_before_restore'` 产自动备份；批4 SnapshotService 经 `outDirOverride`+`excludeTables` 复用本函数产同步快照
  - `Future<RestoreReport> importBackup(String filePath, {String? passphrase})` — 内部顺序：verify → **当前库先 `exportBackup(autoTag:true)`（命名 `auto_before_restore_*.lhbak`，永不进同步目录）** → close → unpack → reopen → 报告（表数/行数/缺失排除表清单）
  - `Future<String?> pickBackupFile()` — file_picker 包装；**测试环境注入 fake 选择器**；若 file_picker 在 CI/模拟器异常，降级路径 = 从导出目录列表选（UI 同时提供「本机导出记录」tab）。

- [ ] **Step 1:** 写 `backup_restore_test.dart`（ffi 内存库 + 临时目录）：导出→改数据→导入→断言数据回滚且 `auto_before_restore_` 文件存在；带口令包走 passphrase 参数链；坏包三类 code 冒泡为 `LhBakException` 不半恢复（恢复前置校验失败时现库不动）。
- [ ] **Step 2:** 红→实现→绿。
- [ ] **Step 3:** 写 UI 测试：S5 半屏含「包含附件」「附带日志」「口令（可空，二次输入一致才启用）」、导出成功 toast 文案「已导出：<文件名>」（无教学句）；导入选择→校验报告态→「恢复将替换当前数据」二次确认→确认后才调 `importBackup`（测试注入 fake 服务断言调用次数=0/1）。
- [ ] **Step 4:** 红→实现（对照原型 `s-backup`；恢复按钮置确认勾选之后）→绿。
- [ ] **Step 5:** 全增量跑 `flutter test test/backup_lh_bak_test.dart test/backup_crypto_test.dart test/backup_restore_test.dart test/backup_sheet_ui_test.dart test/settings_controller_test.dart` 全绿；提交 `feat(backup): 导出/导入恢复全流程+S5半屏（含恢复前自动备份）`。

---

## 批3 · 协议层

### Task 11: `ServiceConfig` + 凭据保险箱 + 兼容单测

**Files:**
- Create: `lib/core/sync/service_config.dart`, `lib/core/sync/credential_vault.dart`
- Test: `test/sync_config_test.dart`

**Interfaces:**
- Produces:
  - `enum StoreProviderKind { webdav, s3 }`
  - `class ServiceConfig { String id; StoreProviderKind provider; String apiUrl; String account; String region; String bucket; String cloudDirName; int requestIntervalMs; bool verifyContent; bool get isS3; }`（**无 authCode 字段**——凭据只走 vault，明文 prefs 里该服务键存 authCode:''占位，D1）
  - `class CredentialVault { Future<String?> read(String serviceId); Future<bool> write(String serviceId, String secret); Future<void> delete(String serviceId); }`（flutter_secure_storage 包装 + `service_secret_{id}` 键约定 + 写失败返回 false 调用方保留原值，R11）
  - `SyncConfigStore`（prefs JSON：`{services:[...], activeId}`）：`load()` 缺 provider/region/bucket/节奏字段一律落 WebDAV 默认（R4）；同服务内 `cloudDirName` 唯一、跨服务可同名（§3 不变式）。
- [ ] **Step 1:** 写失败测试：旧格式 JSON（无 provider 字段）load 成功且 provider==webdav、requestIntervalMs==300；凭据 write→read 一致；write 返回 false 时旧值仍在（内存 fake vault 注 `failNext`）；同服务重名目录报错、跨服务同名通过。测试注入**内存版保险箱**（`CredentialVault.inMemory()`——既定坑：真实加密存储无测试平台通道）。
- [ ] **Step 2:** 红→实现→绿。
- [ ] **Step 3:** 提交 `feat(sync): ServiceConfig/SyncConfigStore/CredentialVault（R4兼容单测）`。

### Task 12: `HttpGate` 唯一请求出口（节流 + 退避）

**Files:**
- Create: `lib/core/sync/http_gate.dart`
- Test: `test/sync_http_gate_test.dart`

**Interfaces:**
- Produces（【云盘】§8 签名，实例化为**实例方法**并导出全局单例 `final httpGate = HttpGate(...)`）:
  - `class HttpGate { HttpGate({Future<void> Function(Duration)? sleeper, DateTime Function()? clock}); Future<http.StreamedResponse> send(http.Client client, http.BaseRequest Function() build, {required ServiceConfig config, required String label, int maxAttempts = 3}); }` —— 测试注入假 sleeper（不真等）+ 假 client；生产 sleeper 默认 `Future.delayed`。
  按 `config.requestIntervalMs` 节流（间隔读取放在 `send` 内，经 `Throttle` 私有内部类按服务 id 记录上次请求时刻）。
  - `Duration? waitForStatus(int statusCode, String? retryAfterHeader, int attempt, DateTime now)` 纯函数（顶层导出供单测）：非 429/503 → null；`Retry-After` 秒数与 HTTP-date 双形态；缺省 `2s<<attempt`；上限 30s。
- [ ] **Step 1:** 写失败测试（`package:http/testing.dart` 的 `MockClient`）：
  - 429→200 两次尝试成功，且断言**请求工厂被调用 2 次**（build 计数）；
  - `Retry-After: 5` → 记录等待 5s（假 sleeper 捕获参数）；HTTP-date 形态按 `now` 差值；
  - 连 3 次 503 → 返回最后一个 503 响应给调用方（不吞）；
  - 节流：config.requestIntervalMs=800 时连续两请求，假 sleeper 断言第二次被喂 ~800ms 减已耗时（宽松下限断言 >0）；
  - 中文 label 透传日志 `AppLog.add` 的脱敏不在此层（已在 Task 5 统一）。
- [ ] **Step 2:** 红→实现→绿。全局唯一性由架构守护补一条规则：`test/architecture_test.dart` R5：`lib/core/sync/**` 除 `http_gate.dart` 外不得出现 `.send(`/`http.Client(`（仿 R4 空增量守护的写法，先注入违例文件验证会变红——既定教训）。
- [ ] **Step 3:** 跑绿 + 守护红→绿复验；提交 `feat(sync): HttpGate唯一出口（按服务节流+429退避重发重建）+R5绕行守护`。

### Task 13: `RemoteStore` 抽象 + `WebDavStore`（坚果云）

**Files:**
- Create: `lib/core/sync/remote_store.dart`, `lib/core/sync/webdav_store.dart`
- Test: `test/sync_webdav_test.dart`

**Interfaces:**
- Produces（【云盘】§8 六方法 + 分发）:
  - `class FileEntry { String relativePath; int size; String? etag; DateTime? modified; }`、`class CloudListing { List<FileEntry> files; }`、`class CloudQuota { int? quotaBytes; int? usedBytes; Map<String,int> collectionUsed; }`、`class VerifyResult { bool ok; String? message; }`
  - `abstract class RemoteStore { Future<CloudListing> list(ServiceConfig c, String cloudDirName, {bool force=false}); Future<void> put(ServiceConfig c, String localPath, String cloudRelative); Future<void> get(ServiceConfig c, String cloudRelative, String localPath); Future<void> ensureDirectory(ServiceConfig c, String cloudRelativeDir); Future<VerifyResult> verify(ServiceConfig c); Future<CloudQuota> quota(ServiceConfig c, {bool force=false}); void close(); static RemoteStore forConfig(ServiceConfig c, {HttpGate? gate}); }`
  - `List<FileEntry> parsePropfindXml(String utf8Xml)` 纯函数导出供单测。
- [ ] **Step 1:** 写失败测试（MockClient 喂固定 XML）：中文+空格+`&` 转义文件名解析正确；`getetag` 去引号、`W/` 前缀保留原样；Depth:1 递归拼相对路径且限深 10 触发 `AppLog` warn；MKCOL 收到 405 视为成功且第二次同目录**不再发请求**（MockClient 计数）；`/nsdav/getUserInfo` 解析 storage_quota/used/collection[]（href 带 URL 编码尾斜杠→归一化命中目录名）；所有 XML 响应走 `utf8.decode(bodyBytes)`（造 latin1 陷阱字节断言不乱码）。
- [ ] **Step 2:** 红→实现（PROPFIND 四属性请求体固定；Authorization Basic 由 config+vault 现取现拼，永不进日志原文——HttpGate label 只写方法+路径）→绿。
- [ ] **Step 3:** 提交 `feat(sync): WebDavStore坚果云（PROPFIND递归/MKCOL记忆/getUserInfo容量/utf8）`。

### Task 14: `S3Store` + 手写 SigV4（缤纷云）

**Files:**
- Create: `lib/core/sync/s3_sigv4.dart`, `lib/core/sync/s3_store.dart`
- Test: `test/sync_s3_sigv4_test.dart`, `test/sync_s3_store_test.dart`

**Interfaces:**
- Produces:
  - `class SigV4Signer { SigV4Signer({required String accessKey, required String secretKey, required String region, required String service, DateTime Function()? clock}); SignableRequest sign(http.BaseRequest req, {required String payloadHash}); }` → `canonicalRequest` 中间串可 `debugCanonical()` 暴露给测试。
  - `S3Store implements RemoteStore`；`listAll` 翻页（max-keys=1000，200 页硬顶，`Key` 尾 `/` 占位对象剔除）；`quota` 打**根 endpoint** ListAllMyBuckets，`usedBytes = Σ(ImageBytes+TmpBytes+VideoBytes+AudioBytes+OtherBytes)`，`quotaBytes = null`；`verify` = `GET /?list-type=2&max-keys=1`；`ensureDirectory` 空实现。
- [ ] **Step 1:** SigV4 测试（**不虚构官方签名期望值**——用结构断言 + 真机复验双保险）：
  - canonical 构造钉死：URI 分段编码（空格→%20、中文→percent-encoding、`/` 不编码）、query 按 key 排序且键值各自编码、`host;x-amz-date;x-amz-content-sha256` 头序、credentialScope=`{yyyyMMdd}/s3/cn-east-1/aws4_request`；
  - PayloadHash 三态：空体 GET=SHA256("")；流式 PUT=`UNSIGNED-PAYLOAD`；带体 POST=实体 SHA256；
  - 签名日期取自注入 clock，clock 拨 +20 分钟 → `X-Amz-Date` 与 credential scope 同步变化（证明日期参与签名；真机 403 复验列入 Task 19 验收项）；
  - 虚拟主机寻址 URL：`https://{bucket}.s3.bitiful.net/{key}`；桶名含点在 host 段的编码一致性用例。
- [ ] **Step 2:** 红→实现→绿。
- [ ] **Step 3:** S3Store 测试（MockClient）：两页 `IsTruncated` 翻页聚合；目录占位对象不计入 files；私有 `*Bytes` 字段解析（缤纷云 XML 样例内联为测试常量）；`?stat`/服务端限速头**不出现**在实现里（grep 守护并入 architecture_test R5 附加断言：`x-bitiful-limit-rate` 0 命中）。
- [ ] **Step 4:** 红→绿；提交 `feat(sync): S3Store+手写SigV4（virtual-hosted/递归列举/私有用量字段）`。

---

## 批4 · 差异引擎与同步编排

### Task 15: `DiffService` 三档一致性

**Files:**
- Create: `lib/core/sync/diff_service.dart`
- Test: `test/sync_diff_test.dart`

**Interfaces:**
- Produces:
  - `enum DiffStatus { onlyLocal, onlyRemote, modified, inSync }`
  - `class FileDiff { String relativePath; DiffStatus status; FileEntry? local, remote; bool staleHint; }`
  - `bool sameEntry(FileEntry l, FileEntry r)`（【云盘】§8 `same()` 逐字语义：size 不等→false；digest 且远端 32hex→摘要比对；双强 ETag→ETag 比对；否则默认档 true；**绝不 mtime**）
  - `List<FileDiff> computeDiff({required List<FileEntry> local, required List<FileEntry> remote, required Set<String> ignorePatterns, Set<String> ledgerKnown = const {}})`（忽略规则**两侧同时剔除**，D5；glob 只支持 `*.ext` 与前缀两类，够本期用；`onlyRemote` 且 `ledgerKnown.contains(path)` → `staleHint=true`，台账空=known 空=不报残留）

- [ ] **Step 1:** 写失败测试：四态判定各一例；弱 ETag（`W/"abc"`）退回 size 档判 inSync；分片 ETag `d41…-7` 且 digest 已算→不误判；两侧各留一个 `.DS_Store` 仅云端版→被忽略规则剔除不报 onlyRemote；同路径大小写敏感性钉死（相对路径按原文匹配，不 lower）。
- [ ] **Step 2:** 红→实现→绿。
- [ ] **Step 3:** 提交 `feat(sync): 差异引擎四态+三档一致性（不用mtime，D5双侧忽略）`。

### Task 16: 同步台账 + 快照生成 `SnapshotService`

**Files:**
- Create: `lib/core/sync/sync_ledger.dart`, `lib/core/sync/snapshot_service.dart`
- Test: `test/sync_ledger_test.dart`, `test/sync_snapshot_test.dart`

**Interfaces:**
- Produces:
  - `class SyncLedger`（prefs 键 `sync_ledger_{serviceId}|{cloudDirName}`，值 `Map<relativePath, {etag,size,ts}>`；`record(list)`、`isKnown(path)`、`prune(paths)`）——残留判定：`onlyRemote && ledger.isKnown(p)` 标 `staleHint: true`（仅提示角标，V1 不提供删除，E5）；**台账空不报残留**。
  - `class SnapshotService`：`Future<List<FileEntry>> localInventory()`（同步目录 = `<docs>/sync/`，含快照 `lifeharness_*.lhbak` + `logs/`）；`Future<SyncSnapshot> build({required int keepN})`——调 `BackupService.exportBackup(withLogs:true)` 产出快照后按 N 裁剪（默认 N=5；`auto_before_restore_` 前缀文件**永不**进同步目录，落 `exports/`），并按 `care.syncExcluded()`（读 `CareRepository.kvBool`，经注入函数）决定 `excludeTables`（呵护十一表清单常量在 DbSchema 加 `static const careTables`）。
- [ ] **Step 1:** 写失败测试：台账空→onlyRemote 全判「新文件」非残留；台账有+本地无+云端在→staleHint；`build(keepN:3)` 生成第 4 个快照后最旧两个被裁、当前激活快照不裁；`syncExcluded=true` 时 manifest.excludedTables ⊇ careTables 且恢复报告（Task 10 链路复用）列缺失表；`false` 时全量。
- [ ] **Step 2:** 红→实现→绿。
- [ ] **Step 3:** 提交 `feat(sync): 同步台账残留判定+快照目录N份裁剪+care排表联动`。

### Task 17: `SyncOrchestrator` 编排（上传/下载/进度/取消/历史）

**Files:**
- Create: `lib/core/sync/sync_orchestrator.dart`
- Test: `test/sync_orchestrator_test.dart`

**Interfaces:**
- Consumes: `RemoteStore.forConfig`、`HttpGate`、`computeDiff`、`SyncLedger`、`SnapshotService`
- Produces:
  - `class SyncTaskState { List<FileDiff> diffs; bool running; FileDiff? current; int done, total; String? rateLimitedWait; }`（`ValueNotifier<SyncTaskState>`）
  - `Future<List<FileDiff>> compare()`（1 次远端 list + 本地清单，60s 清单缓存）
  - `Future<SyncOutcome> run(List<FileDiff> selected)`：仅本地/已修改→上传（先附件类文件后 `.lhbak`——批量原子性「先附件→后DB→成功标记」在此落为「非快照文件先传、快照最后传、成功即 record 台账」）；仅云端→下载到 `exports/`（**不自动导入**，完成提示引导去 S5 导入）；同任务内严格串行（调度方案 R3）；`cancel()` 置标志当前文件传完即停、队列清空；429 退避发生在 HttpGate，进度态透出 `rateLimitedWait`。
  - 历史：`SyncHistory`（prefs JSON，`{ts, serviceId, dir, up, down, bytes, ok, error?}` 上限 100 条）——不落 DB 新表（避免 DB v20；备份可见性走 prefs 导出）。
- [ ] **Step 1:** 写失败测试（注入假 RemoteStore）：串行断言（假 store 记并发水位==1）；勾选混合清单上传顺序=非快照先、快照最后、全部成功后台账含快照路径；中途 cancel → 已传部分台账已记、未传不记、`running=false`；假 store 抛异常 → 该文件计入失败清单且 `run` 正常返回部分成功 outcome（不整任务炸，调度 R9 不吞错但也不 rethrow 到 UI 外）；历史写入 100 条截断。
- [ ] **Step 2:** 红→实现→绿。
- [ ] **Step 3:** 提交 `feat(sync): 编排器（串行/续传台账/取消/仅云端下载引导导入/历史100条）`。

---

## 批5 · UI 接线与收口

### Task 18: `/sync` 主页 + 历史页 + 控流弹层 + 服务配置全接线

**Files:**
- Create: `lib/features/settings/presentation/sync_page.dart`（P1）、`sync_history_page.dart`（P2）、`widgets/sync_sheets.dart`（S1 配置编辑 / S3 差异半屏 / S4 进度半屏 / S6 控流弹层）
- Modify: `lib/core/router/app_router.dart`（`/sync`、`/sync/history`）、批2 占的 `/sync` 空壳页替换、`settings_page.dart`「数据与同步」行副标题从占位文案改为原型口径「WebDAV · 备份 · 加密 · 同步历史」（已是）→ 仅接路由
- Test: `test/sync_page_ui_test.dart`, `test/sync_diff_sheet_ui_test.dart`

**Interfaces:**
- Consumes: 批3/4 全部公开接口
- Produces: 全部路由与弹层组件命名对齐原型屏 id（`p-sync`→`/sync` 等）

- [ ] **Step 1:** 写失败 UI 测试（服务层全 fake 注入——`syncServiceProvider` 等 Riverpod override，禁真实网络）：P1 容量三态各渲染正确（有配额含进度条、仅已用、全 null 无容量行）；provider 切 S3 时 S1 表单标签变「Access Key/Secret Key」；S3 差异半屏四态分组与合计行；勾选后点「同步」→ S4 出现且 fake store 收到对应调用；S6 档位单选回写 `ServiceConfig.requestIntervalMs`。
- [ ] **Step 2:** 红→实现（逐屏对照原型截图验收基线，组件复用 ui_kit/LH 规范）→绿。
- [ ] **Step 3:** 增量组跑绿；提交 `feat(sync): 数据与同步主页/历史/配置/差异/进度/控流全接线`。

### Task 19: 收口（全套回归 + 真机联调 + 四件套升版 + 预发布）

**Files:**
- Modify: `pubspec.yaml`（version `0.1.19+4017`）
- Modify: `docs/需求清单.md`（V1.41 落地条：实现偏差登记、延后项）、`docs/交接文档.md`（进展行+变更日志 3~5 行）、`docs/开发计划书.md`（同步子系统节状态）

- [ ] **Step 1:** 全套回归：`flutter test --reporter expanded`（实时可观察，既定规范）全绿；`flutter analyze` 0 error；`flutter test test/architecture_test.dart` R5 守护含「注入违例→红→撤除→绿」复验记录。
- [ ] **Step 2:** 真机/模拟器联调（AVD Small_Phone_API_35，PowerShell 去 `FLUTTER_STORAGE_BASE_URL` 出 debug 包）：**请产品负责人手动输入坚果云与缤纷云凭据**→ 双服务连接验证（S2 三态）、真机中文文件名上传下载各 1、缤纷云容量只有已用、日志页出现「被限流等待」样本（可临时把档位调 800ms 连续同步观察）、±设备时间演示签名失效（可选）。全程凭据不出现在任何截图存档命名与文档中。
- [ ] **Step 3:** 文档升版三件套 + pubspec 版本号；提交前暂存区凭据特征串扫描（0 命中）并 `git log -p -3` 复核无泄漏。
- [ ] **Step 4:** 本地提交 `chore(v1.41): 日志/备份/双云同步收口 — 全量回归+真机联调+四件套升版 pubspec 0.1.19+4017`。**征得同意后**双通道 push + 预发布挂 APK（Gitee 优先、GitHub 失败仅提醒；Gitee 预发布必须核对三包附件非空——既定规范）。
- [ ] **Step 5:** 项目记忆更新（交付态、遗留项）；提醒进入真机逐屏验收环节。

---

## 延后/不做（本计划边界）

- 数据库级双向记录合并（口径已拍板为目录级差异同步；manifest 校验和已为其预留识别能力）。
- 镜像删除（云端删/本地删传播）——台账数据攒够后按【云盘】E5 另立批次评审。
- logcat 全量镜像、远程日志上报（隐私红线排除）。
- 自动同步多目录映射管理（本期单激活服务 × 单同步目录；`cloudDirName` 字段已预留多目录扩展位）。
