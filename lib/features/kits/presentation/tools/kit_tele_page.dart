// 工具屏 · 提词器（原型 `TOOLS.tele` / `tp*` 同源 · 批3）。
//
// 参数五项：显示方向 / 速度 / 字号 / 文字色·底色（色值一律走应用内
// `kitShowColorSheet`，禁系统取色器）+ LED 点阵开关；行距在舞台上调（原型
// `#tpLhS` 也只存在于 `#tpCtl`）。讲稿与参数全部落 `kit_tool_data.tool='tele'`
// （键名同原型 `KITS.tp*`）。拍板口径：不做语音跟随、自动停顿、反向滚动。
// 「从笔记导入」是注入缝 [KitTele.noteImporter]，未接线时给明确口径而不是假数据。
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

  /// 参数改动即落库（原型每个 oninput 都 `kitSave()`）。
  void _set(KitTeleState next) {
    setState(() => _s = next);
    ref
        .read(kitRepositoryProvider)
        .setToolData(
          kitToolKeyTele,
          kitTeleEncode(_s.copyWith(text: _src.text)),
        );
  }

  void _saveScript() {
    _set(_s.copyWith(text: _src.text));
    AppToast.show(context, '讲稿已存本机 · 下次打开仍在');
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
    _saveScript();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '显示方向',
                style: TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ),
            KitToolChip(
              keyName: 'kit-tele-dir-land',
              label: kitTeleDirLabel(kKitTeleDirLand),
              on: _s.horizontal,
              onTap: () {
                _set(_s.copyWith(dir: kKitTeleDirLand));
                AppToast.show(context, kitTeleDirToast(kKitTeleDirLand));
              },
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-tele-dir-port',
              label: kitTeleDirLabel(kKitTeleDirPort),
              on: !_s.horizontal,
              onTap: () {
                _set(_s.copyWith(dir: kKitTeleDirPort));
                AppToast.show(context, kitTeleDirToast(kKitTeleDirPort));
              },
            ),
          ],
        ),
        _sliderRow(
          label: '速度',
          keyName: 'kit-tele-speed',
          value: _s.speed.toDouble(),
          min: kKitTeleSpeedMin,
          max: kKitTeleSpeedMax,
          step: kKitTeleSpeedStep,
          text: kitTeleSpeedText(_s.speed),
          onChanged: (v) => _set(_s.copyWith(speed: v.round())),
        ),
        _sliderRow(
          label: '字号',
          keyName: 'kit-tele-size',
          value: _s.size.toDouble(),
          min: kKitTeleSizeMin,
          max: kKitTeleSizeMax,
          step: 1,
          text: kitTeleSizeText(_s.size),
          onChanged: (v) => _set(_s.copyWith(size: v.round())),
        ),
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '文字色',
                style: TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ),
            SizedBox(
              key: const ValueKey('kit-tele-fg'),
              child: KitColorSwatchButton(
                hex: _s.fg,
                size: 30,
                onChanged: (v) => _set(_s.copyWith(fg: v)),
              ),
            ),
            const SizedBox(width: 10),
            Text('底色', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
            const SizedBox(width: 6),
            SizedBox(
              key: const ValueKey('kit-tele-bg'),
              child: KitColorSwatchButton(
                hex: _s.bg,
                size: 30,
                onChanged: (v) => _set(_s.copyWith(bg: v)),
              ),
            ),
            const Spacer(),
            Text(
              'LED 点阵屏',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
            SizedBox(
              key: const ValueKey('kit-tele-led'),
              width: 44,
              height: 30,
              child: Switch(
                value: _s.led,
                onChanged: (v) {
                  _set(_s.copyWith(led: v));
                  AppToast.show(context, kitTeleLedToast(v));
                },
              ),
            ),
          ],
        ),
        kitToolNote(
          kitTeleLedNote(_s.led),
          key: const ValueKey('kit-tele-led-note'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            key: const ValueKey('kit-tele-src'),
            controller: _src,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontSize: 12, height: 1.6),
            decoration: InputDecoration(
              isDense: true,
              hintText: '粘贴讲稿 / 台词…',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Wrap(
          spacing: 2,
          children: [
            kitToolBtn(context, '存稿', _saveScript, keyName: 'kit-tele-save'),
            kitToolBtn(
              context,
              '填入演示稿',
              () => setState(() => _src.text = kitTeleDemoScript()),
              keyName: 'kit-tele-demo',
              small: true,
            ),
            kitToolBtn(
              context,
              '进入提词',
              _openStage,
              keyName: 'kit-tele-open',
              color: tokens.accent,
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
        kitToolSubCard(
          context,
          kitToolNote(
            _loaded ? '参数与讲稿已随本机备份保存' : '正在读本机参数…',
            key: const ValueKey('kit-tele-note-tip'),
          ),
        ),
      ],
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
          width: 56,
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
