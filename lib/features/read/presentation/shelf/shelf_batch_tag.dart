part of 'shelf_page.dart';

// 治理G7d1a：批量加标签弹层自 shelf_page 尾随块整块外提（行为零改动）。
// 自持 controller，避免 pop 动画期间用到已 dispose 的控制器。
/// 批量加标签弹层（自持 controller，避免 pop 动画期间用到已 dispose 的控制器）。
class _BatchTagSheet extends StatefulWidget {
  const _BatchTagSheet({required this.count, required this.tags});
  final int count;
  final List<String> tags;

  @override
  State<_BatchTagSheet> createState() => _BatchTagSheetState();
}

class _BatchTagSheetState extends State<_BatchTagSheet> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _pick(String t) => Navigator.of(context).pop(t);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '为 ${widget.count} 本加标签',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in widget.tags)
                    GestureDetector(
                      key: ValueKey('bat-tag-pick-$t'),
                      onTap: () => _pick(t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: cs.surfaceContainerHighest,
                        ),
                        child: Text(
                          '#$t',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('bat-tag-new'),
                controller: _ctl,
                onSubmitted: (v) => _pick(v.trim()),
                decoration: InputDecoration(
                  labelText: '新标签',
                  labelStyle: const TextStyle(fontSize: 12),
                  isDense: true,
                  suffixIcon: IconButton(
                    key: const ValueKey('bat-tag-ok'),
                    icon: const Icon(BsIcons.add, size: 18),
                    onPressed: () => _pick(_ctl.text.trim()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
