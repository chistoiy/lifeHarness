/* ux162_proto.js · 2026-10-07 产品五条反馈的原型面（与 Flutter 同批）
 * 用法：node tools/ux162_proto.js
 * 1) 图片存储清理屏补「全选」钮；2) 日记天气从「我的」挪进「记录管理」；
 * 3) AI 增强页服务商列表收成一行＋半屏选单；4) Key 配置整卡摘除（验证状态与重新验证钮留在服务商卡）。
 * 缩进那条（外观/记录管理与上方条目不齐）＝**实现漂移**，原型这两张卡本来就是 `card ... p-3.5` 同一基准，
 * 与 U11 同类：不过门，直修 Flutter。
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index.html');
const SNAP = path.join(ROOT, 'tmp', 'index-html.before-ux162-20261007.html');
const src = fs.readFileSync(HTML, 'utf8');
fs.writeFileSync(SNAP, src, 'utf8');
let out = src;
const done = [];

function rep(name, from, to) {
  const n = out.split(from).length - 1;
  if (n !== 1) throw new Error('锚点 ' + name + ' 命中 ' + n + ' 处（期望 1）——中止，不落盘');
  out = out.replace(from, to);
  done.push(name);
}
function span(name, a, b, to) {
  const na = out.split(a).length - 1, nb = out.split(b).length - 1;
  if (na !== 1 || nb !== 1) throw new Error('锚点 ' + name + ' 命中异常 a=' + na + ' b=' + nb + '——中止');
  const i = out.indexOf(a), j = out.indexOf(b);
  if (j <= i) throw new Error('锚点顺序不对：' + name + '——中止');
  out = out.slice(0, i) + to + out.slice(j);
  done.push(name + '(' + (j - i) + ')');
}

/* ---- 1 · 图片存储清理：全选钮 ---- */
rep('清理屏全选钮',
  '        <div class="text-[12px] font-extrabold" id="mcSum"></div>\n'
  + '        <button class="text-[11.5px] font-bold text-brand-500" onclick="mcScan()">重新扫描</button>',
  '        <div class="text-[12px] font-extrabold" id="mcSum"></div>\n'
  + '        <span class="flex items-center gap-3">\n'
  + '          <button id="mcAllBtn" class="text-[11.5px] font-bold text-brand-500" onclick="mcAll()">全选</button>\n'
  + '          <button class="text-[11.5px] font-bold text-brand-500" onclick="mcScan()">重新扫描</button>\n'
  + '        </span>');

rep('mcAll 函数',
  'function mcAskDel(){',
  'function mcAll(){const all=MC_FILES.length&&mcOn.size===MC_FILES.length;mcOn.clear();'
  + 'if(!all)MC_FILES.forEach(function(f){mcOn.add(f.h)});mcRender();}\n'
  + 'function mcAskDel(){');

rep('mcRender 同步全选态',
  "  const pf = $('#pfMcCnt'); if (pf) pf.textContent = n + ' 个';",
  "  const a = $('#mcAllBtn'); if (a) { a.textContent = (n && mcOn.size === n) ? '取消全选' : '全选'; a.style.display = n ? '' : 'none' }\n"
  + "  const pf = $('#pfMcCnt'); if (pf) pf.textContent = n + ' 个';");

/* ---- 2 · 日记天气挪进记录管理 ---- */
span('摘除主页天气行',
  '      <!-- 批2e：日记天气城市（一次选定 · 写日记当天自动抓取） -->',
  '      <div class="card mt-4">\n        <div class="flex items-center justify-between"><div class="row-title">底部导航栏自定义</div>',
  '      ');
rep('记录管理加天气行',
  '        <div class="flex items-center justify-between"><span>默认新建模板</span>',
  '        <div class="flex items-center justify-between"><span>日记天气</span>\n'
  + '          <button id="rwCity" class="mini-btn" onclick="openSheet(\'sheetCityPick\')">常州市</button></div>\n'
  + '        <div class="flex items-center justify-between"><span>默认新建模板</span>');

/* ---- 3+4 · AI 增强页：服务商收成一行 + 选单，Key 配置卡摘除 ---- */
const NEWAI = [
  '      <div class="card">',
  '        <div class="flex items-center justify-between"><div class="row-title">服务商</div><button class="mini-btn" onclick="aiProvEdit(null)">+ 添加服务商</button></div>',
  '        <button id="aiCurRow" onclick="aiPickOpen()" class="mt-2 w-full rounded-xl bg-slate-100 dark:bg-slate-800 px-3 py-2.5 text-left flex items-center gap-2 active:opacity-70">',
  '          <span class="flex-1 min-w-0"><b id="aiCurName" class="text-[12.5px] block truncate"></b>',
  '            <span id="apCur" class="text-[10.5px] text-slate-400 block truncate"></span></span>',
  '          <span class="text-slate-300 shrink-0"><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M7 9 12 4l5 5M7 15l5 5 5-5"/></svg></span>',
  '        </button>',
  '        <div class="text-[10px] text-slate-400 mt-2 leading-5">请求只发往所选地址 · 应用自身零埋点；Key 存系统级加密区：不入备份明文、不落日志、不随同步导出。</div>',
  '        <div class="flex justify-between items-center mt-2"><span>验证状态</span>',
  '          <b id="apVerifyState" class="text-emerald-500 text-[11px]">✓ 今日 08:12 通过 · 812ms</b></div>',
  '        <button class="mt-2 w-full py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="aiVfOpen()">重新验证 / 测试新 Key</button>',
  '      </div>',
  '      <div class="card mt-3">',
  ''].join('\n');
span('服务商卡与Key卡合并',
  '      <div class="card">\n        <div class="flex items-center justify-between"><div class="row-title">服务商管理</div>',
  '      <div class="card mt-3">\n        <div class="flex items-center justify-between"><div class="row-title">AI 总开关</div>',
  NEWAI + '\n        <div class="flex items-center justify-between"><div class="row-title">AI 总开关</div>');

/* 选单半屏：整份服务商清单搬进来（复用既有 aiProvRender 的 #aiProvList） */
rep('服务商选单弹层',
  '  <div id="sheetAiProv" class="sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end"',
  '  <div id="sheetAiPick" class="sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end" onclick="if(event.target===this)closeSheet(\'sheetAiPick\')">\n'
  + '    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8 max-h-[80vh] overflow-y-auto">\n'
  + '      <div class="grabber"></div>\n'
  + '      <div class="font-extrabold">选择服务商</div>\n'
  + '      <div class="mt-3 space-y-2 text-xs" id="aiProvList"></div>\n'
  + '      <div class="text-[10px] text-slate-400 mt-3 leading-5">预置只是默认值，<b>不是白名单</b>：官方、中转站/自建网关、局域网 Ollama 都能添加，Base URL、模型名、协议都可改。</div>\n'
  + '    </div>\n'
  + '  </div>\n'
  + '  <div id="sheetAiProv" class="sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end"');

/* JS：当前行渲染 + 选单开合 + 选用后收起 */
rep('当前行渲染改双行',
  " if(cur)cur.innerHTML='当前端点：<b>'+c.n+'</b> · <span class=\"font-mono text-[10px]\">'+c.u+'</span> · '+c.m;",
  " var nm=document.getElementById('aiCurName');\n"
  + " if(nm)nm.textContent=c.n+' · '+(c.p==='anthropic'?'Anthropic Messages':'OpenAI 兼容');\n"
  + " if(cur)cur.innerHTML='<span class=\"font-mono\">'+c.u+'</span> · '+c.m+' · Key '+(c.k?'已单独保存':'未填');");
rep('选单开合',
  "function aiProvUse(id){aiProvs().forEach(function(p){p.cur=p.id===id;});aiProvRender();",
  "function aiPickOpen(){aiProvRender();openSheet('sheetAiPick')}\n"
  + "function aiProvUse(id){aiProvs().forEach(function(p){p.cur=p.id===id;});closeSheet('sheetAiPick');aiProvRender();");

const delta = out.length - src.length;
if (delta < -1500 || delta > 2500) throw new Error('体积变化异常：' + delta + '——中止（不落盘，快照在 tmp/）');
fs.writeFileSync(HTML, out, 'utf8');
console.log('PATCHED ' + done.join(' / ') + '  bytes ' + src.length + ' → ' + out.length + ' (' + delta + ')');
