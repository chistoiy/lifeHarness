const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '') + '\n';
const L0 = S.length;
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
function reg(t, a, b, ins) {
  const i = S.indexOf(a), j = i < 0 ? -1 : S.indexOf(b, i);
  if (i < 0 || j < 0) { console.log('REG MISS', t, i, j); fails++; return }
  S = S.slice(0, i) + ins + S.slice(j);
}

// 1) 习惯 JS 主体（数据模型 + 记量 + 详情 + 统计）
reg('js', 'let HABITS=[', '/* 顶栏页内动作 */', R('hb2_js.txt'));
// 2) 新建 / 编辑器（记录量 + 组子项）
reg('he', '/* 新建 / 编辑 */', '/* 补卡 */', R('hb2_he.txt'));
// 3) 记一次触发（带数量）
reg('tg', 'function hbTrigOpen(i){', '/* 操作菜单 */', R('hb2_tg.txt'));

// 4) 统计页：周 / 月 / 年 + 组构成卡
rep('seg', `      <div class="mt-3 flex gap-2 text-xs font-bold">
        <button id="hsBtnW" class="seg-pill on" onclick="hsPick("w")">本周</button>
        <button id="hsBtnM" class="seg-pill" onclick="hsPick("m")">本月</button>
        <button id="hsBtnA" class="seg-pill" onclick="hsPick("a")">全部纪录</button>
      </div>`,
`      <div class="mt-3 flex gap-2 text-xs font-bold">
        <button id="hsBtnW" class="seg-pill on" onclick="hsPick('w')">本周</button>
        <button id="hsBtnM" class="seg-pill" onclick="hsPick('m')">本月</button>
        <button id="hsBtnA" class="seg-pill" onclick="hsPick('a')">本年</button>
      </div>`);
rep('grp', `      <div class="mt-3 card"><div class="row-title">负向控制</div>`,
`      <div class="mt-3 card hidden"><div class="flex items-center gap-2"><div class="row-title">组习惯构成</div><span class="ml-auto text-[10px] text-slate-400">子项累计量</span></div><div class="mt-2" id="hstGroup"></div></div>
      <div class="mt-3 card"><div class="row-title">负向控制</div>`);
rep('title', `'p-habitStat':['习惯统计','周月完成率 · 排行 · 纪录墙']`, `'p-habitStat':['习惯统计','周 / 月 / 年 · 记录量 · 排行 · 纪录墙']`);

// 5) 弹层：打卡记量 + 编辑记录量字段 + 触发数量
rep('log', '  <!-- ===== 习惯专版 · 补卡 ===== -->', R('hb2_log.txt') + '  <!-- ===== 习惯专版 · 补卡 ===== -->');
rep('edit', `      <div class="mt-3 text-[11px] font-bold text-slate-500">提醒时间</div>`, R('hb2_edit.txt') + `      <div class="mt-3 text-[11px] font-bold text-slate-500">提醒时间</div>`);
rep('tgrow', `      <textarea id="tgNote" class="inp w-full min-h-[62px] mt-3 leading-6 text-[12px]" placeholder="补一句（可选）"></textarea>`,
`      <div id="tgAmtRow" class="mt-3 flex items-center gap-2 text-xs"><span class="font-bold text-slate-500 shrink-0">这次数量</span><input id="tgAmt" class="inp !w-16 !py-1.5 text-center" type="number" min="0" value="1"><span class="text-slate-400" id="tgAmtUnit">次</span></div>
      <textarea id="tgNote" class="inp w-full min-h-[62px] mt-3 leading-6 text-[12px]" placeholder="补一句（可选）"></textarea>`);
rep('name', `<input id="heName" class="inp w-full mt-3" placeholder="习惯名称，如：晨间跑步 30 分钟">`,
  `<input id="heName" class="inp w-full mt-3" placeholder="习惯名称，如：晨间跑步 30 分钟" oninput="heName=this.value">`);

// 6) 习惯列表页 seg 增「分组」入口文案（统计页入口按钮已在 renderHdrActs）
if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
const m = ms[ms.length - 1];
try { new vm.Script(m[1]); console.log('SYNTAX OK js=' + m[1].length) } catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
const keep = S.length / L0;
if (keep < 0.95 || keep > 1.3) { console.log('SIZE GUARD ABORT', L0, '->', S.length); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED', L0, '->', S.length, 'ratio', keep.toFixed(3));
