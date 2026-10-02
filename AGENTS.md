# LifeHarness — Agent 指南

Flutter + sqflite 个人生活管理 App（Android 优先）。本文件只放「每个会话都需要」的事实与禁令。

## 开工先读（三层按需，勿全仓检索）

1. `docs/STATUS.md`（≤60 行）——HEAD/发版/DB/门禁基线/下一站工单/互斥面，唯一状态源。
2. `docs/INDEX.md`——文档地图。按任务类型在 INDEX 找到需要的那几行，**只读那几行指向的文件**，不要通读 docs/。
3. 与本批任务直接对应的活工单（`docs/handoff/`，INDEX 里标「活」）——批次规格唯一依据。

- 需求口径：`docs/需求清单.md` 只含现行定义；逐版修订记录在 `docs/archive/需求修订史-V1.19~V1.59.md`。
- 三源冲突优先序：**需求修订史 > 原型 > 计划文档**；拿不准先问，别自己定。
- UI 相关任务先读 `docs/UI组件规范.md` 与原型 `prototype/index.html`（共享面唯一事实源）。原型 HTML 体量巨大——按屏锚点（深链 `#p-xxx` / `?brNN=`）定位相关段，勿整读全文。
- 流程与排期口径 `docs/开发计划书.md`（发版 §7.1、开场白模板 §7.4）。

## 工单生命周期（新规矩）

- 新工单（交棒话术/验收清单/拍板记录）**直接建在 `docs/handoff/`**，勿再放 docs/ 顶层。
- 批次收口 → 对应工单 `git mv` 入 `docs/archive/` → 在 `docs/INDEX.md` 更新状态一行。archive 只进不出。
- 验收/取证**截图不再入库**：`docs/acceptance*`、`prototype/shots/`、`tools/attic/` 已 gitignore；截图落仓库外目录，验收文档只写结论。
- 状态变化只改 `docs/STATUS.md`；历史时点沉 `docs/交接文档.md` 文末变更日志。

## 环境事实（本机，Windows + Git Bash）

- 工程真实路径 `D:/dev_workplace/flutter_te/lifeHarness`（会话声明路径可能失效）。
- java 用 JetBrains Rider/Studio 的 jbr 全路径；Android SDK `D:\app_workplace\android_studio_sdk`；flutter `D:\app_workplace\flutter`（见 `android/local.properties`）。
- `python` 可能是商店桩程序（零输出 rc=49），用全路径 `D:\app_workplace\python3.11\python.exe`。
- GitHub 直连/`download.flutter.io` 受限时按 `docs/本机构建环境优化操作指导-20260930.md` 的 workaround；tuna 镜像缺引擎 jar 时改 `storage.flutter-io.cn`。
- 双端发布：Gitee 优先（`D:\app_workplace\gitee-cli\gitee.exe`，chistoiy/lifeHarness 私有），GitHub 失败仅提醒；GitHub 可走 `ssh://git@ssh.github.com:443`。

## 验证门禁（两档）

- 批内增量：只跑受影响测试文件（推荐经 `tools/ftest.sh`，治并发测试崩溃）；收口/发版才跑全量（独占约 12 分钟，勿与其他会话抢 CPU/IO）。
- 文档域收口随跑 `python tools/doclint.py`（全路径 `D:\app_workplace\python3.11\python.exe`）：零死链 + 守护五检（工单落位/INDEX 登记/需求清单防复活/交接长行/三件套行数预算），红灯必须清零。
- 全 app widget 测试必须拆分独立文件（同文件多大页会 isolate 污染挂死）；测试日期一律相对构造，23:55–00:30 不跑全量；涉及 pump 的用例注意 override `sharedPreferencesProvider`。
- 脚本改源码：先快照（落 gitignored `tmp/`）、命中断言 + 体积校验，按文件真实编码读写，锚点跟随目标文件行尾；批量修改写成脚本文件执行，勿用 heredoc。

## 禁令（违反会被驳回）

- 禁止对仓库跑 `dart format`（非格式化干净态，小改动会炸成整份重排）。
- UI 变更必须**先改原型**并经用户确认，再动实现；勿动 `prototype/v2.html`（非本系列产物）。
- UI 禁用 emoji 图标（用线性 SVG）；不写教学性说明文案；时间/数值选择就地内嵌滚轮，不做两段式弹层。
- 推送/发布（Gitee、GitHub、预发布 release）必须先获得用户明确同意；发版按计划书 §7.1 新开 worktree、从自己的提交构建、双端挂三包 APK。
- 并行会话共用 git 暂存区：提交用 `git commit -- <路径>` 局部提交，勿 `git add -A`。
- 并行会话互斥面以 `docs/STATUS.md` 当期行与 INDEX 为准；对其余线的未跟踪文件只读不写不提交不回退。

## 忽略清单（勿读勿检索）

`build/`、`.dart_tool/`、`flutter_0*.log`、`device_logcat.txt`、`docs/acceptance*`（历史截图目录，已出仓）、`tmp/`、根目录 `*.apk`、`tools/*.log`、`tools/attic/`、`prototype/shots/`、`tools/` 下浏览器用户数据目录（`.*-profile`、`.f01-probe`、`.xr-probe*`）。

## 下指令/接任务口径

- 用户以「LH-xx 组件名 调整项」下 UI 指令；批次工单以对应 `docs/handoff/*.md` 为唯一规格，不复述内容。
- 已下架勿复活：小工具模块（V1.58 整模块作废）、影音游模块（延后裁定）、Legado 书源（V1.55 撤销）。
