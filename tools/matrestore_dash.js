const fs = require('fs');
const PROTO = 'D:/dev_workplace/flutter_te/lifeHarness/prototype/';
const base = fs.readFileSync(PROTO + 'index.html', 'utf8');
let h = fs.readFileSync(PROTO + 'index-maternity_bady.html', 'utf8');
const must = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exit(1); } };

// 1) 恢复原 p-dashboard 段
const secStart = '    <section id="p-dashboard"', secEnd = '\n    </section>';
const b0 = base.indexOf(secStart); const b1 = base.indexOf(secEnd, b0);
must(b0 > 0 && b1 > b0, 'base dashboard section');
const origDash = base.slice(b0, b1 + secEnd.length);
const h0 = h.indexOf(secStart); const h1 = h.indexOf(secEnd, h0);
must(h0 > 0 && h1 > h0, 'copy dashboard section');
h = h.slice(0, h0) + origDash + h.slice(h1 + secEnd.length);

// 2) 恢复原 renderDash + DASH_IDS
const jsA = '/* ================= 仪表盘', jsB = "'grid'];", jsB2 = "'priv'];";
const j0 = base.indexOf(jsA + ' ================= */');
const j1 = base.indexOf(jsB, j0);
must(j0 > 0 && j1 > j0, 'base renderDash block');
const origJs = base.slice(j0, j1 + jsB.length);
const k0 = h.indexOf(jsA + '（母婴专版'); must(k0 > 0, 'copy renderDash start');
const k1 = h.indexOf(jsB2, k0); must(k1 > k0, 'copy renderDash end');
h = h.slice(0, k0) + origJs + h.slice(k1 + jsB2.length);

// 3) TITLES 还原
const tNew = "'p-dashboard':['母婴呵护','09-19 · 她与宝宝的一天'],";
const tOld = "'p-dashboard':['今天','9月19日 周六 · 第55天记录'],";
must(h.includes(tNew), 'titles entry');
h = h.replace(tNew, tOld);

// 4) 去掉 renderBabyToday 里追加的 renderDash()
h = h.replace("function renderBabyToday(){const el=$('#babyToday');if(!el)return;renderDash();",
  "function renderBabyToday(){const el=$('#babyToday');if(!el)return;");

// 校验残留
must(!h.includes('dhAv') && !h.includes('dhLogs') && !h.includes('dhToday'), 'residual care-home ids');
fs.writeFileSync(PROTO + 'index-maternity_bady.html', h);
console.log('OK restored original dashboard');
