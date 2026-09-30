import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/kits/domain/kit_dist.dart';
import 'package:lifeharness/features/kits/domain/kit_ruler.dart';

/// V1.47 批3 · 长度类工具域层（尺子 / 测距）。纯几何计算，零 I/O、零时钟。
void main() {
  group('1 · 尺子换算', () {
    test('1 逻辑像素 = 25.4/160 mm（dpr 在换算链里相消）', () {
      expect(kitRulerMmPerPx(devicePixelRatio: 1), closeTo(.15875, 1e-6));
      expect(kitRulerMmPerPx(devicePixelRatio: 3), closeTo(.15875, 1e-6));
      expect(kitRulerMmPerPx(devicePixelRatio: 2.75), closeTo(.15875, 1e-6));
      // 倍率 1.15× 时同样长度读出更大毫米数（校准放大）。
      expect(
        kitRulerMmPerPx(devicePixelRatio: 3, cal: 1.15),
        closeTo(.18256, 1e-4),
      );
      // dpr 非法（0/负）不炸。
      expect(kitRulerMmPerPx(devicePixelRatio: 0), closeTo(.15875, 1e-6));
    });

    test('量程：长边 873 逻辑像素 ≈ 139mm · 短边 393 ≈ 62mm', () {
      expect(
        kitRulerTargetMm(
          widthPx: 393,
          heightPx: 873,
          devicePixelRatio: 3,
          longEdge: true,
        ),
        139,
      );
      expect(
        kitRulerTargetMm(
          widthPx: 393,
          heightPx: 873,
          devicePixelRatio: 3,
          longEdge: false,
        ),
        62,
      );
      // 宽高互换不影响长边判定。
      expect(
        kitRulerTargetMm(
          widthPx: 873,
          heightPx: 393,
          devicePixelRatio: 3,
          longEdge: true,
        ),
        139,
      );
    });

    test('每毫米像素数：量程 0 回落 1 防除零', () {
      expect(kitRulerPxPerMm(tapePx: 360, targetMm: 120), 3);
      expect(kitRulerPxPerMm(tapePx: 360, targetMm: 0), 1);
    });

    test('零点/游标钳位（游标至少比零点大 1mm、不超量程）', () {
      final a = kitRulerClamp(zero: 5, cur: 3, targetMm: 100);
      expect((a.zero, a.cur), (5, 6));
      final b = kitRulerClamp(zero: 200, cur: 300, targetMm: 100);
      expect((b.zero, b.cur), (99, 100));
      expect(kitRulerClamp(zero: 10, cur: 42, targetMm: 100).mm, 32);
    });

    test('±1mm 微调贴边不越界', () {
      const m = KitRulerMarks(zero: 0, cur: 1);
      expect(kitRulerNudge(m, delta: -1, targetMm: 100).cur, 1);
      expect(kitRulerNudge(m, delta: 1, targetMm: 100).cur, 2);
      const top = KitRulerMarks(zero: 98, cur: 100);
      expect(kitRulerNudge(top, delta: 1, targetMm: 100).cur, 100);
    });

    test('读数文案：cm 走 mm · in 按 25.4 两位小数', () {
      expect(kitRulerReadout(unit: 'cm', mm: 85), '85 mm');
      expect(kitRulerReadout(unit: 'in', mm: 85), '3.35 in');
      expect(kitRulerSpanText(longEdge: true, mm: 85), '长边 游标 85 mm ≈ 8.5 cm');
      expect(
        kitRulerZeroText(zero: 12, targetMm: 139),
        '零点 12 mm · 量程 139 mm · ±1mm 微调',
      );
      expect(kitRulerCalText(1), '1.000×');
      expect(
        kitRulerShare(
          m: const KitRulerMarks(zero: 12, cur: 97),
          longEdge: false,
          targetMm: 62,
          cal: 0.995,
        ),
        '尺子 · 游标读数 85 mm（短边 · 零点 12 mm）· 量程 62 mm · 校准 0.995×',
      );
    });

    test('银行卡校准：按当前读数反算倍率并夹在滑杆区间', () {
      expect(
        kitRulerBankCal(currentCal: 1, readingMm: 100),
        closeTo(.856, 1e-6),
      );
      // 已带 0.9 倍率时读数要还原成未校准毫米再反算。
      expect(
        kitRulerBankCal(currentCal: .9, readingMm: 90),
        closeTo(.856, 1e-6),
      );
      expect(kitRulerBankCal(currentCal: 1, readingMm: 60), kKitRulerCalMax);
      expect(kitRulerBankCal(currentCal: 1, readingMm: 200), kKitRulerCalMin);
      expect(kitRulerBankCal(currentCal: 1, readingMm: 0), 1.0);
    });

    test('刻度序列：cm 每毫米一档 + 整厘米标数；in 按四分之一英寸', () {
      final cm = kitRulerTicks(targetMm: 20, unit: 'cm');
      expect(cm.length, 21);
      expect(cm[0].len, kKitRulerTickMajor);
      expect(cm[0].label, '0');
      expect(cm[1].len, kKitRulerTickMinor);
      expect(cm[5].len, kKitRulerTickMid);
      expect(cm[10].label, '1');
      expect(cm[10].len, kKitRulerTickMajor);
      expect(cm[20].label, '2');

      final inch = kitRulerTicks(targetMm: 51, unit: 'in');
      expect(inch.first.mm, 0);
      expect(inch.first.label, '0');
      expect(inch[1].mm, closeTo(6.35, .01));
      expect(inch[4].mm, closeTo(25.4, .01));
      expect(inch[4].label, '1');
      expect(kitRulerTicks(targetMm: 0, unit: 'cm'), isEmpty);
    });

    test('参数落库 round-trip · 坏数据回默认', () {
      final d = kitRulerEncode(
        unit: 'in',
        dir: 'short',
        cal: 1.024,
        zero: 7,
        cur: 55,
      );
      final s = KitRulerState.decode(d);
      expect(
        (s.unit, s.dir, s.cal, s.zero, s.cur),
        ('in', 'short', 1.024, 7, 55),
      );
      expect(s.longEdge, isFalse);
      final def = KitRulerState.decode({});
      expect(
        (def.unit, def.dir, def.cal, def.zero, def.cur),
        ('cm', 'long', 1.0, 0, null),
      );
      expect(
        KitRulerState.decode({'cal': 99, 'unit': 'px', 'dir': 'x'}).cal,
        kKitRulerCalMax,
      );
    });

    test('toast 文案与单位/尺边一致（原型 rulerUnit / rulerDir）', () {
      expect(kitRulerUnitToast('cm'), '刻度单位：厘米 · 逻辑毫米基准');
      expect(kitRulerUnitToast('in'), '刻度单位：英寸 · 1in=25.4mm 换算');
      expect(kitRulerDirToast(true), startsWith('尺边：长边 · 尺面转为横向'));
      expect(kitRulerDirToast(false), startsWith('尺边：短边 · 尺面回到竖向'));
    });
  });

  group('2 · 测距', () {
    test('地图模式只记画布坐标 · GPS 模式反算经纬度', () {
      final m = kitDistPointAt(10, 20, mode: kKitDistModeMap);
      expect((m.x, m.y, m.lat, m.lng), (10.0, 20.0, null, null));
      final g = kitDistPointAt(100, 50, mode: kKitDistModeGps);
      expect(g.lat, closeTo(30.28 - 50 * .00002, 1e-9));
      expect(g.lng, closeTo(120.02 + 100 * .000022, 1e-9));
    });

    test('大圆距离：1° 纬度 ≈ 111.19km · 同点为 0', () {
      const a = KitDistPoint(x: 0, y: 0, lat: 30, lng: 120);
      const b = KitDistPoint(x: 0, y: 0, lat: 31, lng: 120);
      expect(kitHaversineMeters(a, a), 0);
      expect(kitHaversineMeters(a, b), closeTo(111195, 60));
    });

    test('总长：地图按像素×比例尺 · GPS 按大圆', () {
      const p0 = KitDistPoint(x: 0, y: 0);
      const p1 = KitDistPoint(x: 3, y: 4);
      expect(
        kitDistTotalMeters([p0, p1], mode: kKitDistModeMap, scaleMPerPx: 2),
        10,
      );
      expect(
        kitDistTotalMeters([p0], mode: kKitDistModeMap, scaleMPerPx: 2),
        0,
      );
      const g0 = KitDistPoint(x: 0, y: 0, lat: 30.0, lng: 120.0);
      const g1 = KitDistPoint(x: 1, y: 1, lat: 30.001, lng: 120.0);
      expect(
        kitDistTotalMeters([g0, g1], mode: kKitDistModeGps, scaleMPerPx: 10),
        closeTo(111.19, 2),
      );
    });

    test('总长/提示/经纬度浮标文案（原型 #distTotal / distHint / #distTrail）', () {
      expect(kitDistTotalText(0, 0), '总长 0 m · 0 个点');
      expect(kitDistTotalText(999.4, 2), '总长 999 m · 2 个点');
      expect(kitDistTotalText(1500, 3), '总长 1.50 km · 3 个点');
      expect(kitDistHintText(kKitDistModeMap, 2.5), '模拟地图 · 轻点落点 · 1px≈2.5m');
      expect(kitDistHintText(kKitDistModeGps, 2.5), 'GPS 轨迹 · 轻点采集定位点 · 大圆距离');
      expect(kitDistTrailText(const [], mode: kKitDistModeGps), isNull);
      expect(
        kitDistTrailText([kKitGpsSeed], mode: kKitDistModeGps),
        '30.28000, 120.02066',
      );
      expect(kitDistTrailText([kKitGpsSeed], mode: kKitDistModeMap), isNull);
    });

    test('模拟行走第 k 步 = 螺旋增量（原型 distGpsWalk 口径）', () {
      final s = kitGpsWalkStep(kKitGpsSeed, 1);
      expect(s.x, closeTo(30 + 5 * .877582562, 1e-6));
      expect(s.y, closeTo(150 + 3 * .327194697, 1e-6));
      expect(s.lat, closeTo(30.279998 - .00004, 1e-9));
      expect(s.lng, closeTo(120.02066 + .00003, 1e-9));
      final s2 = kitGpsWalkStep(kKitGpsSeed, 4);
      expect(s2.x, closeTo(30 + 20 * mathCos2, 1e-6));
    });

    test('撤销：空轨迹不动、逐步回退', () {
      expect(kitDistUndo(const []), isEmpty);
      const pts = [
        kKitGpsSeed,
        KitDistPoint(x: 1, y: 1),
        KitDistPoint(x: 2, y: 2),
      ];
      expect(kitDistUndo(pts).length, 2);
      expect(kitDistUndo(kitDistUndo(pts)).length, 1);
    });

    test('模式与比例尺落库 round-trip · 越界夹紧', () {
      final s = KitDistState.decode(
        kitDistEncode(mode: kKitDistModeGps, scale: 6.5),
      );
      expect((s.mode, s.scale, s.isGps), (kKitDistModeGps, 6.5, true));
      final def = KitDistState.decode({});
      expect((def.mode, def.scale, def.isGps), (kKitDistModeMap, 2.5, false));
      expect(
        KitDistState.decode({'distMode': 'x', 'distScale': 99}).scale,
        kKitDistScaleMax,
      );
      expect(KitDistState.decode({'distScale': -3}).scale, kKitDistScaleMin);
    });
  });
}

/// 行走增量里 cos(4/2) 的期望值（写死便于读）。
const double mathCos2 = -0.416146837;
