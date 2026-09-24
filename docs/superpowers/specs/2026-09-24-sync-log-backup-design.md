# LifeHarness 日志系统 · 本地备份 · 双云同步（坚果云 WebDAV + 缤纷云 S3）设计稿

| 项 | 值 |
|---|---|
| 日期 | 2026-09-24 |
| 状态 | 已与产品负责人逐节确认（四项口径拍板见 §0） |
| 来源需求 | ①日志系统 + 本地导出备份 + 从本地导入；②坚果云(WebDAV)/缤纷云(S3) 双云同步：上传下载、差异对比、差异同步、短时间控流配置、允许切换服务 |
| 参考资料 | `jiucaihezi/developSummary/protocol/cloud-storage-webdav-s3.md`（双协议接入规则，下称【云盘方案】）；`developSummary/engineering/app-log-and-error-reporting.md`（下称【日志方案】）；`developSummary/mobile/single-channel-request-scheduler.md`（下称【调度方案】） |
| 既有口径 | 需求清单 V1.18 数据安全条 / 计划书「sync/ 备份/加密」宿主内核 / 计划书风险表「冲突逐条人工选择、历史快照可回滚」/ 红线 7 呵护敏感数据同步排除（`care.syncExcluded`，默认开） |

## 0. 已拍板口径（2026-09-24 确认门）

1. **同步语义 = 备份目录差异同步**（不做数据库级双向记录合并；快照元数据带 DB 版本与逐表行数校验和，为将来记录级预留识别能力）。
2. **凭据只手动填进 App**：仅存 `flutter_secure_storage`（Keystore），不进仓库、不进任何本地配置文件、不进备份导出（【云盘方案】R11）。
3. **UI 走既定保真流程**：先出专版高保真原型 `prototype/index-sync.html`，逐屏验收定稿后再进 Flutter 实现；不动共享面 `index.html`。
4. **日志 = 全量方案**：内存环形缓冲 + 三处全局捕获 + 设置页一键复制；同时按天滚动落盘，可随备份导出、作为普通文件参与云同步差异。

## 1. 总体架构

```
lib/core/logging/    # 日志系统
  app_log.dart         AppLog：环形缓冲300条、毫秒时间戳、300ms节流通知、防递归+500ms限频
  file_log_sink.dart   按天滚动文件日志（级别过滤、保留天数可配、异步缓冲刷盘）
lib/core/backup/     # 本地备份 .lhbak
  lh_bak.dart          ZIP 容器：打包/解包/manifest 校验/AES-GCM 口令加解密
  backup_service.dart  导出（VACUUM INTO 快照+附件+可选日志）/ 导入恢复（先自动备份现库再整库替换）
lib/core/sync/       # 云同步子系统
  remote_store.dart    协议抽象：list/put/get/ensureDirectory/verify/quota + forConfig 分发
  webdav_store.dart    坚果云：PROPFIND Depth:1 逐层递归(限深10)、MKCOL(201/204/405)、getUserInfo 容量
  s3_store.dart        缤纷云：virtual-hosted、ListObjectsV2 一次递归翻页、ListAllMyBuckets 私有 *Bytes 用量
  s3_sigv4.dart        手写 SigV4（PayloadHash 三态；UNSIGNED-PAYLOAD 流式 PUT）
  http_gate.dart       唯一请求出口：按服务节流排队 + 429/503 退避重发（重发必重建请求对象）
  service_config.dart  多服务配置 + 激活切换；provider 字段缺省落回 WebDAV（向后兼容单测）
  diff_service.dart    差异引擎：两份过滤后 FileEntry 清单 → 四态 FileDiff；一致性三档
  sync_ledger.dart     同步台账：相对路径成功记录；残留判定（台账空不报残留）
  sync_orchestrator.dart 编排：单任务串行、勾选执行、进度/取消、历史摘要、后台执行
```

边界规则：

- 业务层零协议分支：`if (isS3)` 只允许出现在表单字段联动与 `RemoteStore.forConfig`（【云盘方案】R2）。
- 差异引擎与 UI 只消费 `FileEntry`/`FileDiff`，拿不到协议对象。
- 缓存键一律带服务 id 前缀 `{serviceId}|…`（清单/容量/差异/失败清单/台账）（D3）。
- 所有云端请求只能经 `HttpGate` 发出，无任何绕行入口（R10）；同一时刻只允许一个同步任务（P2/调度方案 R3）。

新增依赖：`http`、`archive`、`cryptography`、`flutter_secure_storage`、`file_picker`。

## 2. 日志系统

按【日志方案】R1~R13 落地：

- **记录**：`main()` 最先初始化，启动即记；环形缓冲 300 条超出丢最旧；每条 `HH:mm:ss.SSS` 毫秒时间戳。
- **错误**：`FlutterError.onError`、`PlatformDispatcher.instance.onError`、`ErrorWidget.builder` 三处全覆盖；上报防递归 + 500ms 合并限频；堆栈取前 14 行压单行。错误提示文案给出「详情见日志」行动指引（R12）。
- **通知与渲染**：独立 `ValueNotifier<int>` 版本信号，仅日志面板订阅；UI 渲染最近 120 条窗口，复制永远全量（R6/R11）。
- **落盘**：`FileLogSink` 写应用目录 `logs/`，按天一个文件、单文件封顶 5MB 滚动；级别 info/warn/error；保留天数在日志设置页配置（默认 14 天）。异步缓冲批量刷，不在 UI 线程同步写文件。
- **关键路径**：同步子系统的连接验证、差异结果、限流退避、每轮同步摘要同时进内存缓冲与文件日志，并写「同步历史」。关键路径日志不镜像全量进 logcat（R13）。
- **红线**：凭据不落日志——`Authorization` 头、SigV4 signature、口令一律脱敏后才允许进任何日志（含文件日志与错误上报）。

## 3. 本地备份 `.lhbak` 与导入

`.lhbak` = ZIP 容器：

| 成员 | 内容 |
|---|---|
| `manifest.json` | 应用版本、DB 版本、生成时间、逐表行数+校验和、排除表清单、是否加密、随机盐/nonce 参数 |
| `db.sqlite` | sqflite `VACUUM INTO` 一致性快照（不拷活文件） |
| `attachments/` | 各模块附件目录 |
| `logs/` | 可勾选附带的日志文件 |

- **导出**：默认写应用导出目录，文件名 `lifeharness_YYYYMMDD_HHmmss.lhbak`；沿用记账 L15 的 path_provider 目录注入模式保证可测。**支持用户自定义目录（2026-09-25 增补）**：S5 提供「另存到…」——先落应用目录再经系统 SAF「创建文档」（`flutter_file_dialog.saveFile`）由用户选任意位置，大文件不整读内存；Android 分区存储约束下不做常驻目录授权（不加 MANAGE_EXTERNAL_STORAGE，与隐私红线一致），上次成功目标位置 best-effort 记忆用于提示。可选口令：`cryptography` AES-GCM 加密 payload（PBKDF2 派生密钥，参数进 manifest）。
- **导入**：`file_picker`（SAF）选文件（Android 自动落应用缓存副本，按路径处理不整读进内存）→ manifest 校验（版本、表清单、校验和，坏包明确报错）→ 加密包提示输口令 → 二次确认 → **先把当前库自动备份一份**（`auto_before_restore_*.lhbak`，永不参与云同步）→ 整库替换 → 重启导航回首页并展示恢复报告。
- **口径**：导入 = 恢复到本机，不做记录级合并；本机直接导出的备份始终含全量数据（含呵护表）——红线 7 排除的是「同步」，不是「备份」。

## 4. 云同步

同步对象 = 本机**同步快照目录**：按「保留 N 份历史快照」配置生成的 `.lhbak` 序列（默认 N=5）+ 日志文件。快照在生成时应用 `care.syncExcluded`：置位则排除呵护表并把排除清单写入 manifest。

### 4.1 差异对比与差异同步

- 差异 = 本地快照目录清单 vs 远端目录清单（经忽略规则两侧同时剔除，D5）→ **仅本地 / 仅云端 / 已修改 / 一致** 四态，半屏弹层分组展示、逐条勾选、底部合计。
- 一致性三档（R8）：① 默认只比字节数；② 两端都有强 ETag 比 ETag；③ 严格 MD5 档默认关，仅当远端存在 32 位十六进制 ETag 时可选开。绝不使用 mtime。
- 上传/下载按勾选执行；「仅云端」条目下载完成后引导走 §3 导入恢复。**V1 删除不传播**，冲突默认双留、永不静默丢弃；台账按 D2 维护（`onlyRemote` 不判残留、台账空不报残留），镜像删除只作为将来扩展点（E5），本期不提供入口。
- 批量原子性沿用计划书既有口径：先附件→后 DB→成功标记，无标记下次续传。

### 4.2 控流配置（短时间控流）

- 唯一出口 `HttpGate`：按**服务**配置的 `requestIntervalMs` 排队，档位 **150 / 300 / 800ms**（默认 300），设置页明示当前档位与含义（请求间隔，非全局带宽）。
- 429/503 退避：优先解析 `Retry-After`（秒数与 HTTP-date 两形态），否则 2s→4s→8s，单次等待上限截断 30s，最多重发 3 次；**重发必用工厂重建请求对象**（流式体只读一遍 + SigV4 日期参与签名）。
- 同目录 60s 清单缓存、容量 5min 缓存、MKCOL 进程内记忆；列举/查询超时 20–30s、传输超时 10min 分档；传输全程流式（上传 `StreamedRequest`，下载 pipe 到 sink，喂数据独立 Future 防死锁）；严格校验摘要 64KB 分块读。
- 自动同步：仅 Wi-Fi 可选开关（默认关），每天节流；手动同步不受限。

### 4.3 服务与切换

- `ServiceConfig` 列表 + 单一「当前激活」，支持两条内置模板（坚果云 WebDAV / 缤纷云 S3）与自定义条目；表单字段与标签随协议切换（账户/应用密码 ↔ Access Key/Secret Key）（R3）；跨服务允许同名云端目录，唯一性按「服务 id + 目录名」判定。
- 凭据读写：明文 prefs 的 `authCode` 恒为空串占位，真实凭据按 `sync_secret_{serviceId}` 进保险箱；**只有写保险箱成功才清明文侧**，失败保留原值并记日志（R11）；widget 测试注入内存版保险箱。
- 连接验证：WebDAV `PROPFIND Depth:0`；S3 `GET /?list-type=2&max-keys=1`。响应一律 `utf8.decode(bodyBytes)`（R12）。
- 容量三态（R9）：坚果云有配额（`/nsdav/getUserInfo`，collection href 归一化）；缤纷云只有已用量（ListAllMyBuckets 私有 `*Bytes` 求和，配额恒 null）；全 null 也能只显「已用」。
- 缤纷云写死参数：endpoint `https://s3.bitiful.net`、region `cn-east-1`、virtual-hosted 寻址、不接 AWS SDK（丢私有字段且已停止支持）；不使用 `?stat`、不使用服务端限速头。

## 5. UI 与原型先行

新建专版原型 `prototype/index-sync.html`（模块屏只在副本，共享面改动走变更单回灌），屏幕清单：

| # | 屏/弹层 | 要点 |
|---|---|---|
| P1 | 数据与同步主页 | 当前服务卡（协议/容量三态/最近同步摘要）、服务切换列表、备份入口 |
| S1 | 服务配置编辑弹层 | provider 切换字段联动、凭据输入与「已存入保险箱」反馈、删除服务清孤儿密钥 |
| S2 | 连接验证状态 | 通过 / 凭据错 / 网络失败三态提示，文案随协议切换 |
| S3 | 差异对比半屏 | 四态分组 + 逐条勾选 + 合计；「仅云端」行下载入口 |
| S4 | 同步进度半屏 | 当前文件、序号总数、被限流等待提示（含剩余秒数）、取消 |
| P2 | 同步历史列表 | 每轮摘要（时间/服务/传输量/结果），点击跳日志 |
| P3 | 日志查看页 | 120 条窗口、级别过滤、一键复制全量、保留天数设置 |
| S5 | 备份导出/导入半屏 | 范围勾选（含附带日志）、口令设置、**目标位置：应用目录（默认）/另存到…（SAF）**、导入校验报告、恢复二次确认 |
| S6 | 控流设置弹层 | 节流档位 150/300/800、历史快照份数 N、仅 Wi-Fi 自动开关 |

交互约束沿用既定规范：无教学性文案、无 emoji 图标、时间/数值选择用就地滚轮。设置页现有「数据与同步」占位行在原型定稿后改为真实路由。（注：本表弹层编号 S1~S6 沿用项目弹层 S 前缀惯例，与 S3 协议无关，协议处一律写全称「缤纷云 S3」。）

## 6. 测试策略

- **协议层单测（不真连公网）**：SigV4 固定向量（含 query 排序、path 分段编码、UNSIGNED-PAYLOAD 三态）；WebDAV XML 解析中文/空格文件名；`same()` 三档判定；HttpGate 退避（注入假响应断言请求工厂 ≥2 次、Retry-After 两形态）；S3 翻页聚合与目录占位对象剔除；MKCOL 405 记忆。
- **同步层单测**：台账残留判定（空台账不报残留）；缓存键带服务 id；`care.syncExcluded` 排表联动；旧配置缺 provider 字段落回 WebDAV（R4）。
- **备份层单测**：manifest 校验（坏版本/坏校验和/口令错三类拒绝路径）；导出目录注入；恢复前自动备份存在性。
- **日志单测**：环形上限、节流合并、防递归限频、堆栈截断、复制全量 vs 显示窗口。
- **Widget 测试**：新用例一律拆分独立文件（防 isolate 污染挂死）；secure storage/目录路径均注入 fake；SnackBar 用 `helpers.clearToasts` 小步 pump。
- **真机联调（凭据由产品负责人手动填入）**：双服务连接验证、中文文件名上下载、差异四态截图、容量三态截图、限流退避日志取证；逐屏验收按原型对照。

## 7. 安全与红线

- 隐私红线升版口径：应用内除**用户配置的 WebDAV/S3 同步**外无任何网络请求；密码/应用密钥/AK/SK 不落日志、不进备份导出、不进仓库。
- 调试凭据（坚果云应用密码、缤纷云 AK/SK、邮箱、桶名）不写进任何仓库文件；每次 commit 前对暂存区做特征串全文扫描，push 前再扫一遍并先征得产品负责人同意（Gitee/GitHub 双通道同样适用）。
- 备份文件落在公共目录故永不含凭据；导入换机后服务配置显示「待填凭据」标记。

## 8. 文档与版本

- 需求清单新增 **V1.41「日志系统 · 本地备份 · 双云同步」** 段（含缤纷云 S3 对原「仅 WebDAV」口径的扩展、第十节修订记录追加）；开发计划书同步子系统节勾销「未建」并更新技术选型表（S3 手写 SigV4 入表）；交接文档进展表 + 变更日志行（3~5 行要点 + 提交号引用）。
- 本设计稿随批 0 提交入库（本地提交，push 另行确认）。

## 9. 批次划分（实施顺序）

| 批 | 内容 | 出口判据 |
|---|---|---|
| 批0 | 本设计稿 + 需求 V1.41 升版 + 专版原型 `index-sync.html` 全量 | 逐屏验收定稿 |
| 批1 | 日志系统（core/logging + 日志查看页 + 复制 + 落盘 + 设置） | 日志单测/Widget 全绿 |
| 批2 | 本地备份 .lhbak（导出/导入/恢复/口令） | 备份三类拒绝路径单测绿 |
| 批3 | 协议层（RemoteStore + WebDAV + S3/SigV4 + HttpGate + 服务配置/切换 UI 壳） | 假 store 单测绿；真机双服务连接验证通过 |
| 批4 | 差异引擎 + 台账 + 同步编排 + 控流配置 | 差异四态与退避单测绿；真机小集上下载 |
| 批5 | 同步主页/历史/进度弹层全量接线 + syncExcluded 联动 + 收口四件套 + 预发布 | 真机逐屏验收；双端挂包（含 Gitee 三包附件核对） |

批内遵循两档提速流程（增量批只跑受影响组，收口批全套 + `flutter analyze`）。
