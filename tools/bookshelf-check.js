const fs=require('fs');const p='prototype/index-bookshelf.html';const s=fs.readFileSync(p,'utf8');
const EM=/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu;
const r=[['pages',s.indexOf('<!-- ===== 书架专版 · P-B1'),s.indexOf('    <!-- ===== P4e 小工具合集 =====')],
 ['sheets',s.indexOf('<!-- ===== 书架专版 · 排序'),s.indexOf('<!-- ===== 目录导入格式说明')],
 ['js',s.indexOf('const BS_IC'),s.indexOf('/* ---------- 注册：标题')]];
for(const [n,a,b] of r){if(a<0||b<a){console.log(n,'RANGE FAIL');continue}
 const hits=[...new Set((s.slice(a,b).match(EM)||[]))];console.log(n+' emoji:',hits.join(' ')||'NONE')}
// 单引号串内误插 ${
const bad=[...s.matchAll(/'(?:[^'\n]*?)\$\{bsi\(/g)];console.log('string-内 bsi 误用:',bad.length, bad.slice(0,3).map(x=>s.slice(Math.max(0,x.index-40),x.index+40).replace(/\n/g,' ')).join(' || '));
// 关键函数存在性
['shViewIcon','bsi','bsSessions','bsTrack','bsSaveProgress','ebCovUI','ebCovRead','shGoalInit','shGoalRead','renderRecHub','renderBookDetail'].forEach(f=>{if(!s.includes('function '+f))console.log('MISSING fn',f)});
// 轨迹 tab 是否挂上
console.log('track tab wired:',s.includes("switchBookTab('t')")&&s.includes("bookTrack"));
console.log('bookTrack rendered:',s.includes("id=\"bookTrack\""));
/* ================= R14-4 + R14-6 原型批断言（2026-09-30 · 交棒话术 §3.1） ================= */
const A=[];
const cnt=(sub)=>s.split(sub).length-1;
// —— R14-4：三档卡各自存在且默认档为 A ——
A.push(['三档引擎 bsCovMode',cnt("function bsCovMode()")===1]);
A.push(['默认档 A（正文首图）',cnt("covFallback:'A 正文首图'")>=1]);
A.push(['A 档·首图回落渲染',cnt("bsCovHasFi")>=3]);
A.push(['B 档·书脊色块样式',cnt('.bs-covB{')===1&&cnt('bs-covB')>=3]);
A.push(['B 档·首字元素',cnt('bs-bi')>=2]);
A.push(['C 档·纯文字卡样式',cnt('.bs-covC{')===1&&cnt('bs-ci-t')>=2]);
A.push(['三档登记进阅读设置',cnt("['covFallback','无封面书卡','chips',['A 正文首图','B 书脊色块','C 纯文字卡']")===1]);
A.push(['书架同屏 A/B/C 切换器',cnt('id="bsCovDemo"')===1&&cnt('bsCovDemo(\'A\')')===1&&cnt('bsCovDemo(\'B\')')===1&&cnt('bsCovDemo(\'C\')')===1]);
A.push(['卡面内容注入活模板',cnt("'+bsCovInner(b)+bsProgressBadge")===2&&cnt('${bsCovInner(b)}')>=1&&cnt('cov.innerHTML=bsCovInner(b)')===1]);
A.push(['深链 #p-bookshelf_iN 切档',cnt("p==='p-bookshelf'&&n!=null)window._r144Dl")===1&&cnt('function r144Replay')===1]);
// —— R14-6：工具条容器有不透明底衬且样式含让位规则 ——
A.push(['工具条不透明底衬（token）',/#brSelBar\{[^}]*background:var\(--card\)/.test(s)&&/#brSelBar\{[^}]*backdrop-filter:none/.test(s)]);
A.push(['色板弹层同底衬',/#brColorPop\{[^}]*background:var\(--card\)/.test(s)]);
A.push(['深色模式同样不透明',s.includes('html.dark #brSelBar')]);
A.push(['箭头随底衬 token 色',s.includes('border-top-color:var(--card)')&&cnt('#brSelBar.flip::after')===1]);
A.push(['让位算法（上贴/下压/退化）',cnt('function brSelBarPlace')===1&&s.includes('tAbove>=cT')&&s.includes('tBelow+barH<=stg.height-cB')&&s.includes('stg.height-cB-barH')]);
A.push(['落位可取证 dataset.place',cnt('bar.dataset.place=place')===1]);
A.push(['手柄视觉放大一档',/\.br-h\{[^}]*width:15px[^}]*height:15px/.test(s)&&cnt('stage.left-7')===1]);
A.push(['?r146 深链三带演示',cnt("r146=(\\w+)")===1&&cnt("m==='top'?els[0]")===1]);
let fail=0;
for(const [n,ok] of A){console.log((ok?'PASS ':'FAIL ')+n);if(!ok)fail++}
const rng=r.filter(x=>x[1]<0||x[2]<x[1]).length;if(rng)fail+=rng;
console.log('R14 断言:',A.length-fail+'/'+A.length+(rng?'（另有 RANGE FAIL '+rng+' 段）':''));
process.exit(fail?1:0);
