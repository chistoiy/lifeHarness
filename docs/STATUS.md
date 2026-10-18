# STATUS（唯一状态源 · 最后更新 2026-10-18）

> 状态变化只改本文件；历史时点沉 `docs/交接文档.md` 文末变更日志。本文不钉具体 HEAD sha（防漂移），看 `git log --oneline -3`。
> 体量口径（2026-10-08 立·2026-10-14 并入体量治理·2026-10-17 棘轮下调至 9.7KiB）：硬闸＝doclint 守护七调 `python tools/status_set.py --check`（单行 ≤1200 字符·全文 ≤9,950 字节·批次叙事只留「本批／上一批」两级且正文各 ≤400 字符）；**黄线＝上限 90%（8,955 字节），到线即当轮瘦身；上限随瘦身棘轮只降不升**（口径＝`AGENTS.md`「文档体量治理」·doclint 守护二十一＝单行 ≤700 字符）。溢出细节留 `docs/handoff/` 工单、历史整段沉 `docs/archive/`；收尾改本文件一律走 `tools/status_set.py`（`--rotate`→`--set 本批 --text-file`），禁止在同一行追加历史。瘦身前全文＝`docs/archive/STATUS沉档-20261008-瘦身前全文.md`；治理口径＝`docs/archive/治理方案-20261013-规则与上下文与记忆治理.md`。

- **本批＝** **小组件批E 习惯记录可改可删（6187 已装机·等真机回执）**：产品「缺少修改打卡记录」真因＝四处入口全是死区（桌面已打卡枚撤意图点不动／流水行只读／今天格死提示／记量弹层只能编辑今天且无打卡时间控件）。口径＝弹层按日参数化 `showHabitLogSheet(day:)`＋打卡时间可改（24h）＋改值保留 `origin`/`backfilled`＋删除走 `deleteEntry`＋桌面按钮改导航＋布尔型不出数值区。闸：新 6 例＋15 波全绿·KT-OK。详见批E 工单。
- **上一批＝** **小组件批D 计数型步进＋一次提交（6186 已装机）**：数值型打卡枚 `[−N][值][+N]` 三格＋`打卡`，提交后 `已打卡 · N`。三处改判＝草稿落原生（± 起无头引擎 1~3s 冷启不可用·不进库故不算复刻写库）／两态判据＝今日是否已记／步长取 `habitStepOf` 阶梯。闸：14 波全绿·KT-OK。详见批D 工单 §6。

## 基线（八项，其余不写）

**未推＝NFC 批1＋批1b（2 提交）在本地待推**（2026-10-16 ⑲ 收口后 `a66972ee` 双端推齐 `feat/m0-skeleton` 同头；逐笔 sha 台账沉交接文档变更日志）。⚠ **推送/发版须先取得产品同意**；Gitee/GitHub 姿势与回读禁忌见 `AGENTS.md`「环境事实」段。推前闸＝doclint PASS strict 全绿·protogate strict 0 违例·registry 293/293·cards 15/15。
- 最新预发布＝**`v0.2.15-nfc`**（钉版 `38d355a7`·发版件 **6173**·arm64 单包 42,224,880 B·**双端挂齐＝GitHub `415828988`＋Gitee `1213591`**）／`v0.2.15-desktop-b1`（钉版 `0807a971`·发版件 6144·双端挂齐＝GitHub `413683416`＋Gitee `1207740`）／`-time-b2`／`-journal`／`-nav-collapse`（6106·真机门 31 条）。⚠ 发版口径＝只挂 arm64 瘦身包禁 ≥100MB·Gitee 匿名直链被拦·⚠ 勿卸载＝清库；逐枚钉版/双端 id/md5＝`docs/archive/复测包与发版台账.md`§A
- 再前预发布＝`v0.2.15-tree-swipe`／`tree-follow`／`note-mount`／`note-local`（**DB v39→v42 首枚**）／`v0.2.14-health-media`／`v0.2.13-media`（三包 6089/5089/8089）——台账＝同档 §A。
- DB＝`DbSchema.version=49`（v49＝**NFC 卡片批1b 给 `nfc_cards` 加三列**（加 `desc_text`/`color`/`target_sub`·纯 ALTER；基础 DDL 升 v49、`mig[47]` 用 v48 老口径语句表防 duplicate column）；语句表在 `lib/core/database/schema/nfc.dart`（`nfcSchemaStatements`／`nfcMig47Statements`／`nfcAddColumnStatements`）、migrations 聚合 `...nf.mig`——**S6 抓过漏拼（漏改 `version` ⇒ 真机 onUpgrade 不触发）**，守护 S6/S7 在 `nfc_card_dao_test`；v48＝NFC 批1 建 `nfc_cards`、v47＝思维导图批5 加四列、v46＝思维导图批2 建 `mindmap_folders`、v45＝思维导图批1 双写 DDL，逐版细节＝沉各归档工单）
- 全量门禁基线＝**2756 绿／0 红**（2026-10-08 发版 `v0.2.14-health-media` 前独占跑·8 分 00 秒·rc=0）；**`v0.2.15-note-local` 预发布按产品令跳过全量**（本批新增常驻未归位进基线）→ 下轮正式版前必独占重跑归位；旧基线读数与 `flutter test` reporter 陷阱＝沉档 §门禁段
- 批内增量档（门禁瘦身三条；新增常驻例攒到下轮发版独占重跑归位）＝**批E 习惯记录 6 例＋15 波全绿／批D 计数型步进 14 波全绿**（KT-OK×2）；更早＝**小组件三缺陷修复 138 例** → **NFC 批3f 47 例**；各档细节＝沉 `docs/archive/复测包与发版台账.md`§C
- 未出编号＝**无欠账**（下一枚 ≥6188·口径＝复测包只在**产品令装机**时一枚打包）；最新已出＝**6187（批E 记录可改可删·arm64·已装机）／6186（批D 计数型步进·已装机）／6185（瓦片尺寸二修）／6184（量框试验件·被 6185 取代）／6183（三修）／6182（批C-1 骨架）／6181（冷启崩溃修复）／6180／6179／6176（三缺陷修复）**；更早 6175~6112 逐枚＝沉 `docs/archive/复测包与发版台账.md`§B。**台面纪律**：欠着的编号必须在本行点名「攒 NNNN（未构建）」，doclint 守护九＋九B 双向核对（没点名＝红）。
- 复测包＝**6187 已出·已装机**（批E 定稿件·**arm64 单 ABI**·versionCode 8187·52,446,214 字节·md5 `e5b3c8f2`·构建 5m03s·`install -r` 保数据·冷启 494ms 无 FATAL·aapt 四验过）。上一枚 6186（批D 计数型步进·52,315,150 B·md5 `d7c62b8f`）。下一复测包＝无（≥6188）。累计＝`docs/archive/复测包与发版台账.md`
- 真机门 backlog＝① 6098 十六条＝`tools/release_body_v0215.md`；② UX 审计 U1~U9＝`交棒话术-20261005-UX审计真机批-贴底行吞点击与工装转正.md`；③ 各模块专版逐屏验收积压（书架/阅读·记账·呵护·时间·健康·影音游）；④ 6100~6106＝`release_body_v0215e.md`／`v0215g.md`（侧边栏 ok·6106 A~D 31 条）；⑤ 批3 导出八条＝`v0215f.md`（**第 5 条图片显示＝真判据**·第 8 条只读挂载禁谎报写回失败）；⑥ 批4 八条＝`交棒话术-20261004…` §19（第 3/4 条回写须退回仅应用内·第 6 条清空两步）；⑦ NFC 批1/1b 装机 6156 待逐屏验。
- 下一站＝**6187 等真机回执三条**（已装机）：① 详情页「打卡流水」任一行点开那天的记录（数值／打卡时间／删除）② 日历点今天直接开「打卡记量」（不再死提示）③ 桌面已打卡枚按钮点进 App（不再毫无反应）。6185 目视回执两条仍挂（标签可读性／底部差 29px 已到 MIUI 上限）。回执过后进 **批C-2 壳内 11 枚**（尚缺 5 枚矢量图 `calendar/settings/care/days/goals`）。NFC 批3f 四条口径（8173·已装）＝工单 §7.9 未回执，不催。
- 队列下一项＝**批C-2 壳内 11 枚瓦片**（含今天／我的·**缺 5 枚矢量图标** calendar／settings／care／days／goals）；之后批C-3 全屏 5 枚／批B＝计时·快捷动作两枚 provider。
- 存量待拍板＝① **判据① 余缺 29,714**：产品 2026-10-16 令「先不动」（bookshelf 已无可删孤儿，余量是 21 屏自身活代码）⇒ 挂起非待办，判据②③④ 已终局；② 批1b §9 两处口径待复核（设置层总闸原型漏画·实现已保留／记录类型取母婴内置 12 类而非原型 3 类 mock）；③ 可另点存量＝排期池 #2~#9、#14~#16、#18。批2 三次真机排障沉淀＝沉 `NFC卡片模块-批2写卡与触发.md` §7。
- 并行互斥面（其余线：只读不写不提交不回退）＝**2026-10-17 在飞＝NFC 卡片批3d**（写区＝`lib/features/nfc/**`·`lib/shared/linkage/nfc_mounts.dart`·`lib/shared/linkage/sys_pill_sync.dart`·`lib/shared/widgets/nfc_receipt.dart`·`lib/core/notifications/**`·`test/nfc_*`·`android/**`·`pubspec.yaml`＋`pubspec.lock`·`lib/app.dart` 的 `nfc:` 分支与启动路由消费段；历史写区清单＝沉各归档工单）；其余线常备写区＝影音游 `lib/features/media/**`·`test/media_*`·`prototype/index-media.html`（9a 待过门）；健康线＝`lib/features/health/**`·`test/health_*`·`lib/shared/linkage/health_mounts.dart`；雷电模拟器 `127.0.0.1:5555` 属阅读验证线专用；AVD `lh_x64_api35`／构建棵 `lh-emu-x64`＝验证工装
- 环境/禁令/忽略清单/工单生命周期：一律看 `AGENTS.md`；文档地图看 `docs/INDEX.md`。
