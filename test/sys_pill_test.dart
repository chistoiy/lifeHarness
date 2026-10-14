// 批B（工单 悬浮胶囊增强批-20261014 §7）：app 外系统悬浮窗·dart 侧守护。
//
// 覆盖：目标决策纯函数（§7 口径 ①②③⑦）、`lh/pill` 通道在测试/桌面
// （无原生）下的降级不抛、悬浮窗事件映射、事件消费闭环源码守护
// （变异刀③）。原生侧（TimerPillService）由 kotlin_check 编译门把关，
// 真机观感随复测包装机复验。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/pill_overlay.dart';

const _channel = MethodChannel('lh/pill');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sysPillTarget（纯函数·批B §7 口径）', () {
    test('功能关 → none', () {
      expect(
        sysPillTarget(
          sysPillOn: false,
          canDraw: true,
          appActive: false,
          readRunning: true,
          mediaRunning: false,
        ),
        SysPillTarget.none,
      );
    });

    test('权限缺 → none（即使会话在跑）', () {
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: false,
          appActive: false,
          readRunning: true,
          mediaRunning: true,
        ),
        SysPillTarget.none,
      );
    });

    test('app 前台 → none（免与 app 内胶囊重复）', () {
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: true,
          appActive: true,
          readRunning: true,
          mediaRunning: false,
        ),
        SysPillTarget.none,
      );
    });

    test('阅读页在栈上但 app 退后台 → 仍 read（6131 热修：阅读器豁免只在 app 内）', () {
      // 6129 装机实测：在阅读计时页按 HOME，阅读页仍在栈上——若把 readerOpen
      // 当独立条件，桌面/别的 app 里永不显示（悬浮窗的用武之地恰在 app 外）。
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: true,
          appActive: false,
          readRunning: true,
          mediaRunning: false,
        ),
        SysPillTarget.read,
      );
    });

    test('阅读在跑 → read', () {
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: true,
          appActive: false,
          readRunning: true,
          mediaRunning: false,
        ),
        SysPillTarget.read,
      );
    });

    test('仅影音在跑 → media', () {
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: true,
          appActive: false,
          readRunning: false,
          mediaRunning: true,
        ),
        SysPillTarget.media,
      );
    });

    test('双跑 → read 优先（单浮窗口径）', () {
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: true,
          appActive: false,
          readRunning: true,
          mediaRunning: true,
        ),
        SysPillTarget.read,
      );
    });

    test('全闲 → none', () {
      expect(
        sysPillTarget(
          sysPillOn: true,
          canDraw: true,
          appActive: false,
          readRunning: false,
          mediaRunning: false,
        ),
        SysPillTarget.none,
      );
    });
  });

  group('通道回落（无原生·测试/桌面降级不抛）', () {
    final binding = TestDefaultBinaryMessengerBinding.instance;

    setUp(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null));
    tearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    test('canDrawOverlays 无原生 → false（降级仅 app 内）', () async {
      expect(await sysPillCanDraw(), isFalse);
    });

    test('requestOverlayPermission 受理即 true（拉起成败由 resumed 复探判定）', () async {
      // mock 回 null＝原生在场且受理（MainActivity 侧恒 result.success(null)）；
      // 设置页是否真拉起、用户授没授，由 resumed 后 canDrawOverlays 复探
      // （设置页流程同口径，调用点不消费本返回值）。
      expect(await sysPillRequestPermission(), isTrue);
    });

    test('requestOverlayPermission 通道缺失（MissingPluginException）→ false 不抛', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
      expect(await sysPillRequestPermission(), isFalse);
    });

    test('sync/stop 无原生 → 静默完成不抛', () async {
      await sysPillSync(
          const SysPillState(kind: 'read', title: 't', status: '阅读中', seconds: 65),
          true);
      await sysPillStop();
    });

    test('takePillEvent 无原生 → null', () async {
      expect(await takePillEvent(), isNull);
    });
  });

  group('事件映射（■结束一次性消费）', () {
    final binding = TestDefaultBinaryMessengerBinding.instance;

    setUp(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'takePillEvent') {
        return <String, Object>{'type': 'end', 'kind': 'media'};
      }
      return null;
    }));
    tearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    test('end 事件 → SysPillEvent(type/kind)', () async {
      final ev = await takePillEvent();
      expect(ev, isNotNull);
      expect(ev!.type, 'end');
      expect(ev.kind, 'media');
    });

    test('空 type → null', () async {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (_) async {
        return <String, Object>{'type': '', 'kind': 'read'};
      });
      expect(await takePillEvent(), isNull);
    });
  });

  group('源码守护（变异刀③·事件消费闭环）', () {
    test('消费函数在同步模块：takePillEvent 且结束路径走共用助手', () {
      final src =
          File('lib/shared/linkage/sys_pill_sync.dart').readAsStringSync();
      expect(src, contains('await takePillEvent()'),
          reason: '■结束 事件无人消费＝悬浮窗结束钮失效');
      expect(src, contains('endReadPillTimer'));
      expect(src, contains('endMediaPillTimer'),
          reason: '结束路径必须与 app 内胶囊钮单源，禁抄第二份');
      // 6130 热修守护：可见态每 tick 都推＋重断言钩子（ROM 杀服务后自愈）。
      expect(src, contains('if (visible || sig != _lastSig)'),
          reason: '可见态被 sig 去重挡住＝服务被 ROM 停掉后永不重推（6129 实伤）');
      expect(src, contains('void sysPillMarkStale()'));
    });

    test('组合根 app.dart 必须挂 drainPillEvents 消费点与重断言', () {
      final src = File('lib/app.dart').readAsStringSync();
      expect(src, contains('drainPillEvents'),
          reason: '同步模块只管推状态；消费（WidgetRef 层级）必须挂在组合根');
      expect(src, contains('sysPillMarkStale()'),
          reason: '回前台必须清 sig 备忘强制重推（前台起服务不受 Android 14+ 限制）');
    });

    test('结束助手本体在 timer_bar_overlay 且被两处胶囊钮调用', () {
      final src = File('lib/shared/linkage/timer_bar_overlay.dart')
          .readAsStringSync();
      expect(src, contains('Future<void> endReadPillTimer('));
      expect(src, contains('Future<void> endMediaPillTimer('));
      // 批A 两钮改为调用助手（不再是内联 async 块）。
      expect(src, contains('onTap: () => endReadPillTimer(context, ref, s.bookId)'));
      expect(src, contains('onTap: () => endMediaPillTimer(context, ref, s.itemId)'));
    });

    test('Manifest 必须同时声明 FGS 基础权限与 specialUse 子类型（6128 实伤守护）', () {
      final src =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(src, contains('android.permission.FOREGROUND_SERVICE"'),
          reason: 'FGS 基础权限（API 28+）漏声明＝startForeground 即 '
              'SecurityException 主进程崩，且开关残留导致开 app 即闪退循环');
      expect(src, contains('android.permission.FOREGROUND_SERVICE_SPECIAL_USE'),
          reason: 'API 34+ specialUse 子类型权限漏声明＝同族崩溃');
      expect(src, contains('android:foregroundServiceType="specialUse"'));
      expect(src, contains('.TimerPillService'));
    });
  });
}
