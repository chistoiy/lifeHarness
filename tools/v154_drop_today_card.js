/* 批D4：从 dashboard_page.dart 摘除已拆出的 _TodayScheduleCard 类（含其文档注释块）
   定位：类声明行起、按花括号配平到类结束；摘完断言无残留引用。
   用法：node tools/v154_drop_today_card.js */
const fs = require("fs");
const F = "lib/features/dashboard/presentation/dashboard_page.dart";
const src = fs.readFileSync(F, "utf8");
const lines = src.split("\n");
const ci = lines.findIndex((l) => l.startsWith("class _TodayScheduleCard extends ConsumerWidget {"));
if (ci < 0) { console.error("!! 找不到 _TodayScheduleCard 类声明"); process.exit(1); }
let hi = ci;
while (hi - 1 >= 0 && /^\s*\/\/\//.test(lines[hi - 1])) hi--; // 连文档注释一起摘
let depth = 0, ei = -1;
for (let j = ci; j < lines.length; j++) {
  for (const ch of lines[j]) { if (ch === "{") depth++; else if (ch === "}") depth--; }
  if (depth === 0 && j > ci) { ei = j; break; }
}
if (ei < 0) { console.error("!! 花括号未配平"); process.exit(1); }
const removed = lines.slice(hi, ei + 1).join("\n");
if (!/_TodayScheduleCard/.test(removed) || removed.length < 800 || removed.length > 4500) {
  console.error("!! 摘除范围异常（" + removed.length + " 字节）");
  process.exit(1);
}
lines.splice(hi, ei - hi + 1);
let out = lines.join("\n").replace(/\n\n\n+/g, "\n\n");
if (/_TodayScheduleCard/.test(out)) { console.error("!! 仍残留引用"); process.exit(1); }
fs.writeFileSync(F, out);
console.log("已摘除 " + (ei - hi + 1) + " 行 / " + removed.length + " 字节 · " + src.length + " → " + out.length);
