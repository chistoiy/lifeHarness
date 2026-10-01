/// V1.54 X-Ray 批B · 自学习弹层组（原型 xrfrag/sheets.frag
/// sheetXrAdd / sheetXrDel / sheetXrMerge / sheetXrPeek 的 1:1 落位）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_log.dart';
import '../../data/xray/xray_dao.dart';
import '../../domain/book.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast;

class _Lk {
  static const accent = Color(0xFF6366F1);
  static const muted = Color(0xFF94A3B8);
  static const rose = Color(0xFFF43F5E);
}

const List<(String, String)> _xrTypeTabs = [
  ('per', '人名'),
  ('loc', '地点'),
  ('org', '机构'),
  ('term', '术语'),
  ('abbr', '缩写'),
  ('book', '书名'),
];

/// 类型猜测（原型 xrGuessType 1:1）：加词弹层默认类型预置，用户仍可改。
String xrGuessType(String w) {
  if (RegExp(r'^《.*》$').hasMatch(w)) return 'book';
  if (RegExp(r'^[A-Z]{2,}$').hasMatch(w)) return 'abbr';
  if (RegExp(r'先生|夫人|教授|博士|警司|上校|伯爵|爵士').hasMatch(w)) return 'per';
  if (RegExp(r'国$|市$|省$|河|山|岛|平原').hasMatch(w)) return 'loc';
  if (RegExp(r'公司|委员会|研究院|学院|协会|银行').hasMatch(w)) return 'org';
  return 'term';
}

/// 加为词条（F8①）：词＋类型＋生效范围；确认后登记词条并全书补扫（走调度器）。
Future<void> showXrAddSheet(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  String? md5,
  String prefill = '',
  required Future<String?> Function() ensureMd5,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) {
      var type = xrGuessType(prefill);
      var scopeBook = true;
      final ctrl = TextEditingController(text: prefill);
      return StatefulBuilder(
        builder: (_, setSt) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 24 + MediaQuery.viewInsetsOf(sc).bottom),
            child: Column(
              key: const ValueKey('sheetXrAdd'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('加为词条',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('xrAddWordIn'),
                  controller: ctrl,
                  autofocus: prefill.isEmpty,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '要加入的词',
                    hintStyle: TextStyle(fontSize: 12, color: _Lk.muted),
                  ),
                  onChanged: (_) => setSt(() {}),
                ),
                const SizedBox(height: 10),
                Wrap(
                  key: const ValueKey('xrAddTypes'),
                  spacing: 6,
                  children: [
                    for (final t in _xrTypeTabs)
                      GestureDetector(
                        key: ValueKey('xr-add-${t.$1}'),
                        onTap: () => setSt(() => type = t.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: type == t.$1
                                ? _Lk.accent
                                : const Color(0x2994A3B8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(t.$2,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: type == t.$1
                                      ? Colors.white
                                      : const Color(0xFF64748B))),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  key: const ValueKey('xrAddScope'),
                  children: [
                    for (final (k, l) in const [
                      ('book', '仅本书'),
                      ('global', '加入全局词库')
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          key: ValueKey('xr-addsc-$k'),
                          onTap: () => setSt(() => scopeBook = k == 'book'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: scopeBook == (k == 'book')
                                  ? _Lk.accent
                                  : const Color(0x2994A3B8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(l,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: scopeBook == (k == 'book')
                                        ? Colors.white
                                        : const Color(0xFF64748B))),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  key: const ValueKey('xrAddGo'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final w = ctrl.text.trim();
                    if (w.isEmpty) {
                      readToast(sc, '先填要加入的词');
                      return;
                    }
                    final m = md5 ?? await ensureMd5();
                    if (m == null || m.isEmpty) {
                      if (sc.mounted) readToast(sc, '文件暂不可读 · 稍后再试');
                      return;
                    }
                    if (sc.mounted) Navigator.pop(sc);
                    final sched = ref.read(xraySchedulerProvider);
                    await sched.dao.registerUserWord(
                        md5: m, word: w, type: type, global: !scopeBook);
                    unawaited(sched
                        .scanWord(book: book, md5: m, word: w, type: type));
                    sched.notifyDataChanged();
                    if (sc.mounted) readToast(sc, '已加词「$w」· 全书补扫中');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _Lk.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('加为词条',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 移除确认（F8②）：永久屏蔽＝状态位；可选升级全局黑名单。
Future<void> showXrDelSheet(
  BuildContext context,
  WidgetRef ref, {
  required String md5,
  required List<int> ids,
  required List<String> names,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) {
      var global = false;
      return StatefulBuilder(
        builder: (_, setSt) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              key: const ValueKey('sheetXrDel'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('移除词条',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '移除「${names.join('、')}」后不再出现在索引，阈值再低也不会复活。',
                  style: const TextStyle(fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 6),
                for (final (k, l) in const [
                  ('book', '仅本书'),
                  ('global', '升级到全局黑名单（所有书生效）')
                ])
                  GestureDetector(
                    key: ValueKey('xr-del-$k'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setSt(() => global = k == 'global'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                              global == (k == 'global')
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: _Lk.accent),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(l,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                GestureDetector(
                  key: const ValueKey('xrDelGo'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    Navigator.pop(sc);
                    await ref
                        .read(xrayDaoProvider)
                        .markDeleted(md5, ids, toGlobal: global);
                    ref.read(xraySchedulerProvider).notifyDataChanged();
                    if (sc.mounted) {
                      readToast(sc,
                          '已移除 ${ids.length} 条 · ${global ? '并加入全局黑名单' : '仅本书生效'}');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _Lk.rose,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('确认移除',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 合并进…（F8③）：点一条其余词条＝整条并入（出场归属迁移 + 曾用名）。
Future<void> showXrMergePickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required String md5,
  required XrayEntityRow from,
  required List<XrayEntityRow> others,
  void Function(int intoId)? onDone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          key: const ValueKey('sheetXrMerge'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('合并进…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '「${from.name}」的出场将全部归入所选规范词条（曾用名记入 aliases）',
              style:
                  const TextStyle(fontSize: 10, color: _Lk.muted, height: 1.5),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final v in others)
                    ListTile(
                      key: ValueKey('xr-mg-${v.id}'),
                      dense: true,
                      title: Text('${v.name} · ${v.n} 次',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      trailing: const Icon(Icons.merge_rounded,
                          size: 15, color: _Lk.muted),
                      onTap: () async {
                        Navigator.pop(sc);
                        await ref
                            .read(xrayDaoProvider)
                            .mergeInto(md5, intoId: v.id, fromIds: [from.id]);
                        ref
                            .read(xraySchedulerProvider)
                            .notifyDataChanged();
                        onDone?.call(v.id);
                        if (sc.mounted) {
                          readToast(sc,
                              '已合并「${from.name}」入「${v.name}」· 出场归属已迁移');
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 选区命中迷你卡（F6）：摘要 +「查看全部位置」进面板详情子页。
Future<void> showXrPeekSheet(
  BuildContext context, {
  required XrayEntityRow ent,
  required VoidCallback onViewAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          key: const ValueKey('sheetXrPeek'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(ent.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _Lk.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ent.userAdded ? '我的词条' : 'X-Ray',
                    style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: _Lk.accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${ent.n} 次提及 · 跨 ${ent.chs} 章',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(sc),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(sc).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('关闭',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    key: const ValueKey('xrPeekAll'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(sc);
                      onViewAll();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _Lk.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('查看全部位置',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 屏6 · X-Ray 索引备份半屏（sheets.frag sheetXrBak）：
/// 导出 .xraybak（另存为）/ 从备份导入（选文件→MD5 校验→覆盖确认）。
Future<void> showXrBakSheet(BuildContext context, WidgetRef ref) async {
  final dao = ref.read(xrayDaoProvider);
  final books = await dao.indexedBookCount();
  if (!context.mounted) return;
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          key: const ValueKey('sheetXrBak'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('X-Ray 索引备份',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                const Text('数据',
                    style: TextStyle(fontSize: 9, color: _Lk.muted)),
              ],
            ),
            const SizedBox(height: 10),
            _bakRow(sc, 'xrBakExport', '导出备份（.xraybak）',
                '$books 个索引', () async {
              final svc = ref.read(xrayBackupServiceProvider);
              final saved = await svc.exportAll();
              if (sc.mounted) {
                readToast(sc, saved == null
                    ? '已取消导出'
                    : '已导出 $saved');
              }
            }),
            _bakRow(sc, 'xrBakImport', '从备份导入', '校验 MD5 · 覆盖需确认',
                () async {
              final svc = ref.read(xrayBackupServiceProvider);
              Map<String, Object?>? bundle;
              try {
                bundle = await svc.readPick();
              } catch (e) {
                // 导入包解析失败＝外部文件问题，留痕+toast 双出口。
                AppLog.add('.xraybak 解析失败: $e', level: LhLevel.error);
                if (sc.mounted) readToast(sc, '包不可读：$e');
                return;
              }
              if (bundle == null || !sc.mounted) return;
              final n =
                  ((bundle['indices'] as List?) ?? const []).length;
              final ok = await showDialog<bool>(
                context: sc,
                builder: (d) => AlertDialog(
                  title: const Text('导入索引备份'),
                  content: Text('包内 $n 个索引 · 将覆盖本机同指纹词条'
                      '（含你整理过的加词/屏蔽/合并结果）。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('确认导入')),
                  ],
                ),
              );
              if (ok != true || !sc.mounted) return;
              final r = await svc.importBundle(bundle);
              if (sc.mounted) {
                readToast(sc,
                    '导入完成 · $r.books 册生效 · MD5 校验拒收 $r.bad 册');
              }
              ref.read(xraySchedulerProvider).notifyDataChanged();
            }),
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(sc).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '整包备份已含索引数据 · 单书 .xraybak 供跨设备与分享',
                style: TextStyle(
                    fontSize: 10, height: 1.4, color: _Lk.muted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _bakRow(
    BuildContext ctx, String key, String title, String sub, VoidCallback onTap) {
  return GestureDetector(
    key: ValueKey(key),
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1A94A3B8),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(sub,
              style: const TextStyle(fontSize: 10, color: _Lk.muted)),
        ],
      ),
    ),
  );
}
