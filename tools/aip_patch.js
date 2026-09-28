/* V1.53.1 原型补丁：AI 增强页「服务商管理」从写死列表改为可增删改（Base URL/模型/协议/独立 Key + 实测连接）
 * 区域用 index 定位 + 内容断言，命中异常直接中止不写回。 */
const fs = require('fs');
const F = 'prototype/index.html';
let s = fs.readFileSync(F, 'utf8');
const before = s.length;
fs.writeFileSync('tools/aip_snapshot_before.html', s);
const frag = f => fs.readFileSync('tools/aip_frag_' + f + '.txt', 'utf8');
function span(from, mustHave) {
  const i = s.indexOf(from);
  if (i < 0) { console.error(`定位失败：${from.slice(0, 60)}`); process.exit(1); }
  for (const m of mustHave) {
    if (!s.slice(i, i + 2600).includes(m)) { console.error(`区域缺关键内容：${m}`); process.exit(1); }
  }
  return i;
}
function put(anchor, replacement, label, hits = 1) {
  const n = s.split(anchor).length - 1;
  if (n !== hits) { console.error(`[${label}] 命中 ${n} 次（期望 ${hits}）：${anchor.slice(0, 60)}`); process.exit(1); }
  s = s.replace(anchor, () => replacement);
  console.log(`[${label}] ok`);
}
for (const probe of ['function aiProvRender', 'sheetAiProv', 'AI_PROVS']) {
  if (s.includes(probe)) { console.error(`已打过补丁或撞名（${probe}），拒绝重跑`); process.exit(1); }
}

/* ① 服务商卡：写死三行 → 运行时渲染列表 + 真「+ 添加服务商」 */
{
  const start = span('        <div class="flex items-center justify-between"><div class="row-title">🧩 服务商管理</div>',
    ['DeepSeek', 'Ollama 本地', '应用自身零埋点']);
  const endMark = '          <div class="text-[10px] text-slate-400">协议：OpenAI 兼容 Chat Completions · 请求仅发往已配置端点，应用自身零埋点</div>\n';
  const j = s.indexOf(endMark, start);
  if (j < 0) { console.error('① 结束锚点未找到'); process.exit(1); }
  s = s.slice(0, start) + frag('card') + s.slice(j + endMark.length);
  console.log('[card] ok');
}

/* ② Key 配置卡：模型名输入（属服务商）换成当前端点摘要 + 编辑入口；Key 标注按服务商存 */
put('          <input class="inp w-full" placeholder="模型名，如 deepseek-flash" value="deepseek-flash">\n',
  '          <div id="apCur" class="rounded-xl bg-slate-50 dark:bg-slate-800/60 px-3 py-2 text-[11px]">当前端点：<b>DeepSeek</b></div>\n' +
  '          <div class="flex gap-2"><button class="mini-btn flex-1" onclick="aiProvEdit(aiCurProv().id)">编辑当前服务商</button>' +
  '<button class="mini-btn flex-1" onclick="aiProvEdit(null)">+ 新服务商</button></div>\n', 'keycard');
put('placeholder="API Key · sk-••••••••••••"',
  'placeholder="API Key · 当前服务商单独保存（sk-••••••••••••）"', 'keyhint');

/* ③ 新增/编辑弹层 */
put('  <div id="sheetNoteMove" class="sheet', frag('sheet') + '\n  <div id="sheetNoteMove" class="sheet', 'sheet');

/* ④ JS：服务商列表与表单逻辑 */
put('/* —— 提示词管理（AI批 · 与 assets/ai_prompts/prompts.json 同源的默认模板镜像） —— */',
  frag('js') + '/* —— 提示词管理（AI批 · 与 assets/ai_prompts/prompts.json 同源的默认模板镜像） —— */', 'js');

/* ⑤ 启动即渲染服务商列表（与 AI 使用记录摘要同批挂载） */
put("auBootRender(); /* V1.53 AI 使用记录：入口卡摘要先出数 */",
  "auBootRender(); /* V1.53 AI 使用记录：入口卡摘要先出数 */\naiProvRender(); /* V1.53.1 服务商列表运行时渲染 */", 'boot');

const grew = s.length - before;
if (grew < 1500 || grew > 40000) { console.error(`体积变化异常（${grew}），拒绝写回`); process.exit(1); }
for (const need of ['function aiProvRender', 'id="sheetAiProv"', 'id="aiProvList"', 'id="apCur"', 'aiProvPing']) {
  if (!s.includes(need)) { console.error(`产物缺少 ${need}`); process.exit(1); }
}
if (/placeholder="模型名，如 deepseek-flash"/.test(s)) { console.error('旧模型输入残留'); process.exit(1); }
fs.writeFileSync(F, s);
console.log(`OK 写入完成：${before} → ${s.length}（+${grew}）`);
