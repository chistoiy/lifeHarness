/* R14-14 补丁③：今日心情卡的初始教学文案改为「选中后才出现的状态提示」
   用法：node tools/proto_dash_hero3.js */
const fs = require("fs");
const F = "prototype/index.html";
let s = fs.readFileSync(F, "utf8");
const before = s.length;
function rep(old, neu, label) {
  const n = s.split(old).length - 1;
  if (n !== 1) { console.error("!! [" + label + "] 命中 " + n + " 次（要求 1 次）：" + old.slice(0, 70)); process.exit(1); }
  s = s.replace(old, neu);
}
rep(
  "<div id=\"moodTip\" class=\"text-[11px] text-slate-400 text-center mt-1\">点一下，记录今天的心情</div>",
  "<div id=\"moodTip\" class=\"text-[11px] text-slate-400 text-center mt-1 hidden\"></div>",
  "moodTip-static"
);
/* 注意：目标串里有 `${...}`，必须放在双引号字符串中（模板字面量会就地插值） */
rep(
  "$('#moodTip').innerHTML=`已记录：<b>${b.dataset.m}</b> · 将进入今晚日记与心情趋势（联动 L4）`; });",
  "const mt=$('#moodTip'); mt.innerHTML=`已记录：<b>${b.dataset.m}</b> · 将进入今晚日记与心情趋势（联动 L4）`; mt.classList.remove('hidden'); });",
  "moodTip-js"
);
fs.writeFileSync(F, s);
console.log("体积 " + before + " → " + s.length + "（" + (s.length - before) + "）");
