# STATUS（唯一状态源 · 最后更新 2026-10-02 治理二轮）

> 状态变化只改本文件；历史时点沉 `docs/交接文档.md` 文末变更日志。本文不钉具体 HEAD sha（防漂移），看 `git log --oneline -3`。

- 分支 `feat/m0-skeleton`；远端进度：**链上至 `32f3470` 双端对齐；本地另有 3 提交未推**（批二 R3-3 明细 `7cb6b81` + F01 §1 拍板 `7e566c0` + 本批真机/文档收口）。
- 最新预发布仍为 **`v0.2.10-underline`**（钉版 `f04e248`＝`0.2.10+4047`·三包双端挂齐·Gitee 配额腾挪工装 `tools/gitee_free_quota.py`）· DB `DbSchema.version=34`（批二**零迁移**）· 全量门禁基线 **1786 绿**（未重跑）· 批二批内 **77 绿**（refine 20＋ui 9＋panel 23＋dao/arch/catch/size 回归），变异四刀全红自证。
- 复测包：**6047 已装 ea028260**（覆盖安装·数据未清·`versionName 0.2.10`）；真机轮4① 划线复验 **①②③ 过**（只涂所选字／重进仍精确／书摘行落库含章页色类，④旧整段行未单验＝用例已覆盖），取证截图落仓库外 `tmp/device/`；下一编号 6048。
- 下一站：**V5 视觉线 2026-10-03 由产品判废并出仓 → `lib/features/read/**` 写权解锁 → 批一 LH-F01 字体角色落到 Flutter**（规格与拍板已齐：角色链为默认、主题 `--app-font` 整档覆盖；工单 F01 §1 五处落点＋两条补测）。批三 原书样式保真＝先答预研 §5.4 四项拍板再进原型门（通鉴样包画像缺口已闭合：五层 class 上色/命名色/rem/webkit logical margins/竖排/67 万 span 裁剪定档）。不撞面可开工项＝`docs/handoff/交棒话术-20261003-XRay中心三段同页.md`（先要 §2 三项拍板：AI 段的书归属）。
- 并行互斥面（只读不写不提交不回退）：`prototype/index-health.html` 与健康线、`docs/acceptance_20261001_xray/`、`docs/acceptance_20261002_xray2/`；另有三份**未入库且非 V5** 的当日文档待产品定去留（《阅读模块开场白-20261002》《阅读模块开发省token策略-20261002》《项目拆分重构调研报告-20261002》）。V5 家族（prototype 下 reader / reader-v4 / reader-v5 三目录、书架派生副本 index-bookshelf-reader.html、《阅读模块V5视觉设计说明-20261002》）已移出工作区 → `D:/dev_workplace/flutter_te/tempWork/attic-v5-20261003/`（从未入库＝git 无历史，要硬删删这个目录）。治理后口径：文档路由看 INDEX，状态只看本文，死链体检 `python tools/doclint.py`（批次收口随跑）。
- 环境/禁令/忽略清单/工单生命周期：一律看 `AGENTS.md`；文档地图看 `docs/INDEX.md`。
