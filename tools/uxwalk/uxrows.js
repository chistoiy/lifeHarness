// U1 现场读取器：node tmp/uxrows.js <xml> <cmd> [args...]
//   rows            → 每行 "y1<TAB>y2<TAB>label"（高度≥20px 的节点，按 y1 升序）
//   navtop          → 底栏顶边 y（取 label 恰为 今天/待办/时间/记录/我的 的节点最小 y1）
//   lowest <navTop> → 底栏之上最贴底的一行："cx,cy<TAB>label"
const fs = require("fs");
const xml = fs.readFileSync(process.argv[2], "utf8");
const cmd = process.argv[3];
const nodes = [];
for (const m of xml.matchAll(/<node[^>]*>/g)) {
  const tag = m[0];
  const t = ((tag.match(/text="([^"]*)"/) || [])[1] || "").trim();
  const d = ((tag.match(/content-desc="([^"]*)"/) || [])[1] || "").trim();
  const label = (t || d).replace(/\s+/g, " ");
  const b = (tag.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/) || []).slice(1).map(Number);
  if (!b.length || !label) continue;
  nodes.push({ x1: b[0], y1: b[1], x2: b[2], y2: b[3], label });
}
const TABS = ["今天", "待办", "时间", "记录", "我的"];
if (cmd === "rows") {
  nodes.filter(n => n.y2 - n.y1 >= 20).sort((a, b) => a.y1 - b.y1)
    .forEach(n => console.log(`${n.y1}\t${n.y2}\t${n.label.slice(0, 24)}`));
} else if (cmd === "navtop") {
  // 底栏顶边＝tab 节点里 y1 最大者（页面标题也可能叫「我的」，取靠下的那个）
  const ys = nodes.filter(n => TABS.includes(n.label)).map(n => n.y1);
  console.log(ys.length ? Math.max(...ys) : -1);
} else if (cmd === "gap") {
  // gap <navTop> → 底栏之上最贴底节点的 y2 与底栏顶边的差值（负数＝压在底栏上）
  const navTop = Number(process.argv[4]);
  const cands = nodes.filter(n => (n.y2 - n.y1) >= 20 && n.y1 < navTop && !TABS.includes(n.label));
  cands.sort((a, b) => b.y2 - a.y2);
  const n = cands[0];
  console.log(n ? `${n.y2 - navTop}\t${n.label.slice(0, 20)}` : "");
} else if (cmd === "lowest") {
  const navTop = Number(process.argv[4]);
  // 只看底栏之上的行；排除分组标题类（长度过短且无右侧读数的难判，这里按 y2 最接近 navTop 取）
  const cands = nodes.filter(n => (n.y2 - n.y1) >= 20 && n.y2 <= navTop && !TABS.includes(n.label));
  cands.sort((a, b) => b.y2 - a.y2);
  const n = cands[0];
  console.log(n ? `${((n.x1 + n.x2) >> 1)},${((n.y1 + n.y2) >> 1)}\t${n.label.slice(0, 24)}` : "");
} else if (cmd === "findtail") {
  // findtail <name> → 磁贴类合并节点（label 以「<name>」结尾）的中心
  const want = process.argv[4];
  const n = nodes.find(x => x.label.endsWith(want) && x.label !== want);
  console.log(n ? `${((n.x1 + n.x2) >> 1)},${((n.y1 + n.y2) >> 1)}` : "");
} else if (cmd === "inc") {
  // inc <片段> → 首个「label 含该片段且高度≥20px」的节点中心（行卡类合并标签用这个）
  const want = process.argv[4];
  const n = nodes.find(x => x.label.includes(want) && x.y2 - x.y1 >= 20);
  console.log(n ? `${((n.x1 + n.x2) >> 1)},${((n.y1 + n.y2) >> 1)}` : "");
} else if (cmd === "at") {
  // at <label> → 首个 label 完全相符的节点中心；底栏 tab 常带角标前缀（"2 待办"），
  // 完全匹配落空时回落「以该词结尾且带前缀」的节点。
  const want = process.argv[4];
  let n = nodes.find(x => x.label === want);
  if (!n) {
    // 回落：取「以该词结尾」里最靠下的一枚（底栏 tab 优先于卡片区同名片段）
    const cands = nodes.filter(x => x.label.endsWith(want));
    cands.sort((a, b) => b.y1 - a.y1);
    n = cands[0];
  }
  console.log(n ? `${((n.x1 + n.x2) >> 1)},${((n.y1 + n.y2) >> 1)}` : "");
} else if (cmd === "sig") {
  console.log(nodes.map(n => n.label).join("|").slice(0, 400));
}
