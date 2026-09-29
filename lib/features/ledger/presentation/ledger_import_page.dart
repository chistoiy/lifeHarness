import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/bill_parser.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import '../domain/ledger_txn.dart';
import 'ledger_pick_sheets.dart' show showLCatPick, showLAcctPickForImport;
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L14 账单导入五步向导（原型 p-billImport · 九·补4/V1.36 修订）。
/// 步骤：1 选平台 → 2 粘贴 CSV 与解析选项 → 3 账户匹配 → 4 勾选式预览
/// → 5 完成（commitImport 落账 + 批次可撤销）。
class LedgerImportPage extends ConsumerStatefulWidget {
  const LedgerImportPage({super.key});

  @override
  ConsumerState<LedgerImportPage> createState() => _LedgerImportPageState();
}

/// 向导内一行预览数据（解析行 + 重复标记 + 行级分类改写）。
class _PRow {
  _PRow(this.r, {required this.dup});

  final BillRow r;
  bool dup;
  int? catOverride; // 点分类改写（null=按映射自动）
}

class _LedgerImportPageState extends ConsumerState<LedgerImportPage> {
  int _step = 1;
  String _plat = '微信支付';

  // 选文件（file_picker 读入的原始字节 + 展示名）。
  List<int>? _fileBytes;
  String _fileName = '';

  // 解析选项（图4 主页「只导入支出和收入类型」= skipNonSpend；退款冲抵负支出）。
  bool _skipNonSpend = true;
  bool _refundNeg = true;

  List<_PRow> _rows = [];
  Set<int> _sel = {};
  bool _foldN = true;
  bool _foldD = false;

  /// 步骤3：src → pick（'__new' 或本地账户 id 字符串）。
  final List<(String, int, String)> _agg = [];
  final List<String> _picks = [];

  int _written = 0;
  int _createdAccts = 0;
  String _createdNames = '';

  @override
  void dispose() {
    super.dispose();
  }

  void _toast(String m) => AppToast.show(context, m);

  void _reset() => setState(() {
    _step = 1;
    _rows = [];
    _sel = {};
    _agg.clear();
    _picks.clear();
    _written = 0;
    _createdAccts = 0;
    _createdNames = '';
    _fileBytes = null;
    _fileName = '';
  });

  int _catOf(_PRow p) => p.catOverride ?? mapBillCat(p.r);

  String _appBarTitle() => switch (_step) {
        1 => '账单导入与导出',
        2 => '选择导入文件',
        3 => '关联账户',
        4 => '已选 ${_sel.length} · 共 ${_rows.length} 笔',
        _ => '导入完成',
      };

  // ---- 步骤流转 ----

  Future<void> _next() async {
    if (_step == 1) {
      setState(() => _step = 2);
      return;
    }
    if (_step == 2) {
      final bytes = _fileBytes;
      if (bytes == null) {
        _toast('请先选择账单文件');
        return;
      }
      final res = parseBillFile(bytes, skipNonSpend: _skipNonSpend);
      if (res == null) {
        _toast('未识别到支付宝/微信账单表头 · 请检查导出文件');
        return;
      }
      if (res.rows.isEmpty) {
        AppLog.add('账单导入：$_fileName 解析到 0 条可导入流水'
            '（规则过滤 ${res.skipped} 条）', level: LhLevel.warn);
        _toast('解析到 0 条可导入流水');
        return;
      }
      // 重复判定：交易单号优先，缺失时时间+金额+对方兜底键。
      final repo = ref.read(ledgerRepositoryProvider);
      final seen = <String>{};
      final rows = <_PRow>[];
      for (final r in res.rows) {
        final hash = LedgerRepository.billHashOf(
          tradeNo: r.tradeNo,
          date: r.date,
          time: r.time,
          amt: r.amt,
          counterparty: r.counterparty,
        );
        final dup = seen.contains(hash) || await repo.billHashExists(hash);
        seen.add(hash);
        rows.add(_PRow(r, dup: dup));
      }
      // 账户匹配聚合（含收入行的到账方式）。
      _agg
        ..clear()
        ..addAll(aggBillAccounts(rows.map((p) => p.r).toList()));
      final d = ref.read(ledgerDataProvider).valueOrNull;
      _picks
        ..clear()
        ..addAll([
          for (final (src, _, _) in _agg) _pickFor(d, src),
        ]);
      setState(() {
        _rows = rows;
        _sel = {
          for (var i = 0; i < rows.length; i++)
            if (!rows[i].dup) i,
        };
        _step = 3;
      });
      AppLog.addKey('账单导入预览：文件 $_fileName · 平台 ${res.platform} · '
          '${rows.length} 条（重复命中 ${rows.where((p) => p.dup).length}）· '
          '付款方式 ${_agg.length} 组');
      _toast('解析完成：${rows.length} 条 · 重复命中 ${rows.where((p) => p.dup).length} 条');
      return;
    }
    if (_step == 3) {
      setState(() => _step = 4);
      return;
    }
    if (_step == 4) {
      await _commit();
    }
  }

  /// 同名本地账户优先对应；无则默认自动新建。
  static String _pickFor(LedgerData? d, String src) {
    if (d != null) {
      for (final a in d.accounts) {
        if (!a.archived && a.name == src) return '${a.id}';
      }
    }
    return '__new';
  }

  Future<void> _commit() async {
    if (_sel.isEmpty) {
      _toast('至少勾选 1 条再确认导入');
      return;
    }
    final d = ref.read(ledgerDataProvider).valueOrNull;
    if (d == null) return;
    final repo = ref.read(ledgerRepositoryProvider);
    // 新建账户清单（pick='__new'；credit 无额度默认 0，行 132 口径）。
    final newAccts = <LedgerAccount>[];
    final newIdxOf = <int, int>{}; // agg 下标 → newAccts 下标
    for (var i = 0; i < _agg.length; i++) {
      final pk = _picks[i];
      if (!pk.startsWith('__new')) continue;
      final (src, _, type) = _agg[i];
      final custom = pk.startsWith('__new:') ? pk.substring(6).trim() : '';
      newAccts.add(LedgerAccount(
        type: type,
        name: custom.isEmpty ? src : custom,
        icon: type == LedgerAccount.kCredit ? 'cardplus' : 'card',
        color: type == LedgerAccount.kCredit ? '#fb7185' : '#8b5cf6',
        creditLimit: type == LedgerAccount.kCredit ? 0 : null,
      ));
      newIdxOf[i] = newAccts.length - 1;
    }
    final specs = <ImportRowSpec>[];
    for (final i in _sel.toList()..sort()) {
      final p = _rows[i];
      final r = p.r;
      final aggIdx = _agg.indexWhere((a) => a.$1 == r.payMethod);
      final pick = aggIdx >= 0 ? _picks[aggIdx] : '__new';
      final kind = r.isRefund && _refundNeg
          ? LedgerTxn.kRefund
          : r.isIncome
          ? LedgerTxn.kIncome
          : LedgerTxn.kExpense;
      int acct;
      int? newIdx;
      if (kind == LedgerTxn.kIncome) {
        acct = d.defAcctId ?? 1; // 收入默认落默认账户，可在 L2 编辑改
      } else if (pick.startsWith('__new')) {
        acct = 1; // 占位，commitImport 按 newAcctIndex 覆写
        newIdx = newIdxOf[aggIdx];
      } else {
        acct = int.parse(pick);
      }
      specs.add(ImportRowSpec(
        LedgerTxn(
          kind: kind,
          amt: r.amt,
          catId: _catOf(p),
          accountId: acct,
          date: r.date,
          time: r.time.isEmpty ? null : r.time,
          note: r.counterparty.isEmpty ? r.product : r.counterparty,
          source: LedgerTxn.kSourceBill,
          bk: d.curBook.id,
          billHash: LedgerRepository.billHashOf(
            tradeNo: r.tradeNo,
            date: r.date,
            time: r.time,
            amt: r.amt,
            counterparty: r.counterparty,
          ),
        ),
        newAcctIndex: newIdx,
      ));
    }
    final res = await repo.commitImport(
      bk: d.curBook.id,
      platform: _plat,
      fileName: _fileName.isEmpty ? 'file' : _fileName,
      newAccounts: newAccts,
      rows: specs,
    );
    // 批次 id 只在这里落日志：页面没有「撤销本批」入口（原型无该行，见 set 页注释），
    // 真机要追某批导入只能从这条 key 行起查。
    AppLog.addKey('账单导入落库：批次 ${res.batchId} · 平台 $_plat · '
        '写入 ${res.written}/${specs.length} 条 · 新建账户 ${newAccts.length} 个'
        '（$_fileName）');
    ledgerTouch(ref);
    setState(() {
      _written = res.written;
      _createdAccts = newAccts.length;
      _createdNames = newAccts.map((a) => a.name).join('、');
      _step = 5;
    });
    _toast('已写入 ${res.written} 条 · 支持整批撤销本批导入');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_appBarTitle()),
            Text(
              _step == 4 ? '勾选要导入的账条目 · 点分类可改' : '仅本机解析 · 不上传不联网',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _StepDots(step: _step),
          const SizedBox(height: 16),
          ...switch (_step) {
            1 => _step1(),
            2 => _step2(),
            3 => _step3(),
            4 => _step4(),
            _ => _step5(),
          },
          if (_step < 5) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                if (_step > 1)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const Text('上一步'),
                    ),
                  ),
                if (_step > 1) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: context.tokens.gradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: context.tokens.g1.withValues(alpha: .3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _next,
                          child: Center(
                            child: Text(
                              _step == 4 ? '确认导入 ${_sel.length} 条' : '下一步',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---- 步骤1 选平台 ----

  List<Widget> _step1() {
    Widget pick(String plat, String badge, Color badgeBg, Color fg) {
      final on = _plat == plat;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _plat = plat),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? context.tokens.accent.withValues(alpha: .06) : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: on ? context.tokens.accent : Colors.transparent, width: 2),
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: badgeBg, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900, color: fg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(plat,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800))),
              Icon(
                  on ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: on ? context.tokens.accent : const Color(0xFFCBD5E1)),
            ]),
          ),
        ),
      );
    }

    return [
      const Text('选择账单来源',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      pick('微信支付', '微', const Color(0x2210B981), const Color(0xFF059669)),
      pick('支付宝', '支', const Color(0x220EA5E9), const Color(0xFF0EA5E9)),
      pick('其他记账产品', '其', const Color(0x22EF4444), const Color(0xFFEF4444)),
      pick('通用模板', '表', const Color(0x2216A34A), const Color(0xFF16A34A)),
      const SizedBox(height: 4),
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toast('切换账本请在账本页进行'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: context.cardDecoration,
          child: const Row(children: [
            Text('导入至',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            Spacer(),
            Text('当前账本',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: context.cardDecoration,
        child: Row(children: [
          const Expanded(
              child: Text('只导入支出和收入类型', style: TextStyle(fontSize: 13))),
          Switch(
              value: _skipNonSpend,
              onChanged: (v) => setState(() => _skipNonSpend = v)),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: const Text(
          '隐私承诺：账单文件仅在本机解析，不上传不联网；'
          '自动识别编码（UTF-8 含 BOM / GBK）与表头列结构。',
          style: TextStyle(fontSize: 11, height: 1.6),
        ),
      ),
    ];
  }

  // ---- 步骤2 粘贴内容 + 解析选项 ----

  List<Widget> _step2() {
    Widget opt(String label, bool value, ValueChanged<bool> on) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Switch(
            value: value,
            onChanged: (v) => setState(() => on(v)),
          ),
        ],
      ),
    );
    return [
      Text(
        '$_plat · 选择导出文件',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _pickFile,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
          decoration: BoxDecoration(
            color: context.tokens.accent.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: context.tokens.accent.withValues(alpha: .5), width: 2),
          ),
          child: Column(
            children: [
              Icon(Icons.folder_open, size: 34, color: context.tokens.accent),
              const SizedBox(height: 10),
              Text(
                _fileName.isEmpty ? '点击选择账单文件（.xlsx / .csv）' : _fileName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _fileName.isEmpty
                      ? const Color(0xFF94A3B8)
                      : context.tokens.accent,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '文件仅在本机解析 · 自动识别编码与表头',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: context.cardDecoration,
        child: Column(
          children: [
            opt('跳过「帮人代付 / 零钱通转入」等非支出流水', _skipNonSpend,
                (v) => _skipNonSpend = v),
            opt('退款冲抵记为负支出', _refundNeg, (v) => _refundNeg = v),
          ],
        ),
      ),
    ];
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    List<int>? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      try {
        bytes = await File(f.path!).readAsBytes();
      } catch (e) {
        AppLog.add('账单文件读取失败（${f.name}）：$e', level: LhLevel.warn);
        bytes = null;
      }
    }
    if (bytes == null) {
      _toast('无法读取所选文件');
      return;
    }
    setState(() {
      _fileBytes = bytes;
      _fileName = f.name;
    });
  }

  // ---- 步骤3 账户匹配 ----

  List<Widget> _step3() {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const [];
    final nw = _picks.where((p) => p.startsWith('__new')).length;
    String pickName(int i) {
      final p = _picks[i];
      if (p == '__new') return '新建「${_agg[i].$1}」';
      if (p.startsWith('__new:')) return '新建「${p.substring(6)}」';
      return d.acctById[int.tryParse(p) ?? -1]?.name ?? '未对应';
    }

    return [
      const Text(
        '账户匹配',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      const Text(
        '从账单「付款方式」列识别出以下账户，点击逐条指定写入的本地账户；'
        '未对应的默认新建，已对应的也可改',
        style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), height: 1.4),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < _agg.length; i++)
        Builder(
          builder: (bc) {
            final (src, cnt, _) = _agg[i];
            final isNew = _picks[i] == '__new';
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final res = await showLAcctPickForImport(
                    bc, src: src, curPick: _picks[i]);
                if (res != null) setState(() => _picks[i] = res);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: context.cardDecoration,
                child: Row(
                  children: [
                    LTile(
                      iconKey: isNew ? 'plus' : 'link',
                      color: isNew ? '#f59e0b' : '#6366f1',
                      size: 32,
                      radius: 10,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            src,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '出现 $cnt 笔 · 对应到「${pickName(i)}」',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: isNew
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_right,
                        size: 18, color: Color(0xFFCBD5E1)),
                  ],
                ),
              ),
            );
          },
        ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已对应本地账户 ${_agg.length - nw} 个 · 将新建 $nw 个',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Text(
              '确认后生效',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: context.tokens.accent,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // ---- 步骤4 勾选式预览 ----

  List<Widget> _step4() {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const [];
    final newRows = [
      for (var i = 0; i < _rows.length; i++)
        if (!_rows[i].dup) i,
    ];
    final dupRows = [
      for (var i = 0; i < _rows.length; i++)
        if (_rows[i].dup) i,
    ];
    return [
      const Text(
        '解析预览 · 勾选导入',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _StatCard(
            n: '${_rows.length}',
            label: '解析流水 · 查看',
            color: const Color(0xFF0EA5E9),
            onTap: () => setState(() => _foldN = true),
          ),
          const SizedBox(width: 10),
          _StatCard(
            n: '${dupRows.length}',
            label: '重复命中 · 查看',
            color: const Color(0xFFF59E0B),
            onTap: () => setState(() => _foldD = true),
          ),
          const SizedBox(width: 10),
          _StatCard(
            n: '${_sel.length}',
            label: '将写入（勾选）',
            color: const Color(0xFF10B981),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (newRows.isNotEmpty) _group(d, '解析流水', newRows, _foldN, 'n'),
      if (dupRows.isNotEmpty) ...[
        const SizedBox(height: 10),
        _group(d, '重复命中', dupRows, _foldD, 'd'),
      ],
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '分类自动映射 · 未命中进「其他」可改',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final (from, cid) in const [
              ('餐饮美食 → ', 101),
              ('交通出行 → ', 102),
              ('数码电器 → ', 103),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        from,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    LTile(
                      iconKey: d.catOf(cid).icon,
                      color: d.catOf(cid).color,
                      size: 20,
                      radius: 6,
                      iconSize: 12,
                    ),
                    const SizedBox(width: 5),
                    Text(d.catOf(cid).name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '退款冲抵 → ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const Text(
                    '负支出流水',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        '去重规则：交易单号唯一键优先；缺失时以「时间+金额+对方」组合键兜底 · '
        '支持整批导入记录一键撤销',
        style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), height: 1.5),
      ),
    ];
  }

  Widget _group(LedgerData d, String title, List<int> idxs, bool fold, String g) {
    final selN = idxs.where((i) => _sel.contains(i)).length;
    final all = idxs.isNotEmpty && selN == idxs.length;
    return Container(
      decoration: context.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (g == 'n') {
                _foldN = !_foldN;
              } else {
                _foldD = !_foldD;
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$title · ${idxs.length} 条',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '已选 $selN',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    fold ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          if (fold) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Checkbox(
                    value: all,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _sel.addAll(idxs);
                      } else {
                        _sel.removeAll(idxs);
                      }
                    }),
                  ),
                  const Text('全选', style: TextStyle(fontSize: 10)),
                  const Spacer(),
                  Text(
                    g == 'd' ? '与已有流水单号重复 · 默认不导入' : '逐笔勾选 · 仅写入勾选项',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final i in idxs) _row(d, i),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(LedgerData d, int i) {
    final p = _rows[i];
    final r = p.r;
    final on = _sel.contains(i);
    final cat = d.catOf(_catOf(p));
    final aggIdx = _agg.indexWhere((a) => a.$1 == r.payMethod);
    final pick = aggIdx >= 0 ? _picks[aggIdx] : '__new';
    final target = pick == '__new'
        ? '新建'
        : (d.acctById[int.tryParse(pick)]?.name ?? '?');
    final pre = r.isRefund ? '+' : r.isIncome ? '+' : '−';
    final col = r.isRefund || r.isIncome
        ? const Color(0xFF10B981)
        : const Color(0xFFFB7185);
    return Opacity(
      opacity: on ? 1 : .55,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: on,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() {
                v == true ? _sel.add(i) : _sel.remove(i);
              }),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '${r.date.substring(5)} ${r.time}',
                style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
              ),
            ),
            Expanded(
              child: Text(
                r.counterparty.isEmpty ? r.product : r.counterparty,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            GestureDetector(
              onTap: () async {
                final res = await showLCatPick(
                  context,
                  kind: r.isIncome ? 'income' : 'expense',
                  selCat: _catOf(p),
                );
                if (res != null) {
                  setState(() => p.catOverride = res.catId);
                  _toast('该笔分类已改为「${d.catOf(res.catId).name}」');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  cat.name,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF94A3B8),
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 68,
              child: Text(
                '$pre${money(r.amt)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: col),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                target,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8, color: Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 步骤5 完成 ----

  List<Widget> _step5() {
    final scheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 24),
      const Center(
        child: Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Color(0xFF10B981),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          '导入完成',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          '已写入 $_written 条流水 · 未勾选 ${_rows.length - _written} 条不导入'
          '${_createdAccts > 0 ? '\n新建账户 $_createdAccts 个（$_createdNames）' : ''}'
          '\n月度报表、分类占比与资产页已自动更新 · 支持整批撤销',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF94A3B8),
            height: 1.8,
          ),
        ),
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.tokens.gradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => context.go('/ledger'),
                  child: const Center(
                    child: Text(
                      '查看账本',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            height: 44,
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('再导一份'),
            ),
          ),
        ],
      ),
    ];
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.n,
    required this.label,
    required this.color,
    this.onTap,
  });

  final String n;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              Text(
                n,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 五步 imp-dot 进度条（原型 billStep）。
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        for (var n = 1; n <= 5; n++) ...[
          if (n > 1)
            Expanded(
              child: Container(
                height: 1,
                color: n <= step ? tokens.accent : const Color(0xFFCBD5E1),
              ),
            ),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: n < step
                  ? tokens.accent
                  : n == step
                  ? tokens.accent
                  : Colors.transparent,
              border: Border.all(
                color: n <= step ? tokens.accent : const Color(0xFFCBD5E1),
              ),
            ),
            child: n < step
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: n == step ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}
