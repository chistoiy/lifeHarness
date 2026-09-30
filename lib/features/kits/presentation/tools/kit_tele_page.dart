// 工具屏 · 提词器（原型 `TOOLS.tele` / `tp*` 同源 · 批3 · 反馈轮4 重排）。
//
// 版式按产品给的「手持弹幕」参考图重排：内容 → 文字大小 / 滚动速度 / 行距 →
// 多彩背景 → 文本色 / 背景色 → 显示方向 / 显示方式 → 文字效果 → 文字抖动 →
// 演示稿·从笔记导入 → 显示。长文本提词能力保留（滚动态），静止态即铺屏大字。
// 色值一律走应用内 `kitShowColorSheet`（禁系统取色器）。讲稿与参数全部落
// `kit_tool_data.tool='tele'`（键名同原型 `KITS.tp*`）。拍板口径：不做语音
// 跟随、自动停顿、反向滚动。「从笔记导入」是注入缝 [KitTele.noteImporter]，
// 未接线时给明确口径而不是假数据。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_models.dart';
import '../../domain/kit_tele.dart';
import '../kit_color_sheet.dart';
import '../kit_providers.dart';
import 'kit_tele_stage.dart';
import 'kit_tools_kit.dart';

/// 跨模块能力缝（笔记选择器由批外交接，默认未接线）。
class KitTele {
  KitTele._();

  static Future<String?> Function() noteImporter = () async => null;
}

/// 提词器屏主体。
class KitTeleBody extends ConsumerStatefulWidget {
  const KitTeleBody({super.key});

  @override
  ConsumerState<KitTeleBody> createState() => _KitTeleBodyState();
}

class _KitTeleBodyState extends ConsumerState<KitTeleBody> {
  final TextEditingController _src = TextEditingController();
  KitTeleState _s = KitTeleState.decode(const {});
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _src.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final s = KitTeleState.decode(
      await ref.read(kitRepositoryProvider).toolData(kitToolKeyTele),
    );
    if (!mounted) return;
    setState(() {
      _s = s;
      _src.text = s.text;
      _loaded = true;
    });
  }

  /// 参数改动即落库（原型每个 oninput 都 `kitSave()`；内容同样随改随存）。
  void _set(KitTeleState next) {
    setState(() => _s = next);
    ref
        .read(kitRepositoryProvider)
        .setToolData(
          kitToolKeyTele,
          kitTeleEncode(_s.copyWith(text: _src.text)),
        );
  }

  Future<void> _openStage() async {
    _set(_s.copyWith(text: _src.text));
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => KitTeleStage(
          state: _s,
          onState: (next) => _set(next.copyWith(text: _src.text)),
        ),
      ),
    );
  }

  Future<void> _importNote() async {
    final text = await KitTele.noteImporter();
    if (!mounted) return;
    if (text == null) {
      AppToast.show(context, kKitTeleNotePending);
      return;
    }
    setState(
      () => _src.text = _src.text.isEmpty ? text : '${_src.text}\n\n$text',
    );
    _set(_s.copyWith(text: _src.text));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('kit-tele-src'),
          controller: _src,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontSize: 13, height: 1.6),
          decoration: const InputDecoration(
            isDense: true,
            hintText: '输入内容 / 粘贴讲稿…',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _set(_s.copyWith(text: v)),
        ),
        const SizedBox(height: 12),
        _sliderRow(
          label: '文字大小',
          keyName: 'kit-tele-size',
          value: _s.size.toDouble(),
          min: kKitTeleSizeMin,
          max: kKitTeleSizeMax,
          step: 1,
          text: kitTeleSizeText(_s.size),
          onChanged: (v) => _set(_s.copyWith(size: v.round())),
        ),
        _sliderRow(
          label: '滚动速度',
          keyName: 'kit-tele-speed',
          value: _s.speed.toDouble(),
          min: kKitTeleSpeedMin,
          max: kKitTeleSpeedMax,
          step: kKitTeleSpeedStep,
          text: kitTeleSpeedText(_s.speed),
          onChanged: (v) => _set(_s.copyWith(speed: v.round())),
        ),
        _sliderRow(
          label: '行距',
          keyName: 'kit-tele-lh',
          value: _s.lh.toDouble(),
          min: kKitTeleLhMin,
          max: kKitTeleLhMax,
          step: kKitTeleLhStep,
          text: kitTeleLhText(_s.lh),
          onChanged: (v) => _set(_s.copyWith(lh: v.round())),
        ),
        const SizedBox(height: 4),
        _gradRow(context),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _colorBtn(
                keyName: 'kit-tele-fg',
                label: '文本颜色',
                hex: _s.fg,
                onPick: (v) => _set(_s.copyWith(fg: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _colorBtn(
                keyName: 'kit-tele-bg',
                label: '背景色',
                hex: _s.bg,
                onPick: (v) => _set(_s.copyWith(bg: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _chipRow(
          label: '显示方向',
          keyPrefix: 'kit-tele-dir',
          items: [
            (kKitTeleDirLand, kitTeleDirLabel(kKitTeleDirLand)),
            (kKitTeleDirPort, kitTeleDirLabel(kKitTeleDirPort)),
          ],
          active: _s.dir,
          onPick: (v) {
            _set(_s.copyWith(dir: v));
            AppToast.show(context, kitTeleDirToast(v));
          },
        ),
        _chipRow(
          label: '显示方式',
          keyPrefix: 'kit-tele-mode',
          items: const [
            (kKitTeleModeStatic, '静止'),
            (kKitTeleModeScroll, '滚动'),
          ],
          active: _s.mode,
          onPick: (v) {
            _set(_s.copyWith(mode: v));
            AppToast.show(context, kitTeleModeToast(v));
          },
        ),
        _chipRow(
          label: '文字效果',
          keyPrefix: 'kit-tele-fx',
          items: [
            ('blink', kitTeleFxLabel('blink')),
            ('bold', kitTeleFxLabel('bold')),
            ('led', kitTeleFxLabel('led')),
          ],
          // 三枚效果各自独立开关，active 用「哪个开着」表达不了 → 交给 _fxChip。
          active: '',
          onPick: (_) {},
          builder: (id) => _fxChip(id),
        ),
        const SizedBox(height: 2),
        _sliderRow(
          label: '文字抖动',
          keyName: 'kit-tele-shake',
          value: _s.shake.toDouble(),
          min: kKitTeleShakeMin,
          max: kKitTeleShakeMax,
          step: kKitTeleShakeStep,
          text: kitTeleShakeText(_s.shake),
          onChanged: (v) => _set(_s.copyWith(shake: v.round())),
        ),
        Wrap(
          spacing: 2,
          children: [
            kitToolBtn(
              context,
              '填入演示稿',
              () => setState(() {
                _src.text = kitTeleDemoScript();
                _set(_s.copyWith(text: _src.text));
              }),
              keyName: 'kit-tele-demo',
              small: true,
            ),
            kitToolBtn(
              context,
              '从笔记导入',
              _importNote,
              keyName: 'kit-tele-note',
              small: true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          key: const ValueKey('kit-tele-open'),
          onTap: _openStage,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [tokens.g1, tokens.g3]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              '显示',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        kitToolSubCard(
          context,
          kitToolNote(
            _loaded ? '内容改动即存本机 · 参数随本机备份' : '正在读本机参数…',
            key: const ValueKey('kit-tele-note-tip'),
          ),
        ),
      ],
    );
  }

  /// 多彩背景行（原型 `#tpGradRow`：整行点一下换一档）。
  Widget _gradRow(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      key: const ValueKey('kit-tele-grad'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final id = kitTeleGradNext(_s.grad);
        _set(_s.copyWith(grad: id));
        AppToast.show(context, kitTeleGradToast(id));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _s.gradOn
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          for (final c in _s.gradColors) Color(c),
                        ],
                      )
                    : null,
                color: _s.gradOn ? null : kitColor(_s.bg),
                border: Border.all(color: tokens.cardBorder),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '多彩背景',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              kitTeleGrad(_s.grad).label,
              key: const ValueKey('kit-tele-grad-name'),
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.check,
              size: 16,
              key: const ValueKey('kit-tele-grad-chk'),
              color: _s.gradOn ? tokens.accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  /// 文本色 / 背景色按钮（图2 的「圆点 + 名称」样式，点开应用内取色弹层）。
  Widget _colorBtn({
    required String keyName,
    required String label,
    required String hex,
    required ValueChanged<String> onPick,
  }) {
    final tokens = context.tokens;
    return GestureDetector(
      key: ValueKey(keyName),
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final v = await kitShowColorSheet(context, hex);
        if (v != null) onPick(v);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: kitColor(hex),
                shape: BoxShape.circle,
                border: Border.all(color: tokens.cardBorder),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// 一枚效果开关（闪烁 / 加粗 / LED 点阵）。
  Widget _fxChip(String id) {
    final on = switch (id) {
      'blink' => _s.blink,
      'bold' => _s.bold,
      _ => _s.led,
    };
    return KitToolChip(
      keyName: 'kit-tele-fx-$id',
      label: kitTeleFxLabel(id),
      on: on,
      onTap: () {
        final next = !on;
        _set(
          switch (id) {
            'blink' => _s.copyWith(blink: next),
            'bold' => _s.copyWith(bold: next),
            _ => _s.copyWith(led: next),
          },
        );
        AppToast.show(
          context,
          '${kitTeleFxLabel(id)}：${next ? '开' : '关'}',
        );
      },
    );
  }

  /// 「标签 + 两枚 chip」的选项行（方向 / 方式 / 效果三处共用）。
  Widget _chipRow({
    required String label,
    required String keyPrefix,
    required List<(String, String)> items,
    required String active,
    required ValueChanged<String> onPick,
    Widget Function(String id)? builder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (id, text) in items)
                  builder != null
                      ? builder(id)
                      : KitToolChip(
                          keyName: '$keyPrefix-$id',
                          label: text,
                          on: active == id,
                          onTap: () => onPick(id),
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 参数滑杆行（原型 `input[type=range]` + 右侧读数）。
  Widget _sliderRow({
    required String label,
    required String keyName,
    required double value,
    required int min,
    required int max,
    required int step,
    required String text,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Slider(
            key: ValueKey(keyName),
            value: value.clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions < 2 ? null : divisions,
            label: text,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            text,
            key: ValueKey('$keyName-v'),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
