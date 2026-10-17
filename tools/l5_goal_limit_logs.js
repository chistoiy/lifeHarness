/* L5 补丁二 · 目标「每期上限」三处拒绝各留一条 warn（只加日志，零行为改动）
   为什么单拆一个脚本：`if (existing >= kMaxOkrPerPeriod) return null;` 在文件里出现 3 次，
   必须各带上文才唯一——UI 只 toast 一次，日志页要能查到是哪个入口、期名与当前数量。
   用法：node tools/l5_goal_limit_logs.js（已执行过则预检整体中止，不会重复落笔） */
const fs = require("fs");
const F = "lib/features/goals/data/goals_repository.dart";

function load() {
  const s = fs.readFileSync(F, "utf8");
  const crlf = s.includes("\r\n");
  return { s, nl: (t) => (crlf ? t.replace(/\n/g, "\r\n") : t) };
}

const edits = [
  ["    final existing = (await db.query(DbSchema.tGoals,\n" +
   "            where: 'period = ?', whereArgs: [g.period]))\n" +
   "        .length;\n    if (existing >= kMaxOkrPerPeriod) return null;\n",
   "    final existing = (await db.query(DbSchema.tGoals,\n" +
   "            where: 'period = ?', whereArgs: [g.period]))\n" +
   "        .length;\n    if (existing >= kMaxOkrPerPeriod) {\n" +
   "      AppLog.add('目标新建被拒：${g.period} 已有 $existing 个 O · '\n" +
   "          '每期上限 $kMaxOkrPerPeriod', level: LhLevel.warn);\n" +
   "      return null;\n    }\n", 1],

  ["    final existing = (await db.query(DbSchema.tGoals,\n" +
   "            where: 'period = ?', whereArgs: [toPeriod]))\n" +
   "        .length;\n    if (existing >= kMaxOkrPerPeriod) return null;\n",
   "    final existing = (await db.query(DbSchema.tGoals,\n" +
   "            where: 'period = ?', whereArgs: [toPeriod]))\n" +
   "        .length;\n    if (existing >= kMaxOkrPerPeriod) {\n" +
   "      AppLog.add('目标单个复制被拒：$toPeriod 已有 $existing 个 O · '\n" +
   "          '每期上限 $kMaxOkrPerPeriod', level: LhLevel.warn);\n" +
   "      return null;\n    }\n", 1],

  ["    final existing =\n" +
   "        (await db.query(DbSchema.tGoals, where: 'period = ?', whereArgs: [to])).length;\n" +
   "    if (existing >= kMaxOkrPerPeriod) return null;\n",
   "    final existing =\n" +
   "        (await db.query(DbSchema.tGoals, where: 'period = ?', whereArgs: [to])).length;\n" +
   "    if (existing >= kMaxOkrPerPeriod) {\n" +
   "      AppLog.add('复盘 Try 转下季草稿被拒：$to 已有 $existing 个 O · '\n" +
   "          '每期上限 $kMaxOkrPerPeriod', level: LhLevel.warn);\n" +
   "      return null;\n    }\n", 1],
];

const pre = [];
for (const [old0, , want] of edits) {
  const { s, nl } = load();
  const n = s.split(nl(old0)).length - 1;
  if (n !== want) {
    console.error("!! 预检失败 命中 " + n + " 期望 " + want + "\n   " + old0.split("\n")[0].trim());
    process.exit(1);
  }
}
const { s, nl } = load();
let out = s;
for (const [old0, new0] of edits) out = out.split(nl(old0)).join(nl(new0));
fs.writeFileSync(F, out);
console.log("OK  目标上限三处 warn 已落（+" + (out.length - s.length) + "B）");
