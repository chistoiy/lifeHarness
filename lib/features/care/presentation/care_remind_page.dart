import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import 'care_kit.dart';
import 'care_notify.dart';
import 'care_providers.dart';

/// p-careRemind 呵护提醒（周期三类 / 宝宝 / 敏感数据保护；KV 落 care.rm.*）。
///
/// 红线 7：「母婴数据排除 WebDAV 同步（模块级）」＝care.syncExcluded（默认开）。
class CareRemindPage extends ConsumerWidget {
  const CareRemindPage({super.key});

  Future<void> _setKv(WidgetRef ref, String key, String value) async {
    await ref.read(careRepositoryProvider).setKv(key, value);
    careTouch(ref);
  }

  bool _b(Map<String, String> rm, String k, bool def) =>
      (rm[k] ?? (def ? 'true' : 'false')) == 'true';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('呵护提醒'),
            Text('周期 · 喂养 · 疫苗 · 隐私',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final rm = d.reminders;
          final lead = int.tryParse(rm['care.rm.mensLead'] ?? '2') ?? 2;
          final gap = rm['care.rm.feedGap'] ?? '3h';
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Head('🌸 周期提醒（三类）'),
                    _row(context, '月经来潮', _b(rm, 'care.rm.mens', true),
                        (v) => _setKv(ref, 'care.rm.mens', v ? 'true' : 'false')),
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (v, t) in const [
                            (0, '当天'),
                            (1, '提前1天'),
                            (2, '提前2天'),
                            (3, '提前3天'),
                          ])
                            CChip(
                              key: ValueKey('lead-$v'),
                              label: t,
                              dense: true,
                              selected: lead == v,
                              onTap: () => _setKv(ref, 'care.rm.mensLead', '$v'),
                            ),
                        ],
                      ),
                    ),
                    _row(context, '排卵日当天', _b(rm, 'care.rm.ovu', true),
                        (v) => _setKv(ref, 'care.rm.ovu', v ? 'true' : 'false'),
                        divider: true),
                    _row(context, '易孕期开始', _b(rm, 'care.rm.fertile', false),
                        (v) => _setKv(ref, 'care.rm.fertile', v ? 'true' : 'false'),
                        divider: true),
                    _row(context, '超 ±7 天波动温柔提醒', _b(rm, 'care.rm.wave', true),
                        (v) => _setKv(ref, 'care.rm.wave', v ? 'true' : 'false'),
                        divider: true),
                    const _Note(
                        '提醒遵守全局「免打扰」时段 · 预测日自动写入「重要日子」倒数（联动 L10）'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Head('👶 宝宝提醒'),
                    _row(context, '下次喂养间隔提醒', _b(rm, 'care.rm.feed', true),
                        (v) => _setKv(ref, 'care.rm.feed', v ? 'true' : 'false')),
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final t in const ['2.5h', '3h', '3.5h', '4h'])
                            CChip(
                              key: ValueKey('gap-$t'),
                              label: t,
                              dense: true,
                              selected: gap == t,
                              onTap: () => _setKv(ref, 'care.rm.feedGap', t),
                            ),
                        ],
                      ),
                    ),
                    _row(context, '睡眠计时结束温柔唤醒提示',
                        _b(rm, 'care.rm.sleepWake', true),
                        (v) => _setKv(ref, 'care.rm.sleepWake', v ? 'true' : 'false'),
                        divider: true),
                    _row(context, '疫苗接种提前 7 天', _b(rm, 'care.rm.vax', true),
                        (v) => _setKv(ref, 'care.rm.vax', v ? 'true' : 'false'),
                        divider: true),
                    _row(context, '儿保体检节点提醒', _b(rm, 'care.rm.checkup', false),
                        (v) async {
                      // V1.57 B 批：接真排程（节点表驱动 · 受免打扰顺延）。
                      await _setKv(ref, 'care.rm.checkup', v ? 'true' : 'false');
                      try {
                        await syncCareCheckup(ref.read(careRepositoryProvider),
                            dnd: ref
                                .read(settingsRepositoryProvider)
                                .load()
                                .notify
                                .dnd);
                      } catch (e) {
                        AppLog.add('儿保体检提醒重排失败：$e',
                            level: LhLevel.warn, src: '呵护');
                      }
                    }, divider: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Head('🔒 敏感数据保护'),
                    _row(context, '母婴数据排除 WebDAV 同步（模块级）', d.syncExcluded,
                        (v) async {
                      await ref.read(careRepositoryProvider).setSyncExcluded(v);
                      careTouch(ref);
                    }),
                    // V1.57 拍板 §十：「进入模块需二次验证」已否决整行摘除
                    // （不遮挡、不验证、不做伪装页；历史键由 reminderKvs 读到即清）。
                    _row(context, '本地备份包含本模块', _b(rm, 'care.rm.backup', true),
                        (v) => _setKv(ref, 'care.rm.backup', v ? 'true' : 'false'),
                        divider: true),
                    const _Note('周期 / 喂养数据属敏感类别，默认仅存本机 · 设置页总开关同款联动'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, String label, bool on, ValueChanged<bool> onChanged,
      {bool divider = false, String? vchip}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (divider)
          Divider(color: scheme.outlineVariant.withValues(alpha: .5), height: 1),
        Padding(
          padding: EdgeInsets.symmetric(vertical: divider ? 10 : 8),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                      style: const TextStyle(fontSize: 12),
                      children: [
                        TextSpan(text: label),
                        if (vchip != null) ...[
                          const TextSpan(text: '  '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(vchip,
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurfaceVariant)),
                            ),
                          ),
                        ],
                      ]),
                ),
              ),
              CToggle(
                  key: ValueKey('rm-$label'),
                  label: label,
                  on: on,
                  onChanged: onChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      );
}
