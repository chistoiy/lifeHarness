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
