const fs = require('fs');
const f = 'docs/交接文档.md';
const src = fs.readFileSync(f, 'utf8');
const EOL = src.includes('\r\n') ? '\r\n' : '\n';
const lines = src.split(EOL);
const i = lines.findIndex((l) => l.startsWith('| 2026-09-28 | **预发布 v0.1.31-ai-fix1'));
if (i < 0) throw new Error('未定位 v0.1.31-ai-fix1 行');
const row =
  '| 2026-09-28 | **预发布 v0.1.32-reader 双端挂齐三包（阅读器 V1.53.2 轮5~5.4 Flutter 五批 · DB v27）** | ' +
  '① **流程**：产品负责人「原型已ok，推送预发布」→ 先双端推原型与整改提交，再把已确认的五轮一次性落码（保真红线：每轮先改 `prototype/index-bookshelf.html` 经逐屏确认，再动 `lib/features/read/**`）。' +
  '② **五批提交**：批A `f57d85c` 底栏五图标→三图标（目录/进度/外观）+ 轮3 三个内嵌面板升格为底部弹层（新 `reader_bottom_sheets.dart`）+ `ReaderCfg` 增 `bgTex/bgImg/dim`（新 `reader_bg.dart`：三层背景 + 三种纹理 CustomPainter + `brBarOf` 顶底栏随主题取色）+ 外观弹层补亮度/背景色板/**自绘色相·明度取色**/图片背景（选图后保存时拷进 `support/reader_bg/`）/淡化/首行缩进 + `readerOpenProvider` 计数在阅读页挂起全局计时条；' +
  '批B `308eadf` 目录抽屉「全部折叠/展开」（`_gcount` 在 build 内与行渲染同源算好，勿用 postFrame 回填）+ 跳章 `_jumpFrom` → 抽屉「‹ 回到刚才在读」，**删除正文悬浮 brBackPos 胶囊**；' +
  '批C `38117e0` 选区首尾可拖动手柄（`RenderParagraph.getBoxesForSelection` 定端点、就近段 `_charPosInPara` 命中、两端相遇自动互换）+ 工具条删「前扩/后扩」与 `_growSel`；' +
  '批D `290e929` **DB v27**：`book_sessions` 增 `from_chapter/to_chapter/from_pct/to_pct`，进页 `stampSessionStart`、退出 `endSession(to:,minSecs:)` 自动结算，门槛 `read.brMinSecs`（默认 30 秒·设置组「本地阅读器」chip 行，`initialSec` 索引是 **5** 不是 6）未达门槛整条删行不入账（进度照常更新）；' +
  '批E `9820289` 详情页本地整卡→信息行下方两行紧凑条 `brDstrip`（?/打开/检索/删除），「?」开 `sheetBrLocalInfo`（路径/体积/删除两口径/缓存态 + 清理缓存），非就绪态仍留批3.5 四态行。' +
  '③ **两个坑（已入 memory）**：a) **子级手柄只收到 `onPanDown` 收不到 update**——祖先 `GestureDetector` 的 `HorizontalDragGestureRecognizer` 在竞技场抢走手势，**在回调里 return 无效，必须按条件不挂识别器**（`onHorizontalDragEnd: _sel == null ? _onSwipe : null` + 手柄 `DragStartBehavior.down`）；' +
  'b) **SQL 串内不能写 `//` 注释**——把注释放进 `CREATE TABLE` 字符串里直接让全量测试建库报 `near "/": syntax error`，注释要放在 Dart 侧字符串外。' +
  '另修自引入回归：进度弹层 `onSeek` 与弹层内部各自 `/1000` 造成**双重换算**（拖到 98% 仍算成 0.098 → 位置不动），表现为「滑条拖了没反应」。' +
  '④ **版本号顺延**：v27 被本批 `book_sessions` 四列占用 → **V1.54 X-Ray 四表登记顺延 v28**（已改 `docs/需求清单.md` §V1.54 技术口径行）；`test/ai_usage_v153_test.dart` 的 `expect(DbSchema.version, 26)` 改 `>=26`（用例不钉死全局版本号，同 `50b540b` 口径）。' +
  '⑤ **验证与出包**：全量 `flutter test` **1467/1467 绿**（新增 `test/reader_v52_sess_test.dart` 8 例；`reader_preload_ui_test` 两处断言改走「?」弹层，因清理缓存入口随轮5.3 移位）；analyze 本批改面零 error/warning；' +
  '出包在 **`0379c4e` 的独立 worktree** `D:/dev_workplace/lh_rel_wt`（拷 `android/local.properties`，**并把钉住的 `flutter.versionName` 一起改成 0.1.32**，否则 APK 仍标旧名）；aapt 核对三包 `versionName=0.1.32`、versionCode 按 ABI 分流 6030/5030/8030、release 清单含 `INTERNET`；' +
  '注：worktree 产物里**没有 `libsqlite3.so`**（构建钩子按平台落 `build/native_assets/android/jniLibs`），Android 运行时走 sqflite 平台实现用系统 SQLite，装到 ea028260 后进程存活、crash 缓冲无记录，非缺陷。' +
  '⑥ **发布**：tag `v0.1.32-reader` 双端已推（GitHub 走 `ssh://…:443` 一次性 URL，HTTPS 443 当时不可达）；Gitee release **id=1172667**（`attach_files` 三次 201，列表接口资产 5＝三包 + 两个自动源包，size 字段恒为 undefined 属 Gitee API 现状），GitHub prerelease 三包字节与本地一致（36940314/33940620/39561749）；脚本 `tools/release_v0132.sh`（核对件必须 `gitee api … | node tools/check_gitee_assets.js <tag>` 管道喂）、正文 `tools/release_body_v0132.md`、说明 `docs/发布说明/release_notes_v0.1.32-reader.md`。' +
  '⑦ **待办**：**轮5④ 脚注/角标 + fixed-layout 精排包渲染范围仍未拍板**（A 只做角标↔注释跳转 / B 连精排检测降级 / C 暂缓；动 `epub_doc.dart` 锚点解析会连带 DocStore `snapVersion` 2→3 使快照与分页表作废）；TTS 仍延后；真机逐屏验收归产品负责人（已装 0.1.32 包）。 |';
lines.splice(i, 0, row);
const out = lines.join(EOL);
fs.writeFileSync(f, out, 'utf8');
const chk = fs.readFileSync(f, 'utf8').split(EOL);
const next = chk[i + 1];
if (!next.startsWith('| 2026-09-28 | **预发布 v0.1.31-ai-fix1'))
  throw new Error('插入吞掉下一行行首：' + next.slice(0, 40));
console.log('插入 OK · 下一行行首完好');
