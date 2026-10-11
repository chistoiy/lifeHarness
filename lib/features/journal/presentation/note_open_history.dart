/// V1.64 批4 · N-4「系统打开」历史列表（工单 交棒话术-20261004 §18 面板＝本批唯一规格依据·
/// 需求清单 V1.64 N-4·样张＝`index-bookshelf.html` 的 `sheetNoteOpenHist`/`renderNoh`/
/// `nohGo`/`nohMove`/`nohClr`）。
///
/// 口径（全部按样张与拍板落，不另造形态）：
///  · **不另造独立屏**（拍板 F）——入口＝文件树上的固定「系统打开」行，点开＝本半屏；
///  · 行＝标题＋`origin_path`＋`opened_at` 人话时间＋右侧**三态**胶囊；点行＝关屏后跳该笔记；
///  · 三态＝`已回写原文件`（DB v43 的 `wb_at >= updated_at`）／`仅应用内`／`已转正式目录`
///    （`folder` 已不是临时夹）——依据与取舍见工单 §18.1（回写成功原先只弹 toast 不落库，
///    库里推不出前两者，故本批加列）；
///  · **转入**＝复用既有「移动到」选择弹层，`source='open_with'` **保留不清**（拍板 B 同一口径，
///    也是「已转正式目录」这条态的唯一依据）；
///  · **清空**＝就地两步确认（不另开弹层），只把**仍在临时夹**的进件送进全局回收站（30 天可恢复），
///    **已转入的一行不动**；本批不碰回收站屏与语义；
///  · 计数与列表**同源**＝走同一个 `NoteDao.list()`，不另写 SQL（真机反馈批的同源教训）。
library;

import 'package:flutter/material.dart';

import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../data/note_dao.dart';
import '../domain/note.dart';
import '../domain/note_folder.dart';

/// 历史行三态（原型 `OF_ST` 的三个键＝同一组词，不许另造句子）。
enum NoteHistState { written, app, moved }

/// 三态判定（纯函数·无 context·用例直接喂 `Note`）。
/// 先判「已转入」＝`folder` 已不是临时夹；再判回写：`wb_at` 存在且**不早于**最后一次修改才算
/// 「已回写原文件」——回写后又改了正文必须退回「仅应用内」，否则就是骗人。
NoteHistState noteHistStateOf(Note n) {
  if ((n.folder ?? '') != kSystemOpenFolder) return NoteHistState.moved;
  final wb = n.wbAt;
  return (wb != null && !wb.isBefore(n.updatedAt))
      ? NoteHistState.written
      : NoteHistState.app;
}

/// 胶囊词（与原型 `OF_ST` 同词）。
String noteHistLabel(NoteHistState s) => switch (s) {
      NoteHistState.written => '已回写原文件',
      NoteHistState.app => '仅应用内',
      NoteHistState.moved => '已转正式目录',
    };

/// `app` 态行下那行人话小注（原型同句；另两态不给，避免堆话）。
String? noteHistHint(NoteHistState s) =>
    s == NoteHistState.app ? '原文件不在 · 改动仅存应用内' : null;

/// 行标题：标题为空＝回退到来源文件名去扩展名（列表里不出现空白行）。
String noteHistTitle(Note n) {
  final t = n.title.trim();
  if (t.isNotEmpty) return t;
  final src = n.originPath.isEmpty ? n.originUri : n.originPath;
  final f = (src.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ?? '')
      .replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '')
      .trim();
  // 标题与来源名都是空的（脏数据/手输）＝给一句人话，绝不画一行空白。
  return f.isEmpty ? '未命名进件' : f;
}

/// 打开时间三档人话（与笔记卡片同一规则，不另造措辞）。
String noteHistWhen(DateTime d) {
  final now = DateTime.now();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '今天 ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
  return d.year == now.year ? '$mm-$dd' : '${d.year}-$mm-$dd';
}

/// 从**已在手的同一份列表**里挑出经系统打开的进件（＝与树计数、卡片列表同源，不另查库）。
/// 排序＝最近一次打开时间倒序，没有该时间的按修改时间兜底。
List<Note> openHistFrom(List<Note> all) => [
      for (final n in all)
        if (n.source == 'open_with') n,
    ]..sort((a, b) =>
        (b.openedAt ?? b.updatedAt).compareTo(a.openedAt ?? a.updatedAt));

/// 异步取数版（服务与用例用；UI 侧直接喂 provider 的同一份列表）。
Future<List<Note>> openHistNotes(NoteDao notes) async =>
    openHistFrom(await notes.list());

/// 仍在临时夹的那些＝「清空」唯一能动它们；已转入的一行不动（产品裁定的语义）。
List<Note> openHistPending(List<Note> all) =>
    all.where((n) => (n.folder ?? '') == kSystemOpenFolder).toList();

/// 清空＝把未转入的进件送进回收站（走既有软删，不碰回收站屏语义）。返回条数。
Future<int> openHistClear(NoteDao notes) async {
  final ids = [for (final n in openHistPending(await openHistNotes(notes))) n.id!];
  if (ids.isEmpty) return 0;
  await notes.softDeleteMany(ids);
  return ids.length;
}

/// 「系统打开」历史半屏（原型 `sheetNoteOpenHist`）。
/// 数据由调用方取好传入（与树计数同一份读数）；三个动作回调都只回话不改 UI 结构，
/// 关屏与重取数由调用方决定＝弹层本体零业务、可直接点真断言。
Future<void> showNoteOpenHistorySheet(BuildContext context,
    {required List<Note> notes,
    required void Function(Note n) onOpen,
    required void Function(Note n) onMove,
    required Future<String> Function() onClear}) async {
  var armed = false; // 就地两步确认的开关（每次开屏从「清空」起态＝弹层级局部态，不外泄）
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (bc) => StatefulBuilder(
      builder: (bc2, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('系统打开 · 共 ${notes.length} 条',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              Flexible(
                child: notes.isEmpty
                    ? Container(
                        key: const ValueKey('noh-empty'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Theme.of(bc)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: .6)),
                        ),
                        child: const Text('还没有经系统打开的文件',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final n in notes)
                            _HistRow(
                                note: n,
                                // 原型 `nohGo`/`nohMove` 都是**先收半屏再动作**（跳编辑／开选择层
                                // 都不该压在弹层底下），所以关屏由本件负责，回调只管做事。
                                onOpen: () {
                                                  Navigator.pop(bc2);
                                                  onOpen(n);
                                                },
                                onMove: () {
                                                  Navigator.pop(bc2);
                                                  onMove(n);
                                                }),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('noh-clear'),
                onPressed: () async {
                  // 第一步只改口径问一句，第二步才动手（原型 nohArmed 同形，不再叠一层弹层）。
                  if (!armed) {
                    setSheet(() => armed = true);
                    return;
                  }
                  final line = await onClear();
                  if (!bc2.mounted) return; // 跨 async 只用这一个 context，且先验在场
                  Navigator.pop(bc2);
                  AppToast.show(bc2, line);
                },
                child: Text(armed ? '确认清空？' : '清空'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 一行：标题＋三态胶囊／来源路径＋打开时间／小注／（未转入才给）转入钮。
class _HistRow extends StatelessWidget {
  const _HistRow({required this.note, required this.onOpen, required this.onMove});

  final Note note;
  final VoidCallback onOpen;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = noteHistStateOf(note);
    final hint = noteHistHint(st);
    return InkWell(
      key: ValueKey('noh-row-${note.id}'),
      onTap: onOpen,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(noteHistTitle(note),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800))),
                const SizedBox(width: 6),
                _badge(scheme, st),
              ],
            ),
            const SizedBox(height: 3),
            Text(
                '${note.originPath.isEmpty ? '本机路径未记录' : note.originPath}'
                ' · ${noteHistWhen(note.openedAt ?? note.updatedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint,
                    key: ValueKey('noh-hint-${note.id}'),
                    style: TextStyle(fontSize: 9, color: scheme.error)),
              ),
            if (st != NoteHistState.moved)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: ValueKey('noh-move-${note.id}'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: onMove,
                    child: const Text('转入正式目录',
                        style:
                            TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 三态胶囊＝纯文字线性（零 emoji·〇B 色值棘轮零新增：只有「仅应用内」取 error 标红）。
  Widget _badge(ColorScheme scheme, NoteHistState st) {
    final warn = st == NoteHistState.app;
    final color = warn ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Text(noteHistLabel(st),
          style: TextStyle(
              fontSize: 8, height: 1.2, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
