// 期4真件验证：同一 @js 片段在 真QuickJS(qjs.exe 2026-06-04) 与 Node 下结果对比
import { execFileSync } from 'child_process';
import fs from 'fs';

const CASES = [
  { name: '酷我·状态码转文字', input: '玄幻言情,50',
    js: `result=result.replace(/30/,"连载").replace(/50/,"完结");` },
  { name: '起点·URL模板+java.put', input: '',
    js: `url=baseUrl+"/so/"+encodeURIComponent("测试")+".html";java.put('url',url);result=url;`,
    check: r => r.includes('/so/') },
  { name: '来看·GBK手工encode循环', input: 'act=ABC&q=测试&submit=搜索',
    js: `var xx=result.match(/[^&=]+/g);var out=[];for(var i=0;i<xx.length;i++){out.push(encodeURIComponent(xx[i]));}result=out.length;` },
  { name: '速读谷·正则分组替换', input: '简介文字。第二句！第三句?',
    js: `result=result.replace(/(^|[。！？]+)/g,"$1<br>");` },
  { name: '艾途·JSON解析', input: '{"content":"正文测试","replace":{"aa":"A"}}',
    js: `var r=JSON.parse(result); if(r.content!=null){var e=r.replace; for(var k in e){ r.content=r.content.replace(new RegExp(k,'ig'),e[k]); } result=r.content; }` },
  { name: '奇探·链式match分组提取', input: 'init(v="x"); chapter_url="/c/42.html";',
    js: `var m=result.match(/c.([0-9]+)\\.html/);result=m?m[1]:'ERR';` },
  { name: '通用·箭头函数+模板串', input: '',
    js: 'var f=x=>x*2; result=`计算${f(21)}`;' },
  { name: '通用·try-catch兜底', input: 'x',
    js: `try{ null.foo; }catch(e){ result='caught'; }` },
];

const prelude = (input) => `
var result=${JSON.stringify(input)};
var baseUrl="https://www.qidian.com";
var key="测试"; var page=2; var source={bookSourceUrl:baseUrl};
var java={log:function(){},toast:function(){},longToast:function(){},
  put:function(k,v){java.__m[k]=String(v);},
  getString:function(k){return java.__m[k]||'';},
  ajax:function(u){return '';}};
java.__m={};
var cookie={getCookie:function(){return '';},replaceCookie:function(){},removeCookie:function(){}};
`;

fs.mkdirSync('tmpjs', { recursive: true });
let pass = 0;
for (const c of CASES) {
  const body = prelude(c.input) + c.js + `\nconsole.log(JSON.stringify({out:result}));`;
  fs.writeFileSync('tmpjs/case.js', body);
  let qr, nr;
  try {
    qr = JSON.parse(execFileSync('qjs/qjs.exe', ['--std', 'tmpjs/case.js'], {maxBuffer: 1 << 24 }).toString().trim().split('\n').pop()).out;
  } catch (e) { qr = 'QJS_ERR:' + String(e.message || e).slice(0, 60); }
  try {
    nr = JSON.parse(execFileSync(process.execPath, ['tmpjs/case.js'], { maxBuffer: 1 << 24 }).toString().trim().split('\n').pop()).out;
  } catch (e) { nr = 'NODE_ERR:' + String(e).slice(0, 60); }
  const same = String(qr) === String(nr) && !String(qr).includes('ERR');
  const okCustom = c.check ? c.check(qr) && c.check(nr) : true;
  const ok = same && okCustom;
  if (ok) pass++;
  console.log(`${ok ? '✓' : '✗'} ${c.name}`);
  if (!ok) console.log(`    qjs=${String(qr).slice(0, 70)} | node=${String(nr).slice(0, 70)}`);
  else console.log(`    双引擎一致: ${String(nr).slice(0, 60)}`);
}
console.log(`\nparity ${pass}/${CASES.length}`);
process.exit(pass === CASES.length ? 0 : 1);
