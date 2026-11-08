# STATUS（唯一状态源 · 最后更新 2026-11-08）

> 状态变化只改本文件；历史时点沉 `docs/交接文档.md` 文末变更日志。本文不钉具体 HEAD sha（防漂移），看 `git log --oneline -3`。
> 体量口径：硬闸＝`python tools/status_set.py --check`（单行 ≤1200 字符·全文 ≤6,480 字节·叙事只留「本批／上一批」两级且各 ≤400 字符）；**黄线＝上限 90%（5,832 字节），到线即当轮瘦身，上限随瘦身棘轮只降不升**（细则＝`AGENTS.md`「文档体量治理」）。收尾改本文件一律走 `status_set.py`（`--rotate`→`--set`）。

- **上一批＝** 存量红消化批2＋影音游计时明细接线（11-08）：批2 清 6（导图粘贴钮置灰·日记/待办文案 3·阅读视图切换 2），影音游 4 条随之归零——新建计时明细整屏（原型 m-sesslog：汇总四格/月分组降序/补记/行内改/删）＋详情页 ▶计时钮＋轨迹·更多·资料页三入口＋路由，零 DB 变更；新增常驻 media_sesslog_test 4 例·两把刀实测咬红（去排序/不落块）；analyze 0 error·doclint 全绿·不出包
- **本批＝** 架构 R1 跨模块直连归零（11-08）：存量红最后一条真红——11 条 features 互 import 边全改走 shared/linkage 门面（新建 `mindmap_api` 7 符号白名单＋`export_source_mounts` 3 个 provider；序列化端挂 `ics_collect`）；三消费方只动 import 段（`export_sheet` 净 −5 行）；`architecture_test` +11 绿·7 波 64 例绿·analyze 0 error·不出包（纯 import 改道不需装机）；R1 legacyEdges 四条更早越线仍登记待另批引门面

## 基线（八项，其余不写）

**未推＝0**（11-08 全部已双端推齐＝头 `212e3722`（Gitee/GitHub 回读一致）；对账＝`git rev-list --count origin/feat/m0-skeleton..HEAD`；推送口径＝**批内闸全绿＋全量红面已证存量**）。⚠ 发版须先取得产品同意；Gitee/GitHub 姿势与回读禁忌见 `AGENTS.md`「环境事实」段。
- 最新预发布＝`v0.2.15-mm-p7`（装机 8202·arm64 单包）／`-nfc`／`-desktop-b1` 三枚双端挂齐；逐枚钉版/双端 id/md5＝台账§A。⚠ 只挂 arm64 瘦身包·勿卸载＝清库
- 再前预发布＝`-tree-swipe`／`-tree-follow`／`-note-mount`／`-note-local`（DB v39→v42 首枚）／`-health-media`／`-media`——台账＝同档 §A
- DB＝`DbSchema.version=52`（v52＝物品批A `item_profiles` 加 brand/serial/note·全可空纯加列；v51＝item_events 加 txn_id；v50＝日记批2b 建 tags+tag_links——**version 与 migrations 必须同批改**；v49~v45 逐版＝沉各归档工单；本行读数由守护二十三与 schema.dart 比对）
- 全量门禁基线＝**4272 绿／26 红（11-08 12:24 独占轮·21m50s）**：其中 25 条已由批1（14）＋批2（6）＋影音游计时明细接线（4）＋R1 跨模块直连归零（1）修掉（余 1＝todo 单跑绿噪声），**未复验**；下次全量须产品点头，禁拿半程当全绿
- 批内增量档＝**真机反馈十二整改批2（12 波定向·三刀·6 组常驻守护·analyze 0 warning）**／**C 案批5 对齐零争议项（5 新例·定向波＋三刀）**；更早各档＝沉 `docs/archive/复测包与发版台账.md`§C
- 未出编号＝**无欠编号**（6214 已于 11-08 出包·待装机；装机后下一枚 **≥6215**）·口径＝复测包只在**产品令装机**时一枚打包，不每批自动构建；更早逐枚＝沉 `docs/archive/复测包与发版台账.md`§B/§D。
- 复测包＝**8214 已出·未装机**（base 6214·承载浮动标签批4b/5/6·arm64 分包 39,501,799 B·md5 `04a38501`·aapt 四项全过·构建 7m48s；无线/USB 均未连·产品令跳过装机，连接恢复后 `install -r` 保数据 8213→8214·留档＝`tmp/retest-6214/lifeHarness-8214-arm64.apk`）。8213 已装机已肉眼验；明细＝台账§D
- 真机门 backlog＝① 6098 十六条＝`tools/release_body_v0215.md`；② UX 审计 U1~U9＝20261005 工单；③ 各专版逐屏验收积压；④~⑦＝`release_body_v0215e/f/g.md` 与 NFC/批3/批4 各工单（逐条位置不变，明细指各件）
- 下一站＝① **存量红真红已清零**（26→1：余 `todo` 单跑绿噪声待判）＋ **R1 `legacyEdges` 四条更早越线**（`today_schedule_card`→calendar／`days_providers`→todo／`journal_page`→read／`diary_edit_page`→calendar 仍靠白名单豁免，真还债＝各自引门面后删登记，另批）② 旧 `finance_txns` 处置待拍 ③ 阅读二期批7 欠项待数据源 ④ 竞品/物品余项待点单 ⑤ **C 案批5 余项**（B 项 27 条已裁定＝全按建议通过·分批动刀中；F4 菜单暴露随排序形态；M1 实物卡·M5 听后感流立项另批） ⑥ 存量红余量随全量轮 ⑦ 排期池 #14~#16/#19~#23；⑧ 浮动标签整改余项清零（批4/批5/批6 落地）；体检项＝§4 L2 原型已交·待过门；**浮动标签批3 实现轮已交·8213 已装机·已肉眼验·P2 已批4 整改**（批1/批2 原型已过门；余队列＝20 内联单元格维持豁免／导图专版与 3 类 JS 动态表单原型侧待裁定）
- 队列下一项＝排期池 #14~#16/#19~#22 或思维导图体检余二选；小组件余量＝批B 两枚 provider＋批C-4 收口（图标体积/选择器排序/全量回归）。
- 存量待拍板＝① **判据① 余缺 29,714**：产品 2026-10-16 令「先不动」（bookshelf 已无可删孤儿，余量是 21 屏自身活代码）⇒ 挂起非待办，判据②③④ 已终局；② 批1b §9 两处口径待复核（设置层总闸原型漏画·实现已保留／记录类型取母婴内置 12 类而非原型 3 类 mock）；③ 可另点存量＝排期池 #2~#9、#14~#16（#18 日记改版已点名开工、续落「下一站」）。批2 三次真机排障沉淀＝沉 `NFC卡片模块-批2写卡与触发.md` §7。
- 并行互斥面（其余线：只读不写不提交不回退）＝**2026-11-05 产品确认当前无并行会话（互斥面解除）**；常备写区＝影音游 `lib/features/media/**`·`test/media_*`·`prototype/index-media.html`（9a 待过门）／健康线 `lib/features/health/**`·`test/health_*`·`lib/shared/linkage/health_mounts.dart`；雷电模拟器 `127.0.0.1:5555` 属阅读验证线；AVD `lh_x64_api35`／构建棵 `lh-emu-x64`＝验证工装
- 环境/禁令/忽略清单/工单生命周期：一律看 `AGENTS.md`；文档地图看 `docs/INDEX.md`。
