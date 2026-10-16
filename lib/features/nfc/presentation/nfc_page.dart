import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema/nfc.dart' show NfcTargetKind;
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/nfc_card.dart';
import '../data/nfc_repo.dart';
import 'nfc_sheets.dart';

/// 「NFC 卡片」管理屏（原型 `p-sub-nfc`，家＝壳 `index.html`；本屏 Flutter 侧）。
///
/// 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md §2.1 F1-3 /
/// §3.1 / §4.1 / §5 · 执行工单 docs/handoff/NFC卡片模块-批1数据层与管理屏.md。
///
/// 一屏两卡：①「我的卡片」（列表＋新建＋张数计数＋空态虚线行）
/// ②「贴卡行为」（**总闸 `nfc.enabled` ＋两个明细开关**，C42 层级＝总闸 ＞ 明细）。
///
/// **架构红线（R1）**：本页不 import 任何 `features/calendar|read/**`；
/// 目标选择器的分类/书目数据走 `shared/linkage/nfc_mounts.dart`（由 sheets 消费）。
/// 本页只 import `core/platform/desktop_actions.dart` 的动作表（C9/C18：`nav.*`
/// 唯一动作来源，禁本模块再写一份动作常量）。
class NfcSettingsPage extends ConsumerStatefulWidget {
  const NfcSettingsPage({super.key, this.repoOverride});

  /// 测试注入缝（避免 widget 用例去碰真磁盘库）。
  final NfcRepo? repoOverride;

  @override
  ConsumerState<NfcSettingsPage> createState() => _NfcSettingsPageState();
}

class _NfcSettingsPageState extends ConsumerState<NfcSettingsPage> {
  late final NfcRepo _repo;
  List<NfcCard> _cards = const <NfcCard>[];
  bool _loading = true;

  // 贴卡行为三开关（C42 总闸 ＞ 明细）。切换即时落偏好，**无 loading**（§4.1）。
  bool _enabled = true;
  bool _confirmBeforeRun = false;
  bool _promptUnbound = true;

  SettingsRepository get _prefs => ref.read(settingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _repo = widget.repoOverride ?? NfcRepo(AppDatabase.instance.db);
    final r = _prefs;
    _enabled = r.loadNfcEnabled();
    _confirmBeforeRun = r.loadNfcConfirmBeforeRun();
    _promptUnbound = r.loadNfcPromptUnbound();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.listAll();
    if (!mounted) return;
    setState(() {
      _cards = list;
      _loading = false;
    });
  }

  // ==================== 卡片行副文案 ====================

  /// 副文案＝「目标 · 用过 N 次」（§4.1）。
  ///
  /// ⚠「● 计时中」标记（C23）判据**同源各模块库**，不落卡片表；
  /// 批1 只读数不判定——**进行中态的注入点留给批2 触发链**（`nfcTargetActiveProvider`），
  /// 此处先用 `targetActive` 参数承接，默认全 false，批2 由 provider 喂真值。
  String _subtitle(NfcCard c, {required bool targetActive}) {
    final name = c.targetKindLabel;
    final parts = <String>[];
    if (name != null) parts.add(name);
    parts.add('用过 ${c.useCount} 次');
    return parts.join(' · ');
  }

  /// 右侧写入态（**读 `written_at` 列** · C31）。
  ///
  /// 三态逐字：UID 只读卡＝「只读卡」（换卡才能解决的物理限制）／
  /// `written_at == null`＝「写入」（可补的动作）／已写＝「已写入」。
  String _writeStateOf(NfcCard c) {
    if (c.isReadOnlyTag) return '只读卡';
    return c.isWritten ? '已写入' : '写入';
  }

  Future<void> _deleteCard(NfcCard c) async {
    // C7：不进回收站 ⇒ 确认层必须说清后果（"原卡片会变成未绑定，重新绑定即可再用"）。
    final ok = await lhConfirm(context, '删除后原卡片会变成未绑定，重新绑定即可再用。');
    if (!ok) return;
    await _repo.delete(c.id);
    await _load(); // 行数／入口计数／列表三处随动（同一份读数驱动，§4.1 F1-5）
  }

  Future<void> _openEdit({NfcCard? card, String? bindTagKey}) async {
    final changed = await showNfcEditSheet(context, card: card, bindTagKey: bindTagKey);
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC 卡片'),
        actions: [
          TextButton(
            key: const ValueKey('nfc-new'),
            onPressed: () => _openEdit(),
            child: const Text('新建卡片'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ===== ① 我的卡片 =====
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('我的卡片',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('共 ${_cards.length} 张',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (_cards.isEmpty)
                  // 空态：LH-L04 虚线补录行定式（点击＝新建，禁自造空态插画）
                  InkWell(
                    key: const ValueKey('nfc-empty'),
                    onTap: () => _openEdit(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: scheme.outlineVariant, style: BorderStyle.solid),
                      ),
                      child: Column(
                        children: [
                          const Text('还没有卡片 · 点这里新建',
                              style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                  )
                else
                  ..._cards.map(_cardRow),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== ② 贴卡行为 =====
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('贴卡行为',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                _switchRow(
                  '启用 NFC 卡片',
                  _enabled,
                  (v) async {
                    setState(() => _enabled = v);
                    await _prefs.saveNfcEnabled(v);
                  },
                  keyName: 'nfc-sw-enabled',
                ),
                _switchRow(
                  '贴卡先确认再执行',
                  _confirmBeforeRun,
                  (v) async {
                    setState(() => _confirmBeforeRun = v);
                    await _prefs.saveNfcConfirmBeforeRun(v);
                  },
                  keyName: 'nfc-sw-confirm',
                ),
                _switchRow(
                  '未识别卡片提示绑定',
                  _promptUnbound,
                  (v) async {
                    setState(() => _promptUnbound = v);
                    await _prefs.saveNfcPromptUnbound(v);
                  },
                  keyName: 'nfc-sw-unbound',
                ),
                // 总闸关闭时两个明细开关置灰但**保留已选值**（C42：任一关即不触发，
                // 但重新开总闸不该把用户的明细选择一并抹掉）。
                if (!_enabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('总闸已关，贴卡不会有任何反应',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),

          // ===== 底部三行灰字（§5.7）=====
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // B40：必须点出「息屏贴卡会震动但不会触发」——「震了没反应」
                // 是本模块最可能的差评来源，只写「不派发事件」是开发者语言。
                _grey('锁屏状态下安卓不派发 NFC 事件（息屏贴卡会震动但不会触发），需解锁后贴卡'),
                _grey('卡片选 NTAG213/215 那种硬币圆卡或身份证方卡都行，一张约 0.5~2 元'),
                _grey('同一张卡可在多台装了本 App 的设备间通用，条件是那张卡的记录已通过备份恢复过去'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grey(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s,
          style: TextStyle(
              fontSize: 11, height: 1.6, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  /// 卡片行（LH-C24）：图标块（目标类图标）＋名称＋目标徽标 chip
  /// ＋「目标 · 用过 N 次」＋右侧写入态。点行体出编辑层。
  Widget _cardRow(NfcCard c) {
    final scheme = Theme.of(context).colorScheme;
    final label = c.targetKindLabel;
    final writeState = _writeStateOf(c);

    return Semantics(
      button: true,
      label: '${c.name}，${label ?? '未绑定目标'}，用过 ${c.useCount} 次，$writeState',
      child: InkWell(
        key: ValueKey<String>('nfc-row-${c.id}'),
        onTap: () => _openEdit(card: c),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5))),
          ),
          child: Row(
            children: [
              // 图标块：目标类图标（导航／计时／阅读三种·线性 SVG 语义）
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_iconOf(c.targetKind, bound: c.hasTarget),
                    size: 18, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis, // B：名称单行省略不换行
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        // 目标徽标 chip（B42：与「● 计时中」两枚独立标记共存）
                        if (label != null) ...[
                          const SizedBox(width: 7),
                          _miniChip(label, scheme),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(_subtitle(c, targetActive: false),
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 写入态：已写入＝灰字；未写入/只读＝可点的小钮或说明
              if (c.isWritten || c.isReadOnlyTag)
                Text(writeState,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
              else
                TextButton(
                  key: ValueKey<String>('nfc-write-${c.id}'),
                  // 写卡流程属批2：批1 只落入口，不假装能写（点按给一句明说）。
                  onPressed: () => AppToast.show(context, '写入卡片将在下一批开放'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(writeState,
                      style: TextStyle(fontSize: 11.5, color: scheme.primary)),
                ),
              IconButton(
                key: ValueKey<String>('nfc-del-${c.id}'),
                onPressed: () => _deleteCard(c),
                icon: const Icon(Icons.delete_outline, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: '删除卡片',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
      );

  Widget _switchRow(String label, bool value, Future<void> Function(bool) onChanged,
      {required String keyName}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Divider(height: 1, color: scheme.outlineVariant),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Switch(
                key: ValueKey<String>(keyName),
                value: value,
                onChanged: (v) => onChanged(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      ),
      child: child,
    );
  }

  /// 目标类图标（线性 · 禁 emoji · 禁彩块 · §5.5）。
  IconData _iconOf(String kind, {required bool bound}) {
    if (!bound) return Icons.help_outline;
    switch (kind) {
      case NfcTargetKind.timerCat:
      case NfcTargetKind.timerDuration:
        return Icons.timer_outlined;
      case NfcTargetKind.readBook:
        return Icons.menu_book_outlined;
      case NfcTargetKind.nav:
      default:
        return Icons.bolt_outlined;
    }
  }
}