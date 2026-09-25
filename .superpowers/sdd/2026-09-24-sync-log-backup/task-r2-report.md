# V1.41 真机验收反馈修复批 R2 — 执行报告（六项全收）

- 分支：`feat/m0-skeleton`（未 push，仅本地提交）
- 基线：c3417db（R2 批起点）
- 收尾回归：`flutter test test/sync_webdav_test.dart test/sync_s3_store_test.dart test/sync_page_ui_test.dart test/sync_diff_sheet_ui_test.dart test/log_page_test.dart test/architecture_test.dart test/sync_nav_back_test.dart` → **79/79 全绿**
- `flutter analyze` → 0 error / 3 warning（均为预存在基线：read_log_page unnecessary_cast、care_vaccine closeSheet unused、habit_auto_data unused_import；与 T19-A 记录一致，0 新增）
- 凭据特征串扫描（staged diff）：`Basic <b64>` / `AKIA…` / `ghp_` 等 **0 命中**；测试夹具仅公开 endpoint（dav.jianguoyun.com / s3.bitiful.net）与假值（`apppw-9`、`demo-apppw-7f2c`、`demo-sk-4a71c0f2`、`AKID7f****9f2c`）。

## 提交对照表

| 项 | 主题 | 提交 |
|---|---|---|
| ① | 坚果云 getUserInfo 容量解析 XML（FormatException 炸） | `1fe3322` |
| ②③ | S3 容量优雅降级 + 缤纷云 verify 文案增强 | `fab2c9b` |
| ⑥ | WebDAV 远端目录 404 容错 | `d83c20e` |
| ④ | 二级入口 context.go → push（返回不再退出 app） | `3f9b629` |
| ⑤ | S1 服务配置弹层四改 a-d | `4911107` |
| 原型 | index-sync s-svc-edit/p-sync 同步 + syncproto_check 断言 | `5907a35` |

## 逐项明细与红绿证据

### ① 坚果云容量解析炸（FormatException）— `1fe3322`
- 根因：`lib/core/sync/webdav_store.dart` `parseGetUserInfo` 用 `jsonDecode`，真机实测与参考实现（webdev_sync_app `quota_service.dart` parseUserinfo）均证明 getUserInfo 返回 XML（`<s:user xmlns:s="http://ns.jianguoyun.com">` 含 user/storage_quota、used_storage、collection[]{href,used_storage}）。
- 修法：改 XML 解析。本地 pub 镜像不便新增 package:xml 依赖，按 brief 允许的第二路线——**正则容忍元素/属性两形态**（`<(?:[\w.-]+:)?name>…` 与 `name="…"` 双兼容，命名空间前缀任意）；href 归一化（URL 解码+去尾斜杠+小写）保持。
- 红（`git show 1fe3322^:lib/core/sync/webdav_store.dart` 回退跑 sync_webdav_test）：
  - `quota：GET …/nsdav/getUserInfo 解析 XML 容量；collection href 归一化… [E] FormatException: Unexpected character (at character 1)` ——即真机同型崩溃复现
  - `parseGetUserInfo 容忍属性形态… [E] FormatException`
  - `parseGetUserInfo 异常格式返回 null 字段，绝不抛 FormatException [E] FormatException`
- 绿：修复版三夹具断言（真机 XML 样例三字段 / 属性形态 / 坏格式返回 null 不抛）全过，sync_webdav_test 19/19。

### ② S3 容量优雅降级 — `fab2c9b`
- 修法：`s3_store.dart` `quota()` 对 403（子账户无 ListAllMyBuckets 权限）与非 ListAllMyBuckets 回包形态返回 `CloudQuota(null, null)`（R9 第③态，UI 整行不渲染容量区），不 throw；`_quotaWarned` 集合按服务去重，AppLog warn 每服务每会话一次。
- 红（回退 fab2c9b^ 跑 sync_s3_store_test）：
  - `quota 403（子账户无 ListAllMyBuckets 权限）→ CloudQuota(null,null) 不抛 + AppLog warn 一次 [E]`
  - `quota 200 但非 ListAllMyBuckets 形态（<s:user>）→ null 不抛 + warn [E]`
- 绿：两条断言 + 原 ListAllMyBuckets 求和用例全过，sync_s3_store_test 15/15。

### ③ 缤纷云 verify 文案增强 — `fab2c9b`
- 修法：`_verifyFailMessage` 对 400 MissingFields / 403 输出「缤纷云：桶未解析或子账户无权限 · 请到控制台核对桶名并为子账户分配桶权限」。
- 红：`verify：GET /?list-type=2&max-keys=1 R2③：403 / 400 MissingFields → 文案含「分配桶权限」控制台指引 [E]`（fab2c9b^ 回退态）。
- 绿：同用例断言文案含「分配桶权限」通过。

### ④ 导航返回退出 app — `3f9b629`
- 根因：四处二级入口用 `context.go`——go 替换整导航栈，系统返回键直接退出 app。
- 修法：settings_page.dart（`/sync`、`/log`）与 sync_page.dart（`/sync/history`、`/log`）`context.go` → `context.push` 压栈，返回回来源页。
- 测试：真实 SyncPage 用例两条（进 /log、/sync/history 后 `tester.pageBack()` 回得到 /sync）+ `sync_nav_back_test.dart` 复刻 ShellRoute+顶层栈拓扑（push 返回语义 + 旧 go 替换栈反证）。
- 红（`git show 3f9b629^:…sync_page.dart` 回退跑 sync_page_ui_test）：
  - `导航返回退出修复（R2 项④：go→push） 从 /sync 进 /log：系统返回回 /sync 而非退出 app [E]`
  - `… 从 /sync 进 /sync/history：系统返回回 /sync [E]`
  - （注：sync_nav_back_test 为拓扑微测、导航函数注入式，不依赖源文件版本，故红证据走真实页面组用例，符合 brief「widget 测试」要求。）
- 绿：sync_page_ui_test 导航组 2/2 + sync_nav_back_test 3/3。

### ⑤ S1 服务配置弹层四改 — `4911107`
文件：`lib/features/settings/presentation/widgets/sync_sheets.dart`、`sync_page.dart`、`lib/shared/widgets/ui_kit.dart`（PillChip 增 `enabled`）。
- a) SK 回填+眼睛：`_loadSecretState` 编辑态从 vault 读回填 `_secret.text`（默认 obscure），行尾线性 `IconButton`（`edit-secret-eye`）切显隐；保存逻辑不变（非空即写 vault）。新增态无回填。
- b) 协议锁定：`!_isNew` 时两协议 pill `enabled:false`（PillChip 置灰 `.45` 透明+onTap 摘除），防编辑已建服务改协议覆盖同一条（真机「列表只有一个」根因）；新增可选。
- c) 常驻添加：sync_page 切换服务区底部常驻 `btn-add-svc-persistent`「添加服务」钮（过去仅空态有入口）。
- d) 输入法遮挡：**校准——本工程 Flutter 3.38.9 `showModalBottomSheet` 无 `resizeToAvoidBottomInset` 形参**（本地 SDK bottom_sheet.dart 源码 grep 0 命中，该形参仅 Scaffold 有），故等效兜底：弹层内容外层 `Padding(bottom: MediaQuery.viewInsetsOf(context).bottom)` + TextField `onTap → Scrollable.ensureVisible`。四处弹层中仅 S1 服务配置含 TextField（S2/S4/S6 无输入框、键盘不遮挡），遮挡改动脉落即 S1。
- 红（三 lib 文件回退 HEAD 复跑）：`Compilation failed … The getter 'enabled' isn't defined for the type 'PillChip'`（测试钉住新 API，缺失即红）。
- 绿：R2⑤a/b/c/d 五新用例（含新增态无回填对照、两服务列表两条+钮存在、模拟 `viewInsets bottom:360` 后 SK 框 `hitTestable`）全过，sync_page_ui_test 20/20；邻接 sync_diff_sheet_ui_test + backup_sheet_ui_test 16/16。

### ⑥ WebDAV 远端目录 404 容错 — `d83c20e`
- 修法：list 根 PROPFIND 404（ObjectNotFound）→ 返回空 `CloudListing` + AppLog info「云端目录不存在 · 首次上传将自动创建」；verify 404 → `ok=false` 文案「连接成功 · 云端目录不存在，首次同步将自动创建」；put 的 MKCOL 逐级建链回归不动。
- 红（1fe3322^ 回退态即无 404 容错）：
  - `list：根 PROPFIND 404（云端目录不存在）→ 空清单 + info 日志…（R2 项⑥） [E]`
  - `verify：404→ok=false 且文案「云端目录不存在，首次同步将自动创建」（R2 项⑥） [E]`
- 绿：两条 + MKCOL 链回归全过。

## 原型同步 — `5907a35`
- `prototype/index-sync.html`：s-svc-edit 加 SK 行尾眼睛钮（`.eye-btn` 双态线性 SVG，`toggleSecret` 切 password/text；password 字段 value 改假演示值示意「编辑态回填」）、默认编辑态两协议 pill `.locked` 置灰 + `#svcProvLockNote` 锁定提示 + `openSvcEdit('edit'|'add')` 双模；p-sync 切换服务区底部常驻「添加服务」行 `#rowAddSvc`。
- `tools/syncproto_check.js`：补 R2⑤a/b/c 正则断言 11 条 + jsdom 断言 3 条（jsdom 环境不可用按脚本内置退化口径走正则）。重跑 **RESULT=PASS（82 断言）**。教学句式 0 命中、emoji 码点 0 命中、内联处理器全定义、`$()` 目标 id 全存在均维持。

## 边界与守护
- 精确 `git add`：仅本批 9 个文件；`docs/影音游模块开发计划-20260922.md` 等其他会话脏文件与 untracked tmp/tools 残留一律未动、未暂存。
- 绝不 push：本地领先 origin 6 提交，未推送。
- R5 架构守护（architecture_test）绿：S3 私有字段口径未被容量改动破坏。
