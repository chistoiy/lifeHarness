/* bsrdpatch.js · 一次性：把阅读器能力合入 prototype/index-bookshelf.html
   锚点唯一性强校验；重复执行被守卫拦截。 */
const fs=require('fs'),P=require('path');
const HTML='prototype/index-bookshelf.html';
function rd(name){return fs.readFileSync(P.join(__dirname,name),'utf8').replace(/\r\n/g,'\n')}
let html=fs.readFileSync(HTML,'utf8').replace(/\r\n/g,'\n');
if(html.includes('p-localImport')){console.error('守卫：index-bookshelf.html 已包含阅读器能力，勿重复执行');process.exit(1)}
function one(name,from,to,count){const n=html.split(from).length-1;const exp=count||1;
  if(n!==exp){console.error('锚点异常 ['+name+'] 命中 '+n+' 次，期望 '+exp);process.exit(1)}
  html=html.split(from).join(to);console.log('OK ['+name+']')}

/* 1 沉浸路由 */
one('_imm',"(p==='p-readtimer'&&window.BS_FULLTIMER!==false);","(p==='p-readtimer'&&window.BS_FULLTIMER!==false)||p==='p-readerPage';");
/* 2 封面/行/书脊 本地标识 */
one('cov-badge','${bsProgressBadge(b)}<div class="au">${b.a}</div>','${bsProgressBadge(b)}${b.local?brCovBadge():\'\'}<div class="au">${b.a}</div>',3);
one('row-badge','<div class="text-[13px] font-bold truncate">${b.n}</div>','<div class="text-[13px] font-bold truncate">${b.n}${b.local?brRowBadge():\'\'}</div>');
one('spine-dot','<span>${b.n}</span><i style=','<span>${b.n}</span>${b.local?\'<u style="position:absolute;right:2px;bottom:2px;width:5px;height:5px;border-radius:99px;background:#fff;display:block" title="本地"></u>\':\'\'}<i style=');
/* 3 qeSave 保留划线出处（cf/rid/src） */
one('qesave-cf','if(qeCur>=0)BS_QUOTES[qeCur]=o;else BS_QUOTES.unshift(o);',
 'if(qeCur>=0){const _old=BS_QUOTES[qeCur];if(_old&&_old.cf){o.cf=_old.cf;o.rid=_old.rid;o.src=_old.src}BS_QUOTES[qeCur]=o}else BS_QUOTES.unshift(o);');
/* 4 阅读设置 · 本地阅读器分组 */
one('rs-group',"['sync','服务集成','info','WebDAV / 局域网备份']]]];",
 "['sync','服务集成','info','WebDAV / 局域网备份']]],\n ['本地阅读器',[['epub','导入本地 EPUB','nav',\"navTo('p-localImport');brImpGo(1)\",'添加图书流程内同样有入口 · Android 13+ SAF 单次读取'],['brSync','划线自动存为书摘','bool','阅读器高亮=按所选分类生成一条划线书摘 · 删除高亮同步移除'],['brLink','书籍内外部链接','chips',['禁止','询问','允许'],'章节内跳转不受限制 · 外链默认询问'],['brVoice','朗读音色','chips',['标准女声','温润男声','童声'],'离线引擎 · 扩展包按需下载控制体积'],['brBright','阅读时屏幕常亮','bool','进入阅读器自动生效 · 退出恢复系统策略']]]];");
/* 5 添加图书（先搜后加）FAB 菜单 · 导入本地图书 */
one('bsr-fab','<button class="mini-btn !text-[10.5px] !px-3" onclick="BSR.menu=false;bfOpenNew()">手动输入</button>',
 '<button class="mini-btn !text-[10.5px] !px-3" onclick="BSR.menu=false;navTo(\'p-localImport\');brImpGo(1)">导入本地图书（EPUB）</button>\n      <button class="mini-btn !text-[10.5px] !px-3" onclick="BSR.menu=false;bfOpenNew()">手动输入</button>');
/* 6 屏 / 弹层 / JS 合入 */
one('main','  </main>',rd('bs_frag_screens.txt')+'\n  </main>');
one('sheets','  <!-- ===== Toast ===== -->',rd('bs_frag_sheets.txt')+'\n  <!-- ===== Toast ===== -->');
one('js','store(); bsInit();','store(); bsInit();\n'+rd('bs_frag_js.txt'));
fs.writeFileSync(HTML,html);
console.log('合入完成 · 字节数',html.length);
