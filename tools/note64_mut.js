/* note64_mut.js · V1.64 批2 笔记目录导入层级＋挂载移除 原型闸变异自证（三刀，单批 ≤3）
 * 用法：node tools/note64_mut.js   （靶＝prototype/index-bookshelf.html，闸＝tools/note64check.js）
 * 刀1 摘 niMount 的子夹递归（＝只挂根节点，层级不还原）→ N8 红（子夹节点数＝0）
 * 刀2 长按挂载节点当场就摘（＝摘掉「必须先确认」这道门）→ N13 红（弹层未开·节点已少）
 * 刀3 确认移除时连带删掉库内笔记（＝违拍板 H「保留在库」）→ N14 红（保留条数 0）＋N17 红（重导不再判重）
 * 三条纪律：锚点命中数必须＝1 才注入；跑完与 ORIG 原文比 md5（不与批前快照比）；期望断言不红＝死闸，脚本非零退出。
 */
const fs = require('fs'), path = require('path'), crypto = require('crypto'), { spawnSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index-bookshelf.html');
const orig = fs.readFileSync(HTML, 'utf8');
const md5 = s => crypto.createHash('md5').update(s).digest('hex').slice(0, 8);
const base = md5(orig);
let bad = 0;
function run() {
  const r = spawnSync(process.execPath, ['--experimental-websocket', path.join(ROOT, 'tools', 'note64check.js')],
    { encoding: 'utf8', cwd: ROOT });
  const fails = (r.stdout || '').split('\n').filter(l => /^FAIL/.test(l)).map(l => l.split(' ')[1]);
  return { fails, tail: (r.stdout || '').split('\n').filter(l => /PASS \/ .* FAIL/.test(l))[0] || '(无收尾行)' };
}
function knife(name, from, to, expectIds) {
  const n = orig.split(from).length - 1;
  if (n !== 1) { console.log('SKIP ' + name + '：锚点命中 ' + n); bad++; return }
  fs.writeFileSync(HTML, orig.replace(from, to), 'utf8');
  const r = run();
  fs.writeFileSync(HTML, orig, 'utf8');
  const restored = md5(fs.readFileSync(HTML, 'utf8')) === base;
  const hit = expectIds.every(e => r.fails.includes(e));
  console.log((hit && restored ? 'OK   ' : 'MISS ') + name + ' → 期望 ' + expectIds.join('/')
    + (hit ? ' 红' : ' 未红（死闸！）实红=' + JSON.stringify(r.fails)) + ' ｜ 实红=' + JSON.stringify(r.fails)
    + ' ｜ 复原=' + (restored ? 'md5 一致' : '不一致'));
  if (!hit || !restored) bad++;
}
console.log('== 基线 =='); const b = run(); console.log(b.tail, 'fails=' + JSON.stringify(b.fails));
if (b.fails.length) bad++;
knife('刀1 摘子夹递归（层级不还原）',
  "  (node.c||[]).forEach(function(k){out.push.apply(out,niMount(k,hit.c));});",
  "  /* 刀1：子夹不再挂载 */",
  ['N8']);
knife('刀2 长按即摘（摘掉确认门）',
  "  if(nd&&(nd.src==='local'||nd.src==='export')){nuOpen(nd);return;}",
  "  if(nd&&(nd.src==='local'||nd.src==='export')){nuOpen(nd);nuDo();return;}",
  ['N13']);
knife('刀3 移除连带删库内笔记（违拍板 H）',
  " const p=ntFindPath(nm);if(p)p.arr.splice(p.i,1);",
  " const p=ntFindPath(nm);if(p){var sub=nuSub(p.arr[p.i]);p.arr.splice(p.i,1);D.notes=D.notes.filter(function(x){return sub.indexOf(x.folder)<0});}",
  ['N14', 'N17']);
console.log(bad ? 'MUT-RESULT FAIL 刀数异常 ' + bad : 'MUT-RESULT OK 三刀各红其位·复原 md5 全等（' + base + '）');
process.exit(bad ? 1 : 0);
