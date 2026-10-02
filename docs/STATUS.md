# STATUS（唯一状态源 · 最后更新 2026-10-02 治理二轮）

> 状态变化只改本文件；历史时点沉 `docs/交接文档.md` 文末变更日志。本文不钉具体 HEAD sha（防漂移），看 `git log --oneline -3`。

- 分支 `feat/m0-skeleton`；远端进度：**链上至 `32f3470` 双端对齐；本地一批提交未推**（批二 R3-3 `7cb6b81` → 拍板 `7e566c0` → 收尾 `9689eb5` → 通鉴画像 `7796ced` → V5 判废登记 `1939de9` → 批一 LH-F01 及其文档），推送/发版待产品点头。
- 最新预发布仍为 **`v0.2.10-underline`**（钉版 `f04e248`＝`0.2.10+4047`·三包双端挂齐·Gitee 配额腾挪工装 `tools/gitee_free_quota.py`）· DB `DbSchema.version=34`（批二**零迁移**）· 全量门禁基线 **1786 绿**（未重跑）· 批二批内 **77 绿**（refine 20＋ui 9＋panel 23＋dao/arch/catch/size 回归）· 批一批内 **102 绿**（新增 `reader_f01_font_test` 11 例＋pager/r32/s2t/b4/preload/open_with/theme_tokens/arch/size 回归），两批各四刀变异全红自证。
- 复测包：**6047 已装 ea028260**（覆盖安装·数据未清·`versionName 0.2.10`）；真机轮4① 划线复验 **①②③ 过**（只涂所选字／重进仍精确／书摘行落库含章页色类，④旧整段行未单验＝用例已覆盖），取证截图落仓库外 `tmp/device/`；下一编号 6048。
- 下一站：**批一 LH-F01 已交付（V5 判废后写权解锁，规格与拍板齐）**→ 三件待办按优先级：① 出 **6048 复测包**装机看衬线正文真机观感（并验《資治通鑑》夹注括号缺字是否随字族链自然消解）；② 批三 原书样式保真＝先答预研 §5.4 **四项拍板**（竖排跟不跟/专名线做不做/开关粒度/`.comment` 蓝与 R3-2① 优先级）再进原型门；③ 中心页工单 §2 三项拍板（AI 段的书归属）。批一遗留＝规范〇A body 角色的「日记·笔记·书摘·X-Ray 摘录卡」四个正文面未接（不在 §1 落点表，需逐屏改样式）。
- 并行互斥面（只读不写不提交不回退）：`prototype/index-health.html` 与健康线、`docs/acceptance_20261001_xray/`、`docs/acceptance_20261002_xray2/`；另有三份**未入库且非 V5** 的当日文档待产品定去留（《阅读模块开场白-20261002》《阅读模块开发省token策略-20261002》《项目拆分重构调研报告-20261002》）。V5 家族（prototype 下 reader / reader-v4 / reader-v5 三目录、书架派生副本 index-bookshelf-reader.html、《阅读模块V5视觉设计说明-20261002》）已移出工作区 → `D:/dev_workplace/flutter_te/tempWork/attic-v5-20261003/`（从未入库＝git 无历史，要硬删删这个目录）。治理后口径：文档路由看 INDEX，状态只看本文，死链体检 `python tools/doclint.py`（批次收口随跑）。
- 环境/禁令/忽略清单/工单生命周期：一律看 `AGENTS.md`；文档地图看 `docs/INDEX.md`。
