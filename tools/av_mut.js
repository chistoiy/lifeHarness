/* av_mut.js · 批①变异自证：摘掉决策行必须让对应断言变红（否则闸是死闸）
 * 用法：node tools/av_mut.js
 * 刀1＝摘 aiVfSend 的 avBusy 早退（防重入）→ 期望 V7 红
 * 刀2＝摘 aiVfJudge 的 Key 判定（401 归因）→ 期望 V9 红
 * 每刀跑完按内存原文复原并校验 md5，禁 git checkout（会同文件卷走他批改动）。
 */
const fs = require('fs'), path = require('path'), crypto = require('crypto'), { spawnSync } = require('child_process');
const HTML = path.resolve(__dirname, '..', 'prototype', 'index.html');
const orig = fs.readFileSync(HTML, 'utf8');
const md5 = s => crypto.createHash('md5').update(s).digest('hex').slice(0, 8);
const base = md5(orig);
let bad = 0;

function run() {
  const r = spawnSync(process.execPath, ['--experimental-websocket', path.resolve(__dirname, 'aiverifycheck.js')],
    { encoding: 'utf8', cwd: path.resolve(__dirname, '..') });
  const fails = (r.stdout || '').split('\n').filter(l => /^FAIL/.test(l)).map(l => l.split(' ')[1]);
  const tail = (r.stdout || '').split('\n').filter(l => /PASS \/ .* FAIL/.test(l))[0] || '(无收尾行)';
  return { fails, tail, rc: r.status };
}
function cut(name, from, expectId) {
  const n = orig.split(from).length - 1;
  if (n !== 1) { console.log('SKIP ' + name + '：锚点命中 ' + n + ' 处'); bad++; return }
  fs.writeFileSync(HTML, orig.replace(from, from.replace(/if\((avBusy|!k)\)/, 'if(false&&$1)')), 'utf8');
  const r = run();
  fs.writeFileSync(HTML, orig, 'utf8');
  const okRestore = md5(fs.readFileSync(HTML, 'utf8')) === base;
  const hit = r.fails.includes(expectId);
  console.log((hit && okRestore ? 'OK   ' : 'MISS ') + name + ' → ' + expectId + (hit ? ' 已红' : ' 仍绿（死闸！）')
    + ' ｜ 本轮 ' + r.tail + ' ｜ 复原=' + (okRestore ? 'md5 一致' : '不一致'));
  if (!hit || !okRestore) bad++;
}

console.log('== 基线 =='); const b = run(); console.log(b.tail, 'rc=' + b.rc, 'fails=' + JSON.stringify(b.fails));
if (b.fails.length) bad++;
cut('刀1 摘防重入早退', 'function aiVfSend(){if(avBusy)return;', 'V7');
cut('刀2 摘 401 Key 判定', ' if(!k)return {ok:false,lat:0,t:', 'V9');
console.log(bad ? '== 变异自证未过：' + bad + ' 项 ==' : '== 变异自证全过 ==');
process.exit(bad ? 1 : 0);
