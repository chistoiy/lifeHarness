import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';
import 'package:lifeharness/core/platform/desktop_shortcuts.dart';

/// 四路 Intent 形态守护（冻结档 C15 · `test/desktop_intent_shape_test.dart`）。
///
/// **C15 红线**：长按菜单（`setDynamicShortcuts`）／铺桌面（`requestPinShortcut`）／
/// 小组件（`PendingIntent`，批 2）三路**自建 Intent** 一律
/// `ACTION_VIEW + setData(lh://…)`。
/// **只 setAction 不 setData 会误匹配既有 content/file 打开方式 filter**——
/// 本测试钉住「Dart 侧下发的 scheme 必须携带在 data 里」，原生侧构造由
/// `tools/kotlin_check.sh`＋真机门兜。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/desktop'), (call) async {
      calls.add(call);
      if (call.method == 'syncShortcuts') {
        return ((call.arguments as Map)['actions'] as List).length;
      }
      if (call.method == 'requestPinShortcut') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/desktop'), null);
  });

  test('syncShortcuts 下发的 scheme 逐字等于动作表原值（C15）', () async {
    await syncShortcuts(kDefaultMenuActionIds);
    final m = calls.first.arguments as Map;
    final schemes = (m['schemes']! as List).cast<String>();
    expect(schemes,
        <String>['lh://inbox/new', 'lh://todo/new', 'lh://ledger/add', 'lh://habit/check']);
    // 逐字比对 Uri.toString()：原生侧只做 Uri.parse 转发，不允许改写
    for (var i = 0; i < schemes.length; i++) {
      expect(Uri.parse(schemes[i]).toString(), schemes[i],
          reason: 'scheme 必须能被 Uri.parse 原样还原（原生逐字比较用）');
    }
  });

  test('syncShortcuts 超过 4 枚自动截断到系统硬限', () async {
    await syncShortcuts(kDesktopActions.map((a) => a.id).toList());
    final m = calls.first.arguments as Map;
    expect((m['actions']! as List).length, kMenuMax);
  });

  test('syncShortcuts 过滤表外动作 id（禁拼错意图进系统）', () async {
    await syncShortcuts(<String>['ledger', 'ghost', 'today']);
    final m = calls.first.arguments as Map;
    expect((m['actions']! as List).cast<String>(), <String>['ledger', 'today']);
  });

  test('requestPinShortcut 携带该动作的 scheme（非裸 path）', () async {
    await requestPinShortcut('ledger');
    final m = calls.last.arguments as Map;
    expect(m['action'], 'ledger');
    expect(m['scheme'], 'lh://ledger/add');
    expect(Uri.parse(m['scheme']! as String).scheme, 'lh');
  });

  test('requestPinShortcut 对未知动作抛错（禁静默发空意图）', () {
    expect(() => requestPinShortcut('ghost'), throwsArgumentError);
  });

  test('回归：只 setAction 不 setData 的意图匹配不上 lh://（钉 C15 事故本体）', () {
    // 系统派发 lh:// 的判定依据是 **data 的 scheme**；只有 action 没有 data 的 Intent
    // 进不了本模块的分支，会落到既有 content/file filter 上（或无处可去）。
    final onlyAction = 'android.intent.action.VIEW';
    expect(onlyAction, isNot('lh'));
    // 本模块认的是 data scheme，不是 action ⇒ action 一律等于 ACTION_VIEW，
    // 唯一区分维度在 data。
    for (final a in kDesktopActions) {
      final u = Uri.parse(a.scheme);
      expect(u.scheme, 'lh', reason: '${a.id} 必须落在 lh scheme');
      expect(u.host, a.ns, reason: '${a.id} host 必须是 ns');
    }
  });

  test('四路目标路由同源：任一动作从任一路进来都是同一条 path', () {
    // 四路（长按菜单/铺桌面/小组件/外部链接）都只引用动作表 path —— 天然一致。
    for (final a in kDesktopActions) {
      expect(desktopLaunchUri(a.id).toString(), a.scheme);
      expect(desktopActionOf(a.id)!.path, a.path);
    }
  });

  // ================= V1.67 热修守护：URI 分解口径 =================
  // 真机伤：`lh://ledger/add` 的 ns 落在 **authority(host)**，只取 `Uri.path` 得到
  // "/add" ⇒ ns 校验必失败 ⇒ 意图被静默丢弃 ⇒ 四路点击全落回首页。本组两侧各钉一头。

  test('URI 分解口径：ns 在 authority ⇒ 段＝launchSegOf（钉「只取 Uri.path」的旧口径）',
      () {
    // 反例先行：把事故本体写在断言里，后人一眼看清为什么不能只取 path。
    expect(Uri.parse('lh://ledger/add').path, '/add',
        reason: 'Uri.path 只含 key 段 —— ns 在 authority，取 path 就会丢掉 ns');
    expect(Uri.parse('lh://ledger/add').host, 'ledger');

    for (final a in kDesktopActions) {
      final u = Uri.parse(a.scheme);
      // host 是 ns；段＝ns/key，且能解析回本动作 id（口径闭环）。
      expect(u.host, a.ns, reason: '${a.id}：ns 必须落在 authority');
      expect(launchSegOf(u), a.path == '/' ? a.ns : '${a.ns}/${u.path.replaceAll('/', '')}',
          reason: '${a.id}：归一化段拼法固定为 host+path');
      expect(resolveLaunchUri(u), a.id,
          reason: '${a.id}：launchSegOf→resolveLaunchPath 必须闭环回本动作');
    }
    // today 无 key：段就只是 ns（不能长出斜杠）
    expect(launchSegOf(Uri.parse('lh://today')), 'today');
    // 带参不影响寻址段
    expect(launchSegOf(Uri.parse('lh://inbox/new?text=hi')), 'inbox/new');
    // nfc 透传同口径
    expect(resolveLaunchUri(Uri.parse('lh://nfc/aB3xY9zQ1m2K')), 'nfc:aB3xY9zQ1m2K');
    // 非本 scheme / 表外 ns 一律 null（不放行）
    expect(resolveLaunchUri(Uri.parse('https://evil/x')), isNull);
    expect(resolveLaunchUri(Uri.parse('lh://evil/today')), isNull);
    expect(resolveLaunchUri(Uri.parse('lh://ledger')), isNull);
  });

  test('原生 enqueueLaunch 必须按 host+path 归一化（禁回退到只取 uri.path）', () {
    // 跨语言口径无法用单测直接互通，故在原生源码上钉实现：`enqueueLaunch` 体内
    // 必须出现 `uri.host`。若有人把口径改回 `uri.path`，本断言即红。
    final kt = File(
      'android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt',
    ).readAsStringSync();
    final start = kt.indexOf('private fun enqueueLaunch');
    expect(start, greaterThan(-1), reason: 'enqueueLaunch 缺失');
    final end = kt.indexOf('private fun takeLaunch', start);
    expect(end, greaterThan(start), reason: 'enqueueLaunch 边界未找到');
    final body = kt.substring(start, end);
    expect(body, contains('uri.host'),
        reason: 'ns 在 authority —— 必须拼 host；只取 uri.path 会静默丢掉整条意图');
    expect(body, isNot(matches(RegExp(r'seg\s*=\s*uri\.path'))),
        reason: '旧口径（归一化段直接取 uri.path）禁用，这正是 V1.67 真机伤');
  });

  test('原生 requestPin 标签取该动作自己的短标签（禁写死成某一个动作）', () {
    // 真机伤：曾写死 `LH_LABELS["today"]`，于是铺「记一笔」的桌面图标也叫「今天」。
    final kt = File(
      'android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt',
    ).readAsStringSync();

    final start = kt.indexOf('private fun requestPin');
    expect(start, greaterThan(-1), reason: 'requestPin 缺失');
    final end = kt.indexOf('private fun shortcutManager', start);
    final body = kt.substring(start, end);
    expect(body, contains('LH_LABELS[actionId]'),
        reason: '铺桌面标签必须按动作 id 取（与长按菜单同源）');
    expect(body, isNot(contains('LH_LABELS["today"]')),
        reason: '写死「今天」会让所有铺桌面图标都叫今天');

    // 频道handler 必须把 action 一并透给原生（Dart 已发，原生曾漏收）。
    final hStart = kt.indexOf('"requestPinShortcut" ->');
    expect(hStart, greaterThan(-1), reason: 'requestPinShortcut 分支缺失');
    final hEnd = kt.indexOf('"isPinSupported" ->', hStart);
    final hBody = kt.substring(hStart, hEnd);
    expect(hBody, contains('call.argument<String>("action")'),
        reason: 'handler 必须读 action 入参，否则标签无从按动作取');
    expect(hBody, contains('requestPin(actionId, scheme)'),
        reason: 'action 必须传进 requestPin');
  });

  test('原生逐动作设快捷方式图标（禁回落到应用图标）', () {
    // 真机报障：不调 setIcon 时系统一律回落应用图标 ⇒ 长按菜单 4 枚图标全一样。
    final kt = File(
      'android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt',
    ).readAsStringSync();

    for (final a in kDesktopActions) {
      expect(kt, contains('"${a.id}" to R.drawable.ic_lh_${a.id}'),
          reason: '${a.id} 的图标映射缺失');
      expect(
          File('android/app/src/main/res/drawable/ic_lh_${a.id}.xml').existsSync(),
          isTrue,
          reason: '${a.id} 的图标资源缺文件（字形取自原型 ACTIONS[].icon）');
    }
    expect(kt, contains('.setIcon(lhIcon('),
        reason: '两端（长按菜单 / 铺桌面）都必须 setIcon');
    expect(kt, contains('LH_ICONS[id]'),
        reason: '长按菜单必须按 id 取图标，禁写死某一个');
  });
}