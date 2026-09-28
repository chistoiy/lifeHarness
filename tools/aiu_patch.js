/* V1.53「AI 使用记录」原型补丁（prototype/index.html）
 * 一次性执行：命中断言 + 体积护栏 + 改前快照（大文件脚本化修改三条护栏，见交接文档 §6）。
 * 用法：node tools/aiu_patch.js
 */
const fs = require('fs');
const F = 'prototype/index.html';
const SNAP = 'tools/aiu_snapshot_before.html';
let s = fs.readFileSync(F, 'utf8');
const before = s.length;
if (!fs.existsSync(SNAP)) fs.writeFileSync(SNAP, s);
for (const probe of ['p-aiUsage', 'AI_CALLS', 'function auRender', 'sheetAiUsageCfg']) {
  if (s.includes(probe)) {
    console.error(`已打过补丁或撞名（存在 ${probe}），拒绝重跑`);
    process.exit(1);
  }
}
const frag = (f) => fs.readFileSync('tools/aiu_frag_' + f + '.txt', 'utf8');
function put(anchor, replacement, label, hits = 1) {
  const n = s.split(anchor).length - 1;
  if (n !== hits) {
    console.error(`[${label}] 锚点命中 ${n} 次（期望 ${hits}）：${anchor.slice(0, 80)}`);
    process.exit(1);
  }
  s = s.replace(anchor, () => replacement);
  console.log(`[${label}] ok`);
}

/* ① CSS：日志行族之后补 AI 记录行族 */
put(
  '  .logline.lv-ERROR{background:color-mix(in srgb,#ef4444 6%,transparent)}\n',
  '  .logline.lv-ERROR{background:color-mix(in srgb,#ef4444 6%,transparent)}\n' + frag('css'),
  'css'
);

/* ② TITLES 注册新页 */
put(
  "'p-logs':['日志管理','运行日志 · 级别筛选 · 落盘配置']};",
  "'p-logs':['日志管理','运行日志 · 级别筛选 · 落盘配置'],'p-aiUsage':['AI 使用记录','输入输出留痕 · 按模块筛选 · 可查可删']};",
  'titles'
);

/* ③ 新全屏页：插在提示词编辑页之后 */
const editEnd =
  '        <div class="text-[10px] text-slate-400 mt-2 leading-5">保存后该能力点即刻使用此模板发起请求；清空内容等同恢复默认。</div>\n' +
  '      </div>\n' +
  '    </section>\n';
put(editEnd, editEnd + '\n' + frag('page'), 'page');

/* ④ AI 增强页顶部入口卡（含用量摘要 + 查看全部） */
const promptsCard =
  '      <div class="card mt-3">\n' +
  '        <div class="flex items-center justify-between"><div class="row-title">🧪 提示词管理</div>';
put(promptsCard, frag('card') + promptsCard, 'card');

/* ⑤ 记录设置弹层 */
const sheetAnchor = '  <div id="sheetNoteMove" class="sheet';
put(sheetAnchor, frag('sheet') + '\n' + sheetAnchor, 'sheet');

/* ⑥ JS：数据 + 渲染 + 筛选 + 查删（插在提示词管理 JS 块之前） */
const jsAnchor = '/* —— 提示词管理（AI批 · 与 assets/ai_prompts/prompts.json 同源的默认模板镜像） —— */';
put(jsAnchor, frag('js') + '\n' + jsAnchor, 'js');

const grew = s.length - before;
if (grew < 6000) {
  console.error(`体积增长异常（+${grew} 字节，期望 >6000），已拒绝写回`);
  process.exit(1);
}
fs.writeFileSync(F, s);
console.log(`OK 写入完成：${before} → ${s.length} 字节（+${grew}）`);
