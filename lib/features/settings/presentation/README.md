# settings/presentation — 设置与系统页入口

- `settings_page.dart` 设置主页 · `settings_routes.dart` 设置二级路由注册表（组合根之外路由下沉的模块侧入口）。
- **AI 增强页族**（治理 G7d⑤：主文件 466 行 + 五同库 part）：
  - `ai_page.dart` 留 AiSettingsPage(State) + `kAiCapRows` 能力矩阵 + `aiProtocolLabel`
    ——`kAiCapRows` 是本目录的 R8 现场解析锚，**不得挪出主文件**；
  - `ai_page_usage`（使用记录 + token 台账）· `ai_page_verify`（连通性验证页）·
    `ai_page_prompts`（提示词管理两页）· `ai_page_form`（服务商表单弹层）· `ai_page_widgets`（行/按钮/卡片壳）。
  - `test/architecture_test.dart` 的 R7/R8 按「本目录 `ai_` 前缀族」豁免（`aiPageFamily`），族外文件直取
    `aiServiceProvider` 仍然红。
- 其余系统页：`log_page`（日志管理 V1.43）· `ai_usage_page` · `recmg_page` · `notify_settings_page` ·
  `media_clean_page` · `sync_backup_sheet` · `sync_history_page`。
- `widgets/`＝同步弹层库（见其 README）。
