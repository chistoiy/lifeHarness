/* V1.53.2 轮5 · 深链钩子补丁（?br55=sel|fold|jump|note）+ 页码读数断言用 */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
const mark = "}catch(e){console.warn('br53',e)}})();\n";
const n = src.split(mark).length - 1;
if (n !== 1) { console.error('MISS br53Boot 尾部，命中 ' + n); process.exit(1); }
const hook = mark + [
  '/* V1.53.2 轮5 深链：?br55=sel|fold|jump|note → 选区手柄 / 全折叠 / 跳章返回 / 注释卡 */',
  "(function br55Boot(){try{",
  "  const m=(location.search.match(/br55=(\\w+)/)||[])[1];if(!m)return;",
  "  brOpen('b1');brShowChrome();",
  "  if(m==='sel'){const el=document.querySelector('#brBody [data-pi=\"2\"]')||document.querySelector('#brBody [data-pi]');",
  "    if(el){const pi=+el.dataset.pi;const t=(brChText(brV.b,brLeaves(brV.b)[brV.ci])[pi]||{}).t||'';",
  "      const w=brWordAt(t,4);brSelect(pi,pi,w[0],w[1]);brBindHandles();brHandlePlace()}}",
  "  else if(m==='fold'){brTocOpen('toc');brDrFoldAll();brDrFoldAll()}",
  "  else if(m==='jump'){brTocOpen('toc');brGotoCh(9)}",
  "  else if(m==='note'){const el=document.querySelector('#brBody [data-pi=\"2\"]');if(el)brNoteShow('锚定：启发式之一，判断受最先取得的信息支配，见附录「启发式与偏差清单」。',brV.ci,+el.dataset.pi)}",
  "}catch(e){console.warn('br55',e)}})();",
].join('\n');
const at = src.indexOf(mark);
src = src.slice(0, at) + hook + src.slice(at + mark.length);
fs.writeFileSync(F, src);
console.log('size ' + origLen + ' → ' + src.length);
if (src.length < origLen) { console.error('体积缩小，异常'); process.exit(1); }
