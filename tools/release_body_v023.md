# 预发布 v0.2.3-v158-cut（0.2.3+4035 · 数据库 v30）

发布日期：2026-09-30 ｜ 分支：`feat/m0-skeleton` ｜ 出包提交：`fff610d` ｜ 上一版：v0.2.2-v157-gap

本版主体是 **V1.58 小工具合集（模块 14）整模块下架**（产品负责人拍板「小工具功能全部移除掉，模块价值太低」，
批0~批3 与验收轮2~轮5 的交付一并作废），另含反馈轮5 共享面入口去重、V1.57 收口与两批治理修正。

> ⚠️ **本版含 DB v29→v30 破坏性迁移**：`kit_usage / kit_layout / kit_tool_data / kit_plugin` 四表被 `DROP`，
> 小工具的足迹、收藏编排、工具数据、插件登记**升级后不可恢复**（拍板＝彻底清理）。
> 老版本包（≤0.2.2）装到本版后再降回旧包，旧包也读不到那批表以外的新数据，请按需保留备份。
> 迁移带 `IF EXISTS` 且幂等，新装库重跑不报错；`database_schema_test` 钉了「删表不波及他表 + 索引归零 + 幂等」三条。

## 一、V1.58 小工具整模块下架（`acdcc29` · `4578670`）

- **删除**：`lib/features/kits/**` 35 文件（首页控制盘 / 四弹层 / 11 件工具屏 / 域层 / 仓储 / 路由）、
  只为其服务的 `lib/core/ai/ai_verify_channel.dart`（批3e 新建的 R7 通道，全站唯一消费者就是 kit_aiapi）、
  `lib/core/database/schema/kit.dart` 与 `test/kit_*` 17 个用例文件。
- **摘线**：路由去 `kitShellRoutes/kitPageRoutes`；底栏栏目池去 `kits` 项（自动少一栏）；
  全部功能宫格去「小工具」枚（15→14）；`UserSettings` 摘 `KitSettings` 类与 `kit` 字段六处，
  `SettingsRepository` 删 `_kKit` 读写并在 `load()` 里**读到即清**历史键 `lh.kit`（照 `care.rm.lock` 先例），
  `SettingsController` 删 `setKit`。
- **原型**：`prototype/index.html` 摘 `p-tools` / `p-toolDetail` 两屏、`sheetPlugin` 弹层、AI 增强页借道按钮、
  `TOOLS/TOOL_CATS/PLUGINS` 等 108 行 JS 段与 `NAV_MODS/ICONS/TITLES/D.grid` 的对应项；
  宫格「AI 验证」枚改指 `p-sub-ai`（实现侧 `/settings/ai/verify` 保留）；专版 `index-kits.html` 移入 `prototype/archive/`。
  回归工装 `tools/kits/r6check.js` 12 断言全绿（符号与 DOM 归零 · 栏目池无「工具」 · 宫格 14 枚 · 15 屏无悬空引用）。
- **真机复验**（该会话已做）：6034 同版覆盖装 · 冷启动无崩溃 · `libapp.so` 里小工具符号归零。

## 二、反馈轮5 共享面（`4458071` · `391edde`）

- 「我的」页小工具入口行摘除；全部功能宫格摘「日记 / 笔记」两枚（与记录页重复的入口去重）。
- 宫格「阅读」带段深链 `/journal?tab=book`，进记录页自动切到阅读段；小工具轮盘「结果写日记」同类缺陷回扫，
  改带段参 `?tab=diary`。

## 三、V1.57 收口与两批治理修正（`2dc771c` · `954fbef` · `79a3e24` · `5e7cf39`）

- **V1.57 缺口盘点批 A~E** 的交付与发版文档回灌（上一版 `v0.2.2-v157-gap` 已挂三包，功能面不变）：
  分享长图公共通道 / 通知排程三枚接真 / 时间账本分类下钻 / 同步严格校验真门控 / 待办垃圾箱（DB v29）。
- **catch 守护归位**：V1.57 D 批自己在 `core/sync/snapshot_service.dart` 新增的读失败兜底 catch 补 `catch-ok:` 说明；
  `core/settings/user_settings.dart` 登记数随 V1.58 删码按实收紧 2→1。`catch_log_guard` 现全绿。
- **体积预算治理**：`todo_edit_sheet.dart`（1236 行·超登记值 1231）按计划书 2.2 第三条路线
  把新建/编辑表单整块 809 行外提为 part 文件 `widgets/todo_add_sheet.dart`，宿主留 430 行；
  **纯移动零行为改动**（`g7d_puremove_check.js --toplevel` 取证 806 行逐行全等），
  并**删掉该文件在 `size_budget_test.dart` 的登记项**，归还「>1200 即红」默认面。
  配套把 `todo_remind_1min_test.dart` 的源码级文案锚点改成「扫整个库」（宿主 + `part of` 分片），
  否则每次外提都会把锚点扫成假红。新增目录卡 `widgets/README.md`。

## 四、测试与门禁

- 本版收口跑 `bash tools/run_gate.sh` 全量（结果与用例数见《交接文档》同日期行）。
- V1.57 交付面回归池 47 绿（`todo_test` / `todo_page_test` / `todo_trash_page_test` / `todo_remind_1min_test` /
  `todo_insights_test` / `ai_wire_todo_test` / `size_budget_test`），四守护（size_budget · catch_log_guard ·
  architecture · l2_log_coverage）全绿；`flutter analyze` 零新增。
- **两条门禁红灯至此全部清零**（此前归属：catch 面＝kits 写区与 `core/ai`，size 面＝`32324b2` 遗留）。

## 五、真机验收重点（本版新面）

1. **升级不炸库**：从 0.2.2 包直接覆盖装本版 → 冷启动日志页应出现 `数据库打开：目标版本 30`，
   且既有待办/记账/阅读/呵护数据全在（只 DROP `kit_*` 四表）。
2. **入口归零**：底栏无「小工具」栏目；全部功能宫格 14 枚且无「小工具」；「我的」页无小工具行；
   「AI 验证」枚进的是 AI 增强页而不是废弃的工具屏。
3. **深链带段**：宫格点「阅读」→ 记录页自动落在阅读段；习惯轮盘「结果写日记」→ 记录页自动落在日记段。
4. **V1.57 四条复验**（本版仍成立）：垃圾箱端到端 / 回收站期限档位 force-stop 后仍是所选档 /
   冷启动 `垃圾箱自动清理：删除 N 条 · 保留期 …` key 行 / 分享长图提示条回显真实路径。

## 六、包体与安装

- 三包 release split-per-abi，versionName `0.2.3`；versionCode 按 ABI 分档（基线 4035 → `6035` / `5035` / `8035`），
  minSdk 26 · compileSdk 36，main 清单含 `INTERNET`（出包后 aapt 逐包复验）。
- 同版覆盖装即可（`install -r` 保数据）；**但本版含不可逆 DROP 迁移**，需要留档小工具历史数据的请先做本地备份再升。

## 七、已知延后项（勿当 bug 报）

记账「添加图片附件」、习惯「已导出 x.json（模拟）」、笔记/日记的图片分享卡、影音游模块、
健康管理 V1.48.1、X-Ray 全书索引（产品定本期不做；其迁移号已随 V1.58 顺延为 **自 v31 起**）。
