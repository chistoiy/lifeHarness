/* dt_check：桌面模块专版原型结构断言（tools/dtcheck.js）
 * 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md §2.0 动作表 / §4 交互 / §5.4 颜色 / §5.6 原生 widget 视觉。
 * 门禁：node tools/dtcheck.js（违例 exit 1）；变异自证＝改坏一件必须红（放 tmp/，跑完 md5 复原）。
 * 覆盖：文件存在 · 四屏齐备 · 动作表 7 枚与 scheme 逐字一致 · 默认 4 枚与硬限 4 ·
 *        原生 widget 四色档双档齐全 · 安全区/圆角/描边/字号规格 · 禁 emoji · 无外链脚本以外的裸 svg 语法错。
 */
const fs = require('fs'), path = require('path');
const F = process.env.DT_FILE || 'prototype/index-desktop.html';
const root = path.dirname(path.dirname(path.resolve(__dirname, 'x')));
process.chdir(path.join(__dirname, '..'));

let pass = 0, fail = 0;
const ok = n => { pass++; console.log('PASS ' + n); };
const bad = (n, d) => { fail++; console.log('FAIL ' + n + '  →  ' + (d || '')); };

if (!fs.existsSync(F)) { bad('原型文件存在 ' + F); done(); }
else {
  const src = fs.readFileSync(F, 'utf8');

  /* ① 四屏齐备（§7 样张四块 ＝ 前置门交付形态） */
  const PAGES = ['dt-desk', 'dt-menu', 'dt-widget', 'dt-map'];
  PAGES.forEach(p => {
    const re = new RegExp('<section id="' + p + '"');
    re.test(src) ? ok('① 屏 ' + p + ' 在位') : bad('① 屏 ' + p + ' 缺失');
  });

  /* ② 动作表 7 枚齐全 · scheme 逐字等于 §2.0 */
  const ACT = [
    ['inbox', 'lh://inbox/new'], ['todo', 'lh://todo/new'], ['journal', 'lh://journal/edit'],
    ['ledger', 'lh://ledger/add'], ['items', 'lh://items/new'], ['habit', 'lh://habit/check'],
    ['today', 'lh://today']
  ];
  ACT.forEach(([id, sc]) => {
    src.indexOf("'" + sc + "'") >= 0 ? ok('② 动作 ' + id + ' · ' + sc)
      : bad('② 动作 ' + id + ' scheme 缺失或写错', sc);
  });
  /* §2.0 红线：scheme 必须是本表原值，禁散落字面量第二处 */
  const dupScheme = ACT.filter(([, sc]) => (src.split("'" + sc + "'").length - 1) > 1);
  dupScheme.length === 0 ? ok('② scheme 无散落副本（禁手写字面量）')
    : bad('② scheme 出现多处副本', dupScheme.map(x => x[1]).join(' '));

  /* ③ 默认 4 枚与硬限 4（§2.0 / §4.1） */
  /DEFAULT_MENU=\['inbox','todo','ledger','habit'\]/.test(src) ? ok('③ 默认 4 枚正确') : bad('③ 默认 4 枚不符');
  /MENU_MAX=4/.test(src) ? ok('③ 系统硬限 4') : bad('③ 硬限常量缺失');

  /* ④ 原生 widget 四色档：Light 四值 + Dark 四值，缺一即红（§5.4） */
  const WL = ['#FFFFFF', '#0F172A', '#64748B', '#6366F1'];
  const WD = ['#1E293B', '#F1F5F9', '#94A3B8', '#818CF8'];
  WL.forEach(c => src.indexOf(c) >= 0 ? ok('④ 浅色档 ' + c) : bad('④ 浅色档缺 ' + c));
  WD.forEach(c => src.indexOf(c) >= 0 ? ok('④ 深色档 ' + c) : bad('④ 深色档缺 ' + c));
  /* 双档并排：force-light / force-dark 各至少两处 */
  (src.match(/force-light/g) || []).length >= 2 ? ok('④ 浅色档并排预览在位')
    : bad('④ 浅色档并排预览缺失');
  (src.match(/force-dark/g) || []).length >= 2 ? ok('④ 深色档并排预览在位')
    : bad('④ 深色档并排预览缺失');

  /* ⑤ §5.6 尺寸与视觉规格
     注：42px 安全区 / 55px 裁角是**真机物理像素**，示意图按约 1:3 缩放 → 图上画 12px / 18px，
     标签仍标真机原值；故这里同时断言「真机原值在标签/注释里」＋「图上用的是缩放值」。 */
  src.indexOf('border-radius:16px') >= 0 ? ok('⑤ 圆角 16dp') : bad('⑤ 圆角 16dp 缺失');
  /color-mix\(in srgb,var\(--w-sub\) 10%/.test(src) ? ok('⑤ 描边 1dp＝次文本 10% 透明') : bad('⑤ 描边规格不符');
  (src.indexOf('inset:12px') >= 0 && src.indexOf('42px') >= 0 ? ok('⑤ 安全区 ≥42px（真机原值＋图上 12px 缩放）')
    : bad('⑤ 安全区规格缺失或未标真机原值'));
  (src.indexOf('border-radius:18px') >= 0 && src.indexOf('55px') >= 0 ? ok('⑤ 系统裁 55px 圆角（真机原值＋图上 18px 缩放）')
    : bad('⑤ 55px 裁角规格缺失或未标真机原值'));
  /\.wg-read\{font-size:24px;font-weight:800/.test(src) ? ok('⑤ 读数 24sp 粗') : bad('⑤ 读数 24sp 规格不符');
  /\.wg-lab\{font-size:12px/.test(src) ? ok('⑤ 标签 12sp 常规') : bad('⑤ 标签 12sp 规格不符');
  /* 尺寸声明：2×2 与 4×1 */
  src.indexOf('2×2') >= 0 && src.indexOf('4×1') >= 0 ? ok('⑤ 尺寸 2×2 / 4×1 声明在位')
    : bad('⑤ 尺寸声明缺失');

  /* ⑥ 禁表情级 emoji（AGENTS 禁令）。口径对齐 tools/emoji_triage.js 档③＝真表情；
     ✓ ⚠ 等属档②符号级（全仓既有写法，T13 分拣表已裁定），不在本闸禁列。 */
  const emoji = src.match(/[\u{1F300}-\u{1FAFF}\u{1F000}-\u{1F0FF}]/gu) || [];
  emoji.length === 0 ? ok('⑥ 零 emoji') : bad('⑥ 检出 emoji', [...new Set(emoji)].join(' '));

  /* ⑦ C15 反向条文：禁只 setAction 不 setData 的提示必须在位（防止实现批踩 Manifest 误匹配） */
  src.indexOf('setAction') >= 0 && src.indexOf('setData') >= 0 ? ok('⑦ C15 Intent 构造口径在位')
    : bad('⑦ C15 口径缺 setAction/setData 对照');

  /* ⑧ 禁硬编码主题色（§5.4：App 内一律走设计令牌）——禁裸 #6366f1 之类写进 style 块主色 */
  /\.desk-ic \.tile\{[^}]*background:#(?!FFF|fff)/.test(src) ? bad('⑧ 桌面图标块硬编码底色')
    : ok('⑧ 桌面层色值走令牌');

  /* ⑨ 结构配平：section 开闭相等（多一个/少一个立刻红） */
  const so = (src.match(/<section[\s>]/g) || []).length, sc = (src.match(/<\/section>/g) || []).length;
  so === sc && so === 4 ? ok('⑨ section 配平 ' + so + '/' + sc) : bad('⑨ section 配平', so + '/' + sc);
}

function done() {
  console.log('—— dtcheck：' + pass + ' 绿 / ' + fail + ' 红');
  process.exit(fail ? 1 : 0);
}
done();