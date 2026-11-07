/* ux162_mut.js · 2026-10-07 UX 批原型闸的变异自证（三刀，单批 ≤3）
 * 用法：node tools/ux162_mut.js
 * 刀1 摘「全选」文案与可见性同步 → U1/U2 红
 * 刀2 记录管理那行的入口 id 改名（等价于「天气行没挪进来」）→ U3 红
 * 刀3 当前服务商行不再开选单 → U4/U5 红
 */
const fs = require('fs'), path = require('path'), crypto = require('crypto'), { spawnSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index.html');
const orig = fs.readFileSync(HTML, 'utf8');
const md5 = s => crypto.createHash('md5').update(s).digest('hex').slice(0, 8);
const base = md5(orig);
let bad = 0;
function run() {
  const r = spawnSync(process.execPath, ['--experimental-websocket', path.join(ROOT, 'tools', 'ux162check.js')],
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
    + (hit ? ' 全红' : ' 未全红（死闸！）实红=' + JSON.stringify(r.fails)) + ' ｜ 复原=' + (restored ? 'md5 一致' : '不一致'));
  if (!hit || !restored) bad++;
}
console.log('== 基线 =='); const b = run(); console.log(b.tail, 'fails=' + JSON.stringify(b.fails));
if (b.fails.length) bad++;
knife('刀1 摘全选文案同步',
  "  const a = $('#mcAllBtn'); if (a) { a.textContent = (n && mcOn.size === n) ? '取消全选' : '全选'; a.style.display = n ? '' : 'none' }\n",
  '', ['U1', 'U2']);
knife('刀2 记录管理天气行改 id',
  '<button id="rwCity" class="mini-btn" onclick="openSheet(\'sheetCityPick\')">常州市</button>',
  '<button id="rwCityX" class="mini-btn" onclick="openSheet(\'sheetCityPick\')">常州市</button>', ['U3']);
knife('刀3 当前行不再开选单',
  '<button id="aiCurRow" onclick="aiPickOpen()"',
  '<button id="aiCurRow"', ['U5']);
console.log(bad ? '== 变异自证未过：' + bad + ' 项 ==' : '== 变异自证全过 ==');
process.exit(bad ? 1 : 0);
