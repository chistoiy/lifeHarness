# widgets/ — 同步弹层库入口（sync_sheets）

治理 G7d②：`sync_sheets.dart` 原 1,950 行按类整块外提为 part 库，入口 43 行
（15 import + 7 part + 家族文档 + `kSyncWifiOnlyKey`）。每段自带 State 类，setState 天然合法。

- `sync_mini_widgets.dart` 格式化小件 + `NumberWheel` 单列滚轮
- `sync_service_edit_sheet.dart` 服务配置编辑（凭据只经 CredentialVault 写入＝R11）
- `sync_verify_sheet.dart` 连接验证三态 · `sync_diff_sheet.dart` 差异半屏 · `sync_progress_sheet.dart` 进度半屏
- `sync_throttle_sheet.dart` 控流弹层（档位 + 快照份数 + 仅 Wi-Fi 开关）
- `sync_cloud_clean_sheet.dart` 云端孤儿附件清理（归档/彻底删除两段式）

调用面：`sync_page` / `sync_history_page` import 本库即可，公开符号经库入口导出、无需逐 part 引用。
mini 池＝sync_page 家族 5 件（按「谁 import 本库」选）。
