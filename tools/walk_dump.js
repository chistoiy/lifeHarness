/* 真机走查取证工装 v2：dump → pull → 本地解析语义树（text/content-desc/rid + 中心点）
 * 用法：node tools/walk_dump.js [标签] [--tap "文本关键字"] [--back]
 * 说明：release 包无 run-as，取证＝语义树＋截图＋应用内日志页；坐标按 PNG/树原始像素（本机 1200x2670）。
 */
const { execSync } = require('child_process');
const fs = require('fs');
const Serial = 'ea028260';
const args = process.argv.slice(2);
const tag = args[0] && !args[0].startsWith('--') ? args[0] : 'now';
const tapFor = (() => { const i = args.indexOf('--tap'); return i >= 0 ? args[i + 1] : null; })();
const doBack = args.includes('--back');

function adb(cmd, opt) {
  return execSync(`adb -s ${Serial} shell "${cmd.replace(/"/g, '\\"')}"`, {
    encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
    env: Object.assign({}, process.env, { MSYS_NO_PATHCONV: '1', MSYS2_ARG_CONV_EXCL: '*' }),
    silent: true,
  });
}

function nodes() {
  adb('uiautomator dump /sdcard/walk.xml');
  const xml = adb('cat /sdcard/walk.xml');
  const out = [];
  for (const raw of xml.match(/<node\b[^>]*>/g) || []) {
    const attr = (k) => { const m = new RegExp(' ' + k + '="([^"]*)"').exec(raw); return m ? m[1] : ''; };
    const b = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(attr('bounds'));
    if (!b) continue;
    const label = (attr('text') || attr('content-desc') || '').replace(/\s+/g, ' ').trim();
    const rid = attr('resource-id').split('/').pop();
    if (!label && !rid) continue;
    out.push({ label: label.slice(0, 34) || rid, cx: Math.round((+b[1] + +b[3]) / 2),
      cy: Math.round((+b[2] + +b[4]) / 2), clickable: attr('clickable') === 'true' });
  }
  return out;
}

if (doBack) { adb('input keyevent KEYCODE_BACK'); }
let ns = nodes();
if (tapFor) {
  const hit = ns.filter(n => n.label.includes(tapFor) && n.clickable);
  const pick = hit.length ? hit[0] : ns.filter(n => n.label.includes(tapFor))[0];
  if (!pick) { console.log('TAP-MISS 未见：' + tapFor + '（当前 ' + ns.length + ' 节点）'); process.exit(2); }
  console.log('tap → ' + pick.cx + ',' + pick.cy + ' 「' + pick.label + '」');
  adb(`input tap ${pick.cx} ${pick.cy}`);
  ns = nodes();
}
fs.writeFileSync('tmp/walk-' + tag + '.json', JSON.stringify(ns, null, 1), 'utf8');
console.log('[' + tag + '] 节点 ' + ns.length + '（* ＝可点）');
ns.forEach(n => console.log('  ' + String(n.cx).padStart(4) + ',' + String(n.cy).padStart(4) + (n.clickable ? ' *' : '  ') + '  ' + n.label));
