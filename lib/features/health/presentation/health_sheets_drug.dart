part of 'health_sheets.dart';
// ==================== 用药建档（批5 · 原型 `sheetHDrug`） ====================

/// 新增药品档案一张表单（原型 `hDrugOpen`/`hDrugSave`）。**只有新增，没有编辑**：
/// 原型 `hDrugOpen()` 不带 id、保存走 `push`，`p-med` 上没有任何改档入口（工单 §3 偏离⑧）；
/// 仓储侧 `updateDrug` 的 id＋档案双闸已备好并有用例钉住，等真有改档需求时接线，不在此假装能改。
///
/// 四条口径写在最近处：
/// · 服用时刻＝**就地滚轮选档 →「＋ 加入」进 chips**（原型 `hdAddT`），chips 点一下就摘掉（同原型
///   `hdTimes.splice`）；滚轮 96 档＝24 小时 × 4 刻（`medTimeOptions` 单源），一条时刻都不留时
///   按原型回落 `08:00`，不空着写进档案（空 `times` 永远判不出漏服）；
/// · 剂量滚轮 0.5~6 片、半片一档（原型 `hNums(0.5,6,0.5)`），**新增默认 1 片**＝原型可见选中档 index 1；
/// · 单位固定「片」＝原型 `hDrugSave` 硬编码，表单不给单位输入位（`medUnit` 与卡副信息同一份）；
/// · 疗程结束日是文本＋自校验：原型那颗 `type=date` 的浏览器自带合法性检查在这里得自己卡
///   （`medEndDateErr` 拒越界月份与 2 月 30 日这类归一），留空＝不设置；原型预填的 2026-10-19 是演示数据，不搬。
///
/// 提醒开关默认**开**（原型 `toggle on`），文案不吹「已排程到通知中心」——排程在批8 才接线，
/// 这条口径收在 `medSavedTx` 里，弹层与卡片两处共用同一句话。
Future<void> showHealthDrugSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DrugSheet(),
  );
}

class _DrugSheet extends ConsumerStatefulWidget {
  const _DrugSheet();

  @override
  ConsumerState<_DrugSheet> createState() => _DrugSheetState();
}

class _DrugSheetState extends ConsumerState<_DrugSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _spec = TextEditingController();
  final TextEditingController _end = TextEditingController();

  /// 已选时刻（原型 `hdTimes`）：新增即带 08:00 一档，可见、可摘。
  final List<String> _times = [medDefaultTime];

  late int _timeIdx = medTimeIdx(medDefaultTime);
  late int _doseIdx = medDoseIdx(null);
  late bool _rem = true;

  @override
  void dispose() {
    _name.dispose();
    _spec.dispose();
    _end.dispose();
    super.dispose();
  }

  /// 「＋ 加入」：重复时刻当场拒（原型 `hdAddT` 原话），收下就升序排进 chips。
  void _addTime() {
    final t = medTimeOptions()[_timeIdx];
    if (_times.contains(t)) {
      AppToast.show(context, medDupTimeTx);
      return;
    }
    setState(() => _times
      ..add(t)
      ..sort());
    AppToast.show(context, medAddedTx(t));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, medNameRequiredTx);
      return;
    }
    final err = medEndDateErr(_end.text);
    if (err != null) {
      AppToast.show(context, err);
      return;
    }
    // 跨弹层的写库不带发起页的失效 ref（既定坑）：先抓 container，pop 之后只用它。
    final container = ProviderScope.containerOf(context, listen: false);
    final times = mdCleanTimes(_times);
    final plan = DrugPlan(
      profileId: container.read(activeHealthProfileProvider),
      name: name,
      spec: _orNull(_spec),
      unit: medUnit,
      dose: medDoseAt(_doseIdx),
      times: times.isEmpty ? const [medDefaultTime] : times,
      remind: _rem,
      endDate: _orNull(_end),
    );
    await container.read(healthRepositoryProvider).addDrug(plan);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    AppToast.show(context, medSavedTx(name, _rem));
    Navigator.of(context).pop();
  }

  static String? _orNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// 时刻 chips（原型 `tag-chip on` ＋ ✕）：整枚就是删除热区，不再套一层编辑态。
  Widget _timeChip(BuildContext context, String t) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('hdrug-time-$t'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _times.remove(t)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: scheme.onPrimary)),
            const SizedBox(width: 3),
            Icon(Icons.close, size: 11, color: scheme.onPrimary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opts = medTimeOptions();

    return _sheetShell(
      context,
      title: '新增药品',
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: _field(context, '名称', 'hdrug-name', _name, '如 维生素 D3')),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field(context, '规格', 'hdrug-spec', _spec, '400IU')),
          ],
        ),
        const SizedBox(height: 12),
        Text('服用时刻（可多选）',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (_times.isEmpty)
          Text('尚未选择时刻',
              key: const ValueKey('hdrug-times-empty'),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
        else
          Wrap(
            key: const ValueKey('hdrug-times'),
            spacing: 8,
            runSpacing: 6,
            children: [for (final t in _times) _timeChip(context, t)],
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: _wheel(context,
                  label: '添加',
                  labels: opts,
                  index: _timeIdx,
                  onSelect: (v) => setState(() => _timeIdx = v),
                  keyPrefix: 'hdrugT',
                  key: const ValueKey('hdrug-time-wheel')),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 34),
                child: OutlinedButton(
                  key: const ValueKey('hdrug-time-add'),
                  onPressed: _addTime,
                  child: const Text('+ 加入', style: TextStyle(fontSize: 11.5)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _wheel(context,
                  label: '每次剂量',
                  labels: medDoseLabels(),
                  index: _doseIdx,
                  onSelect: (v) => setState(() => _doseIdx = v),
                  keyPrefix: 'hdrugD',
                  key: const ValueKey('hdrug-dose-wheel')),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(mdDoseUnitTx(medUnit),
                  key: const ValueKey('hdrug-dose-unit'),
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
                child: Text('按时刻提醒',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
            Switch(
                key: const ValueKey('hdrug-rem'),
                value: _rem,
                onChanged: (v) => setState(() => _rem = v)),
          ],
        ),
        const SizedBox(height: 6),
        _inlineDate(context, _end, '疗程结束日（选填）'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hdrug-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                  key: const ValueKey('hdrug-save'),
                  onPressed: _save,
                  child: const Text('保存药品')),
            ),
          ],
        ),
      ],
    );
  }
}
