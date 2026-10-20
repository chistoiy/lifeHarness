/* V1.54 UI 保真批（R14-7/8/12/13/14 落 Flutter）文档同步
   用法：node tools/doc_v154_sync.js */
const fs = require("fs");
function edit(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  const crlf = s.includes("\r\n"); // 命中按原文匹配，插入文本随文件行尾，避免混行尾
  const nl = (t) => (crlf ? t.replace(/\n/g, "\r\n") : t);
  for (const [old_, neu0, want, label] of pairs) {
    const neu = nl(neu0);
    const n = s.split(old_).length - 1;
    if (n !== (want || 1)) {
      console.error("!! [" + F + "][" + (label || "") + "] 命中 " + n + " 次，期望 " + (want || 1));
      process.exit(1);
    }
    s = s.split(old_).join(neu);
  }
  const before = fs.statSync(F).size;
  fs.writeFileSync(F, s);
  console.log("已更新 " + F + " " + before + " → " + Buffer.byteLength(s) + "B" + (crlf ? " (CRLF)" : ""));
}

const MARK_OLD = "**[原型已改·待逐屏确认]**";
const MARK_NEW = "**[原型已确认 · Flutter 已落地 · 待真机复验]**";
const CL = "docs/真机逐屏验收清单-20260929.md";

edit(CL, [
  [MARK_OLD, MARK_NEW, 5, "五处状态位"],
]);

// 表后追加本批 Flutter 落地记录（锚点＝R14 余项推进口径段首）
edit(CL, [
  ["**R14 余项推进口径（2026-09-29 拍板）**",
   "**R14-7/8/12/13/14 Flutter 落地记录（2026-09-29 续批）**：\n" +
   "① R14-7：`settings_page.dart` 11 个入口行 + 外观页 2 个 `_SetIc` 全部改线性图标（`_EntryRow` 的 `emoji` 形参已删，只留 `iconWidget`），\n" +
   "   标题/按钮装饰 emoji 前缀（🧭🎨🧩🔒）改纯文字；`recmg_page` 9 处、`notify_settings_page` 3 处段标题与行标题同步（措辞与原型一致）。\n" +
   "② R14-8：块视图顶部说明条改刻度读数「1 格 = N 分 · 全天 0-24」、右列标题改「分类」；仪表盘「长按任意卡片可编排顺序」删除；\n" +
   "   心情提示改为「选中后才出现的状态行」（未选不占位）。\n" +
   "③ R14-12：`UserSettings` 新增 `profileNick`/`profileBio`（**走设置项 KV，不建表不做迁移**），新增 `profile_edit_sheet.dart`\n" +
   "   （昵称必填 ≤12 走框架 errorText 就地报错、签名 ≤20、Flutter 3.38 起弹层自理 viewInsets 抬升）；头像首字/昵称/资料卡副行/今天页问候语四处联动。\n" +
   "④ R14-13：`stats_providers` 新增 `shelfBookCountProvider`（走 `booksProvider`，可被测试注入），第三格接真数；\n" +
   "   完成任务/连续记录天原本已是实算，保持。\n" +
   "⑤ R14-14：`_HeroCard` 四数改口径——今日待办＝截止日=今天（逾期与无期限另有入口，不混计）、完成环按今日 x/y、\n" +
   "   精力占比只算未完成、场安排＝「今日日程」列表条数；`today_schedule_card.dart`（自 dashboard 拆出）把事件与手动/计时块\n" +
   "   合成一份列表（事件回填块 `source=event` 不重复计，与日历轴视图同谓词）。\n" +
   "   拆出同时修掉两处旧缺陷：`D.events` 迁移后今日日程卡恒空的问题在 Flutter 侧不存在，但**事件回填块会被重复列示**；\n" +
   "   另修 `timeLabel` 的 `'$_hm(startMin)'` 写法（会被解析成函数 tear-off，渲染出 \"Closure: …\" 长串并把卡片撑爆 206px）。\n" +
   "   守门用例：`test/v154_ui_fidelity_test.dart` 8 例（含数据层联动与源码级文案守门）。\n\n" +
   "**R14 余项推进口径（2026-09-29 拍板）**"],
]);

edit("docs/交接文档.md", [
  ["| 2026-09-29 | **L2 日志批交付（通知 / AI / 图片三域）**",
   "| 2026-09-29 | **V1.54 UI 保真批：R14-7/8/12/13/14 落 Flutter** 用户放行后按已确认原型改实现：① 设置族三页 11 入口行 + 2 方格图标位改线性图标，`_EntryRow` 的 `emoji` 形参删除，标题/按钮装饰 emoji（🧭🎨🧩🔒📔📝🎬⚙️📅🕘）改纯文字； ② 块视图顶部说明条改刻度读数、右列标题改「分类」，仪表盘删「长按任意卡片可编排顺序」，心情提示改选中后才出现的状态行；③ `UserSettings` 加 `profileNick`/`profileBio`（设置项 KV，不建表不迁移）+ 新增 `profile_edit_sheet.dart`（空昵称走 errorText 就地报错 · 弹层自理 viewInsets），头像首字/昵称/副行/今天页问候语四处联动；④ `stats_providers` 新增 `shelfBookCountProvider` 接在册书籍；⑤ `_HeroCard` 四数口径对齐原型（今日待办=截止日今天 · 完成环按今日 x/y · 精力占比只算未完成 · 场安排＝今日日程列表条数），`today_schedule_card.dart` 自 dashboard 拆出并合并事件与手动/计时块（`source=event` 回填块不重复计）。顺带修 `timeLabel` 的 `'$_hm(x)'` tear-off 写法（渲染成 \"Closure:…\" 并撑爆卡片 206px）。测试：新增 `test/v154_ui_fidelity_test.dart` 8 例；跟随文案改动更新 `calendar_test`/`note_test`/`notify_test`/`widget_test`/`home_order_test`/`grid_block_test`/`dashboard_test` 断言（含把两处 SnackBar 断言改 `pollText`、末卡点击改「先滚到已构建再 ensureVisible」）。全量 run_gate 1671 例 0 失败。 | lib/features/settings/presentation/settings_page.dart, lib/features/settings/presentation/profile_edit_sheet.dart, lib/features/settings/presentation/recmg_page.dart, lib/features/settings/presentation/notify_settings_page.dart, lib/features/calendar/presentation/widgets/grid_day_view.dart, lib/features/dashboard/presentation/dashboard_page.dart, lib/features/dashboard/presentation/widgets/today_schedule_card.dart, lib/core/settings/user_settings.dart, lib/core/settings/settings_controller.dart, lib/core/settings/settings_repository.dart, lib/shared/linkage/stats_providers.dart, test/v154_ui_fidelity_test.dart, docs/真机逐屏验收清单-20260929.md |\n| 2026-09-29 | **L2 日志批交付（通知 / AI / 图片三域）**"],
]);

edit("docs/交棒话术-20260929-r14轮.md", [
  ["2. **R14-12/13/14 落 Flutter（原型已改·待确认后开发）**：",
   "2. **R14-12/13/14 落 Flutter** —— **[已交付 2026-09-29 续批]** 见 `docs/真机逐屏验收清单-20260929.md`「R14-7/8/12/13/14 Flutter 落地记录」；原条目内容如下："],
]);
