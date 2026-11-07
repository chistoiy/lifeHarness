// 走查工装：解析 uiautomator dump，打印语义节点（可过滤 y 区间）。用法：
//   adb shell "uiautomator dump /data/local/tmp/ui.xml" >/dev/null && adb shell "cat /data/local/tmp/ui.xml" > .walkthrough/ui.xml
//   node tools/walk_nodes.js [minY] [maxY]
const fs = require('fs');
const s = fs.readFileSync('.walkthrough/ui.xml', 'utf8');
const minY = +(process.argv[2] ?? 0), maxY = +(process.argv[3] ?? 99999);
for (const m of s.matchAll(/<node[^>]*>/g)) {
  const tag = m[0];
  const d = ((tag.match(/content-desc="([^"]*)"/) || [])[1] || '').trim();
  const t = ((tag.match(/text="([^"]*)"/) || [])[1] || '').trim();
  const b = (tag.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/) || []).slice(1).map(Number);
  const label = (d || t).replace(/\n/g, '⏎').slice(0, 22);
  if (!label || b.length < 4) continue;
  if (b[1] < minY || b[1] > maxY) continue;
  console.log(`${label}  [${b.join(',')}]  tap(${(b[0] + b[2]) >> 1},${(b[1] + b[3]) >> 1})`);
}
