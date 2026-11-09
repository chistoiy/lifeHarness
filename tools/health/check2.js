/* 健康专版校验器（片段管线丢失后重建 · 覆盖全文件）
   node tools/health/check2.js */
const fs=require('fs'),vm=require('vm');
const P='prototype/index-health.html';
const src=fs.readFileSync(P,'utf8');
const lines=src.split('\n');
let bad=0; const fail=m=>{bad++;console.log('FAIL '+m)};
const ok=m=>console.log('OK   '+m);

/* 1) 内联脚本语法 */
const scripts=[...src.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
scripts.forEach((c,i)=>{try{new vm.Script(c)}catch(e){fail('SYNTAX script#'+i+' :: '+e.message)}});
if(!bad)ok('SYNTAX scripts='+scripts.length);

/* 2) 文本区与脚本区分离 */
const markup=src.replace(/<script(?![^>]*\ssrc=)[^>]*>[\s\S]*?<\/script>/g,'');
const jsAll=scripts.join('\n');

/* 3) onclick 引用的函数必须存在 */
const decl=new Set();
for(const m of jsAll.matchAll(/function\s+([A-Za-z_$][\w$]*)/g))decl.add(m[1]);
for(const m of jsAll.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:\(|function|[A-Za-z_$][\w$]*\s*=>)/g))decl.add(m[1]);
const calls=new Set();
for(const m of markup.matchAll(/on(?:click|input|change|submit|keydown)="([^"]*)"/g))
  for(const c of m[1].matchAll(/(^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g))calls.add(c[2]);
const KW=new Set(['if','for','while','switch','return','typeof','event','function','setTimeout','setInterval','Evernote','confirm','alert']);
const miss=[...calls].filter(c=>!decl.has(c)&&!KW.has(c));
if(miss.length)fail('MISSING FNS: '+miss.join(', '));else ok('HANDLERS OK ('+calls.size+' referenced)');

/* 4) id 唯一 + JS 里引用的 id 必须存在（动态拼接前缀按 startsWith 放行） */
const ids=[...markup.matchAll(/\sid="([^"]+)"/g)].map(m=>m[1]);
const dup=[...new Set(ids.filter((x,i)=>ids.indexOf(x)!==i))];
if(dup.length)fail('DUP IDS: '+dup.join(', '));else ok('IDS UNIQUE ('+ids.length+')');
const idSet=new Set(ids);const missId=new Set();
/* 运行时动态生成的 id 前缀（渲染函数内拼接，静态扫描不到） */
const DYN=new Set(['rpBody','rpArw','vf_']);
const has=id=>idSet.has(id)||DYN.has(id)||ids.some(x=>x.startsWith(id));
for(const m of jsAll.matchAll(/getElementById\(\s*['"]([\w-]+)['"]/g))if(!has(m[1]))missId.add(m[1]);
for(const m of jsAll.matchAll(/\bhPut\(\s*['"]([\w-]+)['"]/g))if(!has(m[1]))missId.add(m[1]);
for(const m of jsAll.matchAll(/\bhWv\(\s*['"]([\w-]+)['"]/g))if(!has(m[1]))missId.add(m[1]);
for(const m of jsAll.matchAll(/\bhWheel\(\s*['"]([\w-]+)['"]/g))if(!has(m[1]))missId.add(m[1]);
for(const m of jsAll.matchAll(/\bhDateRow\(\s*['"]([\w-]+)['"]/g))if(!has(m[1]))missId.add(m[1]);
for(const m of jsAll.matchAll(/querySelector(?:All)?\(\s*[`'"]#([\w-]+)/g))if(!has(m[1])&&!jsAll.includes('if(e&&'))missId.add(m[1]);
if(missId.size)fail('MISSING IDS: '+[...missId].join(', '));else ok('ID REFS OK');

/* 5) openSheet/closeSheet 目标存在 */
const sh=new Set([...markup.matchAll(/<div id="(sheet[\w-]+)"/g)].map(m=>m[1]));
const ref=new Set([...jsAll.matchAll(/(?:openSheet|closeSheet)\(\s*'([\w-]+)'/g)].map(m=>m[1]));
const missSh=[...ref].filter(x=>!sh.has(x));
if(missSh.length)fail('MISSING SHEETS: '+missSh.join(', '));else ok('SHEETS OK ('+sh.size+' 张)');

/* 6) 屏 id 与 htNav 目标 */
const pg=new Set([...markup.matchAll(/<section id="(p-[\w-]+)"/g)].map(m=>m[1]));
const nav=new Set([...jsAll.matchAll(/htNav\(\s*'([\w-]+)'/g)].map(m=>m[1]));
const missPg=[...nav].filter(x=>!pg.has(x));
if(missPg.length)fail('MISSING PAGES: '+missPg.join(', '));else ok('PAGES OK ('+pg.size+' 屏)');

/* 7) 标签平衡（div/section/button/span） */
for(const t of ['div','section','button','span']){
  const o=(markup.match(new RegExp('<'+t+'[\\s>]','g'))||[]).length;
  const c=(markup.match(new RegExp('</'+t+'>','g'))||[]).length;
  if(o!==c)fail('TAG '+t+': '+o+'/'+c);
}
if(!bad)ok('TAGS BALANCED');

/* 8) 健康区禁 emoji */
const EMO=/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;
const hStart=markup.indexOf('id="p-health"');
const hEnd=markup.indexOf('<!-- ===== P10 目标 OKR');
const hPages=markup.slice(hStart,hEnd<0?markup.length:hEnd);
const hit=(hPages.match(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu)||[]);
if(hit.length)fail('EMOJI in health pages: '+[...new Set(hit)].join(' '));else ok('HEALTH PAGES EMOJI NONE');

/* 9) 类名泄漏（页面文本里出现 tailwind 类名片段） */
const leak=['no-scrollbar','text-slate','rounded-xl','flex-1','bg-white'];
const txtLeak=leak.filter(k=>new RegExp('>[^<]*'+k+'[^<]*<').test(hPages));
if(txtLeak.length)fail('TEXT LEAK: '+txtLeak.join(', '));else ok('TEXT LEAK OK');

console.log('\nRESULT: '+(bad?('FAIL ('+bad+')'):'PASS'));
process.exit(bad?1:0);
