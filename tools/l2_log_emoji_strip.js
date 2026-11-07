/* L2 附项：日志文本去 emoji（日志页即 UI，按「UI 禁 emoji」硬规矩；级别标记 [W]/[E] 已表意）
   只改 AppLog.add/reportError 的**文案前缀**，不动任何逻辑。命中数逐处断言。
   用法：node tools/l2_log_emoji_strip.js */
const fs = require("fs");
const targets = [
  ["lib/core/media/media_hash_migrator.dart", 1],
  ["lib/main.dart", 1],
  ["lib/core/logging/error_capture.dart", 3],
  ["lib/core/sync/snapshot_service.dart", 1],
  ["lib/core/sync/s3_store.dart", 2],
  ["lib/core/sync/cloud_clean_service.dart", 3],
  ["lib/features/settings/presentation/sync_page.dart", 1],
];
let total = 0;
for (const [f, want] of targets) {
  let s = fs.readFileSync(f, "utf8");
  const lines = s.split("\n");
  let n = 0;
  const out = lines.map((l) => {
    if (!/AppLog\.\w+\(/.test(l)) return l;
    const t = l.replace("⚠️ ", "").replace("‼️ ", "");
    if (t !== l) n++;
    return t;
  });
  if (n !== want) {
    console.error("!! " + f + " 命中 " + n + " 处，期望 " + want + " 处，整批中止");
    process.exit(1);
  }
  fs.writeFileSync(f, out.join("\n"));
  total += n;
  console.log("  " + f + "：" + n + " 处");
}
console.log("已去 emoji 前缀 " + total + " 处");
