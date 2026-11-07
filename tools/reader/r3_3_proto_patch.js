/* R3-3 批C · 原型补丁：AI 精化过程可见性（面板段内 + X-Ray 中心两处同构）。
   按真实编码读入、锚点命中断言、体积校验，任一不命中即整批不落盘。 */
const fs = require('fs');
const P = 'D:/dev_workplace/flutter_te/lifeHarness/prototype/index-bookshelf.html';
const src = fs.readFileSync(P, 'utf8');
const size0 = Buffer.byteLength(src, 'utf8');
const nl = src.includes('\r\n') ? '\r\n' : '\n';
const J = (a) => a.join(nl);

let s = src;
const hits = [];
function rep(label, from, to) {
  const f = J(from), t = J(to);
  const i = s.indexOf(f);
  if (i < 0) throw new Error('ANCHOR MISS: ' + label);
  if (s.indexOf(f, i + 1) >= 0) throw new Error('ANCHOR AMBIGUOUS: ' + label);
  s = s.slice(0, i) + t + s.slice(i + f.length);
  hits.push(label);
}

// 1) XRAI 状态加逐批明细与展开位
rep('state', [
  "  var XRAI={st:'idle',b:0,n:0,err:0,budget:3000,scope:'book',sel:{},t:0,applied:0};",
], [
  "  var XRAI={st:'idle',b:0,n:0,err:0,budget:3000,scope:'book',sel:{},t:0,applied:0,log:[],open:false};",
  "  /* R3-3 过程可见性：每批一条明细（条数/前 3 词名/删改补/用时/tokens/失败归类）。",
  "     演示数据按下标定值，断言可钉；四类失败原因轮转，一屏能看到全部口径。 */",
  "  var XRAI_FAILS=['超时','端点无响应','输出不合约定','未授权'];",
  "  function xrAiSimRow(i,n){",
  "    var c=['几乎','概念','种种','玫瑰战争','谷地庄园','波洛','马普尔','王座','御前会议'];",
  "    var del=i%3, cls=(i+1)%3, add=(i+2)%2;",
  "    var fail=(XRAI.err&&i===XRAI.err);",
  "    return {",
  "      i:i, n:n, cnt:8+((i*5)%9),",
  "      prev:[c[(i*2)%c.length],c[(i*2+1)%c.length],c[(i*2+3)%c.length]],",
  "      del:fail?0:del, cls:fail?0:cls, add:fail?0:add,",
  "      sec:fail?6.0:(1.2+((i*7)%9)/10), tok:Math.round((8+((i*5)%9))*900/1.5),",
  "      fail:fail?XRAI_FAILS[i%XRAI_FAILS.length]:''",
  "    };",
  "  }",
  "  window.xrAiLogToggle=function(){XRAI.open=!XRAI.open;xrAiBarRender();};",
  "  window.xrAiLogHtml=function(){",
  "    if(!XRAI.log.length)return '';",
  "    var g={del:0,cls:0,add:0};XRAI.log.forEach(function(r){g.del+=r.del;g.cls+=r.cls;g.add+=r.add});",
  "    var h='<div class=\"mt-1.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2\">'",
  "      +'<div class=\"flex items-center gap-2 text-[9.5px] font-bold\"><span id=\"xrAiSum\">已出建议 删 '+g.del+' · 改 '+g.cls+' · 补 '+g.add+'</span>'",
  "      +'<span class=\"flex-1\"></span><span class=\"text-slate-400\" id=\"xrAiLogTg\" onclick=\"xrAiLogToggle()\">'",
  "      +(XRAI.open?'收起明细':'明细 '+XRAI.log.length+'/'+XRAI.n)+'</span></div>';",
  "    var rows=XRAI.open?XRAI.log:XRAI.log.slice(-1);",
  "    h+=rows.map(function(r){",
  "      var base='第 '+r.i+'/'+r.n+' 批 · 本批 '+r.cnt+' 条（'+r.prev.slice(0,3).join('、')+'）· '",
  "        + (r.fail",
  "          ? '<span class=\"text-rose-500\">'+r.fail+' · 已跳过 · 不影响后续</span>'",
  "          : '建议 删'+r.del+' 改'+r.cls+' 补'+r.add+' · 用时 '+r.sec.toFixed(1)+'s · 约 '+(r.tok>=1000?(r.tok/1000).toFixed(1)+'k':r.tok)+' tokens');",
  "      return '<div class=\"mt-1 text-[9px] leading-3.5 text-slate-500 dark:text-slate-400\" id=\"xrAiRow-'+r.i+'\">'+base+'</div>';",
  "    }).join('');",
  "    return h+'</div>';",
  "  };",
]);

// 2) 逐批推进时落明细（含失败批）
rep('tick', [
  "      XRAI.b++;",
  "      if(XRAI.b===4)XRAI.err=4;",
], [
  "      XRAI.b++;",
  "      if(XRAI.b===4)XRAI.err=4;",
  "      XRAI.log.push(xrAiSimRow(XRAI.b,XRAI.n));",
]);

// 3) 重新开始时清空明细（中止/跑完则保留，供事后按日志追）
rep('reset-start', [
  "    XRAI.b=0;XRAI.err=0;XRAI.sel={};XRAI_SUG.forEach(function(x){XRAI.sel[x.k]=true});",
  "    xrAiRun();toast('已按 '+XRAI.budget+' 字预算逐批发起');",
], [
  "    XRAI.b=0;XRAI.err=0;XRAI.sel={};XRAI.log=[];XRAI.open=false;XRAI_SUG.forEach(function(x){XRAI.sel[x.k]=true});",
  "    xrAiRun();toast('已按 '+XRAI.budget+' 字预算逐批发起');",
]);
rep('reset-center', [
  "    XRAI.st='run';XRAI.b=0;XRAI.err=0;XRAI.sel={};XRAI_SUG.forEach(function(x){XRAI.sel[x.k]=true});",
  "    xrAiRun();renderXrcAi();toast('已按 '+XRAI.budget+' 字预算逐批发起');",
], [
  "    XRAI.st='run';XRAI.b=0;XRAI.err=0;XRAI.sel={};XRAI.log=[];XRAI.open=false;XRAI_SUG.forEach(function(x){XRAI.sel[x.k]=true});",
  "    xrAiRun();renderXrcAi();toast('已按 '+XRAI.budget+' 字预算逐批发起');",
]);

// 4) 面板段内进度卡挂明细（两处同构＝同一渲染函数）
rep('bar', [
  "    bar.className='mb-2';bar.innerHTML=h;",
], [
  "    h+=xrAiLogHtml();",
  "    bar.className='mb-2';bar.innerHTML=h;",
  "    /* X-Ray 中心的精化段与面板同源：这里一并刷，免得两处各算一份迟早分叉 */",
  "    var xc=document.getElementById('xrcAiLast');",
  "    if(xc)xc.innerHTML=xrAiLogHtml()||xc.textContent;",
]);

// 5) 中心页精化段状态字改挂同一份明细
rep('center', [
  "    var l=document.getElementById('xrcAiLast');",
  "    if(l)l.textContent=XRAI.applied?('上次已写 '+XRAI.applied+' 条 · 随词库导出带走')",
  "      :(XRAI.st==='done'?('上次跑完 · 建议 '+XRAI_SUG.length+' 条待确认'):",
  "      (XRAI.st==='run'||XRAI.st==='pause'?('逐批中 · 第 '+XRAI.b+'/'+XRAI.n+' 批'):'未跑 · 逐批顺序请求，批间可暂停续跑'));",
], [
  "    var l=document.getElementById('xrcAiLast');",
  "    if(l){",
  "      var idle=XRAI.applied?('上次已写 '+XRAI.applied+' 条 · 随词库导出带走')",
  "        :(XRAI.st==='done'?('上次跑完 · 建议 '+XRAI_SUG.length+' 条待确认'):'未跑 · 逐批顺序请求，批间可暂停续跑');",
  "      /* 有明细就上明细（与面板段内同一函数），没有才回状态字 */",
  "      l.innerHTML=xrAiLogHtml()||('<span id=\"xrcAiIdle\">'+idle+'</span>');",
  "    }",
]);

fs.writeFileSync(P, s, 'utf8');
const size1 = Buffer.byteLength(s, 'utf8');
console.log('hits=' + hits.length + '/' + 6, 'bytes ' + size0 + ' -> ' + size1);
if (size1 <= size0) throw new Error('体积没长大，可疑（应只增不减）');
