import 'package:flutter/material.dart';

import '../../core/platform/module_tiles.dart';

/// 「添加模块瓦片（1×1）」的模块选择层（批C · 2026-10-18 真机报障后补）。
///
/// 产品原话：「app 内没有添加这个 1×1 的小组件能力，需要修改下」——读数四枚与打卡枚
/// 在设置页各有入口，瓦片没有。本层就是那个入口的选择步：**一枚瓦片＝一个模块**，
/// 没有二级参数，所以只有一个扁平列表，不需要打卡那套五段选择器。
///
/// 只列 [kImplementedModuleTiles]（真能落桌面的那些）：列了没实现的，用户点「添加」
/// 系统必然不出弹窗，按引导去小部件库也找不到。
///
/// 返回 `null`＝用户取消（什么都不落，与打卡枚「取消即不落桌面」同口径）。
Future<ModuleTile?> showModuleTilePicker(BuildContext context) {
  return showModalBottomSheet<ModuleTile>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final tiles = kImplementedModuleTiles;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('添加模块瓦片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                '每个模块一枚 1×1 瓦片，放到桌面后点一下直达该模块页——不用先打开 App 再找。',
                style: TextStyle(
                    fontSize: 12.5, height: 1.6, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: tiles.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1, color: scheme.outlineVariant.withValues(alpha: .5)),
                  itemBuilder: (_, i) {
                    final t = tiles[i];
                    return InkWell(
                      key: ValueKey<String>('wg-tile-pick-${t.id}'),
                      onTap: () => Navigator.of(ctx).pop(t),
                      child: SizedBox(
                        height: 52,
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                color: scheme.primary.withValues(alpha: .12),
                              ),
                              child: Icon(t.icon, size: 19, color: scheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(t.label,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Icon(Icons.chevron_right,
                                size: 18, color: scheme.outline),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
