# schema.dart — 数据库 schema 枢纽

- `schema.dart`（392 行）：`DbSchema` 门面类，全量别名 API 指向九个域库；外部一律经 `DbSchema.xxx` 取用，不直接 import 域库。
- `../schema/` 九域库（治理 G5 拆分，SQL 字面量原样留置）：`core` 核心表 · `read` 阅读 · `habit` 习惯 · `ledger` 记账 · `care` 呵护 · `days` 日子 · `items` 物品 · `goals` 目标 · `ai` AI 留痕。
- 迁移按版本整条分域（各域 migrations 键互斥）；`createStatements` 字面量留对应域类内。
- 等价性校验：`tools/dump_schema.dart`（由 `tools/gen_dump_schema.js` 生成）→ 快照 `tools/schema-dump-baseline.json`（v27 / 92 consts / 221 create / 26 版本 245 迁移）。**改 schema 前后都要跑它，快照逐字段全等才算纯移动。**
