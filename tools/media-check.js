// 影音游专版回归检查 · emoji 扫描 + 关键函数存在性 + 三视图与四类卡断言
// 用法：node tools/media-check.js [path]   默认 prototype/index-media.html
const fs = require('fs');
const p = process.argv[2] || 'prototype/index-media.html';
const s = fs.readFileSync(p, 'utf8');
const EM = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu;
// 范围：本副本内新增/修改段
const rs = s.indexOf('<div id="recMedia"'), re = s.indexOf('id="mdsHubRev"', rs);
const ranges = [
  ['mds-css', s.indexOf('/* ---- 影音游专版 · 桌面微拟物基线'), s.indexOf('</style>')],
  ['recMedia-workbench', rs, re],
  ['mds-pages+sheets', s.indexOf('<!-- ===== 影音游专版 · M-SHELF'), s.indexOf('<!-- ===== P10c 母婴呵护')],
  ['mds-js', s.indexOf('let MDEMO=['), s.lastIndexOf('</script>')],
];
for (const [n, a, b] of ranges) {
  if (a < 0 || b < a) { console.log(n, 'RANGE FAIL (anchor missing)'); continue; }
  const hits = [...new Set((s.slice(a, b).match(EM) || []))];
  console.log(n + ' emoji:', hits.join(' ') || 'NONE');
}
// 关键函数存在性
['mItems', 'mCardHTML', 'mRenderShelf', 'mRenderHub', 'mRenderDetail', 'mRenderNotes', 'mRenderMgr',
  'mRenderLists', 'mRenderStat', 'mRenderGoal', 'mRenderImport', 'mRenderSortSheet', 'mRenderOpsSheet',
  'mRenderProgressSheet', 'mSetAddKind', 'mAddSave', 'mOpen', 'mMusicTap', 'mSeriesTap',
  'mCycleState', 'mToggleSel', 'mBulkDel'].forEach(f => { if (!s.includes('function ' + f)) console.log('MISSING fn', f) });
// 关键屏 id 存在性（工作台已并入共享记录页 #recMedia·不再有独立 m-hub）
['recMedia', 'm-shelf', 'm-detail', 'm-notes', 'm-mgr', 'm-lists', 'm-stat', 'm-goal', 'm-import', 'm-timer',
  'm-sheet-add', 'm-sheet-sort', 'm-sheet-ops', 'm-sheet-note-edit', 'm-sheet-progress', 'm-sheet-search'].forEach(id => {
  if (!s.includes('id="' + id + '"')) console.log('MISSING id', id);
});
// 四类卡 CSS 类存在性
['mds-movie', 'mds-series', 'mds-music', 'mds-game', 'mds-desk', 'mds-card', 'mds-badge'].forEach(c => {
  if (!s.includes('.' + c)) console.log('MISSING css', c);
});
// 微拟物令牌
['--mds-desk-bg', '--mds-shadow-contact', '--mds-shadow-ambient', '--mds-font-title', '--mds-font-mono',
  '--mds-plastic-hl', '--mds-box-blue', '--mds-vinyl-black', '--mds-tape-plastic'].forEach(t => {
  if (!s.includes(t)) console.log('MISSING token', t);
});
// 剧集 BOX 书脊 + 单集迷你碟
console.log('series spine:', s.includes('.mds-series .spine'));
console.log('series discs (单集迷你碟):', s.includes('.mds-series .discs') && s.includes('class="disc"'));
// 黑胶旋转动画
console.log('vinyl spin:', s.includes('@keyframes mdsSpin') && s.includes('mds-music.spin'));
// 电影卡右上卷边
console.log('movie curl (::after):', s.includes('.mds-movie::after'));
// 卡带撕角 + 金手指 + 卡槽
console.log('game sticker curl:', s.includes('.mds-game .sticker::after'));
console.log('game connector (金手指):', s.includes('.mds-game .connector'));
console.log('game slot (卡槽):', s.includes('.mds-game .slot'));
// 脊视图电影隐藏
console.log('spine skips movie:', s.includes("x.kind!=='movie'"));
// 复习卡翻面
console.log('review flip:', s.includes('.mds-rev.flipped') && s.includes('mFlipReview'));
// 桌面热力图
console.log('desk heatmap:', s.includes('.mds-heat') && s.includes('mRenderStat'));
// 与阅读不共表口径提示
console.log('plan doc linked:', require('fs').existsSync('docs/影音游模块开发计划-20260922.md'));
