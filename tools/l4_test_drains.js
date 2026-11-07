/* L4 收尾排空：给「会走日志的模块」的每个 testWidgets 末尾补 drainLogTimer
   背景：AppLog 的 300ms 节流 Timer 在 FakeAsync 下不随帧到期，L4 起仓库写入
   会落 key 行 → 末次动作在断言之后的用例收尾判「A Timer is still pending」。
   用法：node tools/l4_test_drains.js [相对路径...]（缺省=下面 files 列表）
   护栏：命中数打印 + 文件体积变化 + 已含 drainLogTimer 的块跳过。 */
const fs = require("fs");

const files = process.argv.slice(2).length
    ? process.argv.slice(2)
    : [
        "test/care_event_sheet_test.dart",
        "test/care_baby_day_test.dart",
        "test/care_baby_page_test.dart",
        "test/care_cycle_page_test.dart",
        "test/care_growth_page_test.dart",
        "test/care_stats_page_test.dart",
        "test/care_vaccine_milestones_test.dart",
        "test/habit_aux_page_test.dart",
        "test/habit_auto_page_test.dart",
        "test/habit_backfill_page_test.dart",
        "test/habit_detail_page_test.dart",
        "test/habit_settings_page_test.dart",
        "test/habit_stat_page_test.dart",
        "test/habits_page_test.dart",
        "test/journal_test.dart",
        "test/note_test.dart",
        "test/inbox_test.dart",
      ];

let total = 0;
for (const f of files) {
  if (!fs.existsSync(f)) { console.error("!! 缺文件 " + f); process.exit(1); }
  const src = fs.readFileSync(f, "utf8");
  const EOL = src.includes("\r\n") ? "\r\n" : "\n";
  const L = src.split(/\r?\n/);
  const out = [];
  let inserted = 0;
  for (let i = 0; i < L.length; i++) {
    const line = L[i];
    // 测试块结束：同层 "});"，回溯同层最近的关键字行
    let drained = false;
    if (/^(\s*)\}\);\s*$/.test(line)) {
      const ind = line.match(/^(\s*)/)[1].length;
      if (ind === 2 || ind === 4) {
        let k = i - 1, head = null;
        for (; k >= 0; k--) {
          const m = L[k].match(/^(\s*)(testWidgets|setUp|tearDown|test|group)\b/);
          if (!m || m[1].length !== ind) continue; // 同层才可比
          head = L[k];
          break;
        }
        if (head && /^\s*testWidgets\(/.test(head) && /async \{/.test(head) &&
            !/drainLogTimer/.test(L[i - 1] || "")) {
          // 补在收尾 "});" **之前**（用例体最后一条语句）
          out.push(" ".repeat(ind + 2) +
              "await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer");
          inserted++;
          drained = true;
        }
      }
    }
    out.push(line);
    if (drained) continue;
  }
  if (inserted) {
    fs.writeFileSync(f, out.join(EOL));
    total += inserted;
    console.log("OK  " + f + "  补 " + inserted + " 处");
  } else {
    console.log("--  " + f + "  无需补");
  }
}
console.log("共补 " + total + " 处");
