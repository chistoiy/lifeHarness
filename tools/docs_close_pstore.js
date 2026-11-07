/* docs_close_pstore.js · 插件中心删屏批的文档收口（STATUS 本批段·变更日志·交棒工单 §3 追加一句）
 * 用法：node tools/docs_close_pstore.js
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const P = f => path.join(ROOT, f);
let touched = [];

/* 1 · STATUS 本批段 */
let s = fs.readFileSync(P('docs/STATUS.md'), 'utf8');
const a = '# STATUS（唯一状态源 · 最后更新 2026-10-07 **本批＝健康模块批0/1 数据层';
const b = '# STATUS（唯一状态源 · 最后更新 2026-10-07 **本批＝插件中心整簇下架（产品拍板「删屏」·提交待补）'
  + '＋健康模块批0/1 数据层';
if (s.split(a).length - 1 !== 1) throw new Error('STATUS 锚点命中异常——中止');
if (!s.includes('插件中心整簇下架')) { s = s.replace(a, b); touched.push('STATUS'); }

/* 2 · 变更日志追加一条 */
const L = fs.readFileSync(P('docs/交接文档.md'), 'utf8').split('\n');
const i = L.findIndex(l => l.startsWith('- 2026-10-07 13:0x'));
if (i < 0) throw new Error('变更日志锚点找不到——中止');
if (!L.some(l => l.startsWith('- 2026-10-07 13:4x'))) {
  L.splice(i + 1, 0,
    '- 2026-10-07 13:4x 插件中心整簇下架（产品拍板「删屏」）＝壳原型摘 `p-pstore` 屏＋`sheetPlugin`／`sheetPSDetail` 两弹层'
    + '＋插件中心 JS 簇（PS 数据与 renderPstore 等）＋ICONS/TITLES 两处登记＋init 行里的 `renderPstore()` 死调用，'
    + '净减 14,239 字符；Flutter 侧设置页「插件中心 · 敬请期待」占位行摘除（分类管理升为组末行）。'
    + '影音游专版 `index-media.html`（冻结）里那两份副本本刀不碰，注册表三件的 home 随之改指该文件——'
    + '随影音游开工批定去留（交棒工单 §3）。**插件化平台的调研与设计文档全部保留**，日后要做＝另批先过原型门。'
    + '闸＝`entryretirecheck.js` 6/6（E5 翻面成「摘净判定」）·protogate strict 全绿·registry 310 条全复现·'
    + 'protojscheck bad=0；常驻 `entry_retire_test` 新增一条防复活守护（7 例全绿）·analyze 零新增·DB 零迁移·未推送。');
  fs.writeFileSync(P('docs/交接文档.md'), L.join('\n'), 'utf8');
  touched.push('变更日志');
}

/* 3 · 交棒工单 §3 追加一句 */
const t = P('docs/handoff/交棒话术-20261007-健康批2起与影音游解禁.md');
let k = fs.readFileSync(t, 'utf8');
if (!k.includes('插件中心那两枚副本')) {
  k = k.replace('既有记忆口径：扁平主框架＋三模型（见项目记忆 `mediashelf-proto-and-plan`），插件化已否决。',
    '既有记忆口径：扁平主框架＋三模型（见项目记忆 `mediashelf-proto-and-plan`），插件化已否决。\n'
    + '**2026-10-07 追加**：壳里的插件中心已整簇下架（产品拍板「删屏」），`index-media.html` 里还留着 `p-pstore` 与 '
    + '`sheetPlugin` 两枚副本、注册表三件的 home 已改指该文件——影音游开工批第一件事就是定这两枚的去留（'
    + '要么随该模块正式登记，要么删净并把条目作废）。');
  fs.writeFileSync(t, k, 'utf8');
  touched.push('工单§3');
}
if (touched.length) fs.writeFileSync(P('docs/STATUS.md'), s, 'utf8');
console.log('TOUCHED ' + touched.join(' / '));
