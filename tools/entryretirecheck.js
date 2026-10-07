/* entryretirecheck.js · 批②③原型面静态闸（无需浏览器：纯文本判定）
 * 用法：node tools/entryretirecheck.js
 * 刀口：待办页回收站末卡与主页插件中心瓦片＝已下架，不许复活；留下的两枚回收站入口与 p-pstore 屏不许被顺手删。
 */
const fs = require('fs'), path = require('path');
const HTML = path.resolve(__dirname, '..', 'prototype', 'index.html');
const REG = path.resolve(__dirname, '..', 'prototype', '_modules.json');
const s = fs.readFileSync(HTML, 'utf8');
const reg = JSON.parse(fs.readFileSync(REG, 'utf8'));
let pass = 0, fail = 0;
const ok = (n, i) => { pass++; console.log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; console.log('FAIL ' + n + '  →  ' + (i || '')) };
function block(id) {
  const re = new RegExp('<(section|div)\\b[^>]*\\bid="' + id + '"');
  const m = re.exec(s); if (!m) return null;
  const tag = m[1]; const r2 = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi'); r2.lastIndex = m.index;
  let d = 0, x, end = -1;
  while ((x = r2.exec(s))) { d += x[0][1] === '/' ? -1 : 1; if (d === 0) { end = r2.lastIndex; break } }
  return end < 0 ? null : s.slice(m.index, end);
}

/* E1 待办页段内不再有回收站末卡（判定用结构指纹；段里那行下架记号注释含「回收站」三字，属留痕不是入口） */
const todo = block('p-todo') || '';
(!todo.includes('todoTrashMeta') && !/ttOpen\(/.test(todo) && !/onclick="ttOpen/.test(todo)
    && !/<button class="mt-4 w-full card !py-3/.test(todo))
  ? ok('E1 p-todo 段内无回收站入口卡') : bad('E1', '入口指纹仍在');

/* E2 ttOpen 死函数已摘净 */
(!/function\s+ttOpen\s*\(/.test(s)) ? ok('E2 ttOpen 已随入口摘除') : bad('E2', '函数仍在');

/* E3 全部功能宫格不再有插件中心 */
(!s.includes("['🧩','插件中心','p-pstore']")) ? ok('E3 宫格瓦片已摘') : bad('E3', '瓦片仍在');

/* E4 反向：留下的两枚回收站入口不许被顺手删（我的页行＋回收站屏） */
const prof = block('p-profile') || '';
(prof.includes('pfTrashCnt') && (block('p-sub-trash') || '').length > 500)
  ? ok('E4 「我的」页入口与回收站屏在位') : bad('E4', JSON.stringify({ prof: prof.includes('pfTrashCnt') }));

/* E5 p-pstore 屏本体留着（本批只摘入口，屏的去留等产品裁定） */
((block('p-pstore') || '').length > 200) ? ok('E5 插件中心屏仍在册待裁定') : bad('E5', '屏被误删');

/* E6 批①新屏已登记（防「改了原型没入册」） */
const v = reg.screens.filter(x => x.id === 'p-sub-aiVerify')[0];
(v && v.home === 'index.html' && v.files && v.files['index.html'] && v.files['index.html'].hash)
  ? ok('E6 p-sub-aiVerify 已登记且有实测 hash', v && v.files['index.html'].hash) : bad('E6', JSON.stringify(v));

console.log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
process.exit(fail ? 1 : 0);
