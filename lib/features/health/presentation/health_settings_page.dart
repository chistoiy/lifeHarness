import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/lh_wheel.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart' show dayKey;
import '../domain/health_export.dart';
import 'health_goal_row.dart';
import 'health_providers.dart';

/// 健康设置（原型 `p-hSet` · 路由 `/health/settings` · 批6b）。
///
/// 四条口径写在最近处：
/// · **单位只影响展示**（§五.10）：kg/斤、km/mile 存的一直是公制原值，切档只改读侧，
///   身体数据页与运动页的读数当场跟着变（写 prefs 后必 `healthTouch`，否则「点了没反应」）；
/// · **两个提醒时刻存而不排程**（工单 §3 · 排程接线在批8）：文案只说记录时刻，
///   不许出现「已排程」这类吹过头的实话；
/// · **备份开关只管本地 `.lhbak`**：关掉＝健康十四表整模块剔出本地备份包，
///   WebDAV 同步快照不吃这枚（同步排除另有 `care.syncExcluded` 的形，两条各管各的，需求 176 行）；
/// · 导出走仓内既有落盘通道（应用文档目录，与记账导出同一落点），
///   完成提示带条数与「含敏感记录」一句实话。
///
/// 两处**不铺**（工单 §3 登记的偏离）：原型「悬浮球喝水快捷」是需求明列的延后项、
/// 「分类映射 运动 · 睡眠休息」那条联动本仓尚未实现——都不做成看得见的假信息。
class HealthSettingsPage extends ConsumerStatefulWidget {
  const HealthSettingsPage({super.key});

  static const Key kDash = ValueKey('hs-dash');
  static const Key kCup = ValueKey('hs-cup');
  static const Key kStage = ValueKey('hs-stage');
  static const Key kNotify = ValueKey('hs-notify');
  static const Key kDaily = ValueKey('hs-daily');
  static const Key kRemind = ValueKey('hs-remind');
  static const Key kKgUnit = ValueKey('hs-kg-unit');
  static const Key kKmUnit = ValueKey('hs-km-unit');
  static const Key kBackup = ValueKey('hs-backup');
  static const Key kExportRow = ValueKey('hs-export');
  static const Key kExportPanel = ValueKey('hs-export-panel');
  static const Key kScopeWheel = ValueKey('hs-scope-wheel');
  static const Key kMonthWheel = ValueKey('hs-month-wheel');
  static const Key kPreview = ValueKey('hs-export-preview');
  static const Key kRun = ValueKey('hs-export-run');
  static const Key kFoot = ValueKey('hs-footnote');

  /// 小结时刻档（原型 `hWheelPick` 的第 4 参逐字）。
  static const List<String> dailyTimeLabels = ['20:00', '20:30', '21:00', '21:30', '22:00'];

  /// 体重打卡提醒档（同上）。
  static const List<String> remindTimeLabels = ['07:30', '08:00', '08:30', '09:00', '21:00', '21:30'];

  /// 一杯换算量八档（原型 `[200,220,250,300,330,350,400,500]`）。
  static const List<int> cupMlOptions = [200, 220, 250, 300, 330, 350, 400, 500];

  @override
  ConsumerState<HealthSettingsPage> createState() => _HealthSettingsPageState();
}

class _HealthSettingsPageState extends ConsumerState<HealthSettingsPage> {
  /// 导出面板是否展开（就地内嵌，不做二段弹层）。
  bool _exportOpen = false;

  /// 导出的两维状态：范围键 + 格式键 + 月份（仅「按月份」时有值）。
  String _scope = 'all';
  String _fmt = 'csv';
  String? _month;

  /// 导出进行中（禁重复点击——两次点击写出两份文件，用户只看见一句 toast）。
  bool _busy = false;

  void _touch() {
    if (mounted) healthTouch(ref);
  }

  Future<void> _setSwitch(Future<void> Function() write, {String? toastText}) async {
    await write();
    _touch();
    if (toastText != null && mounted) AppToast.show(context, toastText);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final st = ref.watch(healthSettingsProvider);
    final now = ref.watch(healthClockProvider)();
    final months = healthMonthLabels(now);

    return Scaffold(
      appBar: AppBar(title: const Text('健康设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _card([
            _switchRow(
              key: HealthSettingsPage.kDash,
              label: '主页健康概览卡',
              value: st.showDashCard(),
              onChanged: (v) => _setSwitch(() => st.setShowDashCard(v)),
            ),
            HealthGoalRow(
              key: HealthSettingsPage.kCup,
              rowKey: const ValueKey('hs-cup-row'),
              wheelKey: const ValueKey('hs-cup-wheel'),
              icon: Icons.local_drink_outlined,
              label: '一杯换算量',
              hint: '按 ml 记账时用于换算',
              valueText: '${st.cupMl()} ml',
              labels: [for (final ml in HealthSettingsPage.cupMlOptions) '$ml ml'],
              currentIndex: HealthSettingsPage.cupMlOptions.indexOf(st.cupMl()).clamp(
                  0, HealthSettingsPage.cupMlOptions.length - 1),
              onChanged: (i) => _setSwitch(() => st.setCupMl(HealthSettingsPage.cupMlOptions[i])),
            ),
            _switchRow(
              key: HealthSettingsPage.kStage,
              label: '睡眠分期逐段补录',
              hint: '关闭时只记起止与质量',
              value: st.stageLog(),
              onChanged: (v) => _setSwitch(() => st.setStageLog(v)),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            _navRow(
              key: HealthSettingsPage.kNotify,
              label: '提醒通知中心（用药 / 达成度）',
              onTap: () => context.push('/settings/notify'),
            ),
            HealthGoalRow(
              key: HealthSettingsPage.kDaily,
              rowKey: const ValueKey('hs-daily-row'),
              wheelKey: const ValueKey('hs-daily-wheel'),
              icon: Icons.today_outlined,
              label: '每日达成度小结',
              hint: _notScheduledHint,
              valueText: st.dailySummaryAt(),
              labels: HealthSettingsPage.dailyTimeLabels,
              currentIndex: _indexIn(HealthSettingsPage.dailyTimeLabels, st.dailySummaryAt()),
              onChanged: (i) => _setSwitch(
                  () => st.setDailySummaryAt(HealthSettingsPage.dailyTimeLabels[i])),
            ),
            HealthGoalRow(
              key: HealthSettingsPage.kRemind,
              rowKey: const ValueKey('hs-remind-row'),
              wheelKey: const ValueKey('hs-remind-wheel'),
              icon: Icons.monitor_weight_outlined,
              label: '体重打卡提醒',
              hint: _notScheduledHint,
              valueText: st.weightRemindAt(),
              labels: HealthSettingsPage.remindTimeLabels,
              currentIndex: _indexIn(HealthSettingsPage.remindTimeLabels, st.weightRemindAt()),
              onChanged: (i) => _setSwitch(
                  () => st.setWeightRemindAt(HealthSettingsPage.remindTimeLabels[i])),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            _unitRow(
              key: HealthSettingsPage.kKgUnit,
              keyBase: 'hs-kg-unit',
              label: '体重单位',
              hint: '存储恒 kg · 切换只影响展示',
              options: const ['kg', '斤'],
              value: st.kgUnit(),
              onTap: (v) => _setSwitch(() => st.setKgUnit(v),
                  toastText: '体重单位 → $v · 1 kg = 2 斤'),
            ),
            _unitRow(
              key: HealthSettingsPage.kKmUnit,
              keyBase: 'hs-km-unit',
              label: '距离单位',
              hint: '存储恒 km · 切换只影响展示',
              options: const ['km', 'mile'],
              value: st.kmUnit(),
              onTap: (v) =>
                  _setSwitch(() => st.setKmUnit(v), toastText: '距离单位 → $v'),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            _switchRow(
              key: HealthSettingsPage.kBackup,
              label: '健康数据随本地备份',
              hint: '关闭后整模块不进 .lhbak 包',
              value: st.includeInBackup(),
              onChanged: (v) => _setSwitch(() => st.setIncludeInBackup(v),
                  toastText: v
                      ? '健康数据将写入本地备份'
                      : '本模块数据排除出备份（含敏感用药记录）'),
            ),
            _exportRow(months),
          ]),
          Padding(
            key: HealthSettingsPage.kFoot,
            padding: const EdgeInsets.only(top: 16),
            child: Text(healthLocalOnlyFootnote,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  static const String _notScheduledHint = '仅记录时刻 · 未接系统排程';

  int _indexIn(List<String> labels, String v) {
    final i = labels.indexOf(v);
    return i < 0 ? 0 : i;
  }

  // ==================== 导出（就地展开：范围×格式＋预览＋落盘） ====================

  Widget _exportRow(List<String> months) {
    final month = _month ?? months.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: HealthSettingsPage.kExportRow,
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _exportOpen = !_exportOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            child: Row(
              children: [
                Text('导出健康流水',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${healthScopeLabel(_scope)} · ${healthFormatLabel(_fmt)}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary)),
                Icon(_exportOpen ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (_exportOpen)
          Padding(
            key: HealthSettingsPage.kExportPanel,
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final f in kHealthExportFormats)
                      _fmtChip(f.$1, f.$2),
                  ],
                ),
                const SizedBox(height: 6),
                _Wheel(
                  key: HealthSettingsPage.kScopeWheel,
                  keyPrefix: 'hs-scope-',
                  labels: healthScopeLabels(),
                  currentIndex: _scopeIndex(),
                  onSelect: (i) => setState(() {
                    _scope = healthScopeKey(i);
                    _month ??= months.last;
                  }),
                ),
                if (_scope == 'month')
                  Padding(
                    key: HealthSettingsPage.kMonthWheel,
                    padding: const EdgeInsets.only(top: 4),
                    child: _MonthWheel(
                        labels: months,
                        current: month,
                        onSelect: (m) => setState(() => _month = m)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(healthFieldNote(_fmt),
                      key: HealthSettingsPage.kPreview,
                      style: TextStyle(
                          fontSize: 9,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 4),
                Text(healthExportSensitiveNote,
                    style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: HealthSettingsPage.kRun,
                    onPressed: _busy ? null : _runExport,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    child: Text(_busy ? '导出中…' : '导出'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  int _scopeIndex() {
    final i = kHealthExportScopes.indexWhere((s) => s.$1 == _scope);
    return i < 0 ? 0 : i;
  }

  Widget _fmtChip(String key, String label) {
    final on = _fmt == key;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: ValueKey('hs-fmt-$key'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _fmt = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: on ? scheme.onPrimary : scheme.onSurfaceVariant)),
        ),
      ),
    );
  }

  Future<void> _runExport() async {
    setState(() => _busy = true);
    try {
      final pid = ref.read(activeHealthProfileProvider);
      final now = ref.read(healthClockProvider)();
      final all = await ref
          .read(healthRepositoryProvider)
          .exportRows(pid, '0000-01-01', dayKey(now));
      final rows = healthExportScope(rows: all, scope: _scope, now: now, month: _month);
      final dir = await ref.read(healthExportDirProvider)();
      final res = await writeHealthExportFile(dir: dir, fmt: _fmt, rows: rows, now: now);
      // 一条记录＝一行落盘（自建日志口径），路径进日志，屏上提示也带同一路径。
      AppLog.addKey('健康流水导出完成：${res.count} 条 · ${res.path}');
      if (mounted) {
        AppToast.show(
            context,
            healthExportToast(
                path: res.path, count: res.count, scope: _scope));
      }
    } catch (e) {
      if (mounted) AppToast.showError(context, '导出失败，详情见日志');
      AppLog.add('健康流水导出失败：$e', level: LhLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==================== 通用行件 ====================

  Widget _card(List<Widget> rows) => Container(
        decoration: context.cardDecoration,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        child: Column(children: rows),
      );

  /// 开关行（`key` 直接挂在开关上：测试按 `find.byKey(kBackup)` 拿到的就是可点的那枚）。
  Widget _switchRow({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (hint != null)
                  Text(hint,
                      style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(key: key, value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _navRow({required Key key, required String label, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// 两档单位选择（选中态必须可辨：底色＋描边一起换，别只改字色）。
  /// 档位键＝`'$keyBase-$档名'`（如 `hs-kg-unit-斤`），行本体键＝`keyBase`。
  Widget _unitRow({
    required String keyBase,
    required Key key,
    required String label,
    required String? hint,
    required List<String> options,
    required String value,
    required ValueChanged<String> onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (hint != null)
                  Text(hint, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: InkWell(
                key: ValueKey('$keyBase-$o'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(o),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: o == value ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(o,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: o == value ? scheme.onPrimary : scheme.onSurfaceVariant)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 屏内滚轮（共享 `LHWheel` 的原语，键前缀随档别走——范围轮与月份轮会同屏出现，
/// 前缀撞了测试就取不到唯一一枚）。
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.keyPrefix,
    required this.labels,
    required this.currentIndex,
    required this.onSelect,
  });

  final String keyPrefix;
  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 106,
        child: LHWheel(
          labels: labels,
          initialIndex: currentIndex,
          itemExtent: 30,
          keyPrefix: keyPrefix,
          onSelect: onSelect,
        ),
      );
}

/// 月份滚轮（「按月份」档才出现；回调用月份串而不是下标，避免调用侧再算一遍序）。
class _MonthWheel extends StatelessWidget {
  const _MonthWheel({required this.labels, required this.current, required this.onSelect});

  final List<String> labels;
  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final i = labels.indexOf(current);
    return _Wheel(
      keyPrefix: 'hs-month-',
      labels: labels,
      currentIndex: i < 0 ? labels.length - 1 : i,
      onSelect: (idx) => onSelect(labels[idx]),
    );
  }
}
