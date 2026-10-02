# STATUS（唯一状态源 · 最后更新 2026-10-02 治理二轮）

> 状态变化只改本文件；历史时点沉 `docs/交接文档.md` 文末变更日志。本文不钉具体 HEAD sha（防漂移），看 `git log --oneline -3`。

- 分支 `feat/m0-skeleton`；远端进度：治理二轮+守护升级+方案库沉淀记录**已双端推送对齐**（Gitee https / GitHub ssh-on-443，2026-10-02 用户授权）；本地无未推提交链。
- 最新预发布 **`v0.2.9-reader-r3`**（钉版 `79473f5`＝`0.2.9+4046`）· DB `DbSchema.version=34` · 全量门禁基线 **1786 绿 / 0 红**（治理二轮零代码改动，基线不变）。
- 复测包 worktree：`D:/dev_workplace/flutter_te/lh-r31` 复用（`git reset --hard <自己的提交>`）；出包 `--release --target-platform android-arm64 --build-number=60xx`。**6047 已出**（钉 `0a0e300`·aapt 核过 versionCode 6047/0.2.9/INTERNET 在 main 清单），真机 ea028260 装机时掉线**待重连后装**；下一个编号 6048。
- 下一站：**真机轮4 两条拍板（2026-10-02）→ ① 划线精确化批已交付并双端推送 `0a0e300`（批内 29+52+74 绿·复测包 6047 已出待装机复验）；② 顺延批＝原书样式保真（F01 工单 §3 完整档 CSS 全解析，原型先行未过门不许实现，规格 `docs/handoff/交棒话术-20261002-下一版实现批-F01-批C-R32精修.md`）**。F01 批次一/二/三与本批②同动 `lib/features/read/**` 按工单 §4 串行；V5 视觉线写权归产品裁定。治理后口径：文档路由看 INDEX，状态只看本文，死链体检 `python tools/doclint.py`（批次收口随跑）。
- 并行互斥面（只读不写不提交不回退）：`docs/阅读模块V5视觉设计说明-20261002.md`、`docs/阅读模块开场白-20261002.md`、`docs/阅读模块开发省token策略-20261002.md`、`docs/项目拆分重构调研报告-20261002.md`、`prototype/reader-v4|v5|reader/`、`prototype/index-bookshelf-reader.html`、`prototype/index-health.html`、`docs/acceptance_20261001_xray/`、`docs/acceptance_20261002_xray2/`。与本批同打 `lib/features/read/**`——V5 线写权先后归用户裁定。
- 环境/禁令/忽略清单/工单生命周期：一律看 `AGENTS.md`；文档地图看 `docs/INDEX.md`。
