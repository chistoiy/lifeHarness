import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema/nfc.dart' show NfcTargetKind;
import '../../../core/platform/desktop_actions.dart';
import '../../../shared/linkage/nfc_mounts.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/nfc_repo.dart';
import '../domain/nfc_card.dart';

/// 新建/编辑卡片弹层（原型 `sheetNfcEdit` · LH-S41 · 冻结档 §4.2）。
///
/// 三态标题：新建卡片／编辑卡片／绑定这张卡（绑定态多一行卡号提示 · B8）。
///
/// 字段顺序（§4.2 逐条）：① 卡号提示行（仅绑定态）② 名称输入 ③ **目标三区块单选** ④ 主钮保存。
/// **目标三区块互斥单选**（C28·扁平，**不嵌套二级弹层**）：快捷动作 7 枚／计时分类 N 枚／
/// 阅读书目 N 枚；区块内无数据 → 整块隐藏 ＋ 一行灰字（不显示空 chips）。
///
/// 返回值：`true`＝有落库（调用方据此刷新列表），`null`＝取消。
Future<bool?> showNfcEditSheet(
  BuildContext context, {
  NfcCard? card,
  String? bindTagKey,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NfcEditSheet(card: card, bindTagKey: bindTagKey),
  );
}

class _NfcEditSheet extends StatefulWidget {
  const _NfcEditSheet({this.card, this.bindTagKey});

  final NfcCard? card;

  /// 绑定态预填的卡号提示（B8：贴到未绑定的卡 → 自动打开绑定表单，预填卡号）。
  final String? bindTagKey;

  @override
  State<_NfcEditSheet> createState() => _NfcEditSheetState();
}

class _NfcEditSheetState extends State<_NfcEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.card?.name ?? '');
  late final NfcRepo _repo = NfcRepo(AppDatabase.instance.db);

  // 三区块互斥单选：一时刻只有一个 (kind, ref) 被选中。
  late String _kind = widget.card?.targetKind ?? NfcTargetKind.nav;
  late String _ref = widget.card?.targetRef ?? '';

  bool _saving = false;
  bool _nameError = false;
  List<NfcCategoryOption> _cats = const [];
  List<NfcBookOption> _books = const [];

  bool get _isBinding => widget.bindTagKey != null && widget.bindTagKey!.isNotEmpty;
  bool get _isEditing => widget.card != null;

  String get _title {
    if (_isBinding) return '绑定这张卡';
    return _isEditing ? '编辑卡片' : '新建卡片';
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    // 目标选择器的两区块数据**一律经 linkage 出口**（守 R1：本 feature 不 import
    // features/calendar|read）。空列表＝该区块整块隐藏（C28/§4.2）。
    final cats = await nfcCategoryOptions();
    final books = await nfcBookOptions();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _books = books;
      // 新建态默认选中第一区块第一项（§4.2）。
      if (!_isEditing && _ref.isEmpty) {
        if (cats.isNotEmpty && _kind == NfcTargetKind.timerCat) {
          _ref = '${cats.first.id}';
        }
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      // B13：保存被拒，框下一行红字「起个名字」，层保持打开（不做静默默认名）。
      setState(() => _nameError = true);
      return;
    }
    setState(() {
      _nameError = false;
      _saving = true;
    });
    try {
      if (_isEditing) {
        // 改名/换目标**不重写标签**（C3）⇒ 不碰 written_at / tag_key。
        await _repo.update(widget.card!.id,
            name: name, targetKind: _kind, targetRef: _ref);
      } else {
        await _repo.create(name: name, targetKind: _kind, targetRef: _ref);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // catch-ok: 本地写库失败已在下面给用户一句「保存失败 · 请重试」；错误本身
      // （表结构/磁盘满）属开发期问题，无可执行的运行时动作，不进日志面。
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '保存失败 · 请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nameLen = _name.text.characters.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34, height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(_title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),

              // ① 卡号提示行（**仅绑定态** · B8）
              if (_isBinding)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('这张卡还没绑定 · 卡号 ${widget.bindTagKey}',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ),

              // ② 名称输入（必填 · 硬限 12 字 B14）
              TextField(
                key: const ValueKey('nfc-name'),
                controller: _name,
                maxLength: kNfcNameMaxLen, // B14：超出不接收
                inputFormatters: [LengthLimitingTextInputFormatter(kNfcNameMaxLen)],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: '名称',
                  hintText: '给这张卡起个名字',
                  counterText: '$nameLen/$kNfcNameMaxLen',
                  errorText: _nameError ? '起个名字' : null,
                ),
              ),
              const SizedBox(height: 12),

              // ③ 目标三区块（C28·扁平互斥单选·无二级弹层）
              _sectionTitle('快捷动作', scheme),
              _chips(
                kDesktopActions
                    .map((a) => _ChipOpt(NfcTargetKind.nav, a.id, a.label))
                    .toList(),
              ),
              if (_cats.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('计时分类', scheme),
                _chips([
                  for (final c in _cats)
                    // B23：多级分类显示父级路径「工作 › 开会」；同名按 id 区分。
                    _ChipOpt(NfcTargetKind.timerCat, '${c.id}',
                        c.parentId == null ? c.name : c.path),
                ]),
              ] else ...[
                const SizedBox(height: 16),
                _sectionTitle('计时分类', scheme),
                _grey('还没有分类'),
              ],
              if (_books.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('阅读书目', scheme),
                _chips([
                  for (final b in _books)
                    _ChipOpt(NfcTargetKind.readBook, b.id,
                        b.title.isEmpty ? b.id : '《${b.title}》'),
                ]),
              ] else ...[
                const SizedBox(height: 16),
                _sectionTitle('阅读书目', scheme),
                _grey('书架里还没有书'),
              ],

              // ④ 编辑态额外两行（§4.2：目标三区块之下、主钮之上）
              if (_isEditing) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: scheme.outlineVariant),
                ListTile(
                  key: const ValueKey('nfc-edit-write'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('写入卡片', style: TextStyle(fontSize: 13)),
                  trailing: Text(
                    widget.card!.isReadOnlyTag
                        ? '只读卡'
                        : (widget.card!.isWritten ? '已写入' : '未写入'),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                  onTap: () {
                    // 写卡流程属批2；批1 只给一句明说，不假装能写。
                    AppToast.show(context, '写入卡片将在下一批开放');
                  },
                ),
                ListTile(
                  key: const ValueKey('nfc-edit-del'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('删除卡片',
                      style: TextStyle(fontSize: 13, color: Color(0xFFF43F5E))),
                  onTap: () => Navigator.pop(context, true),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('nfc-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String s, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
      );

  Widget _grey(String s) => Text(s,
      style: TextStyle(
          fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant));

  /// 三区块共用的 chips 网格（**区块之间互斥**＝共用 `_kind`+`_ref` 一份选中态）。
  Widget _chips(List<_ChipOpt> opts) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            PillChip(
              key: ValueKey<String>('nfc-target-${o.kind}-${o.ref}'),
              label: o.label,
              selected: _kind == o.kind && _ref == o.ref,
              onTap: () => setState(() {
                _kind = o.kind;
                _ref = o.ref;
              }),
            ),
        ],
      );
}

class _ChipOpt {
  const _ChipOpt(this.kind, this.ref, this.label);
  final String kind;
  final String ref;
  final String label;
}