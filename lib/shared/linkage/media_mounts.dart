import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/media/presentation/media_add_sheet.dart';
import '../../features/media/presentation/media_workbench.dart';

/// 记录页·影音游 tab 挂载点（shared/linkage 聚合装配 feature，R1 与 read_mounts 同法）。
/// 记录页（journal feature）不直接 import 影音游模块。

/// 影音游工作台（影音架入口＋四类在册计数＋最近四条俯瞰）。
Widget mediaWorkbench() => const MediaWorkbench();

/// 影音游 tab FAB ＝ 新条目录入（原型 S-09：FAB 随记录页 tab 语境变，四类分派四套字段）。
void mediaTabFabTap(BuildContext context, WidgetRef ref) =>
    showMediaAddSheet(context, ref);
