/* aiverify_proto.js · 批①：把实现真页 /settings/ai/verify 画进壳原型（排期池候选·V1.58 下架带出的缺口）
 *
 * 用法：node tools/aiverify_proto.js            # 打补丁（四把锚点全中才落盘）
 *       node tools/aiverify_proto.js --revert    # 用快照复原
 *
 * 护栏（AGENTS「脚本改源码」四条）：改前快照已在 tmp/；逐锚点命中断言＝1，多处或零处即中止；
 * 落盘后体积校验；index.html 是 LF，锚点串用 \n 拼接不引 CRLF。
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index.html');
const SNAP = path.join(ROOT, 'tmp', 'index-html.before-aiverify-20261007.html');
const argv = process.argv.slice(2);

if (argv.includes('--revert')) {
  fs.copyFileSync(SNAP, HTML);
  console.log('REVERTED from snapshot, bytes=' + fs.statSync(HTML).size);
  process.exit(0);
}

const before = fs.readFileSync(HTML, 'utf8');
const bytesBefore = before.length;
let out = before;
const hits = [];

function rep(name, from, to, expect) {
  expect = expect || 1;
  const n = out.split(from).length - 1;
  if (n !== expect) throw new Error('锚点 ' + name + ' 命中 ' + n + ' 处（期望 ' + expect + '）——中止，不落盘');
  out = out.split(from).join(to);
  hits.push(name + '=1');
}

/* ---------- 1 · p-sub-ai 的「验证状态」行加重新验证入口 ---------- */
rep('入口行',
  '<div class="flex justify-between items-center"><span>验证状态</span><b class="text-emerald-500">✓ 今日 08:12 通过 · 812ms</b></div>',
  '<div class="flex justify-between items-center gap-2"><span>验证状态</span>'
  + '<span class="flex items-center gap-2 shrink-0">'
  + '<b id="apVerifyState" class="text-emerald-500 text-[11px]">✓ 今日 08:12 通过 · 812ms</b>'
  + '<button class="mini-btn" onclick="aiVfOpen()">重新验证 ›</button></span></div>');

/* ---------- 2 · 新屏 section（住在 p-sub-aiPrompts 之前，与实现页同序） ---------- */
const SEC = [
  '    <!-- ===== P12c1b 二级：AI API 验证（实现真页 /settings/ai/verify 对齐 · 三态＝通过/凭据错误/网络失败） ===== -->',
  '    <section id="p-sub-aiVerify" class="page px-5 safe-pb no-scrollbar">',
  '      <div class="card">',
  '        <div class="row-title">端点与凭据</div>',
  '        <div id="avChips" class="flex flex-wrap gap-2 mt-2"></div>',
  '        <input id="avUrl" class="inp w-full mt-3 font-mono text-[11px]" type="text" placeholder="https://api.xxx.com/v1">',
  '        <div class="flex gap-2 mt-2">',
  '          <div class="relative flex-1">',
  '            <input id="avKey" class="inp w-full pr-10 font-mono text-[11px]" type="password" placeholder="API Key">',
  '            <button id="avEye" class="absolute right-1 top-1/2 -translate-y-1/2 w-8 h-8 flex items-center justify-center rounded-lg text-slate-500 active:bg-slate-100 dark:active:bg-slate-800" onclick="apPeek(\'avKey\',\'avEye\')" title="显示或隐藏明文" aria-label="显示或隐藏明文"></button>',
  '          </div>',
  '          <input id="avModel" class="inp flex-1 text-[11px]" type="text" placeholder="模型名">',
  '        </div>',
  '        <textarea id="avPrompt" class="inp w-full mt-2 text-[11px]" rows="2" placeholder="请只回复四个字：连接成功"></textarea>',
  '        <button id="avSend" class="w-full py-3 mt-3 rounded-xl grad text-white text-sm font-bold" onclick="aiVfSend()">真实发送验证</button>',
  '      </div>',
  '      <div class="card mt-3">',
  '        <div class="flex items-center justify-between"><div class="row-title">验证结果</div><span id="avLat" class="text-[10px] text-slate-400"></span></div>',
  '        <div id="avRes" class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 px-3 py-2.5 font-mono text-[10.5px] leading-5" style="white-space:pre-wrap;color:#94a3b8">结果将显示在此：模型回复 / 延迟 / token 用量，或精确错误原因（401 Key 无效 · 404 模型名 · 429 限流 · 超时）。</div>',
  '      </div>',
  '      <div class="text-[10px] text-slate-400 mt-2 leading-5">请求仅发往上方地址 · 应用自身零埋点；Key 存系统加密区，不入备份明文、不落日志。</div>',
  '    </section>',
  '',
  ''].join('\n');
rep('新屏锚点',
  '    <!-- ===== P12c2 二级：提示词管理（AI批 · 能力点模板按模块查看/覆盖 · 默认来自内置资产） ===== -->',
  SEC + '    <!-- ===== P12c2 二级：提示词管理（AI批 · 能力点模板按模块查看/覆盖 · 默认来自内置资产） ===== -->');

/* ---------- 3 · TITLES 表头标题 ---------- */
rep('TITLES',
  "'p-goals':['目标 OKR','V1.x 完整版预览'],",
  "'p-goals':['目标 OKR','V1.x 完整版预览'],'p-sub-aiVerify':['AI API 验证','端点 · Key · 模型连通性'],");

/* ---------- 4 · 状态机 JS（插在服务商层之前） ---------- */
const JS = [
  '/* ===== AI API 验证屏（p-sub-aiVerify · 对齐实现 AiVerifyPage：三态＝通过/凭据错误/网络失败） ===== */',
  'let avBusy=false,avTimer=null;',
  'const AV_IDLE=\'结果将显示在此：模型回复 / 延迟 / token 用量，或精确错误原因（401 Key 无效 · 404 模型名 · 429 限流 · 超时）。\';',
  'function aiVfNorm(u){return String(u||\'\').trim().replace(/\\/+$/,\'\');}',
  'function aiVfProto(u){var p=aiProvs().filter(function(x){return aiVfNorm(x.u)===aiVfNorm(u);})[0];return p?p.p:\'openai\';}',
  'function aiVfChips(){var box=document.getElementById(\'avChips\');if(!box)return;',
  ' box.innerHTML=aiProvs().map(function(p){var on=aiVfNorm(p.u)===aiVfNorm(document.getElementById(\'avUrl\').value);',
  '  return \'<button class="mini-btn" style="\'+(on?\'background:#0f172a;color:#fff\':\'\')+\'" data-avp="\'+p.id+\'" onclick="aiVfPick(\\\'\'+p.id+\'\\\')">\'+p.n+\'</button>\';}).join(\'\');}',
  'function aiVfPick(id){var p=aiProvById(id);if(!p)return;',
  ' document.getElementById(\'avUrl\').value=p.u;document.getElementById(\'avModel\').value=p.m;',
  ' document.getElementById(\'avKey\').value=p.k?\'sk-demo-\'+p.id:\'\';aiVfChips();}',
  'function aiVfFill(){var p=aiCurProv();',
  ' document.getElementById(\'avUrl\').value=p.u;document.getElementById(\'avModel\').value=p.m;',
  ' document.getElementById(\'avKey\').value=p.k?\'sk-demo-\'+p.id:\'\';',
  ' document.getElementById(\'avPrompt\').value=\'请只回复四个字：连接成功\';',
  ' document.getElementById(\'avRes\').textContent=AV_IDLE;',
  ' document.getElementById(\'avRes\').style.color=\'#94a3b8\';',
  ' document.getElementById(\'avLat\').textContent=\'\';',
  ' document.getElementById(\'avEye\').innerHTML=AP_EYE;aiVfChips();}',
  'function aiVfOpen(){navTo(\'p-sub-aiVerify\');aiVfFill();}',
  'function aiVfJudge(u,m,k){',
  ' if(!/^https?:\\/\\//.test(u))return {ok:false,lat:0,t:\'✕ 网络失败：无法连接 \'+(u||\'（地址为空）\')+\'\\n请检查 Base URL 是否带 http(s):// 且拼写正确\'};',
  ' if(!k)return {ok:false,lat:0,t:\'✕ 401 未授权：API Key 无效或未填\\n该服务商的 Key 请在「服务商管理」里补齐\'};',
  ' if(!m)return {ok:false,lat:0,t:\'✕ 404 模型不存在：模型名留空或拼写错误\'};',
  ' return {ok:true,lat:812,t:\'✓ 812ms · 200 OK\\n模型回复：连接成功\\nusage: 12 + 4 tokens\\n验证通过 · 可回 AI 增强页逐项开启能力矩阵\'};}',
  'function aiVfSend(){if(avBusy)return;',
  ' var u=document.getElementById(\'avUrl\').value,m=document.getElementById(\'avModel\').value.trim(),k=document.getElementById(\'avKey\').value.trim();',
  ' var path=aiVfProto(u)===\'anthropic\'?\'/messages\':\'/chat/completions\';',
  ' avBusy=true;var btn=document.getElementById(\'avSend\');btn.classList.add(\'opacity-40\');btn.textContent=\'请求中…\';',
  ' var res=document.getElementById(\'avRes\');res.style.color=\'#64748b\';',
  ' res.textContent=\'⏳ POST \'+aiVfNorm(u)+path+\' · model=\'+(m||\'—\')+\' …\';',
  ' clearTimeout(avTimer);',
  ' avTimer=setTimeout(function(){avBusy=false;btn.classList.remove(\'opacity-40\');btn.textContent=\'真实发送验证\';',
  '  var r=aiVfJudge(u,m,k);res.textContent=r.t;res.style.color=r.ok?\'#10b981\':\'#f43f5e\';',
  '  document.getElementById(\'avLat\').textContent=r.ok?\'延迟 \'+r.lat+\'ms\':\'未通过\';',
  '  var s=document.getElementById(\'apVerifyState\');',
  '  if(s){s.textContent=r.ok?\'✓ 刚刚通过 · \'+r.lat+\'ms\':\'✕ 刚刚失败\';s.style.color=r.ok?\'#10b981\':\'#f43f5e\';}',
  '  toast(r.ok?\'验证通过 · Key 已存入该服务商加密槽\':\'验证未通过 · 原因见结果区\');',
  ' },620);}',
  'function aiVfBusy(){return avBusy;}',
  'let AI_PROVS=null,apEdit=null;',
  ''.replace(/\n$/, '')
].join('\n');
rep('状态机 JS', 'let AI_PROVS=null,apEdit=null;', JS);

/* ---------- 体积校验 ---------- */
const delta = out.length - bytesBefore;
if (delta < 1200 || delta > 9000) throw new Error('体积变化异常：' + delta + ' 字节（期望 1200~9000）——中止');
fs.writeFileSync(HTML, out, 'utf8');
console.log('PATCHED ' + hits.join(' ') + '  bytes ' + bytesBefore + ' → ' + out.length + ' (+' + delta + ')');
