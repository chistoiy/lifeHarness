/* V1.53 原型第三轮：三组筛选收成三个胶囊，点某个胶囊才横向展开该组选项
 * 区域定位一律用「函数名到函数名」切片 + 内容断言，避免整段文本逐字匹配失败。 */
const fs = require('fs');
const F = 'prototype/index.html';
let s = fs.readFileSync(F, 'utf8');
const before = s.length;
fs.writeFileSync('tools/aiu_snapshot_page3_before.html', s);
function cut(from, to, mustHave, label) {
  const i = s.indexOf(from), j = s.indexOf(to);
  if (i < 0 || j < 0 || j <= i) { console.error(`[${label}] 区域定位失败`); process.exit(1); }
  const seg = s.slice(i, j);
  for (const m of mustHave) if (!seg.includes(m)) { console.error(`[${label}] 区域缺少 ${m}`); process.exit(1); }
  return [i, j, seg];
}
function replaceRange(from, to, mustHave, replacement, label) {
  const [i, j] = cut(from, to, mustHave, label);
  s = s.slice(0, i) + replacement + s.slice(j);
  console.log(`[${label}] ok`);
}

/* ① 页面骨架：#auBar 只放三个胶囊，选项条挂 #auPop，列表限高再放宽 */
{
  const a = '    <section id="p-aiUsage" class="page px-5 no-scrollbar">';
  const i = s.indexOf(a);
  if (i < 0) { console.error('[page] 找不到 p-aiUsage 段首'); process.exit(1); }
  const win = s.slice(i, i + 8000);
  const k = win.indexOf('</section>');
  if (k < 0) { console.error('[page] 找不到 </section>'); process.exit(1); }
  if (!win.slice(0, k).includes('auBox')) { console.error('[page] 段内缺 auBox，定位可疑'); process.exit(1); }
  s = s.slice(0, i) + fs.readFileSync('tools/aiu_frag_page3.txt', 'utf8') + s.slice(i + k + '</section>\n'.length);
  console.log('[page] ok');
}

/* ② 状态变量补 auPop */
{
  const anchor = 'var auD=0,auSt=\'all\',auMod=\'all\',auBodyOn=true,auKeepDays=30,auArm=null;';
  if (s.split(anchor).length - 1 !== 1) { console.error('[state] 锚点异常'); process.exit(1); }
  s = s.replace(anchor, anchor.replace('auArm=null;', 'auArm=null,auPop=null;'));
  console.log('[state] ok');
}

/* ③ auModChips → 胶囊与选项条渲染 */
replaceRange('function auModChips(){', 'function auRender(){',
  ['auModRow', 'pool.length'],
`/* 三组选项的候选集（模块组按当前时间范围计数） */
function auOpts(g){
  if(g==='d')return [['0','今日'],['7','7 天'],['30','30 天'],['9999','全部']];
  if(g==='st')return [['all','全部'],['ok','成功'],['fail','失败'],['cancel','取消'],['denied','未启用']];
  var pool=AI_CALLS.filter(auInRange),cnt={};
  pool.forEach(function(r){cnt[r.m]=(cnt[r.m]||0)+1;});
  return [['all','全部 '+pool.length]].concat(Object.keys(cnt).sort().map(function(m){return [m,m+' '+cnt[m]];}));
}
function auCur(g){return g==='d'?String(auD):(g==='st'?auSt:auMod);}
function auLblOf(g,v){var o=auOpts(g).filter(function(x){return x[0]===v;})[0];return o?o[1]:'全部';}
/* 点胶囊=横向弹出该组选项；再点同一胶囊=收起 */
function auPopToggle(g){auPop=(auPop===g?null:g);auRender();}
function auPopPick(g,v){
  if(g==='d')auD=+v;else if(g==='st')auSt=v;else auMod=v;
  auPop=null;auRender();
}
function auPills(){
  var cur={d:auLblOf('d',String(auD)),st:auLblOf('st',auSt),mod:auLblOf('mod',auMod)};
  $('#auBar').innerHTML=[['d','时间'],['st','状态'],['mod','模块']].map(function(p){
    var on=auPop===p[0];
    return '<button id="aup-'+p[0]+'" class="auf'+(on?' on':'')+'" onclick="auPopToggle(\\''+p[0]+'\\')">'
      +p[1]+' · '+cur[p[0]]+' <span class="au-ar">'+(on?'▾':'▸')+'</span></button>';
  }).join('');
}
function auPopRender(){
  auPills();
  var box=$('#auPop');if(!box)return;
  if(!auPop){box.className='hidden';box.innerHTML='';return;}
  box.className='';
  box.innerHTML='<div class="flex gap-1 overflow-x-auto no-scrollbar mt-1.5 pb-1">'
    +auOpts(auPop).map(function(o){
      return '<button class="auf'+(o[0]===auCur(auPop)?' on':'')+'" onclick="auPopPick(\\''+auPop+'\\',\\''+o[0]+'\\')">'+o[1]+'</button>';
    }).join('')+'</div>';
}
`, 'pills');

/* ④ auRender 里改调 auPopRender */
{
  const anchor = 'function auRender(){\n  auModChips();\n';
  if (s.split(anchor).length - 1 !== 1) { console.error('[render] 锚点异常'); process.exit(1); }
  s = s.replace(anchor, 'function auRender(){\n  auPopRender();\n');
  console.log('[render] ok');
}

/* ⑤ 段选函数改为纯设值（胶囊态由 auPopRender 统一渲染），并兼容既有调用签名 */
replaceRange('function auSetRange(', 'function auToggle(',
  ['auSetRange', 'auSetSt', 'auPickMod'],
`function auSetRange(d){auD=+d;auRender();}
function auSetSt(st){auSt=st;auRender();}
function auPickMod(m){auMod=m;auRender();}
`, 'setters');

const grew = s.length - before;
/* 本轮是「静态标记换运行时渲染」，体积近乎持平：改判内容而非增量 */
if (grew < -4000 || grew > 20000) { console.error(`体积变化异常（${grew}），拒绝写回`); process.exit(1); }
for (const need of ['function auPopRender', 'function auPopToggle', 'id="auPop"', 'auLblOf']) {
  if (!s.includes(need)) { console.error(`产物缺少 ${need}，拒绝写回`); process.exit(1); }
}
if (/function auModChips\(/.test(s)) { console.error('旧函数 auModChips 残留，拒绝写回'); process.exit(1); }
fs.writeFileSync(F, s);
console.log(`OK 写入完成：${before} → ${s.length}（${grew >= 0 ? '+' : ''}${grew}）`);
