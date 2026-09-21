import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/widgets/ui_kit.dart';

/// V1.29轮3①+轮6③ 记录管理二级页（原型 p-sub-recmg）：
/// 按 日记/笔记/阅读/影音游 四段 + 通用 分组收纳记录类设置。
/// 真实项：笔记版本恢复方式（settings 持久化）；其余为规划占位。
class RecmgSettingsPage extends ConsumerWidget {
  const RecmgSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restore = ref.watch(settingsControllerProvider).noteRestoreMode;
    final latex = ref.watch(settingsControllerProvider).noteLatex;
    return Scaffold(
      appBar: AppBar(title: const Text('记录管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Label('📔 日记'),
          _Card(children: [
            _Row(
                title: '默认新建模板',
                trailing: '纯文本',
                onTap: () => _soon(context, '日记默认模板')),
            _Row(
                title: '连续记录提醒',
                trailing: '断签 2 天时提醒',
                last: true,
                onTap: () => _soon(context, '连续记录提醒')),
          ]),
          const _Label('📝 笔记'),
          _Card(children: [
            _Row(
                keyName: 'nr-mode',
                title: '🕘 版本恢复方式',
                trailing: restore == 'replace' ? '直接替换正文' : '新增为副本',
                onTap: () async {
                  await ref.read(settingsControllerProvider.notifier).
                      setNoteRestoreMode(
                          restore == 'replace' ? 'copy' : 'replace');
                  if (context.mounted) {
                    AppToast.show(
                        context,
                        ref.read(settingsControllerProvider).noteRestoreMode ==
                                'replace'
                            ? '恢复=直接替换当前正文（替换前自动留快照）'
                            : '恢复=新增一条副本笔记，当前正文不动');
                  }
                }),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                  '恢复快照时：直接替换当前正文（替换前自动留快照，可反悔）⇄ 新增为一条副本笔记',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ),
            _Row(
                title: '自动快照节奏',
                trailing: '停输 30 秒 / 每 500 字',
                onTap: () => _soon(context, '自动快照节奏')),
            // V1.29轮9k：LaTeX 公式渲染开关（默认关·预览按原文显示 $..$/$$..$$）。
            _SwitchRow(
                keyName: 'latex-tgl',
                title: 'LaTeX 公式渲染',
                value: latex,
                onChanged: (v) async {
                  await ref
                      .read(settingsControllerProvider.notifier)
                      .setNoteLatex(v);
                  if (context.mounted) {
                    AppToast.show(
                        context,
                        v
                            ? '已开启 LaTeX 渲染：\$..\$ 与 \$\$..\$\$ 显示为公式'
                            : '已关闭 LaTeX 渲染：公式按原文显示');
                  }
                }),
            _Row(
                title: '🗂 文件夹管理',
                trailing: '记录 › 笔记 › 📂',
                last: true,
                onTap: () => AppToast.show(
                    context, '在 记录 › 笔记 点 📂 打开树侧栏管理（增删改/嵌套）')),
          ]),
          const _Label('📚 阅读'),
          _Card(children: [
            _Row(
                title: '默认进度方式',
                trailing: '页数',
                onTap: () => _soon(context, '阅读默认进度方式')),
            _Row(
                title: '阅读计时',
                trailing: '开始阅读时询问',
                last: true,
                onTap: () => _soon(context, '阅读计时询问')),
          ]),
          const _Label('🎬 影音游'),
          _Card(children: [
            _Row(
                title: '默认进度方式',
                trailing: '集数',
                last: true,
                onTap: () => _soon(context, '影音游默认进度方式')),
          ]),
          const _Label('⚙️ 通用'),
          _Card(children: [
            _Row(
                keyName: 'trash-days',
                title: '回收站自动清理',
                trailing: '30 天',
                last: true,
                onTap: () => _soon(context, '回收站自动清理期限')),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text('日记 / 笔记 / 阅读 / 影音游 删除的内容统一进各模块回收站，按期限自动彻底删除',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('$what · 规划 V1.x'),
          duration: const Duration(milliseconds: 1500)));
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(children: children),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(
      {this.keyName, required this.title, required this.value, required this.onChanged});

  final String? keyName;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x14000000)))),
        child: Row(
          children: [
            Expanded(
                child: Text(title,
                    style:
                        const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            Switch(
              key: keyName == null ? null : ValueKey<String>(keyName!),
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(
      {this.keyName,
      required this.title,
      required this.trailing,
      this.last = false,
      required this.onTap});

  final String? keyName;
  final String title;
  final String trailing;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        key: keyName == null ? null : ValueKey<String>(keyName!),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: Color(0x14000000))),
          ),
          child: Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700))),
              Text(trailing,
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
              const Text(' ›', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}
