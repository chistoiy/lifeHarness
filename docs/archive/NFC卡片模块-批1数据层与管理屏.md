# NFC 卡片模块 · 批1（卡片数据层与管理屏）

> **立项**：需求模块 19（V1.68）·产品 2026-10-15 点名开工，**2026-10-16 22:40 产品令开批1**。
> **规格唯一来源（代码模型不得新增需求）**＝`docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md`（V3·【方案冻结】·裁决 C1~C42＋边界 B1~B43）。本工单**只做批1 ＝ §2.1 F1-1~F1-7**，批2（写卡与触发）与批3（UID 轨）另开工单。
> **排期池溯源**：本件原为排期池 #17 断链补登（2026-10-16 22:40）——2026-10-15 已点名开工但**两处台账都无面**（排期池只在摘除说明留一句「只落 STATUS」，而 STATUS 下一站当时写「无在飞工单」），代码零落地。补登后当轮摘行、落 STATUS 下一站。

---

## ⚙ 执行面板六项（开工唯一规格依据）

| 项 | 内容 |
|---|---|
| **受影响测试** | `test/journal_test.dart`（S6 版本自检＋S7 v47→v48 真升级）｜`test/settings_page_test.dart`（入口行新增）｜`test/architecture_test.dart`（R1 不直连）｜`test/desktop_actions_test.dart`（动作表只读引用唯一性）｜`test/size_budget_test.dart`｜`test/catch_log_guard_test.dart`｜`test/backup_scope_test.dart`（**新建**·三处登记判据）｜`test/export_sheet_test.dart`（子集导出面板多一枚单元）。经 `bash tools/ftest_waves.sh nfc1 <文件…>` **一文件一波**，全程单轨、禁第二个 flutter 进程 |
| **变异刀**（单批 ≤3） | **刀1** `nfc_cards.id` 主键降级为普通列 → `nfc_card_dao_test` 的 UPSERT 断言红 ｜ **刀2** 摘掉 `written_at` 写入态判定（改成反推/恒已写入）→ `nfc_card_dao_test` ＋ `nfc_card` 列表态红 ｜ **刀3** 摘掉**备份三处登记的 `export_units` 一处** → `backup_scope_test` 红。三刀自证＝锚点命中=1 → 跑完回写 ＋ md5 断言、工装落 `tmp/` |
| **新增常驻** | `test/nfc_card_dao_test.dart`（建卡/改名换目标/删卡/列全表/按 `tag_key` 取/记一次使用/按 id UPSERT 不产生重复行/`written_at` 三态/`id` 12 位 base62 合规）｜`test/nfc_target_test.dart`（目标四类解析＋三区块互斥单选＋同名分类按 `catId` 区分＋已删目标失效分支）｜`test/nfc_settings_test.dart`（三偏好键默认态与冷启动读回）｜`test/nfc_linkage_test.dart`（`nfc_mounts` 两个读取转发口＋R1 反向守护）｜`test/nfc_privacy_test.dart`（卡号与 `uid:<指纹>`·`tag_key` 原文不入日志）｜`test/backup_scope_test.dart`（三处登记）。**批2/批3 的 `nfc_write_state_test`／`nfc_trigger_test` 本批不建**（无被测物） |
| **回灌成句** | **零原型回灌**（`p-sub-nfc`＋三弹层＋`p-profile` 入口行已于 2026-10-15 补齐并过门 `tools/nfc_proto_check.js` 14/14）。本批只做 `docs/UI组件规范.md` 登记四组件：LH-C24 卡片行 / LH-S41 新建编辑层 / LH-S42 写卡等待层（批2 用·**本批只登记不实现**）/ LH-L17 写卡状态行（同上） |
| **下一复测包号** | **攒 6156**（6155 仍欠·未构建）。本批**纯 Dart 零 android/** ⇒ 不触发攒批出包条件（AGENTS：动原生/改 DB 迁移的批才必出）——但 DB 迁移批按 AGENTS「含改 DB 迁移」口径**须攒**。装机归入产品令装机那一次 |
| **互斥面** | 本批写区＝`lib/features/nfc/**`（新目录）＋`lib/shared/linkage/nfc_mounts.dart`（新）＋`lib/core/database/schema/nfc.dart`（新）＋`lib/core/database/schema.dart`（version＋聚合两行）＋`lib/shared/linkage/export_units.dart`（+1 单元）＋`lib/core/backup/db_overview.dart`（+1 行）＋`lib/core/settings/settings_repository.dart`（+3 键）＋`lib/core/router/`（+1 行路由）＋`lib/features/settings/presentation/`（入口行）＋`test/nfc_*`／`test/backup_scope_test.dart`。**零 `android/**`**（批2 才动 ⇒ 那时才跑 `kotlin_check.sh`）｜其余线常备写区不变（影音游／健康／模拟器） |

---

## 1 · 前置门核对（开工前必须满足）

| # | 冻结档 §6.5 前置门 | 实况 | 判定 |
|---|---|---|---|
| 1 | **桌面模块批1 已落地**（`lh://` 解析＋`takeLaunchRoute`＋`desktop_actions.dart`）——硬前置 | `lib/core/platform/desktop_actions.dart` 在册：`kDesktopNamespaces` 已含 `'nfc'`（放行不解释）、`resolveLaunchPath` 的 `ns=='nfc'` 分支返回 `'nfc:<cardId>'`、`LaunchRoute.isNfc` 齐；`lib/app.dart` 冷启动先入队＋`takeLaunchRoute` 单次消费在位 | ✅ **满足**（批1 不碰触发放 anyway，本批只做数据层与管理屏） |
| 2 | ✅ App 内原型已补并过门 | `p-sub-nfc`＋`sheetNfcEdit`＋`sheetNfcWrite`＋`sheetNfcDel`＋`p-profile` 入口行在册；`tools/nfc_proto_check.js` 在仓 | ✅ 满足（**本批零原型改动**） |
| 3 | ⬜ 真机门八条 | **归批2**（写卡与触发才需装机验）；批1 的真机面＝入口行张数随动＋空态＋开关默认态 | 待批2 |
| 4 | `kotlin_check.sh`／`prebuild_check.js` | **本批零 `android/**` ⇒ 不跑**（AGENTS：纯 dart 批不必跑） | N/A |

---

## 2 · 本批做什么（F1-1 ~ F1-7）

### F1-1 · 卡片表 `nfc_cards`（DB v47→v48）

新语句表 `lib/core/database/schema/nfc.dart`（**域库 G5 惯例**：表名常量＋基础 DDL＋`mig` 三段，与 `mindmap.dart` 同款）。

| 列 | 类型 | 约束与口径 |
|---|---|---|
| `id` | TEXT | **PRIMARY KEY**；**12 位 base62**（`0-9a-zA-Z`＋`Random.secure()`），**禁 uuid／时间戳／自增**（C33：会让 §5.7 容量核算当场失真，且可枚举泄露创建顺序） |
| `name` | TEXT | NOT NULL；≤12 字（超长不接收 · B14） |
| `target_kind` | TEXT | NOT NULL；四值 `nav`/`timer_cat`/`read_book`/`timer_duration`（§2.0 目标表） |
| `target_ref` | TEXT | **可空**——未绑定的卡先建行再绑（B39：`written_at` 空且 `target_ref` 空 ⇒ 只写库不执行） |
| `tag_key` | TEXT | **UNIQUE**；`ndef:<cardId>` 或 `uid:<指纹>` |
| `tag_kind` | TEXT | `ndef`/`uid`；**UID 只读卡在列表显示「只读卡」而非「未写入」**（C31-B29 联动） |
| `created_at` | INTEGER | NOT NULL，毫秒 |
| `last_used_at` | INTEGER | 可空 |
| `use_count` | INTEGER | NOT NULL DEFAULT 0 |
| `written_at` | INTEGER | **NULL＝未写入**，毫秒＝最后成功写入时刻；**判定只读本列，不靠读标签反推**（C31：写入态是历史事实，反推不可行） |

- 聚合：`schema.dart` 顶部 `import 'schema/nfc.dart' as nf;`；`version` 47→**48** ＋版本注释；`createStatements` 尾部 `...nf.createStatements`；`migrations` 尾部 `...nf.mig`；静态常量 `tNfcCards = nf.tNfcCards` 上收（供 `export_units` 引用，照 `tMindmaps` 惯例）。
- **`mig` 键 47**（＝47→48 段）只含建表 ＋ 索引；**基础 DDL 与 mig 引同一份语句表**（照 `mindmap.dart` 的 `mindmapMig45Statements` 做法，避免两处各写一份漂移）。
- ⚠ **老口径语句表一字不加**（v45/v47 的既有教训：老库 44→48 直升不撞 duplicate column）。
- `journal_test` 的 **S6**（`version == migrations` 最高键 ＋ 1）与 **S7**（v47→v48 真升级建出 `nfc_cards`）跑绿。

### F1-1b · 日志与隐私

`uid:<指纹>` **永不进任何日志（含 debug 级）**——UID 可反查物理卡序列，比卡号更敏感；排障只看 `tag_kind` ＋ 指纹**后 4 位**。`tag_key` 原文亦不入日志。守护写进 `nfc_privacy_test`。

### F1-2 · 卡片 DAO（`lib/features/nfc/data/nfc_repo.dart`）

增／删／改名改目标／按 id 取／**按 `tag_key` 取**／列全表／记一次使用（`use_count+1`、`last_used_at=now`）＋两个 UPSERT：恢复备份按 **id** UPSERT（B18，不产生第二行）、`tag_key` 撞车按 UPSERT（B28）。全部有单测。

### F1-3 · 卡片管理屏 `/nfc`

一屏两卡：①「我的卡片」列表——图标块（**目标类图标**：导航／计时／阅读三种）＋名称＋**目标徽标 chip**（B42，用目标类名如「学习」「《书名》」）＋副文案「目标 · 用过 N 次」＋**「● 计时中」标记**（C23，与徽标**两枚共存**；判据同源读各模块库，**卡片自身不持久化计时态**）＋右侧写入态（**读 `written_at`**；UID 只读卡显示「只读卡」）｜②「贴卡行为」——**总闸 `nfc.enabled`（默认开）＋两个明细开关**。空态虚线行（点击＝新建）＋底部三行灰字（锁屏边界含「息屏贴卡会震动但不会触发」·B40／卡片选型 NTAG213/215＋外型＋0.5~2 元·B41／多机通用·B36）。

### F1-4 · 新建/编辑弹层（`sheetNfcEdit`）

名称（必填 ≤12 字）＋**目标三区块单选**（快捷动作 7 枚／计时分类 N 枚／阅读书目 N 枚；C28 **扁平、无二级弹层、三区块互斥**，默认选中第一区块第一项）；三态标题「新建卡片」/「编辑卡片」/「绑定这张卡」。**无图标选择器**（C13）。区块内无数据 → 该区块整块隐藏 ＋ 一行灰字（不显示空 chips）。

### F1-5 · 删除卡片（`sheetNfcDel`）

独立确认层（`lhConfirm`，**禁自造**）：标题「删除卡片」＋后果一行「原卡片会变成未绑定，重新绑定即可再用」；确认后行数／入口计数／列表三处随动。

### F1-6 · 我的入口行

「我的 › 外观与交互」组内「桌面与快捷方式」**下一行** ＝「NFC 卡片」，右侧显示卡片张数；不支持 NFC 的设备置灰不可点（B1）。

### F1-7 · 偏好持久化

`SettingsRepository` 加三键：`nfc.enabled`（默认 `true`·C42 总闸）／`nfc.confirmBeforeRun`（默认 `false`）／`nfc.promptUnbound`（默认 `true`）。照 `kDeskXxxKey` 独立读写口（**不进 UserSettings 整包**·照桌面批1 惯例），**不动既有键**；冷启动读回；测试环境不落真盘。

### 备份三处登记（§6.1 · C8-V3 · 缺一即视为未进包）

① **不加 `excludeTables`**（全量实表差集自然收）｜② **`export_units.dart` 新增 `ExportUnit(id:'nfc', label:'NFC 卡片', tables:[DbSchema.tNfcCards])`**——不登记则**子集备份不导出该表**（子集走差集法，未登记＝归属不明＝不收），而子集备份是 V1.66 批2 刚拍板的主推路径｜③ **`db_overview.dart` 补 `'nfc_cards': (label:'NFC 卡片', module:'NFC')`**。**三处由 `backup_scope_test` 逐条断言**。

---

## 3 · 本批明确不做（防越界）

- 写卡层 `sheetNfcWrite` 与七态状态机（**批2**）——本批**只登记组件号 LH-S42/LH-L17，不实现**
- 贴卡触发、去抖 3 秒、toggle、总闸在触发链的判定（**批2**）——本批**只落偏好键与读取，不接触发链**
- UID 轨 `enableReaderMode`（**批3**）
- `android/**` 任何改动（Manifest／`MainActivity`／`nfc_manager` 依赖）——**批2 才动**，故本批不跑 `kotlin_check.sh`
- 触觉锚（P1·待拍板）／卡片数量上限（P2·建议不设）／导出卡片链接清单（P3·建议不做）／标读完（P4·建议不做）／贴卡备注层（P5·建议不做）

---

## 4 · 收口链

1. **受影响测试**（面板清单·一文件一波·单轨）
2. **三刀变异自证**（锚点命中=1 → 回写 ＋ md5 断言）
3. **`node tools/nfc_proto_check.js`**（原型零改动，仍必跑防旁证漂移）
4. **`D:\app_workplace\python3.11\python.exe tools/doclint.py`**（含 `status_set.py --check` 守护七）
5. **`node tools/time52check.js` ＋ `node tools/ts8check.js`**——**本批不适用**（不动时间模块专版与 `lib/features/calendar/**`）
6. `flutter analyze` 零新增
7. 组件登记 `docs/UI组件规范.md`（LH-C24/LH-S41/LH-S42/LH-L17）
8. STATUS 改口（本批／批内增量档／未出编号＝攒 6156／下一站）＋ INDEX NFC 行 ＋ 变更日志 ≤3 行且 ≤400 字节
9. 文件级 pathspec 局部提交；**推送/发版另行取得产品同意**

---

## 5 · 风险与预判

| 风险 | 预判与处置 |
|---|---|
| **`export_units` 子集差集法**：漏登记 ⇒ 子集备份不含 `nfc_cards` ⇒ **换机后同一张物理标签不可用**（C8 的全部意义落空） | 刀3 专门钉这一处；`backup_scope_test` 三条逐条断言 |
| **`version` 与 `migrations` 不同步**：schema.dart:68 有实锤前例（6109 预发布漏改 version 仍 43 ⇒ 真机 onUpgrade 不触发 ⇒ 表缺列 ⇒ 读写全断） | 本批 version＋mig 同文件同段改；S6/S7 两条断言覆盖 |
| **`size_budget_test` 体量闸**：`schema/nfc.dart` ＋ 三个 presentation 件可能触登记 | 拆 part 而非塞大文件；闸红了按登记项处置，**不删断言** |
| **`architecture_test` R1**：`features/nfc/**` 禁 import `features/calendar|read/**` | 分类/书目/计时读取**一律经 `nfc_mounts.dart`**（本批只需两个读取转发口：`nfcCategoryOptions()`／`nfcBookOptions()`；两个 toggle 转发口属批2） |
| **12 位 base62 撞号** | `Random.secure()` ＋ 12 位空间（62^12≈3.2×10^21）碰撞可忽略；DAO 插入撞主键 → 重生成一次，仍撞则抛（**不静默覆盖别人的卡**） |
| **测试隔离** | `nfc_card_dao_test` 用真内存库（照 `mindmap` 域测试范式）；`nfc_settings_test` 须 override `sharedPreferencesProvider` |

---

## 6 · 偏离与待产品（批1 收口回填 · 2026-10-16）

### 6.1 规格偏离（实现与 §2 有出入处，以实现为准并登记）

| # | 规格处 | 实现 | 原因 |
|---|---|---|---|
| D1 | §2 F1-4 弹层函数名 `sheetNfcEdit` | 实际导出 `showNfcEditSheet`（返回 `bool?`） | 与桌面批1 的 `show*Sheet` 家族命名对齐；`docs/UI组件规范.md` LH-S41 已同步改口 |
| D2 | §2 F1-4 字段顺序「名称 → 目标」 | 绑定态多一行**卡号提示**置顶（只读展示 `maskedTagKey`，尾 4 位） | C1「标签只存编号」需让用户能核对贴的是哪张；脱敏串由 `maskedTagKey()` 单点产出 |
| D3 | §2 F1-7 三开关与 §6.1 备份登记 | 三开关**不进备份**（偏好走 kv `SettingsRepository`，与桌面批1 同口径），卡片数据才进 `export_units` | 偏好属设备侧行为，跨机恢复会造成「A 机关了总闸、B 机却生效」的错位 |
| D4 | §5 风险表「`nfc_settings_test` 须 override `sharedPreferencesProvider`」 | 未新建该文件，三开关口径并入 `nfc_card_dao_test` + 屏级 widget 用 `repoOverride` 注入缝覆盖 | 批1 三开关只落偏好读写，未落**行为分支**（真分支在批2 触发层），单独建文件会产生「只测 getter」的假覆盖 |

### 6.2 真实缺陷修复（实现过程中抓出，非本批引入但同批修掉）

- **`nfcBookExists` 漏软删过滤**（`lib/shared/linkage/nfc_mounts.dart`）：原实现只按 `id = ?` 查存在性，而**书删除是软删**（`deleted_at` 非空，行仍在表里）⇒ 已删的书仍被判定「目标有效」。后果不是报错而是**贴了没反应**（走到 `startSession` 才失败），用户侧表现为绑定失效无声无息。已补 `AND deleted_at IS NULL`，由 `nfc_linkage_test` 的「分类已删即失效」镜像用例抓出并钉住。
  ⚠ 同一模式请在**批2 的 `nfcCategoryExists`/计时分类存在性检查**上复核一遍——软删表不止 `books` 一张。

### 6.3 工装修复（非本批引入的闸缺陷，但会让本批结论失真）

- **`tools/nfc_proto_check.js` 固定 `wait(2800)` 在本机整片假红**：现象＝`RESULT FAIL 0/5` 且报 `setPage is not defined`／`NFC_CARDS is not defined`，但同轮 `PAGE ERRORS 0`、`node --check` 对 4 个内联 script 全过、`prototype/index.html` 经 `git hash-object` 与 HEAD 一致（**零本批改动**）。根因＝`index.html` 主脚本 167KB ＋ Tailwind CDN，固定 sleep 在本机不够。已改为**轮询等就绪**（判据 `typeof setPage === 'function' && typeof NFC_CARDS !== 'undefined'`，40 次 × 300ms 上限），复跑 14/14 全绿。
  **教训**：无头闸的等待策略必须是**就绪判据**，固定 sleep 只是概率——概率闸会产生「有时红有时绿」，而红的那些次会被误读成本批引入的回归。

### 6.4 待产品（批1 无法自决，攒到批2 前拍板）

| # | 待拍板 | 影响面 | 现状默认值 |
|---|---|---|---|
| P1 | **攒 6156 何时装机**（含 DB v47→v48 迁移，首装即迁移） | 装机后才有真机读数；**卸载＝清库**（不可回退） | 未构建，按攒批／产品令装机 |
| P2 | **批2 是否带 toggle 回执浮层**（C 系列裁决里 toggle 类目标「必回执」已定，但**回执形态**：toast / 屏内横幅 / 系统通知 未定） | 批2 写卡与触发的 UI 面 | 未实现，等拍板 |
| P3 | **UID 轨（批3）在锁屏态的兜底口径**：锁屏不可用是已定边界，但**锁屏时贴到标签的用户预期**（静默忽略 vs 提示「解锁后贴」）未写 | 批3 | 未实现，等拍板 |

### 6.5 本批交付实测读数（收口链九步全过）

- **受影响测试 11 波全绿**：`nfc_card_dao_test` 19／`backup_scope_test` 6／`nfc_linkage_test` 5／`nfc_privacy_test` 4 ＋ 复跑 `architecture_test`／`journal_test`（S6/S7 真升级路径）／`desktop_settings_test`／`widget_test`／`desktop_actions_test`／`size_budget_test`／`catch_log_guard_test`。
- **三刀变异自证全红其位、复原 md5 全等、零 MUT 残留**：刀1 `id` 主键降级 ⇒ 红 4 处；刀2 `isWritten` 恒 true ⇒ 红 2 处；刀3 摘掉 `export_units` 登记 ⇒ 红 2 处。
- **`node tools/nfc_proto_check.js` 14/14**（工装修后，见 §6.3）。
- **`flutter analyze lib` 零新增**（10 issues 全为存量，NFC 相关文件零问题）。
- **doclint PASS strict 全绿** ＋ `status_set.py --check` 绿；顺带消除两处体量黄灯：STATUS 9,881→**9,650 B**（黄线 9,677 内）、`docs/交接文档.md` 23,289→**17,209 B**（黄线 23,040 内，10-12~10-15 十条变更日志沉 `docs/archive/变更日志沉档-20261012-20261015.md`）。