/* 批D1 续（R14-7）：记录管理页 + 提醒通知页标题装饰 emoji 前缀摘除
   措辞与已确认原型 prototype/index.html 对齐（p-sub-recmg / p-sub-notify）。
   用法：node tools/v154_settings_text.js */
const fs = require("fs");
let hits = 0;
function apply(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  const before = s.length;
  for (const [old_, neu, label] of pairs) {
    const n = s.split(old_).length - 1;
    if (n !== 1) {
      console.error("!! [" + F + "][" + label + "] 命中 " + n + " 次（要求 1）");
      process.exit(1);
    }
    s = s.replace(old_, neu);
    hits++;
  }
  fs.writeFileSync(F, s);
  console.log("  " + F + "：" + pairs.length + " 处 · " + before + " → " + s.length);
}

apply("lib/features/settings/presentation/recmg_page.dart", [
  ["const _Label('📔 日记'),", "const _Label('日记'),", "sec-diary"],
  ["const _Label('📝 笔记'),", "const _Label('笔记'),", "sec-note"],
  ["title: '🕘 版本恢复方式',", "title: '版本恢复方式',", "row-restore"],
  ["title: '🗂 文件夹管理',", "title: '文件夹管理',", "row-folders"],
  ["trailing: '记录 › 笔记 › 📂',", "trailing: '记录 › 笔记',", "row-folders-trailing"],
  ["context, '在 记录 › 笔记 点 📂 打开树侧栏管理（增删改/嵌套）'",
   "context, '在 记录 › 笔记 tab 打开树状侧栏管理（增删改/拖动嵌套）'", "row-folders-toast"],
  ["const _Label('📚 阅读'),", "const _Label('阅读'),", "sec-read"],
  ["const _Label('🎬 影音游'),", "const _Label('影音游'),", "sec-media"],
  ["const _Label('⚙️ 通用'),", "const _Label('通用'),", "sec-general"],
]);

apply("lib/features/settings/presentation/notify_settings_page.dart", [
  ["_row(context, '📅 日程与任务提醒',", "_row(context, '日程与任务提醒',", "row-event"],
  ["_row(context, '📔 日记复盘',", "_row(context, '日记复盘',", "row-diary"],
  ["_row(context, '🔁 习惯提醒',", "_row(context, '习惯提醒',", "row-habit"],
]);
console.log("合计 " + hits + " 处");
