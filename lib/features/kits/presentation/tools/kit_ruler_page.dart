// 工具屏 · 尺子（原型 `TOOLS.ruler` / `ruler*` 同源 · 批3）。
//
// 页面是参数台（单位 / 尺边 / 倍率 / 校准），**尺面在全屏舞台**（V1.47 验收轮2
// 口径：全屏 + 可滑动游标与零点）；量程按实测 DPI 计算（见 `domain/kit_ruler.dart`）。
// 参数与游标位置落 `kit_tool_data.tool='ruler'`（键名同原型 `KITS.*`）。
// 反馈轮4：尺边=长边时把页面真的转成横向（原型 `#rulerStage.rs-land` 同义）——
// 之前只换量程数字、尺条仍铺在竖屏宽度上，用户点「长边」看不出任何变化。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_models.dart';
import '../../domain/kit_ruler.dart';
import '../kit_providers.dart';
import 'kit_ruler_stage.dart';
import 'kit_tools_kit.dart';

/// 尺边 → 屏幕方向：长边=横向（手机横过来量），短边=竖向。
Future<void> kitRulerApplyOrientation({required bool longEdge}) =>
    SystemChrome.setPreferredOrientations(
      longEdge
          ? const [DeviceOrientation.landscapeLeft]
          : const [DeviceOrientation.portraitUp],
    );

/// 离开尺子：把方向决策交还系统（本 app 其余屏不锁方向，不能留锁死状态）。
Future<void> kitRulerRestoreOrientation() =>
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

/// 当前视口下的量程（毫米）：长/短边像素 × 实测密度 × 倍率。
///
/// 页面与全屏舞台共用这一处取数：旋转后 `MediaQuery` 立刻变，量程跟着变，
/// 不再出现「舞台里换了尺边、量程还是进入时那份」的冻结值。
int kitRulerTargetOf(BuildContext context, KitRulerController c) {
  final mq = MediaQuery.of(context);
  return kitRulerTargetMm(
    widthPx: mq.size.width,
    heightPx: mq.size.height,
    devicePixelRatio: mq.devicePixelRatio,
    longEdge: c.longEdge,
    cal: c.cal,
  );
}

/// 尺子参数与游标位置（页面与全屏舞台共用同一份，改一处即通知另一方）。
///
/// 量程不进控制器：它由「当前视口像素 × 实测密度 × 倍率」现场算出
/// （[kitRulerTargetMm]），在 build 里算不会触发 notifyListeners。
class KitRulerController extends ChangeNotifier {
  KitRulerController({required this.persist});

  /// 落库回调（屏侧注入仓储写盘）。
  Future<void> Function(KitRulerController) persist;

  String unit = 'cm';
  String dir = 'long';
  double cal = 1.0;
  int zero = 0;
  int? cur;

  bool get longEdge => dir != 'short';

  /// 全屏舞台进入时的游标初值（原型 `rsCur ?? round(target*.4)`）。
  int curOrDefault(int targetMm) => cur ?? (targetMm * .4).round();

  void load(Map<String, Object?> d) {
    final s = KitRulerState.decode(d);
    unit = s.unit;
    dir = s.dir;
    cal = s.cal;
    zero = s.zero;
    cur = s.cur;
    notifyListeners();
  }

  void setUnit(String u) {
    unit = u;
    notifyListeners();
    persist(this);
  }

  void setDir(String d) {
    dir = d;
    notifyListeners();
    persist(this);
    // 换尺边=换持机姿势：页面方向必须跟着转，否则尺条还是铺在短边上。
    kitRulerApplyOrientation(longEdge: longEdge);
  }

  void setCal(double v) {
    cal = v.clamp(kKitRulerCalMin, kKitRulerCalMax);
    notifyListeners();
    persist(this);
  }

  /// 拖动/微调游标与零点（钳位在量程内；量程由调用侧按当前视口给出）。
  void setMarks(int z, int c, {required int targetMm}) {
    final m = kitRulerClamp(zero: z, cur: c, targetMm: targetMm);
    zero = m.zero;
    cur = m.cur;
    notifyListeners();
    persist(this);
  }
}

class KitRulerBody extends ConsumerStatefulWidget {
  const KitRulerBody({super.key});

  @override
  ConsumerState<KitRulerBody> createState() => _KitRulerBodyState();
}

class _KitRulerBodyState extends ConsumerState<KitRulerBody> {
  final KitRulerController _c = KitRulerController(persist: (ctl) async {});

  @override
  void initState() {
    super.initState();
    _c.persist = (ctl) => ref
        .read(kitRepositoryProvider)
        .setToolData(
          kitToolKeyRuler,
          kitRulerEncode(
            unit: ctl.unit,
            dir: ctl.dir,
            cal: ctl.cal,
            zero: ctl.zero,
            cur: ctl.cur,
          ),
        );
    _boot();
  }

  @override
  void dispose() {
    // 尺子是全屏里唯一会改系统方向的屏；离开时一律交还给系统。
    kitRulerRestoreOrientation();
    _c.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyRuler);
    if (!mounted) return;
    _c.load(d);
    kitRulerApplyOrientation(longEdge: _c.longEdge);
  }

  /// 当前视口下的量程（毫米）：长/短边像素 × 实测密度 × 倍率。
  int _targetMm(BuildContext context) => kitRulerTargetOf(context, _c);

  Future<void> _openStage() async {
    // 舞台内每次拖动结束都会经控制器落库，退出时不必再回写。
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => KitRulerStage(controller: _c)),
    );
    // 舞台里可能换过尺边：回到参数台时按当前尺边重新对齐方向。
    kitRulerApplyOrientation(longEdge: _c.longEdge);
  }

  void _bank() {
    final target = _targetMm(context);
    final marks = kitRulerClamp(
      zero: _c.zero,
      cur: _c.curOrDefault(target),
      targetMm: target,
    );
    _c.setCal(kitRulerBankCal(currentCal: _c.cal, readingMm: marks.mm));
    AppToast.show(
      context,
      '已按银行卡 ${kKitRulerBankCardMm}mm 对齐 · 倍率 ${kitRulerCalText(_c.cal)}'
      '（游标还没量到卡片时，请先在全屏尺子上按住红线拉开到卡片两端）',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListenableBuilder(
      listenable: _c,
      // 量程与读数都在 builder 里现算：控制器一变（含换尺边、舞台落库）就跟着重算。
      builder: (context, _) {
        final target = _targetMm(context);
        final marks = kitRulerClamp(
          zero: _c.zero,
          cur: _c.curOrDefault(target),
          targetMm: target,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                KitToolChip(
                  keyName: 'kit-ruler-unit-cm',
                  label: '厘米 cm',
                  on: _c.unit == 'cm',
                  onTap: () {
                    _c.setUnit('cm');
                    AppToast.show(context, kitRulerUnitToast('cm'));
                  },
                ),
                const SizedBox(width: 6),
                KitToolChip(
                  keyName: 'kit-ruler-unit-in',
                  label: '英寸 in',
                  on: _c.unit == 'in',
                  onTap: () {
                    _c.setUnit('in');
                    AppToast.show(context, kitRulerUnitToast('in'));
                  },
                ),
                const Spacer(),
                KitToolChip(
                  keyName: 'kit-ruler-dir-long',
                  label: '长边 · 横向',
                  on: _c.longEdge,
                  onTap: () {
                    _c.setDir('long');
                    AppToast.show(context, kitRulerDirToast(true));
                  },
                ),
                const SizedBox(width: 6),
                KitToolChip(
                  keyName: 'kit-ruler-dir-short',
                  label: '短边 · 竖向',
                  on: !_c.longEdge,
                  onTap: () {
                    _c.setDir('short');
                    AppToast.show(context, kitRulerDirToast(false));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 30,
                  child: Text(
                    '倍率',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('kit-ruler-cal'),
                    value: _c.cal,
                    min: kKitRulerCalMin,
                    max: kKitRulerCalMax,
                    divisions:
                        ((kKitRulerCalMax - kKitRulerCalMin) / kKitRulerCalStep)
                            .round(),
                    label: kitRulerCalText(_c.cal),
                    onChanged: _c.setCal,
                  ),
                ),
                SizedBox(
                  key: const ValueKey('kit-ruler-cal-v'),
                  width: 60,
                  child: Text(
                    kitRulerCalText(_c.cal),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              key: const ValueKey('kit-ruler-fs'),
              onTap: _openStage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [tokens.g1, tokens.g3]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  '全屏尺子 · 按住红线滑动读数',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '量程 ${kitRulerSpanCard(target)}',
                  key: const ValueKey('kit-ruler-span-card'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                  ),
                ),
                const Spacer(),
                kitToolBtn(
                  context,
                  '银行卡校准',
                  _bank,
                  keyName: 'kit-ruler-bank',
                  small: true,
                ),
                kitToolBtn(
                  context,
                  '重置 1.000',
                  () => _c.setCal(1.0),
                  keyName: 'kit-ruler-cal-reset',
                  small: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            kitToolSubCard(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  kitToolSection('最近一次读数'),
                  const SizedBox(height: 6),
                  Text(
                    _c.cur == null
                        ? '全屏尺子上按住红线滑动即可读数'
                        : kitRulerReadout(unit: _c.unit, mm: marks.mm),
                    key: const ValueKey('kit-ruler-last'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  kitToolNote(
                    '量程 = ${_c.longEdge ? '长边' : '短边'} 像素 × 实测密度换算'
                    ' · 倍率参与换算 · 参数随本机备份',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
