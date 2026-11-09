/* R3-8 全局字体角色（LH-F01）· 原型改造脚本
   三条角色栈全部系统回落（不随包字体）：正文衬线 / UI 无衬线 / 数字等宽。
   护栏：逐条锚点命中数断言、体积只增、可选规则允许 0 命中但必须打印。 */
const fs = require('fs');

const FILES = [
  'D:/dev_workplace/flutter_te/lifeHarness/prototype/index.html',
  'D:/dev_workplace/flutter_te/lifeHarness/prototype/index-bookshelf.html',
];

const ROLES = [
  '  /* LH-F01 全局字体角色（产品 2026-10-02 定）：正文＝衬线（长文阅读），标题·UI·底栏＝无衬线，数字·代码＝等宽。',
  "     全部走系统回落链，不随包字体文件（Android 无 Microsoft YaHei，故它只作 Windows 预览兜底）。 */",
  "  :root{--f-ui:Inter,'Noto Sans SC','Source Han Sans SC','PingFang SC','Microsoft YaHei',system-ui,sans-serif;",
  "        --f-body:'Noto Serif SC','Source Han Serif SC','Songti SC','STSong','SimSun',Georgia,serif;",
  "        --f-code:ui-monospace,'JetBrains Mono',Consolas,Menlo,monospace}",
  "  .f-body{font-family:var(--f-body)}.f-code{font-family:var(--f-code)}",
].join('\n');

const RULES = [
  // 共享面
  { label: 'tailwind-sans', from: "sans: ['Inter','PingFang SC','Microsoft YaHei','sans-serif']",
    to: "sans: ['Inter','Noto Sans SC','Source Han Sans SC','PingFang SC','Microsoft YaHei','system-ui','sans-serif']", min: 1 },
  { label: 'html-body', from: "  html,body{height:100%;background:#0f172a;font-family:Inter,'PingFang SC','Microsoft YaHei',sans-serif;}",
    to: ROLES + "\n  html,body{height:100%;background:#0f172a;font-family:var(--f-ui);}", min: 1 },
  { label: 'retro-phone-serif', from: "  html[data-theme=\"retro\"] #phone{font-family:Georgia,'Songti SC','STSong','SimSun',serif;letter-spacing:.01em}",
    to: "  html[data-theme=\"retro\"] #phone{font-family:var(--f-body);letter-spacing:.01em}", min: 1 },
  { label: 'nav-ui', from: "  nav{background:var(--nav-bg)!important;border-color:var(--nav-bd)!important}",
    to: "  nav{background:var(--nav-bg)!important;border-color:var(--nav-bd)!important;font-family:var(--f-ui)}", min: 1 },
  { label: 'mono-stack', from: "font-family:ui-monospace,Consolas,monospace", to: "font-family:var(--f-code)", min: 1 },
  { label: 'times-serif', from: "font-family:Georgia,'Times New Roman',serif", to: "font-family:var(--f-body)", min: 1 },
  // 主题 JSON 里随包写的 app-font 值
  { label: 'theme-app-font-serif', from: "\"--app-font\":\"Georgia,'Songti SC','SimSun',serif\"", to: "\"--app-font\":\"var(--f-body)\"", min: 0 },
  { label: 'theme-app-font-mono', from: "\"--app-font\":\"ui-monospace,Consolas,Inter,sans-serif\"", to: "\"--app-font\":\"var(--f-code)\"", min: 0 },
  // 阅读器（书架专版独有）
  { label: 'br-fonts', from: "const BR_FONTS={system:['系统默认',\"'PingFang SC',system-ui,sans-serif\",'系统'],serif:['衬线','Georgia,\"Noto Serif SC\",serif','衬线'],song:['宋体','SimSun,\"Noto Serif SC\",serif','衬线'],hei:['黑体','SimHei,\"Microsoft YaHei\",sans-serif','黑体'],yahei:['雅黑','\"Microsoft YaHei\",sans-serif','黑体'],kaiti:['楷体','KaiTi,STKaiti,serif','楷体'],fangsong:['仿宋','FangSong,STFangsong,serif','楷体'],mono:['等宽','ui-monospace,monospace','其他'],xingshu:['行书','STXingkai,KaiTi,cursive','其他']};",
    to: "const BR_FONTS={system:['系统默认',\"'Noto Sans SC','Source Han Sans SC','PingFang SC',system-ui,sans-serif\",'系统'],serif:['衬线',\"'Noto Serif SC','Source Han Serif SC','Songti SC','SimSun',serif\",'衬线'],song:['宋体',\"'Noto Serif SC','SimSun',serif\",'衬线'],hei:['黑体',\"'Noto Sans SC','Source Han Sans SC',SimHei,'Microsoft YaHei',sans-serif\",'黑体'],yahei:['雅黑',\"'Microsoft YaHei','Noto Sans SC',sans-serif\",'黑体'],kaiti:['楷体',\"KaiTi,STKaiti,'Noto Serif SC',serif\",'楷体'],fangsong:['仿宋',\"FangSong,STFangsong,'Noto Serif SC',serif\",'楷体'],mono:['等宽',\"ui-monospace,'JetBrains Mono',Consolas,monospace\",'其他'],xingshu:['行书',\"STXingkai,KaiTi,'Noto Serif SC',cursive\",'其他']};",
    min: 0 },
  { label: 'br-def-serif', from: "theme:'day',bg:'#faf6ee',fg:'#3b3630',font:'system'",
    to: "theme:'day',bg:'#faf6ee',fg:'#3b3630',font:'serif'", min: 0 },
];

for (const f of FILES) {
  const s0 = fs.readFileSync(f, 'utf8');
  let s = s0, rep = 0, skip = [];
  for (const r of RULES) {
    const parts = s.split(r.from);
    const n = parts.length - 1;
    if (n === 0) { if (r.min > 0) throw new Error(f + ' :: MISS ' + r.label); skip.push(r.label); continue; }
    s = parts.join(r.to); rep += n;
  }
  const b0 = Buffer.byteLength(s0, 'utf8'), b1 = Buffer.byteLength(s, 'utf8');
  if (b1 <= b0) throw new Error(f + ' :: 体积没长大，可疑');
  fs.writeFileSync(f, s, 'utf8');
  console.log(f.split('/').pop(), '· 规则命中', rep, '· 跳过[' + skip.join(',') + ']', '· bytes', b0, '->', b1);
}
