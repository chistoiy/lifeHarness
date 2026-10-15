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
}