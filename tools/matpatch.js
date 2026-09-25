const fs = require('fs');
const ROOT = 'D:/dev_workplace/flutter_te/lifeHarness';
const P = ROOT + '/prototype/index-maternity_bady.html';
const fragPages = fs.readFileSync(ROOT + '/tools/mat_frag_pages.html', 'utf8');
const fragSheets = fs.readFileSync(ROOT + '/tools/mat_frag_sheets.html', 'utf8');
const fragJs = fs.readFileSync(ROOT + '/tools/mat_frag_js.js', 'utf8');
let h = fs.readFileSync(P, 'utf8');
const must = (cond, msg) => { if (!cond) { console.error('FAIL: ' + msg); process.exit(1); } };
const count = (s, sub) => s.split(sub).length - 1;

// 1) 替换 p-care 段（含新增 8 个子屏）
const m0 = '    <!-- ===== P10c 母婴呵护 ===== -->', m1 = '    <!-- ===== P10d 插件中心';
must(count(h, m0) === 1 && count(h, m1) === 1, 'care page markers');
let i0 = h.indexOf(m0), i1 = h.indexOf(m1);
h = h.slice(0, i0) + fragPages + '\n' + h.slice(i1);

// 2) 弹层插入到「插件详情弹层」注释之前（sheetBabyMeasure 之后）
const anchor = '  <!-- ===== 插件详情弹层 ===== -->';
must(count(h, anchor) === 1, 'sheet anchor');
h = h.replace(anchor, fragSheets + '\n' + anchor);

// 3) JS 段替换
const j0 = '/* ================= 母婴呵护 ================= */', j1 = '/* ================= FAB 按需显示配置';
must(count(h, j0) === 1 && count(h, j1) === 1, 'js markers');
i0 = h.indexOf(j0); i1 = h.indexOf(j1);
h = h.slice(0, i0) + fragJs.replace(/\s+$/, '') + '\n' + h.slice(i1);

// 4) TITLES 增补
const tAnchor = "'p-care':['母婴呵护','生理周期 · 宝宝喂养记录'],";
must(count(h, tAnchor) === 1, 'titles anchor');
h = h.replace(tAnchor, tAnchor +
 "'p-cycleCal':['周期日历','经期 · 易孕 · 排卵三区'],'p-cycleStats':['周期统计','14 个周期 · 规律度分析'],'p-symHistory':['感受历史','每日记录 · 趋势解读'],'p-careRemind':['呵护提醒','周期 · 喂养 · 疫苗 · 隐私'],'p-babies':['宝宝档案','多宝宝 · 记录人身份'],'p-babyDay':['全天记录','时间线 · 按类型筛选'],'p-growth':['生长曲线','WHO 百分位 · P3/P50/P97'],'p-vaccine':['疫苗计划','完成自动生成下次接种提醒'],");

// 5) init 调用聚合
const initOld = 'renderCycle(); renderSym(); renderBabyToday(); drawGrowth(\'w\'); renderVax(); renderWeekBaby();';
must(count(h, initOld) === 1, 'init anchor');
h = h.replace(initOld, 'renderCare();');

fs.writeFileSync(P, h);
console.log('OK patched. lines =', h.split('\n').length);
