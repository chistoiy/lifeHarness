# LifeHarness — Agent 指南

Flutter + sqflite 个人生活管理 App（Android 优先）。本文件只放「每个会话都需要」的事实与禁令。

## 开工先读（三层按需，勿全仓检索）

1. `docs/STATUS.md`（≤60 行）——HEAD/发版/DB/门禁基线/下一站工单/互斥面，唯一状态源。
2. `docs/INDEX.md`——文档地图。按任务类型在 INDEX 找到需要的那几行，**只读那几行指向的文件**，不要通读 docs/。
3. 与本批任务直接对应的活工单（`docs/handoff/`，INDEX 里标「活」）——批次规格唯一依据。

- 需求口径：`docs/需求清单.md` 只含现行定义；逐版修订记录在 `docs/archive/需求修订史-V1.19~V1.59.md`。
- 三源冲突优先序：**需求修订史 > 原型 > 计划文档**；拿不准先问，别自己定。
- UI 相关任务先读 `docs/UI组件规范.md` 与原型。**屏单一归属（2026-10-03 立）**：一张屏（含弹层/抽屉）只有一个家——壳与跨模块屏在 `prototype/index.html`，模块细节屏（含主屏/代表屏）在该模块专版，别处不留副本——2026-10-03 追加拍板：壳内代表屏也已下架，模块入口一律直达专版（navTo 兜底重定向承载，见注册表 redirects）；`index.html` 不是全部模块的事实源，回灌只回入口/角标/联动层。原型体量巨大，**禁止整读**——按屏锚点（深链 `#p-xxx` / `?brNN=`）定位相关段；治理方案、测量与动刀顺序见 `docs/archive/交棒话术-20261003-原型瘦身与屏单一归属治理.md`。
- **对象定位纪律（2026-10-03 立）**：开发者说的是自然语言（"记账那个 hero 太挤"）或截图圈选，**不是口令**——任何 UI/功能指令先解析 `{模块, 屏/弹层, 组件, 意图}` 四元组（靠模块注册表的人话别名与 `pfind`，判不出意图按最保守一类走并明说）。回执分档：**L0 目标唯一→回一行摘要直接开工；L1 跨屏→摘要不阻塞；L2 视觉分歧/不可逆/定位多义→圈红截图停下等确认**，判定句＝改错代价 ≤ 一次 `git revert` 就直接走。给人看的回执**禁止出现 id／行号／类名／函数名**，连带影响要说功能语言（"这两屏会一起变"），锚点明细折叠在下面。细则与四道闸见 `docs/archive/交棒话术-20261003-原型瘦身与屏单一归属治理.md` §8。
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
- **同一收口轮的全量只跑一遍**（2026-10-06 立）：跑完以 `rc`＋尾行 `All tests passed` 定案即算门禁过。**对日志读数起疑时先做便宜判定**（要数覆盖面用 `--reporter json`，秒级），**任何重跑（尤其独占全量）必须先取得产品同意**。**已知读数陷阱**：`flutter test` 输出落盘时并发 reporter 只写部分文件路径——日志里出现的路径数≠覆盖面证据（同一命令两遍同为 2111，路径数却分别 82／118）；拿它当「没跑全」会白烧一整遍全量。
- **收尾轮成本口径（2026-10-06 立）**：三件套含超长行（`docs/STATUS.md` 表头一行近 3 万字符），按锚点 grep 取要改那一段，**不整读**；一轮收尾的模型调用预算 12–20 次（analyze 1／增量测试 1–2／改文档 3–5／提交 1／双端推送 2–3／报告 1），超预算即属自造浪费。
- **单批 20 分钟收口流水线（2026-10-06 拍板 · 全细则＝计划书 §7.5）**：方案已定的批，从开工到双端推送墙钟 ≤ 20 分钟（等用户确认不计；全量门禁／复测包构建／装机复验照旧攒批在窗外）。五段打点 `bash tools/timelog.sh start|mark|report`（P0 读面板 2'→P1 实现 8'→P2 门禁 4'→P3 文档 3'→P4 提交推送 3'；窗外动作段名以「窗外·」开头不计窗内，起表可 `--from` 回填），收尾必贴判定行；超时＝变更日志行尾归因三选（工单欠预编译／门禁超时／网络回退）。**执行面板**六项（受影响测试清单／变异刀清单／新增常驻用例／回灌成句／下一复测包编号／互斥面）＝开工唯一规格依据，新施工活工单缺面板＝doclint 守护六红灯。**瘦身三条**：变异只钉本批新增守护/原语、单批 ≤3 刀；相邻回归三件套（architecture/size/catch）退出每批随收口全量；批内增量只跑面板清单。**并发纪律**：flutter test 全程单轨；**批内增量一律 `bash tools/ftest_waves.sh <批次名> <文件…>` 逐档拆波（2026-10-11 改口，V1.64 批1 实伤：8 件混场 `flutter test` isolate 挂死 40 分钟零输出，父 bash 被杀后 dart/flutter_tester 残骸占场、下一轮在无形态里空转）**——**一律一文件一波**（首版轻件 3 合波当晚二次实锤同场挂死：pump 套件跨文件同 isolate 互踩，与「全 app widget 拆独立文件」同族）、每波日志直写 `tmp/gate_<批次名>/`（可增量 tail）＋`--timeout 90s` 防单例挂死、波毕落 `rc＋尾行` 进 progress.txt、开跑前探场拦残骸进程、缺文件名秒红（勿拿假红当回归）；与测试同场只许 node 工装/git/doclint/文档起草，禁第二个 flutter 进程（analyze 须在测试起爆前收口）。
- 文档域收口随跑 `python tools/doclint.py`（全路径 `D:\app_workplace\python3.11\python.exe`）：零死链 + 守护六检（工单落位/INDEX 登记/需求清单防复活/交接长行/三件套行数预算/活施工工单执行面板）＋守护十色值棘轮（新增硬编码 `Color(0x` 即红；确需新增色值先人审，跑 `python tools/color_ratchet.py --write` 钉基线并写理由，条文＝`docs/UI组件规范.md` 〇B），红灯必须清零。
- 全 app widget 测试必须拆分独立文件（同文件多大页会 isolate 污染挂死）；测试日期一律相对构造，23:55–00:30 不跑全量；涉及 pump 的用例注意 override `sharedPreferencesProvider`。
- 脚本改源码：先快照（落 gitignored `tmp/`）、命中断言 + 体积校验，按文件真实编码读写，锚点跟随目标文件行尾；批量修改写成脚本文件执行，勿用 heredoc。
- **复测包＝攒批出，一轮一枚（2026-10-11 产品改口，覆盖同日「收口即出」条）**：出装机包**不需要**"等推送/发版同意"，但也**不再每批自动构建**——**只在产品说「这轮要装机／出包」时出一枚 arm64 复测包**，覆盖从那之后攒下的所有批次（含改了 DB 迁移、原生通道 `android/**`、手势或交互入口的批）。实测代价＝Gradle 约 6.5 分钟/枚，而真机验证本来就是一次装机做完（本会话 6104＋6105 各建一次＝两枚间隔 60 分钟，合并可省 7 分钟）。
  - **欠着的编号必须写进 `docs/STATUS.md` 的「- 未出编号＝」行并点名「攒 NNNN（未构建）」，且该行必须写明当前口径（含「攒批」或「产品令装机」字样）**——doclint **守护九＋九B** 双向核对：攒着的没点名＝红；叙事里声称「收口即出 NNNN」而「- 复测包＝」行没有「NNNN 已出」＝红。
  - 历史教训保留：6097/6098 曾攒两天，6098 装上当天报出三条只有真机能发现的问题；6104 装机即确认「侧边栏 ok」——所以**攒批的边界是「攒几轮就要尽早安排一次装机」**，产品多久没令装机，STATUS 那行就欠着几个编号，收尾必报，不许静默攒没。
  - 推送/发版仍按下方禁令先取同意；**发版执行件与真机门说明（`tools/release_*.sh`／`release_body_*.md`）只在产品提到预发布／推送／发版时才建**，纯复测包轮次不预先写（2026-10-11 裁定的文档最小集之一）。
- **改了 Kotlin 必跑编译校验（2026-10-11 立·配 `tools/kotlin_check.sh`）**：动 `android/**` 的批，收口链里跑 `bash tools/kotlin_check.sh`（只编 Kotlin，约 3~4 分钟）——`flutter analyze` 盖不住 Kotlin，等全量构建才炸要多烧一趟 4 分钟（本会话实锤：两处可空串/属性式写法错误只有构建能抓到）。纯 dart 批不必跑。
- **出包预检（2026-10-04 拍板成文 · 2026-10-05 分包口径同步）**：任何 `flutter build apk`（复测包/发版同此）前先跑 `node tools/prebuild_check.js --dir <构建目录> --code <期望versionCode>`——红灯禁止构建，避免建完才现版本不对二次构建。该闸拦三类实锤坑：① `local.properties` 钉版盖过期望值；② `--split-per-abi` 抬 ABI 偏移（arm64 +2000：4067→6067）——分包要带 `--split`，`--code` 仍传**装机期望编号**（60xx），闸自动折算 base＝期望-2000 并要求钉版/`--build-number` 都用 base；把 base 当期望传会被判「误传 base」红。**复测包形态须与机上包一致**（机上仍是 universal 期间照旧打 universal，勿赌分包；换包那轮起按下方拍板改 arm64 分包）；③ 忘带 `--build-number`（pubspec build≠base 时提示）。预检绿后按它打印的四项 aapt 复验清单执行（badging 版本/INTERNET/库集对齐/mtime 新）。
- **出包时序纪律（2026-10-05 拍板）**：该编号的 dart 改动**全部落定**才起构建——build6066 剖析实证耗时大头＝dart AOT 全量重算占全程 97%，且源码与 `FLUTTER_BUILD_NUMBER`（注入 dart-defines）任一变化都必换全量，没有「只改编号」快路径；构建中途发现要改 dart，一律攒到下一枚编号，不重打本轮。**复测包自下次换机装包起与机上包统一改 arm64 分包**（`--split-per-abi`，base＝期望编号-2000，随发版形态对齐；机上仍是 universal 期间照旧 universal，细则＝开发计划书 §7.1 拍板段）。

## 禁令（违反会被驳回）

- 禁止对仓库跑 `dart format`（非格式化干净态，小改动会炸成整份重排）。
- UI 变更必须**先改原型**并经用户确认，再动实现；勿动 `prototype/v2.html`（非本系列产物）。
- UI 禁用 emoji 图标（用线性 SVG）；不写教学性说明文案；时间/数值选择就地内嵌滚轮，不做两段式弹层。
- 推送/发布（Gitee、GitHub、预发布 release）必须先获得用户明确同意；发版按计划书 §7.1 新开 worktree、从自己的提交构建、双端挂三包 APK。
- 并行会话共用 git 暂存区：提交用 `git commit -- <路径>` 局部提交，勿 `git add -A`。
- 并行会话互斥面以 `docs/STATUS.md` 当期行与 INDEX 为准；对其余线的未跟踪文件只读不写不提交不回退。

## 忽略清单（勿读勿检索）

`build/`、`.dart_tool/`、`flutter_0*.log`、`device_logcat.txt`、`docs/acceptance*`（历史截图目录，已出仓）、`tmp/`、根目录 `*.apk`、`tools/*.log`、`tools/attic/`、`prototype/shots/`、`tools/` 下浏览器用户数据目录（`.*-profile`、`.f01-probe`、`.xr-probe*`）。

## 会话口令（用户只需这几个词，其余全由本文件驱动）

- **「开工」**（新会话唯一开场）＝ 读本文件 → `docs/STATUS.md` → 下一站行指向的 `docs/handoff/` 活工单，按其规格依批次顺序开工；无需任何背景复述。流水线口径下带「⚙ 执行面板」的批只读面板段与批次规格，不通读工单、不重做设计。要限定范围就写「开工 <工单名>」。
- **「收尾」**＝下面六步仪式；「收尾并推送」再追加双端 push（Gitee→GitHub）。
- **「记一下 <主题>」**＝把该结论落进 STATUS/INDEX/变更日志对应处，不许只回「收到」。

复杂批次（多会话并行交接）才用计划书 §7.4 开场白模板；日常批禁止再写长开场白——信息都应在 STATUS 下一站行里，STATUS 没写就是没做完收尾，先补收尾。

## 会话收尾仪式（每轮工作结束前，用户说「收尾」即按此执行）

> **收尾走快车道（2026-10-11 立，V1.64 批1 五分钟内收口口径）**：「收尾」＝先把整条验证链后台化——一条 `tmp/<批>/closeout.sh` 串完「门禁→三刀→doclint→STATUS→日志/工单→本地提交→CLOSEOUT 判定行」，任一红步即 STOP 不提交；主会话不阻塞盯梢，读数由一次性 cron 或下一条消息一次取回。盯梢式轮询/有界 sleep 均违此口径（本批实伤：三轮盯空转 30 分钟）。
>
> **两段式回知（同日补，产品问「为何不主动通知」）**：closeout 主链仍用 nohup+disown 起（免疫会话后台 10 分钟掐长任务），但**脱离监护＝跑完无事件**；所以起链后必须立刻另发一条**会话内后台监听**（Bash run_in_background：`until grep -qE 'ALL-DONE|STOP@' CLOSEOUT; do sleep 5; done; cat CLOSEOUT`）——监听命中判定行即退出，会话收到完成通知自动向用户播报。≤10 分钟的链直接整条用 run_in_background 起（免监听）；预计超 10 分钟才用「nohup 主链＋监听」两段式。禁只留 cron 或让用户来问进展。

1. 门禁：受影响测试 + 文档改动随跑 `python tools/doclint.py`，红灯清零；跑 `bash tools/timelog.sh report` 并贴判定行（超 20 分钟＝变更日志行尾归因）。
2. 状态：只更新 `docs/STATUS.md`（HEAD/发版/DB/门禁数/下一站/互斥面）。
3. 工单流转：已闭环批次 `git mv` 入 `docs/archive/`，INDEX 更新对应行。
4. 登记：交接文档 §5 变更日志追加 ≤3 行（结论+提交+发版），细节留在工单里。
5. 提交：文件级 pathspec 局部提交；推送/发版另行取得同意。
6. 可复用方案按 developSummary 模板沉淀（用户点名时）。

## 下指令/接任务口径

- 用户以「LH-xx 组件名 调整项」下 UI 指令；批次工单以对应 `docs/handoff/*.md` 为唯一规格，不复述内容。
- 已下架勿复活：小工具模块（V1.58 整模块作废）、Legado 书源（V1.55 撤销）、插件中心屏（2026-10-07 产品拍板删屏）。
  影音游模块**已于 2026-10-07 产品令解禁并开工**（此前「延后裁定」作废；规格＝`prototype/index-media.html`＋《影音游模块开发计划-20260922.md》）。
