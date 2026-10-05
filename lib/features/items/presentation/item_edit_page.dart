import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/item_mounts.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/items_repository.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';
import 'items_kit.dart';
import 'items_providers.dart';

/// `/items/edit` 的 typed extra（T10 路由收口）：路由表只认这一个形状。
///
/// 深链 `/items/edit`（**无 extra**）＝空白新建（仪表盘 FAB 那条路）；
/// 「编辑某件」「记账流水升级预填」必须带本对象——不许再往 `extra:` 塞裸 Object。
class ItemEditArg {
  const ItemEditArg({this.origin, this.prefill});

  /// 非空＝编辑该档案。
  final ItemProfile? origin;

  /// 记账流水升级候选（新建预填路径）。
  final LedgerCandidate? prefill;
}

/// P7b 物品档案编辑（新建/修改共用一版全屏表单，HG-H1 同表单单版本）。
///
/// 口径：购入/保修日期就地内嵌滚轮（HG-D1）；计费方式三 chip + 条件区
/// （times 计划次数/单位、stop 预期年/止损线%）；状态四 chip；编辑态转
/// 已报废/已回收(转出) 按 billingForStatus 冻结；建档/升级/同步流水三路径
/// 统一走 itemCreate（联动 L12，升级挂来源徽标不重复生成流水）。
class ItemEditPage extends ConsumerStatefulWidget {
  const ItemEditPage({super.key, this.origin, this.prefill});

  /// null=新建；非空=编辑档案。
  final ItemProfile? origin;

  /// 记账流水升级候选（新建预填路径，来源徽标 source='ledger'）。
  final LedgerCandidate? prefill;

  @override
  ConsumerState<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends ConsumerState<ItemEditPage> {
  final _nameCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _planCtl = TextEditingController(text: '300');
  final _stopPctCtl = TextEditingController(text: '30');

  late DateTime _buy;
  DateTime? _warranty;
  String _cat = '数码';
  int? _years; // 预期年限（null=不设预期）
  ItemMode _mode = ItemMode.day;
  String _unit = '次';
  int _stopYears = 5;
  String _status = kItemStatusActive;
  bool _syncTxn = true;
  bool _syncRemind = true;

  @override
  void initState() {
    super.initState();
    // 默认购入日＝itemsClockProvider 的「今天」（时间源缝统一口径，测试可固定）。
    final n = ref.read(itemsClockProvider)();
    _buy = DateTime(n.year, n.month, n.day);
    final o = widget.origin;
    final p = widget.prefill;
    if (o != null) {
      _nameCtl.text = o.name;
      _priceCtl.text = o.price.toStringAsFixed(
          o.price == o.price.roundToDouble() ? 0 : 2);
      _buy = parseYmd(o.buyDate);
      _cat = o.category;
      _years = o.expectedYears;
      _warranty = o.warranty == null ? null : parseYmd(o.warranty!);
      _mode = o.mode;
      _unit = o.unit;
      _planCtl.text = (o.planUnits ?? 300).toStringAsFixed(0);
      _stopPctCtl.text = '${o.stopPct}';
      _stopYears = o.expectedYears ?? 5;
      _status = o.status;
    } else if (p != null) {
      _nameCtl.text = p.title;
      _priceCtl.text =
          p.amount == p.amount.roundToDouble() ? '${p.amount.round()}' : '${p.amount}';
      _buy = parseYmd(p.date);
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _priceCtl.dispose();
    _planCtl.dispose();
    _stopPctCtl.dispose();
    super.dispose();
  }

  InputDecoration _inp(String hint) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: context.tokens.accent)));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.origin != null;
    final upgrading = widget.prefill != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(editing ? '编辑档案' : '录入物品'),
            Text(editing ? widget.origin!.name : '建档即开始每日计费',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _photoRow(),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('i-edit-name'),
            controller: _nameCtl,
            textCapitalization: TextCapitalization.none,
            decoration: _inp('名称 · 品牌型号，如 MacBook Air M3'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('i-edit-price'),
                  controller: _priceCtl,
                  keyboardType: TextInputType.number,
                  decoration: _inp('购入价格 ¥'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown(
                  key: const ValueKey('i-edit-cat'),
                  value: _cat,
                  items: kItemCats,
                  labelOf: (v) => v,
                  onChanged: (v) => setState(() => _cat = v),
                ),
              ),
            ],
          ),
          const _Lbl('购入日期'),
          Container(
            key: const ValueKey('i-edit-buy-wheel'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: context.cardDecoration,
            child: InlineDateWheel(
              value: _buy,
              onChanged: (v) => setState(() => _buy = v),
            ),
          ),
          Text(
            '购入日期 ${fmtYmd(_buy)} · 保存后按自然日摊薄',
            key: const ValueKey('i-edit-buy-label'),
            style: const TextStyle(fontSize: 10, color: kItemMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  key: const ValueKey('i-edit-years'),
                  value: _yearsLabel,
                  items: const ['预期 3 年', '预期 5 年', '预期 8 年', '不设预期'],
                  labelOf: (v) => v,
                  onChanged: (v) => setState(() =>
                      _years = switch (v) {
                        '预期 3 年' => 3,
                        '预期 5 年' => 5,
                        '预期 8 年' => 8,
                        _ => null,
                      }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _warrantyButton()),
            ],
          ),
          if (_warranty != null) ...[
            const _Lbl('保修到期日期（滚轮选择 · 可清除）'),
            Container(
              key: const ValueKey('i-edit-war-wheel'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: context.cardDecoration,
              child: InlineDateWheel(
                value: _warranty!,
                onChanged: (v) => setState(() => _warranty = v),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: MiniBtn(
                key: const ValueKey('i-edit-war-clear'),
                icon: Icons.close,
                label: '清除保修日期',
                onTap: () => setState(() => _warranty = null),
              ),
            ),
          ],
          const _Lbl('计费方式'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in ItemMode.values)
                PillChip(
                  key: ValueKey('i-edit-mode-${m.wire}'),
                  label: m.label,
                  selected: _mode == m,
                  onTap: () => setState(() => _mode = m),
                ),
            ],
          ),
          if (_mode == ItemMode.times) ..._timesSection(),
          if (_mode == ItemMode.stop) ..._stopSection(),
          const _Lbl('状态'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const [
                kItemStatusActive,
                kItemStatusIdle,
                kItemStatusRecycleOut,
                kItemStatusScrapped,
              ])
                PillChip(
                  key: ValueKey('i-edit-status-$s'),
                  label: s == kItemStatusRecycleOut ? '已回收' : s,
                  selected: _status == s,
                  onTap: () => setState(() => _status = s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('i-edit-toggles'),
            decoration: context.cardDecoration,
            child: Column(
              children: [
                if (upgrading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 15, color: kItemMint),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                '由记账流水升级建档 · 不重复生成流水，原流水挂来源徽标（联动 L12）',
                                style: TextStyle(fontSize: 11.5))),
                      ],
                    ),
                  )
                else if (!editing)
                  _toggleRow(
                      '建档同步生成一条记账流水（联动 L12）',
                      const ValueKey('i-edit-sync-txn'),
                      _syncTxn,
                      (v) => setState(() => _syncTxn = v),
                      first: true),
                _toggleRow(
                    '保修到期自动汇入「日子 · 提醒中心」（联动 L10）',
                    const ValueKey('i-edit-sync-remind'),
                    _syncRemind,
                    (v) => setState(() => _syncRemind = v),
                    first: upgrading || editing),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GradButton(
            key: const ValueKey('i-edit-save'),
            label: '保存档案',
            onTap: _save,
          ),
          const SizedBox(height: 8),
          const Text(
              '直线法：（价 ＋ 二次付费 − 残值）÷ 持有天数 · 保存后每日 00:00 自动重算',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: kItemMuted)),
        ],
      ),
    );
  }

  String get _yearsLabel => switch (_years) {
        3 => '预期 3 年',
        5 => '预期 5 年',
        8 => '预期 8 年',
        _ => '不设预期',
      };

  Widget _photoRow() {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('i-edit-photo'),
      onTap: () => AppToast.show(context, '拍照 / 相册（本地存储）'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: scheme.outlineVariant, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(itemCatIcon(_cat), size: 30, color: kItemMuted),
            const SizedBox(height: 6),
            Text(
              widget.origin != null
                  ? '点击更换照片'
                  : widget.prefill != null
                      ? '来自记账流水 · 点击可更换照片'
                      : '添加物品照片（点击拍摄/选择）',
              style: const TextStyle(fontSize: 11, color: kItemMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warrantyButton() {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('i-edit-war-toggle'),
      onTap: () => setState(() => _warranty ??= _buy),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _warranty == null ? '保修到期（可选）' : '保修至 ${fmtYmd(_warranty!)}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  List<Widget> _timesSection() => [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('i-edit-plan'),
                controller: _planCtl,
                keyboardType: TextInputType.number,
                decoration: _inp('计划总次数'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown(
                key: const ValueKey('i-edit-unit'),
                value: _unit,
                items: kItemUnits,
                labelOf: (v) => v,
                onChanged: (v) => setState(() => _unit = v),
              ),
            ),
          ],
        ),
        const Text('每次成本 ＝ 成本池 ÷ 计划次数 · 日均按近 30 天实际频次折算',
            style: TextStyle(fontSize: 10, color: kItemMuted)),
      ];

  List<Widget> _stopSection() => [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                key: const ValueKey('i-edit-stopyears'),
                value: '预期 $_stopYears 年',
                items: const ['预期 3 年', '预期 5 年', '预期 8 年'],
                labelOf: (v) => v,
                onChanged: (v) => setState(() => _stopYears = switch (v) {
                  '预期 3 年' => 3,
                  '预期 8 年' => 8,
                  _ => 5,
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('i-edit-stoppct'),
                controller: _stopPctCtl,
                keyboardType: TextInputType.number,
                decoration: _inp('止损线：净值跌破购入价 30%'),
              ),
            ),
          ],
        ),
        const Text('按直线折旧预估净值曲线 · 接近止损线时提醒择机回收/转卖',
            style: TextStyle(fontSize: 10, color: kItemMuted)),
      ];

  Widget _dropdown<T extends Object>({
    Key? key,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: scheme.surface,
          style: TextStyle(fontSize: 12, color: scheme.onSurface),
          items: [
            for (final i in items)
              DropdownMenuItem(value: i, child: Text(labelOf(i))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _toggleRow(String label, Key key, bool on, ValueChanged<bool> onChanged,
      {bool first = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (!first) Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 11.5))),
              ItemsToggle(on: on, onChanged: onChanged),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, '先填物品名称');
      return;
    }
    final price = double.tryParse(_priceCtl.text.trim().replaceAll(',', ''));
    if (price == null || price <= 0) {
      AppToast.show(context, '先填购入价格');
      return;
    }
    final plan = double.tryParse(_planCtl.text.trim());
    final stopPct = int.tryParse(_stopPctCtl.text.trim()) ?? 30;
    final editing = widget.origin;
    final upgrading = widget.prefill;

    if (editing == null) {
      final profile = ItemProfile(
        name: name,
        iconId: 'box',
        category: _cat,
        buyDate: fmtYmd(_buy),
        price: price,
        expectedYears: _mode == ItemMode.stop ? _stopYears : _years,
        warranty: _warranty == null ? null : fmtYmd(_warranty!),
        status: _status,
        billing: billingForStatus(_status),
        mode: _mode,
        planUnits: _mode == ItemMode.times ? (plan ?? 100) : null,
        unit: _mode == ItemMode.times ? _unit : '次',
        stopPct: _mode == ItemMode.stop ? stopPct : 30,
        source: 'manual',
      );
      final id = await itemCreate(
        ref,
        profile,
        upgradeTxnId: upgrading?.txnId,
        syncTxn: _syncTxn && upgrading == null,
      );
      if (!mounted) return;
      // 起计值取重算后的实算 costPerDay（HG-E1，禁预估公式旁算）。
      final data = await ref.read(itemsRepositoryProvider).loadAll();
      if (!mounted) return;
      final fresh = data.items.where((x) => x.id == id).firstOrNull ?? profile;
      final todayCost = costPerDay(fresh, ref.read(itemsClockProvider)()) ?? 0;
      itemsTouch(ref);
      AppToast.show(context,
          '物品已建档 · 今日成本 ${itemMoney(todayCost)} 起计');
      Navigator.pop(context);
    } else {
      final updated = editing.copyWith(
        name: name,
        category: _cat,
        buyDate: fmtYmd(_buy),
        price: price,
        expectedYears: _mode == ItemMode.stop ? _stopYears : _years,
        warranty: _warranty == null ? null : fmtYmd(_warranty!),
        status: _status,
        billing: billingForStatus(_status), // 转已报废/转出即冻结
        mode: _mode,
        planUnits: _mode == ItemMode.times ? (plan ?? editing.planUnits) : null,
        unit: _mode == ItemMode.times ? _unit : editing.unit,
        stopPct: _mode == ItemMode.stop ? stopPct : editing.stopPct,
      );
      await ref.read(itemsRepositoryProvider).updateItem(updated);
      if (!mounted) return;
      itemsTouch(ref);
      AppToast.show(context, '档案已更新 · 日均已重算');
      Navigator.pop(context);
    }
  }
}

/// 分节小标题（原型 text-xs font-bold 节头）。
class _Lbl extends StatelessWidget {
  const _Lbl(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );
}
