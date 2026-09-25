const fs = require('fs');
const ROOT = 'D:/dev_workplace/flutter_te/lifeHarness';
const P = ROOT + '/prototype/index-maternity_bady.html';
let h = fs.readFileSync(P, 'utf8');
const stats = fs.readFileSync(ROOT + '/tools/mat3_stats.js', 'utf8');
const must = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exit(1); } };
const rep = (a, b, tag) => { must(h.includes(a), tag); h = h.replace(a, b); };

// 1) 汇总 JS → 喂养分析 JS
const s0 = h.indexOf('/* —— 照护多维汇总 —— */'), s1 = h.indexOf('/* —— 汇总 init 时渲染一次即可');
must(s0 > 0 && s1 > s0, 'stats block');
h = h.slice(0, s0) + stats.replace(/\s+$/, '') + '\n' + h.slice(s1);

// 2) openEvent：添加人副标 + 键盘输入复位
rep(`$('#elNote').value=src&&src.note?src.note:'';`,
  `$('#elNote').value=src&&src.note?src.note:'';
 $('#elWho').textContent='添加人：'+(src?src.rec:curCarer);
 $('#elAmtKb').classList.add('hidden');$('#elAmtKb').value='';$('#elAmtWheelRow').classList.remove('hidden');`, 'openEvent who/kb');

// 3) saveEvent 量读取走 elAmtVal
rep(`if(E.amt){const w=WHEELS.elAmtW;r.ml=w?+w.items[w.i]:+$('#elSuppName')||E.def;}`,
  `if(E.amt)r.ml=elAmtVal()||E.def||0;`, 'saveEvent ml');
rep(`r.amt=WHEELS.elAmtW?+WHEELS.elAmtW.items[WHEELS.elAmtW.i]:0;`,
  `r.amt=elAmtVal();`, 'saveEvent custom amt');

// 4) 步进/键盘函数
rep(`function elAmtSet(v){const w=WHEELS.elAmtW;if(!w)return;let bi=0,bd=1e9;w.items.forEach((it,i)=>{const d=Math.abs(+it-v);if(d<bd){bd=d;bi=i}});w.i=bi;renderW('elAmtW');}`,
  `function elAmtSet(v){const w=WHEELS.elAmtW;if(!w)return;let bi=0,bd=1e9;w.items.forEach((it,i)=>{const d=Math.abs(+it-v);if(d<bd){bd=d;bi=i}});w.i=bi;renderW('elAmtW');}
function elAmtStep(d){const w=WHEELS.elAmtW;if(!w)return;w.i=Math.max(0,Math.min(w.items.length-1,w.i+d));renderW('elAmtW');}
function elKb(){const kb=$('#elAmtKb'),on=kb.classList.contains('hidden');kb.classList.toggle('hidden',!on);$('#elAmtWheelRow').classList.toggle('hidden',on);
 if(on){const w=WHEELS.elAmtW;if(w)kb.value=w.items[w.i];kb.focus();}}
function elAmtVal(){const kb=$('#elAmtKb');if(!kb.classList.contains('hidden'))return +kb.value||0;const w=WHEELS.elAmtW;return w?+w.items[w.i]:0;}`, 'amt step/kb');

// 5) renderCare 补 renderDayFilter
rep('function renderCare(){renderCycle();renderSym();renderSymHist();renderCycStats();renderBabyHero();renderEvGrid();renderBabyToday();renderBabies();renderBabySwitch();drawGrowth(\'w\');renderMeasureHist();renderVax();renderWeekBaby();renderBabyDay();renderStats();}',
  'function renderCare(){renderCycle();renderSym();renderSymHist();renderCycStats();renderBabyHero();renderEvGrid();renderDayFilter();renderBabyToday();renderBabies();renderBabySwitch();drawGrowth(\'w\');renderMeasureHist();renderVax();renderWeekBaby();renderBabyDay();renderStats();}', 'renderCare');

for (const dead of ['bdStep', 'bsRange', 'bdSummary', 'bdFilters', 'bsTot', 'bsTrend', 'bsInsight', 'bsEvents'])
  must(!h.includes(dead), 'dead ref: ' + dead);
fs.writeFileSync(P, h);
console.log('OK mat3 applied. lines =', h.split('\n').length);
