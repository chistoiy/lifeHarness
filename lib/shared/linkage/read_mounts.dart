import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/read/presentation/read_sheets.dart';
import '../../features/read/presentation/read_tab.dart';

// 记录页同库 part（journal_page_card.dart）的「当日阅读摘录」provider 取这三枚，
// 由本门面透出，journal_page.dart 不再直连 read feature（R1 零豁免）。
export '../../features/read/domain/book_quote.dart' show BookQuote;
export '../../features/read/presentation/read_providers.dart'
    show readRepositoryProvider, readTickProvider;

/// 记录页·阅读 tab 挂载点（shared/linkage 聚合装配 feature，R1 同 pomo_linkage 惯例）。
/// 记录页（journal feature）不直接 import 阅读模块。

/// 阅读工作台（今日卡 + 五图标入口 + 封面轨道 + 最近摘录 + 复习卡）。
Widget readWorkbench() => const ReadWorkbench();

/// 阅读 tab FAB ＝ 唯一摘录表单（默认书=在读最近那本 · §3.3）。
void readTabFabTap(BuildContext context, WidgetRef ref) =>
    showQuoteSheet(context, ref);
