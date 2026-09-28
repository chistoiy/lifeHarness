import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/providers.dart';
import '../../../../core/sync/cloud_clean_service.dart';
import '../../../../core/sync/diff_service.dart';
import '../../../../core/sync/remote_store.dart';
import '../../../../core/sync/service_config.dart';
import '../../../../core/sync/snapshot_service.dart';
import '../../../../core/sync/sync_ledger.dart';
import '../../../../core/sync/sync_orchestrator.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';

part 'sync_mini_widgets.dart';
part 'sync_service_edit_sheet.dart';
part 'sync_verify_sheet.dart';
part 'sync_diff_sheet.dart';
part 'sync_progress_sheet.dart';
part 'sync_throttle_sheet.dart';
part 'sync_cloud_clean_sheet.dart';

/// V1.41 Task 18 · /sync 弹层家族（原型 index-sync.html s-svc-edit /
/// s-svc-verify / s-diff / s-syncprog / s-throttle；s-backup 归 Task 10）。
///
/// 口径：
/// - S1 凭据只经 [CredentialVault] 写入，成功才落配置（R11）；删服务连带清
///   保险箱键 + 台账键（D1/D3 无孤儿）。
/// - S2 三态 = 连接通过 / 凭据错误 / 网络失败，文案随协议（WebDAV 提示应用
///   密码 · S3 提示子账户 AK/SK + 桶权限）；凭据缺失时本地预检直出，不发请求。
/// - S3 四态分组 + 一致组折叠计数 + 逐条勾选 + 合计行；仅云端行带「下载」
///   （下载到导出目录，**绝不自动导入**）。
/// - S4 订阅 [SyncOrchestrator.state]（current/done/total + 取消钮）。
/// - S6 档位写回当前 ServiceConfig、快照份数滚轮（T6 同源单列滚轮实现）、
///   仅Wi-Fi 开关存 prefs `sync_wifiOnly`（T19 消费）。
/// - 文案一律功能标签式，无教学句、无 emoji（UI 规范）。

/// 仅 Wi-Fi 自动同步开关的 prefs 键（本期只存值）。
const String kSyncWifiOnlyKey = 'sync_wifiOnly';
