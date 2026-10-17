/* pfind.js · 对象定位（§8.2 轻量版）：人话别名/屏名/模块 id/深链 → {模块, 家, 代表屏, 关联工装}
 * 用法：node tools/pfind.js 记账        （别名模糊匹配，列模块与屏）
 *       node tools/pfind.js p-bookDetail（屏 id 反查归属）
 *       node tools/pfind.js --text "生成决算"  （转发 psearch 全文反查）
 * 未覆盖：--lh 词典档、--shot 截图档（动刀批按 §8.2 三档补全，届时先声明定位不到，勿硬猜）。
 * 别名非空闸要求查不到的关键词直接报错退出 1。
 */
const fs = require('fs');
const { execFileSync } = require('child_process');
const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
const args = process.argv.slice(2);
if (!args.length || args[0].startsWith('--h')) { console.log('用法见文件头'); process.exit(2); }
if (args[0] === '--text') {
  console.log(execFileSync('node', ['tools/psearch.js', args[1]].concat(args.slice(2)), { encoding: 'utf8' }));
  process.exit(0);
}
const q = args[0].toLowerCase();

const CHECKS = {
  shell: ['protostructcheck', 'hero144check', 'ts8check', 'trash6check', 'time52check', 'aiprovcheck', 'aiusagecheck', 'r1478check', 'f01typecheck'],
  read: ['bookshelf-check', 'br57check', 'xraycheck', 'protojscheck', 'f01typecheck'],
  ledger: ['ledgercheck', 'ledger3check', 'r151check', 'g1sharecheck'],
  habit: ['hbcheck', 'hb2check', 'g1sharecheck'],
  days: ['g1sharecheck'], items: ['g1sharecheck'], goals: ['g1sharecheck'],
  health: [], care: [], media: [], kits: [], sync: ['sync7check', 'syncproto_check'],
};
let mods = reg.modules.filter(m =>
  m.id.toLowerCase().includes(q) || q.includes(m.id) ||
  (m.name || '').toLowerCase().includes(q) ||
  (m.aliases || []).some(a => a.toLowerCase().includes(q) || q.includes(a.toLowerCase())));
const scr = reg.screens.filter(s => s.id.toLowerCase().includes(q) || (s.title || '').toLowerCase().includes(q));
if (!mods.length && !scr.length) {
  console.error('pfind 查不到："' + args[0] + '"（注册表无此别名/屏/标题——按 §8.2 直说定位不到，勿硬猜；可试 --text 反查文案）');
  process.exit(1);
}
for (const s of scr) {
  const home = s.status === 'collision' ? JSON.stringify(s.homes) : (s.home || '（已作废勿复活）');
  console.log(`屏 ${s.id}「${s.title || ''}」 家=${home} 代表屏允许处=${(s.reps || []).join(' ') || '-'} 现状副本=${Object.keys(s.files || {}).length} 份 状态=${s.status}${s.action ? ' 处置=' + s.action : ''}`);
}
for (const m of mods) {
  const screens = reg.screens.filter(s => s.home === m.file);
  console.log(`模块 ${m.id}「${m.name}」 状态=${m.status}/${m.dev} 专版=${m.file || '（壳内）'} 代表屏=${m.rep || '-'} 家屏 ${screens.length} 个 · 别名=${m.aliases.join('、')}`);
  console.log(`  工装：check=${(CHECKS[m.id] || []).join(' ') || '（无专版 check）'} · 读屏=tools/pslice.js ${m.file || 'index.html'} --list · 定位=tools/pfind.js`);
  if (screens.length) console.log('  屏：' + screens.slice(0, 12).map(s => s.id).join(' ') + (screens.length > 12 ? ` …共${screens.length}` : ''));
}
