const fs = require('fs');
const ROOT = 'D:/dev_workplace/flutter_te/lifeHarness';
const P = ROOT + '/prototype/index-maternity_bady.html';
const rd = f => fs.readFileSync(ROOT + '/tools/' + f, 'utf8');
let h = fs.readFileSync(P, 'utf8');
const must = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exit(1); } };
const splice = (startMark, endMark, content, tag) => {
  const i0 = h.indexOf(startMark), i1 = h.indexOf(endMark);
  must(i0 > 0 && i1 > i0, tag + ' markers');
  h = h.slice(0, i0) + content.replace(/\s+$/, '') + '\n' + h.slice(i1);
};
splice('    <!-- ===== P10c 母婴呵护 · 专版主页（她 / 宝宝 双页） ===== -->', '    <!-- ===== C2 周期日历', rd('mat2_pages.html'), 'pages');
splice('  <!-- ===== 母婴专版 · 弹层组 ===== -->', '  <!-- ===== 插件详情弹层 ===== -->', rd('mat2_sheets.html'), 'sheets');
splice('/* ================= 母婴呵护 · 专版（对话', '/* —— 保留：小工具页运动换算', rd('mat2_js_full.js'), 'js');
const statsAnchor = '    <!-- ===== P10d 插件中心';
must(h.includes(statsAnchor), 'stats anchor');
h = h.replace(statsAnchor, rd('mat2_stats.html').replace(/\s+$/, '') + '\n' + statsAnchor);
must(h.includes(`onclick="stack.length=0;careTab('baby');setPage('p-care')"`), 'babyDay back button');
h = h.replace(`onclick="stack.length=0;careTab('baby');setPage('p-care')"`, `onclick="stack.length=0;setPage('p-baby')"`);
const tOld = "'p-care':['母婴呵护','生理周期 · 宝宝喂养记录'],";
must(h.includes(tOld), 'titles');
h = h.replace(tOld, "'p-care':['母婴呵护','她 · 生理周期'],'p-baby':['母婴呵护','宝宝 · 照护记录'],'p-babyStats':['照护汇总','事件 × 时段 × 趋势'],");
for (const dead of ['careTab(', 'sheetBottle', 'sheetSupp"', 'sheetPoop', 'sheetPlay', 'sheetRecDetail', 'qTap(', 'babyLogs'])
  must(!h.includes(dead), 'dead ref remains: ' + dead);
fs.writeFileSync(P, h);
console.log('OK mat2 applied. lines =', h.split('\n').length);
