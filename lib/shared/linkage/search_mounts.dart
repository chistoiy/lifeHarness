import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/journal/presentation/note_search.dart';

/// 全局搜索唯一出口（UIUX批 2026-10-12）：笔记＋日记双源搜索半屏
/// （note_search 的 showNoteSearchSheet，V1.68 起日记已纳入搜索范围）。
///
/// 动机＝AppBar 的「全局搜索 · 即将开放」僵尸钮：此前仪表盘点它只弹 toast，
/// 而搜索基建（含日记）早已在。仪表盘等共享面只 import 本文件
/// （架构守护 R1：features 不直连其他 feature，挂载件走 shared/linkage）。
/// 待办/日历/收集箱三页同款僵尸钮同口径接此出口（另行批次跟进）。
Future<void> showGlobalSearch(BuildContext context, WidgetRef ref) =>
    showNoteSearchSheet(context, ref);
