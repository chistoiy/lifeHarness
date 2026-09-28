/* V1.53 原型第二轮改版补丁：AI 使用记录去底栏 + 筛选合一行 + 统计/删除上移（列表区最大化）
 * 一次性执行：锚点全部从第一轮过程件里取，命中数不符即中止（大文件脚本化修改三条护栏）。 */
const fs = require('fs');
const F = 'prototype/index.html';
let s = fs.readFileSync(F, 'utf8');
const before = s.length;
fs.writeFileSync('tools/aiu_snapshot_page2_before.html', s);
const frag = f => fs.readFileSync('tools/aiu_frag_' + f + '.txt', 'utf8');
function put(anchor, replacement, label, hits = 1) {
  const n = s.split(anchor).length - 1;
  if (n !== hits) { console.error(`[${label}] 锚点命中 ${n} 次（期望 ${hits}）：${anchor.slice(0, 70)}`); process.exit(1); }
  s = s.replace(anchor, () => replacement);
  console.log(`[${label}] ok`);
}
/* 第一轮的 JS 过程件里切出函数原文当锚点，保证逐字一致 */
const oldJs = frag('js');
function slice(from, to) {
  const i = oldJs.indexOf(from), j = oldJs.indexOf(to);
  if (i < 0 || j < 0 || j <= i) { console.error(`切片失败：${from} ~ ${to}`); process.exit(1); }
  return oldJs.slice(i, j);
}

/* ① 底栏：与日志页同款——本页隐藏 #tabNav 且 main 吃掉底栏高度 */
put("  if(_tn)_tn.classList.toggle('hidden',_imm||p==='p-logs'); /* V1.50批3.6 V5：日志页无底栏（日志窗通底） */",
  "  if(_tn)_tn.classList.toggle('hidden',_imm||p==='p-logs'||p==='p-aiUsage'); /* V1.50批3.6 V5 日志页 / V1.53 AI 使用记录：无底栏，列表通底 */",
  'setPage-tab');
put("  if(_mn)_mn.style.height=(p==='p-logs')?'calc(100% - 78px)':'';",
  "  if(_mn)_mn.style.height=(p==='p-logs'||p==='p-aiUsage')?'calc(100% - 78px)':'';",
  'setPage-main');

/* ② CSS：一行式筛选条（时间/状态/模块合行） */
put('  .au-h{font-size:10px;font-weight:800;color:#64748b;margin:10px 0 4px}\n',
  '  .au-h{font-size:10px;font-weight:800;color:#64748b;margin:10px 0 4px}\n' +
  '  .au-cap{font-size:9px;font-weight:800;color:#94a3b8;flex-shrink:0;padding:0 2px}\n' +
  '  .au-div{width:1px;height:14px;background:color-mix(in srgb,var(--card-bd) 90%,transparent);flex-shrink:0;margin:0 4px}\n' +
  '  .auf{flex-shrink:0;font-size:10.5px;font-weight:700;color:#64748b;background:color-mix(in srgb,var(--accent) 7%,transparent);border:1px solid color-mix(in srgb,var(--card-bd) 80%,transparent);border-radius:99px;padding:3px 9px;white-space:nowrap}\n' +
  '  .auf.on{background:var(--accent);color:#fff;border-color:transparent}\n',
  'css');

/* ③ 页面骨架：统计与三个动作上移到首行，筛选合成一行，列表限高放宽 */
put(frag('page'), frag('page2'), 'page');

/* ④ 渲染：模块 chips 换 .auf；摘要行并入筛选统计；行加长按复制 */
put(slice('function auModChips(){', 'function auKpi(){'),
`function auModChips(){
  var pool=AI_CALLS.filter(auInRange);var cnt={};
  pool.forEach(function(r){cnt[r.m]=(cnt[r.m]||0)+1;});
  var mods=Object.keys(cnt).sort();
  var h='<button class="auf'+(auMod==='all'?' on':'')+'" onclick="auPickMod(\\'all\\')">全部 '+pool.length+'</button>';
  mods.forEach(function(m){h+='<button class="auf'+(auMod===m?' on':'')+'" onclick="auPickMod(\\''+m+'\\')">'+m+' '+cnt[m]+'</button>';});
  $('#auModRow').innerHTML=h;
}
function auRender(){
  auModChips();
  var list=auList(),h='';
  if(!list.length){h='<div class="p-6 text-center text-[11px] text-slate-400">该范围暂无 AI 调用记录<br><span class="opacity-70">换时间范围或清掉关键词再看</span></div>';}
  list.forEach(function(r){
    var open=r.open?' open':'';
    h+='<div class="ailine st-'+r.st+open+'" data-i="'+r.i+'">'
      +'<div class="ah" onclick="auToggle('+r.i+')" oncontextmenu="event.preventDefault();auCopyLine('+r.i+')">'
      +'<span class="at">'+r.t+'</span><span class="as">'+auStTxt(r.st)+'</span>'
      +'<span class="am">'+r.m+' · '+r.n+'</span>'
      +'<span class="aq">'+(r.it||r.ot?('入'+r.it+'/出'+r.ot):'—')+' · '+auMsTxt(r.ms)+'</span></div>'
      +'<div class="ab">'
      +(r.err?('<h5>'+(r.st==='ok'?'提示':'原因')+'</h5><pre class="err">'+auEsc(r.err)+'</pre>'):'')
      +(r.sys?('<h5>System · 发送设定</h5><pre>'+auEsc(r.sys)+'</pre>'):'')
      +(r.usr?('<h5>User · 本次输入</h5><pre>'+auEsc(r.usr)+(r.cut?' <span class="cut">…已截断（上限 8000 字）</span>':'')+'</pre>'):'')
      +(r.out?('<h5>输出</h5><pre>'+auEsc(r.out)+'</pre>'):'')
      +(!r.sys&&!r.usr&&!r.out?'<div class="text-[10px] text-slate-400 mt-2">本条未存正文（记录设置里「记录输入与输出正文」已关闭）</div>':'')
      +'<div class="ops">'
      +'<button class="mini-btn" onclick="event.stopPropagation();auCopy('+r.i+',\\'usr\\')">复制输入</button>'
      +'<button class="mini-btn" onclick="event.stopPropagation();auCopy('+r.i+',\\'out\\')">复制输出</button>'
      +'<button class="mini-btn" onclick="event.stopPropagation();auCopy('+r.i+',\\'all\\')">复制全部</button>'
      +'<button class="mini-btn" style="color:#ef4444" onclick="event.stopPropagation();auDel('+r.i+',this)">删除本条</button>'
      +'</div></div></div>';
  });
  $('#auBox').innerHTML=h;
  var s=auSumOf(list);
  var today=auSumOf(AI_CALLS.filter(function(r){return r.d===0;}));
  $('#auSum').textContent='筛选 '+list.length+' 条 · 入 '+s.it+'/出 '+s.ot+' tokens · 未成功 '+s.f
    +' · 今日 '+today.n+' 次';
  auKpi();
}
/* 长按一行＝复制该行摘要（与日志页同交互） */
function auCopyLine(i){var r=auFind(i);if(!r)return;
  var t='['+r.t+'] '+r.m+' · '+r.n+' · '+auStTxt(r.st)+' · 入'+r.it+'/出'+r.ot+' · '+auMsTxt(r.ms)
    +(r.err?('\\n'+r.err):'');
  navigator.clipboard.writeText(t).then(function(){toast('已复制该行记录');}).catch(function(){toast('复制失败');});}
`, 'render');

/* ⑤ 段选样式切换改吃 .auf.on */
put(slice('function auSeg(', 'function auSetRange('),
`function auSeg(id,ids){ids.forEach(function(i){var b=document.getElementById(i);if(b)b.classList.remove('on');});
  var on=document.getElementById(id);if(on)on.classList.add('on');}
`, 'seg');

const grew = s.length - before;
if (grew < 200) { console.error(`体积增长异常（+${grew}），已拒绝写回`); process.exit(1); }
fs.writeFileSync(F, s);
console.log(`OK 写入完成：${before} → ${s.length}（${grew >= 0 ? '+' : ''}${grew}）`);
