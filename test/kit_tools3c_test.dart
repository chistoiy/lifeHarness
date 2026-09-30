import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/domain/kit_b64.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_b64_page.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_imgz_page.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_tele_page.dart';

/// V1.47 批3d · Base64 四 tab + 提词器屏与舞台。
/// 取图/解码/探针/另存/笔记导入全部走注入缝；示例串是真实 PNG 字节，
/// 界面上的字符数与体积都由域层实算。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late KitRepository repo;
  late ProviderContainer container;

  final pngBytes = kitB64DecodeBytes(kitB64Split(kKitB64SampleDataUri).raw)!;
  List<String?> pickQueue = const [];
  (int, int)? probeResult = (24, 24);
  String? savedName;
  Uint8List? savedBytes;
  String? noteText;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
    SharedPreferences.setMockInitialValues({});
    pickQueue = const ['/dcim/sample.png'];
    probeResult = (24, 24);
    savedName = null;
    savedBytes = null;
    noteText = null;
    KitB64.pickImage = () async => pickQueue.isEmpty ? null : pickQueue.first;
    KitB64.probe = (bytes) async => probeResult;
    KitB64.save = (name, bytes) async {
      savedName = name;
      savedBytes = bytes;
      return '/sdcard/Download/$name';
    };
    KitImgz.loader = (path) async =>
        KitImgzSource(width: 24, height: 24, bytes: pngBytes);
    KitTele.noteImporter = () async => noteText;
  });
  tearDown(() => db.close());

  Future<void> pumpTool(WidgetTester tester, String key) async {
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        kitRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/kits/tool/$key',
      routes: [
        ShellRoute(builder: (_, _, child) => child, routes: kitShellRoutes()),
        ...kitPageRoutes(),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle5(tester);
  }

  String selOf(WidgetTester tester, String key) =>
      tester.widget<SelectableText>(find.byKey(ValueKey(key))).data!;

  String noteOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  group('1 · Base64 四 tab', () {
    testWidgets('初始态：四 tab 齐备 · 留痕两条空口径', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'b64');
      for (final t in kKitB64Tabs) {
        expect(find.byKey(ValueKey('kit-b64-tab-$t')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('kit-b64-pick')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-b64-out')), findsNothing);
      expect(noteOf(tester, 'kit-b64-recent-empty'), '尚无转换记录 · 选图或粘贴文本后即留痕');
      expect(noteOf(tester, 'kit-b64-hist-empty'), '尚无操作记录 · 编码/解码后自动留痕');
      await drainLogTimer(tester);
    });

    testWidgets('图→串：真实字节实算长度 · 近期与记录双留痕 · 另存走缝', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'b64');
      await tester.tap(find.byKey(const ValueKey('kit-b64-pick')));
      await settle5(tester);
      final raw = kitB64EncodeBytes(pngBytes);
      expect(selOf(tester, 'kit-b64-out'), raw);
      expect(
        noteOf(tester, 'kit-b64-outlen'),
        '原文件 123B · Base64 ${raw.length} 字符 ≈ 0.2 KB（约 +33%）',
      );
      // 123B 的串是 164 字符 < 180，预览不截断。
      expect(noteOf(tester, 'kit-b64-peek'), raw);
      expect(noteOf(tester, 'kit-b64-recent-0'), contains('sample.png'));
      // 记录行的键在整行容器上（行内三个 Text），按后代取。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('kit-b64-hist-0')),
          matching: find.textContaining('编码 sample.png → ${raw.length} 字符'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-b64-prev'))).data,
        'sample.png · 24×24',
      );

      await tester.tap(find.byKey(const ValueKey('kit-b64-save-txt')));
      await settle5(tester);
      expect(savedName, 'sample.png.b64.txt');
      await pollText(tester, '已保存 → /sdcard/Download/sample.png.b64.txt');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-b64-copy-uri')));
      await settle5(tester);
      await pollText(tester, '已复制 data URI');
      await clearToasts(tester);

      final d = await repo.toolData('b64');
      expect((d['b64Recent'] as List).length, 1);
      expect((d['b64Hist'] as List).length, greaterThanOrEqualTo(2));
      await drainLogTimer(tester);
    });

    testWidgets('串→图：示例自动还原 · 补前缀 · 两类错误各有文案', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'b64');
      await tester.tap(find.byKey(const ValueKey('kit-b64-tab-dec')));
      await settle5(tester);

      // 空串先给「先粘贴」口径。
      await tester.tap(find.byKey(const ValueKey('kit-b64-decode')));
      await settle5(tester);
      expect(noteOf(tester, 'kit-b64-err'), '先粘贴 Base64 字符串');
      await pollText(tester, '先粘贴 Base64 字符串');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-b64-sample')));
      await settle5(tester);
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('kit-b64-in')))
            .controller!
            .text,
        kKitB64SampleDataUri,
      );
      expect(noteOf(tester, 'kit-b64-back'), '还原成功 · 24×24 · 123B · 本地解码');
      await pollText(tester, '已还原为图片 · 可保存');
      await clearToasts(tester);

      // 非法字符 / 长度非 4 倍数各有文案，且都记进操作记录（✖）。
      await tester.enterText(find.byKey(const ValueKey('kit-b64-in')), 'ab!c');
      await tester.tap(find.byKey(const ValueKey('kit-b64-decode')));
      await settle5(tester);
      expect(noteOf(tester, 'kit-b64-err'), contains('含非法 Base64 字符'));

      await tester.enterText(find.byKey(const ValueKey('kit-b64-in')), 'AB');
      await tester.tap(find.byKey(const ValueKey('kit-b64-decode')));
      await settle5(tester);
      expect(noteOf(tester, 'kit-b64-err'), '长度不是 4 的倍数 · 串可能被截断');
      expect(find.byKey(const ValueKey('kit-b64-back')), findsNothing);

      // 裸串补前缀后仍在可解范围。
      await tester.enterText(find.byKey(const ValueKey('kit-b64-in')), 'QUJD');
      await tester.tap(find.byKey(const ValueKey('kit-b64-prefix')));
      await settle5(tester);
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('kit-b64-in')))
            .controller!
            .text,
        'data:image/png;base64,QUJD',
      );
      probeResult = null; // 不是图片流
      await tester.tap(find.byKey(const ValueKey('kit-b64-decode')));
      await settle5(tester);
      expect(noteOf(tester, 'kit-b64-err'), '内容可解码但不是有效图片流');
      await clearToasts(tester);
      await drainLogTimer(tester);
    });

    testWidgets('文本⇄串：实时计数 · 转去解码验证 · 还原后可另存', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'b64');
      await tester.tap(find.byKey(const ValueKey('kit-b64-tab-xenc')));
      await settle5(tester);
      await tester.enterText(find.byKey(const ValueKey('kit-b64-src')), '数据在自己手里');
      await settle5(tester);
      expect(noteOf(tester, 'kit-b64-meta'), '7 字 · UTF-8 21 B · Base64 28 字符');
      expect(selOf(tester, 'kit-b64-txtout'), kitB64EncodeText('数据在自己手里'));

      await tester.tap(find.byKey(const ValueKey('kit-b64-txt-take')));
      await settle5(tester);
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('kit-b64-txtin')))
            .controller!
            .text,
        kitB64EncodeText('数据在自己手里'),
      );
      await tester.tap(find.byKey(const ValueKey('kit-b64-txtdec')));
      await settle5(tester);
      expect(selOf(tester, 'kit-b64-txtback'), '数据在自己手里');
      await pollText(tester, '已还原为文本 · 本地解码');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-b64-back-save')));
      await settle5(tester);
      expect(savedName, 'decoded.txt');
      expect(savedBytes?.length, 21);
      await pollText(tester, '已保存 → /sdcard/Download/decoded.txt');
      await clearToasts(tester);

      // 清空记录只清操作记录；文本两类转换不进「近期转换」（同原型 b64Log 口径）。
      await tester.tap(find.byKey(const ValueKey('kit-b64-hist-clear')));
      await settle5(tester);
      expect(noteOf(tester, 'kit-b64-hist-empty'), '尚无操作记录 · 编码/解码后自动留痕');
      expect(noteOf(tester, 'kit-b64-recent-empty'), '尚无转换记录 · 选图或粘贴文本后即留痕');
      final d = await repo.toolData('b64');
      expect((d['b64Hist'] as List), isEmpty);
      await clearToasts(tester);
      await drainLogTimer(tester);
    });
  });

  group('2 · 提词器（反馈轮4 版式：图2 选项集 + 图3 展示态）', () {
    testWidgets('默认参数齐备 · 新版选项集都可改并落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'tele');
      expect(noteOf(tester, 'kit-tele-speed-v'), '60 px/s');
      expect(noteOf(tester, 'kit-tele-size-v'), '40 px');
      expect(noteOf(tester, 'kit-tele-lh-v'), '155%');
      expect(noteOf(tester, 'kit-tele-shake-v'), '0 px');
      expect(noteOf(tester, 'kit-tele-grad-name'), '纯色');
      expect(
        noteOf(tester, 'kit-tele-note-tip'),
        '内容改动即存本机 · 参数随本机备份',
      );
      expect(find.byKey(const ValueKey('kit-tele-stage-speed')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('kit-tele-dir-port')));
      await settle5(tester);
      await pollText(tester, '显示方向：竖屏');
      await clearToasts(tester);

      final slider = find.byKey(const ValueKey('kit-tele-speed'));
      await tester.drag(slider, Offset(tester.getRect(slider).width, 0));
      await settle5(tester);
      expect(noteOf(tester, 'kit-tele-speed-v'), '300 px/s');

      // 多彩背景：点一行换一档（纯色 → 糖果）。
      await tester.tap(find.byKey(const ValueKey('kit-tele-grad')));
      await settle5(tester);
      expect(noteOf(tester, 'kit-tele-grad-name'), '糖果');
      await pollText(tester, '背景：糖果');
      await clearToasts(tester);

      // 静止 + 闪烁 / 加粗 / LED 四枚开关各自独立。
      await tester.tap(find.byKey(const ValueKey('kit-tele-mode-static')));
      await settle5(tester);
      await pollText(tester, '显示方式：静止铺屏');
      await tester.tap(find.byKey(const ValueKey('kit-tele-fx-blink')));
      await settle5(tester);
      await pollText(tester, '闪烁：开');
      await tester.tap(find.byKey(const ValueKey('kit-tele-fx-bold')));
      await settle5(tester);
      await pollText(tester, '加粗：开');
      await tester.tap(find.byKey(const ValueKey('kit-tele-fx-led')));
      await settle5(tester);
      await pollText(tester, 'LED 点阵：开');
      await clearToasts(tester);

      final shk = find.byKey(const ValueKey('kit-tele-shake'));
      await tester.drag(shk, Offset(tester.getRect(shk).width, 0));
      await settle5(tester);
      expect(noteOf(tester, 'kit-tele-shake-v'), '8 px');

      await tester.tap(find.byKey(const ValueKey('kit-tele-demo')));
      await settle5(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('kit-tele-src')))
            .controller!
            .text,
        startsWith('各位好，欢迎参加本次产品复盘。'),
      );

      final d = await repo.toolData('tele');
      expect(d['tpOri'], 'port');
      expect(d['tpSpeed'], 300);
      expect(d['tpGrad'], 'candy');
      expect(d['tpMode'], 'static');
      expect(d['tpBlink'], true);
      expect(d['tpBold'], true);
      expect(d['tpLed'], true);
      expect(d['tpShake'], 8);
      expect(d['tpText'] as String, contains('产品复盘'));
      await drainLogTimer(tester);
    });

    testWidgets('文本色走应用内选色弹层 · 结果落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'tele');
      await tester.tap(find.byKey(const ValueKey('kit-tele-fg')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-cc-presets')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kit-cc-dot-#facc15')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-cc-ok')));
      await settle5(tester);
      final d = await repo.toolData('tele');
      expect(d['tpFg'], '#facc15');
      await clearToasts(tester);
      await drainLogTimer(tester);
    });

    testWidgets('从笔记导入：未接线给明确口径 · 接线后追加并落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'tele');
      await tester.tap(find.byKey(const ValueKey('kit-tele-note')));
      await settle5(tester);
      await pollText(tester, '笔记选择器待接入');
      await clearToasts(tester);

      noteText = '【来自笔记】把手机横过来，眼睛跟着字走就好。';
      await tester.tap(find.byKey(const ValueKey('kit-tele-note')));
      await settle5(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('kit-tele-src')))
            .controller!
            .text,
        noteText,
      );
      final d = await repo.toolData('tele');
      expect(d['tpText'], noteText);
      await clearToasts(tester);
      await drainLogTimer(tester);
    });

    testWidgets('舞台：滚动态进入即走字 · 控制条点按收起/唤回 · 退出回参数页', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'tele');
      await tester.tap(find.byKey(const ValueKey('kit-tele-dir-port')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-tele-demo')));
      await tester.tap(find.byKey(const ValueKey('kit-tele-open')));
      // 进入即自动播放：周期 Timer 持续排帧，这一段禁用 pumpAndSettle。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('kit-tele-stage')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-tele-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-tele-stage-lh')), findsOneWidget);
      final stageTop = tester.getTopLeft(find.byKey(const ValueKey('kit-tele-stage'))).dy;
      final y0 = tester.getTopLeft(find.byKey(const ValueKey('kit-tele-body'))).dy;
      await tester.pump(const Duration(milliseconds: 320));
      final y1 = tester.getTopLeft(find.byKey(const ValueKey('kit-tele-body'))).dy;
      expect(y1, lessThan(y0));

      // 先进入展示态：1.8s 自动收起是一次性定时器，越过它之后控制条只跟随点按。
      await tester.pump(const Duration(milliseconds: 1600));
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('kit-tele-ctl'))).opacity,
        0,
        reason: '展示态应只剩返回箭头（图3）',
      );
      // 点按屏幕唤回控制条。
      await tester.tap(find.byKey(const ValueKey('kit-tele-stage')));
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('kit-tele-ctl'))).opacity,
        1,
        reason: '点按必须能把控制条唤回来',
      );

      await tester.tap(find.byKey(const ValueKey('kit-tele-play')));
      await tester.pump();
      await settle5(tester);
      await pollText(tester, '已暂停');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-tele-reset')));
      await settle5(tester);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('kit-tele-body'))).dy,
        closeTo(stageTop, 1),
      );
      await pollText(tester, '已回到稿首');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-tele-stage-led')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-tele-led-grid')), findsOneWidget);
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-tele-close')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-tele-src')), findsOneWidget);
      final d = await repo.toolData('tele');
      expect(d['tpOri'], 'port');
      expect(d['tpLed'], true);
      expect(d['tpText'] as String, contains('谢谢大家'));
      await drainLogTimer(tester);
    });

    testWidgets('静止态：进入后不再位移，内容按视口居中铺屏', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'tele');
      await tester.enterText(find.byKey(const ValueKey('kit-tele-src')), '宥淇');
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-tele-mode-static')));
      await settle5(tester);
      await clearToasts(tester);
      await tester.tap(find.byKey(const ValueKey('kit-tele-open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final body = find.byKey(const ValueKey('kit-tele-body'));
      final stage = find.byKey(const ValueKey('kit-tele-stage'));
      final dy = tester.getTopLeft(body).dy;
      expect(dy, greaterThan(tester.getTopLeft(stage).dy + 1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getTopLeft(body).dy, dy);
      await tester.tap(find.byKey(const ValueKey('kit-tele-close')));
      await settle5(tester);
      final d = await repo.toolData('tele');
      expect(d['tpMode'], 'static');
      expect(d['tpText'], '宥淇');
      await clearToasts(tester);
      await drainLogTimer(tester);
    });
  });
}
