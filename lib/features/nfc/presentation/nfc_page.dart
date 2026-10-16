import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/nfc_mounts.dart';
import '../data/nfc_repo.dart';
import '../domain/nfc_card.dart';
import 'nfc_sheets.dart';

/// 「NFC 卡片」管理屏（原型 `p-sub-nfc`，家＝壳 `index.html`；本屏 Flutter 侧）。
///
/// 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md §2.1 F1-3 /
/// §3.1 / §4.1 / §5 ＋ 批1b 工单 docs/handoff/NFC卡片模块-批1b管理屏交互改造.md
/// §5（列表双节点）/ §6（贴卡设置收进右上角）。
///
/// 一屏一卡：①「我的卡片」（列表＋新建＋张数计数＋空态虚线行）；
/// ② 底部三行灰字（锁屏边界 / 卡片选型 / 多机与张贴）。
/// 「贴卡行为」三开关已收进右上角齿轮 → `showNfcSettingsSheet`（批1b §6）。
///
/// **架构红线（R1）**：本页不 import 任何 `features/calendar|read|habit|care/**`；
/// 目标数据与失效判定一律走 `shared/linkage/nfc_mounts.dart`。
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

  /// 目标解析结果（名字＋是否仍有效）——与列表**同一份读数**驱动。
  Map<String, NfcTargetState> _states = const <String, NfcTargetState>{};
  bool _loading = true;

  SettingsRepository get _prefs => ref.read(settingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _repo = widget.repoOverride ?? NfcRepo(AppDatabase.instance.db);
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.listAll();
    // 目标名与有效性**一次批量解析**（列表里逐行查库＝每行三次查询）。
    final states = await nfcTargetStates(list);
    if (!mounted) return;
    setState(() {
      _cards = list;
      _states = states;
      _loading = false;
    });
  }

  /// 右侧副行的写入态三态（**读 `written_at` 列** · C31）。
  ///
  /// 三态逐字：UID 只读卡＝「只读卡」（换卡才能解决的物理限制）／
  /// `written_at == null`＝「未写入」（可补的动作）／已写＝「已写入」。
  String _writeStateOf(NfcCard c) {
    if (c.isReadOnlyTag) return '只读卡';
    return c.isWritten ? '已写入' : '未写入';
  }

  /// 「用过 N 次 · 最后时间」副行。
  ///
  /// 时间三档：今天／昨天带时分，更早只给月日，从没用过＝「还没用过」。
  String _usedText(NfcCard c) {
    final ms = c.lastUsedAt;
    if (ms == null) return '用过 ${c.useCount} 次 · 还没用过';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    final when = diff == 0
        ? '今天 $hm'
        : diff == 1
            ? '昨天 $hm'
            : '${t.month} 月 ${t.day} 日';
    return '用过 ${c.useCount} 次 · $when';
  }

  /// 进行中态（C23「● 计时中」）。**批2 触发链**才有真值源
  /// （`activeTiming()` / `runningSession()` 同源回显）；批1b 只保留注入点，
  /// 不假装能判定（卡片表**不存计时态** · B30）。
  bool _runningOf(NfcCard c) => false;

  Future<void> _openEdit({NfcCard? card, NfcEditMode mode = NfcEditMode.full}) async {
    final changed = await showNfcEditSheet(context, card: card, mode: mode);
    if (changed == true) await _load();
  }

  Future<void> _openSettings() => showNfcSettingsSheet(context, prefs: _prefs);

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
          IconButton(
            key: const ValueKey('nfc-set'),
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '贴卡设置',
          ),
          const SizedBox(width: 4),
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
                const SizedBox(height: 2),
                Text('贴卡即执行绑定的动作；改名或换动作不用重写卡片',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
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
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: const Center(
                        child: Text('还没有卡片 · 点这里新建',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  )
                else
                  ..._cards.map(_cardRow),
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
                _grey('卡片选 NTAG213/215/216 那种硬币圆卡或身份证方卡都行，一张约 0.5~2 元'),
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

  /// 列表行＝**一条目两节点**（批1b §5）：左＝绑定目标 —虚线链条— 右＝卡片。
  ///
  /// 两节点**各自点开各自的形态**：左节点 → 绑定目标形态（只改目标）；
  /// 右节点 → 卡片信息形态（只改卡片信息）。写入/删除不再挂在行内
  /// （写入撤到卡片信息形态，删除也在那一层 · 行更干净）。
  Widget _cardRow(NfcCard c) {
    final scheme = Theme.of(context).colorScheme;
    final st = _states[c.id];
    final alive = st?.alive ?? false;
    final label = nfcTargetLabelOf(c, targetName: st?.name);
    final running = _runningOf(c);
    final color = Color(kNfcColors[c.colorIndex]);
    final writeState = _writeStateOf(c);

    // 已失效＝主行整行替换（不显示目标名，免得用户以为还能用）。
    final leftMain = alive ? (running ? '● 计时中 · $label' : label) : '已失效';

    return Semantics(
      button: true,
      label: '${c.name}，${alive ? label : '目标已失效'}，${_usedText(c)}，$writeState',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5))),
        ),
        child: Row(
          children: [
            // ===== 左节点：绑定目标（浅底）=====
            Expanded(
              child: InkWell(
                key: ValueKey<String>('nfc-row-target-${c.id}'),
                onTap: () => _openEdit(card: c, mode: NfcEditMode.target),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leftMain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: alive ? color : scheme.error,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _usedText(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ===== 中：虚线链条图标（线性 · 禁 emoji）=====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.link, size: 15, color: scheme.outlineVariant),
            ),

            // ===== 右节点：卡片（实底）=====
            SizedBox(
              width: 104,
              child: InkWell(
                key: ValueKey<String>('nfc-row-card-${c.id}'),
                onTap: () => _openEdit(card: c, mode: NfcEditMode.card),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis, // B：名称单行省略不换行
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (c.descText ?? '').trim().isEmpty
                            ? writeState
                            : c.descText!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
}
