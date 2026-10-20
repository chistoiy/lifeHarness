import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// 我的页「编辑资料」半屏弹层（R14-12 · 原型 sheetProfile）。
///
/// 口径：昵称必填（≤12 字，空值就地报错不关闭弹层）、签名可空（≤20 字）；
/// 保存只写设置项 KV（本地模式无账号，不建表），头像首字 / 页面副标题 /
/// 「今天」页问候语三处随同一份数据联动。
Future<void> showProfileEditSheet(BuildContext context, WidgetRef ref) {
  final s = ref.read(settingsControllerProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProfileSheet(nick: s.profileNick, bio: s.profileBio),
  );
}

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({required this.nick, required this.bio});
  final String nick;
  final String bio;

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late final TextEditingController _nick = TextEditingController(text: widget.nick);
  late final TextEditingController _bio = TextEditingController(text: widget.bio);
  String? _nickErr;

  @override
  void dispose() {
    _nick.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _nick.text.trim();
    if (v.isEmpty) {
      // 就地报错，不弹提示条也不关弹层（原型同款）。
      setState(() => _nickErr = '昵称不能为空');
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setProfile(nick: v, bio: _bio.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  InputDecoration _box(BuildContext context, String label) => InputDecoration(
        labelText: label,
        hintText: label == '昵称' ? '显示在「我的」与今天页问候语' : '出现在顶栏副标题',
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none),
      );
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Flutter 3.38 起 showModalBottomSheet 不再随键盘抬升，含输入框要自理 viewInsets。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('编辑资料',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('pf-nick'),
                controller: _nick,
                maxLength: 12,
                // 就地报错：错误文案走框架 errorText，不再叠提示条。
                decoration: _box(context, '昵称').copyWith(errorText: _nickErr),
              ),
              TextField(
                key: const ValueKey('pf-bio'),
                controller: _bio,
                maxLength: 20,
                decoration: _box(context, '一句话签名'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('pf-save'),
                      onPressed: _save,
                      child: const Text('保存'),
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
}
