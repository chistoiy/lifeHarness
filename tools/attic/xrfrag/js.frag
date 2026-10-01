/* ================= V1.54 X-Ray 全书索引 · 批2 v2（上拉面板「目录｜X-Ray」· Kindle 图2/3 形态 · ?xr= 深链） =================
   屏1 解析范围 ?xr=scope ｜ 屏2 书架入口+角标 ?xr=shelf / ?xr=menu
   屏3 面板（上拉段内：范围段+类型段+当前页分组+词条行内分布条）?xr=panel ｜ 详情（段内子页）?xr=ent / 跳转 ?xr=jump
   整理/自学习 ?xr=org / ?xr=del / ?xr=addword / ?xr=merge ｜ 屏5 入口 ?xr=more / ?xr=peek / ?xr=add
   屏6 备份 ?xr=bak ｜ 屏7 失败 ?xr=fail */
(function xrInit(){
  var XR_TYPES=[['per','人名'],['loc','地点'],['org','机构'],['term','术语'],['abbr','缩写'],['book','书名']];
  var XR_TL={};XR_TYPES.forEach(function(t){XR_TL[t[0]]=t[1]});
  var XR_CHS=['理解的起点','行得快','跳板','直觉型判断的可靠性','基础比率','相似性','可得性','质量与信念','预测与判断','小错误与影响','稳健的错觉','专家预测 vs 公式','回归均值','因果关系','选择与框架','惊奇与情绪','双系统案例','尾声'];
  function xrChTitle(ch){return XR_CHS[ch-1]||('第'+ch+'章')}
  var XR={total:18,done:12,status:'ready',kw:'',type:'all',sort:'score',org:false,sel:{},cur:null,lowOpen:false,cites:false,scope:'book',mode:'list'};
  function e(id,name,type,n,chs,score,toc,ment,dlg,q){return {id:id,name:name,type:type,n:n,chs:chs,score:score,toc:toc,ment:ment,dlg:dlg,q:q}}
  var XR_ENTS=[
    e('e_kmn','卡尼曼','per',143,12,0.96,1,[[1,2,'卡尼曼在讲座上第一次提出了双系统框架。'],[3,1,'按照卡尼曼的说法，直觉只是识别。'],[7,4,'卡尼曼与特沃斯基在耶路撒冷开始了合作。'],[12,0,'卡尼曼坚持：公式胜过专家的直觉判断。']],34,'「直觉只是识别。」'),
    e('e_dk','丹尼尔·卡尼曼','per',18,5,0.88,0,[[2,1,'全名丹尼尔·卡尼曼出现在传记脚注。']],null,null),
    e('e_tvs','特沃斯基','per',112,10,0.94,1,[[1,3,'特沃斯基是他毕生的合作者。'],[5,2,'特沃斯基设计的问卷显示锚定效应稳定复现。'],[9,1,'「人们相信随机世界」是特沃斯基的主题。']],21,'「人们相信随机世界。」'),
    e('e_slv','斯洛曼','per',46,6,0.86,0,[[4,2,'斯洛曼对心智模块化的解释最清楚。']],7,null),
    e('e_lgh','吉格伦泽','per',31,5,0.81,0,[[5,3,'吉格伦泽的生态理性研究补充了实验线。']],4,null),
    e('e_lp','拉普斯','per',18,4,0.72,0,[[6,1,'拉普斯对锚定做了商业谈判复验。']],1,null),
    e('e_lov','洛瓦洛','per',12,3,0.64,0,null,null,null),
    e('e_kli','克莱因','per',9,3,0.58,0,null,null,null),
    e('e_pri','普林斯顿','loc',24,4,0.79,0,[[2,0,'高等研究院所在的普林斯顿。']],null,null),
    e('e_jer','耶路撒冷','loc',14,3,0.71,0,[[7,4,'他们在耶路撒冷的课堂拍摄了那部著名影片。']],null,null),
    e('e_cai','开罗','loc',6,2,0.55,0,null,null,null),
    e('e_rand','兰德公司','org',11,3,0.74,0,[[11,2,'兰德公司的项目资助了这批判断研究。']],null,null),
    e('e_nob','诺贝尔委员会','org',8,2,0.68,0,null,null,null),
    e('e_s1','系统1','term',287,16,0.99,1,[[1,0,'系统1几乎在暗中决定一切。'],[2,3,'系统1的判断来自联想记忆网络。'],[5,1,'锚定效应：系统1被起点数值拖动。'],[7,2,'系统1喜欢连贯，不在乎证据量。']],null,null),
    e('e_s2','系统2','term',264,15,0.98,1,[[1,1,'系统2把输入转化为行动。'],[3,2,'注意力预算由系统2分配。']],null,null),
    e('e_anc','锚定效应','term',96,9,0.90,1,[[5,2,'锚定效应在随机轮盘下依然生效。']],null,null),
    e('e_avai','可得性','term',78,8,0.87,0,[[7,1,'可得性启发：容易想起的更容易相信。']],null,null),
    e('e_loss','损失厌恶','term',64,7,0.85,0,null,null,null),
    e('e_fram','框架效应','term',41,6,0.80,0,null,null,null),
    e('e_reg','均值回归','term',22,4,0.66,0,null,null,null),
    e('e_wys','WYSIATI','abbr',26,5,0.83,0,[[4,1,'WYSIATI：眼见即全部。']],null,null),
    e('e_hce','HCE','abbr',14,3,0.69,0,null,null,null),
    e('e_mtm','《模型思维》','book',7,2,0.75,0,null,null,null),
    e('e_rtm','《不确定世界的理性选择》','book',5,2,0.71,0,null,null,null)
  ];
  var XR_DESC={e_kmn:'本书作者，心理学家，2002 年诺贝尔经济学奖得主。',e_s1:'快、自动、几乎不费力的思维系统。',e_tvs:'卡尼曼毕生合作者，启发式与偏差研究奠基人。'};
  XR_ENTS.forEach(function(x){x.desc=XR_DESC[x.id]||null});
  var XR_LOW=0.7;
  var BR_TOC_TAB='toc';

  function xrCurCh(){try{return (brV&&brV.b)?brV.ci+1:1}catch(e){return 1}}
  function xrPagePis(){var s={};try{[].slice.call(document.querySelectorAll('#brBody [data-pi]')).forEach(function(el){s[+el.dataset.pi]=1})}catch(e){}return s}
  function xrOnPage(x){
    var m=x.ment||[],ch=xrCurCh(),pis=xrPagePis(),any=false;
    for(var i=0;i<m.length;i++){if(m[i][0]===ch){any=true;if(pis[m[i][1]]!==undefined)return true}}
    return any
  }
  function xrInCh(x,ch){return (x.ment||[]).some(function(m){return m[0]===ch})}
  function xrScoped(){
    var ch=xrCurCh();
    if(XR.scope==='page')return XR_ENTS.filter(xrOnPage);
    if(XR.scope==='chapter')return XR_ENTS.filter(function(x){return xrInCh(x,ch)});
    return XR_ENTS.slice()
  }
  function xrByType(pool,t){return t==='all'?pool:pool.filter(function(x){return x.type===t})}
  function xrSorted(a){
    if(XR.sort==='score')return a.slice().sort(function(p,q){return q.score-p.score});
    if(XR.sort==='n')return a.slice().sort(function(p,q){return q.n-p.n});
    return a.slice().sort(function(p,q){return p.name.localeCompare(q.name,'zh')})
  }
  function xrKwHl(text,kw){if(!kw||text.indexOf(kw)<0)return text;return text.split(kw).join('<b>'+kw+'</b>')}
  function xrBarHtml(x,lg){
    var ch=xrCurCh(),h='';
    (x.ment||[]).forEach(function(mm,k){
      h+='<i class="'+(mm[0]>ch?'unread':'')+'" id="xr-tick-'+x.id+'-'+k+'" style="left:'+Math.round((mm[0]-0.5)/XR.total*100)+'%"></i>'
    });
    h+='<i class="now" id="xr-now-'+x.id+'" style="left:'+Math.round((ch-0.5)/XR.total*100)+'%"></i>';
    return '<span class="xr-bar'+(lg?' lg':'')+'" id="xr-bar-'+x.id+'">'+h+'</span>'
  }
  function xrRowHtml(x,cur){
    var sel=!!XR.sel[x.id];
    return '<div class="xr-row'+(XR.org&&sel?' sel':'')+(cur?' curg':'')+'" id="'+x.id+'" onclick="'+(XR.org?'xrSel(\''+x.id+'\')':'xrPickEnt(\''+x.id+'\')')+'">'
      +'<div class="flex items-center gap-2">'+(XR.org?'<span class="xr-ck'+(sel?' on':'')+'" id="xr-s-'+x.id+'">✓</span>':'')
      +'<b class="text-[12px] shrink-0">'+x.name+'</b><span class="text-[9px] text-slate-400 shrink-0">'+x.n+'次</span>'
      +(x.toc?'<span class="xr-tbadge toc">目录词</span>':'')+(x.usr?'<span class="xr-tbadge user">我的词条</span>':'')
      +'<span class="flex-1"></span>'+xrBarHtml(x,false)+'</div>'
      +(x.desc?'<div class="text-[9.5px] text-slate-400 mt-1 leading-4 truncate">'+x.desc+'</div>':'')
      +'</div>'
  }
  function xrHeadHtml(){
    var st=XR.status;
    var lbl=st==='run'?('解析中 '+XR.p+'%'):st==='pause'?'已暂停 · 断点已存':st==='fail'?'上次失败':('已解析 '+XR.done+'/'+XR.total+' 章');
    var r1='<div class="flex items-center gap-2 text-[10px]"><b class="font-black">'+lbl+'</b><span class="flex-1"></span>';
    if(st==='ready'&&XR.done<XR.total)r1+='<span class="chip !text-[9px] !px-2.5" id="xrBarContinue" onclick="xrContinue()">继续生成</span>';
    if(st==='ready'||st==='fail')r1+='<span class="chip !text-[9px] !px-2.5" onclick="xrScopeOpen()">重新解析</span>';
    r1+='<span class="chip !text-[9px] !px-2.5" onclick="xrReset()">重置</span></div>';
    var segs=[['page','当前页'],['chapter','本章'],['book','全书']].map(function(s){
      return '<div class="xr-seg'+(XR.scope===s[0]?' on':'')+'" id="xr-scope-'+s[0]+'" onclick="xrSetScope(\''+s[0]+'\')">'+s[1]+'</div>'
    }).join('');
    var r2='<div class="flex items-center gap-2"><div class="flex rounded-xl bg-slate-100 dark:bg-slate-800 p-1 gap-1">'+segs+'</div><span class="flex-1"></span>'
      +'<span class="chip !text-[9px] !px-2.5" id="xrAddBtn" onclick="xrAddOpen(\'\')">＋加词</span>'
      +'<span class="chip !text-[9px] !px-2.5'+(XR.org?' chip-on':'')+'" id="xrOrgBtn" onclick="xrToggleOrg()">整理词条</span></div>';
    return r1+r2
  }
  function xrTypesHtml(pool){
    var h=['<div class="xr-tab'+(XR.type==='all'?' on':'')+'" id="xr-tp-all" onclick="xrPickType(\'all\')">全部 · '+pool.length+'</div>'];
    XR_TYPES.forEach(function(t){
      var n=pool.filter(function(x){return x.type===t[0]}).length;
      if(n)h.push('<div class="xr-tab'+(XR.type===t[0]?' on':'')+'" id="xr-tp-'+t[0]+'" onclick="xrPickType(\''+t[0]+'\')">'+t[1]+' · '+n+'</div>')
    });
    return h.join('')
  }
  function xrListHtml(){
    var pool=xrByType(xrScoped(),XR.type);
    if(XR.kw.trim())pool=pool.filter(function(x){return x.name.indexOf(XR.kw.trim())>=0});
    var hi=[],lo=[];pool.forEach(function(x){(x.score<XR_LOW?lo:hi).push(x)});
    hi=xrSorted(hi);lo=xrSorted(lo);
    var h='';
    /* ④（工单20261001轮2）：全书范围不再置顶「在当前页」分组——当前页只由范围段切换表达。 */
    var rest=hi;
    if(!hi.length&&!lo.length)h+='<div class="text-[10px] text-slate-400 py-6 text-center">该范围没有词条</div>';
    h+=rest.map(function(x){return xrRowHtml(x,false)}).join('');
    if(lo.length){
      h+='<div class="xr-grplbl mt-2 cursor-pointer" id="xr-lowmore" onclick="xrToggleLow()">'+(XR.lowOpen?'收起低置信':'低置信 · '+lo.length+' · 展开')+'</div>';
      if(XR.lowOpen)h+=lo.map(function(x){return xrRowHtml(x,false)}).join('')
    }
    h+='<div class="xr-sortrow"><span class="chip !text-[10px]" id="xrSortBtn" onclick="xrToggleSort()">'+({score:'按相关度',n:'按出场',name:'按名称'})[XR.sort]+' ▾</span></div>';
    h+='<div class="text-[9px] text-slate-400 text-center pb-2">'+XR_ENTS.length+' 个词条 · 出场锚点全量 · 上下文截断（每实体前 N 条）</div>';
    return h
  }
  function xrDetailHtml(x){
    if(!x)return xrListHtml();
    var ch=xrCurCh();
    var h='<div class="flex items-center gap-2"><b class="text-[11px] font-black" id="xr-back" onclick="xrBackList()" style="color:var(--accent)">‹ 词条列表</b><span class="flex-1"></span><b class="text-[14px]">'+x.name+'</b><span class="flex-1"></span><span class="text-[10px] text-slate-400">置信 '+x.score.toFixed(2)+'</span></div>';
    h+='<div class="mt-1 flex items-center gap-1.5 flex-wrap"><span class="xr-tbadge '+(x.usr?'user':x.type)+'">'+(x.usr?'我的词条':XR_TL[x.type])+'</span>'+(x.toc?'<span class="xr-tbadge toc">目录词</span>':'')+'<span class="text-[9px] text-slate-400">'+x.n+' 次 · 跨 '+x.chs+' 章'+(x.dlg!=null?' · 台词 '+x.dlg+' 段':'')+(x.aliases&&x.aliases.length?' · 曾用名 '+x.aliases.join('、'):'')+'</span></div>';
    if(x.desc)h+='<div class="mt-1.5 text-[11px] leading-5 text-slate-500 dark:text-slate-400" id="xr-desc-'+x.id+'">'+x.desc+'</div>';
    if(x.q)h+='<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5"><span class="text-slate-400">代表语录</span><div class="mt-0.5">'+x.q+'</div></div>';
    h+='<div class="mt-3">'+xrBarHtml(x,true)+'</div><div class="flex justify-between text-[8px] text-slate-400 mt-1"><span>书首</span><span>橙线＝读到第'+ch+'章</span><span>书尾</span></div>';
    var mAll=(x.ment||[]).slice().sort(function(a,b){return a[0]-b[0]||a[1]-b[1]});
    var mVis=XR.cites?mAll:mAll.filter(function(mm){return mm[0]<=ch}),hidden=mAll.length-mVis.length;
    h+='<div class="mt-3 text-[10px] font-bold text-slate-400 flex items-center"><span>出场 · 点按跳回阅读位置</span><span class="flex-1"></span><span class="chip !text-[9px] !px-2.5'+(XR.cites?' chip-on':'')+'" id="xr-cites" onclick="xrToggleCites()">显示全部引用</span></div><div class="mt-1.5 space-y-2" id="xr-ments-'+x.id+'">';
    if(!mVis.length)h+='<div class="text-[10px] text-slate-400">已读范围内没有出场</div>';
    mVis.forEach(function(mm,k){
      h+='<div class="xr-clip" id="xr-clip-'+x.id+'-'+k+'" onclick="xrJumpTo('+mm[0]+','+mm[1]+')"><div class="xr-chlabel">'+xrChTitle(mm[0])+' · 段 '+(mm[1]+1)+'</div><div class="mt-0.5">'+xrKwHl(mm[2],x.name)+'</div></div>'
    });
    if(hidden)h+='<div class="text-[9px] text-slate-400 px-1" id="xr-spoiler">剧透保护 · 隐藏未读 '+hidden+' 处引用</div>';
    h+='</div>';
    var cands=XR_ENTS.filter(function(v){return v.id!==x.id&&(v.name.indexOf(x.name)>=0||x.name.indexOf(v.name)>=0)});
    if(cands.length)h+='<div class="mt-3 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px]" id="xr-cand">疑似同一条目：「'+cands[0].name+'」'+cands[0].n+' 次<span class="flex-1"></span><button class="grad text-white !text-[10px] font-bold px-3 py-1.5 rounded-lg" onclick="xrMergeInto(\''+cands[0].id+'\',\''+x.id+'\')">并入当前词条</button></div>';
    h+='<div class="mt-2.5 flex gap-2"><button class="flex-1 py-2 rounded-xl border border-slate-200 dark:border-slate-700 text-[10px] font-bold" id="xr-merge-into" onclick="xrShowMergeSheet(\''+x.id+'\')">合并进…</button><button class="flex-1 py-2 rounded-xl border border-rose-200 dark:border-rose-500/40 text-[10px] font-bold text-rose-500" id="xr-ban" onclick="xrBan(\''+x.id+'\')">不再显示该词</button></div>';
    h+='<div class="mt-2.5 rounded-xl border border-dashed border-slate-200 dark:border-slate-700 p-2.5 text-[10px] text-slate-400 flex items-center gap-2" id="xr-aihold">AI 释义 · 二期占位<span class="flex-1"></span></div>';
    return h
  }
  window.xrRender=function(){
    var hd=document.getElementById('xrHead');if(hd)hd.innerHTML=xrHeadHtml();
    var pool=xrByType(xrScoped(),XR.type);
    var tb=document.getElementById('xrTypes');if(tb)tb.innerHTML=xrTypesHtml(xrScoped());
    var cur=XR_ENTS.find(function(v){return v.id===XR.cur});
    var ls=document.getElementById('xrList');
    if(ls)ls.innerHTML=(XR.mode==='detail'&&cur)?xrDetailHtml(cur):xrListHtml();
    var bar=document.getElementById('xrBar');
    if(bar){
      if(XR.org){
        var s=Object.keys(XR.sel).filter(function(k){return XR.sel[k]});
        bar.innerHTML='<div class="rounded-2xl bg-white dark:bg-slate-900 border border-slate-100 dark:border-slate-800 p-2.5 space-y-2"><div class="text-[10px] font-bold text-slate-400 flex items-center"><span>已选 '+s.length+' 条</span><span class="flex-1"></span><button class="text-slate-400" onclick="xrExitOrg()">退出整理</button></div><div class="flex gap-2">'
          +'<button class="flex-1 py-2 rounded-xl grad text-white text-[11px] font-bold'+(s.length<2?' opacity-40':'')+'" onclick="xrMerge()">合并</button>'
          +'<button class="flex-1 py-2 rounded-xl bg-rose-500 text-white text-[11px] font-bold'+(s.length<1?' opacity-40':'')+'" onclick="xrDelOpen()">移除</button></div></div>'
      } else bar.innerHTML=''
    }
  };
  window.xrSetScope=function(k){XR.scope=k;XR.mode='list';xrRender()};
  window.xrPickType=function(t){XR.type=t;XR.mode='list';xrRender()};
  window.xrToggleLow=function(){XR.lowOpen=!XR.lowOpen;xrRender()};
  window.xrToggleCites=function(){XR.cites=!XR.cites;xrRender()};
  window.xrEnts=function(){return XR_ENTS};
  window.xrState=function(){return XR};
  var XR_SORTS=[['score','按相关度'],['n','按出场'],['name','按名称']];
  window.xrToggleSort=function(){var i=0;XR_SORTS.forEach(function(s,k){if(s[0]===XR.sort)i=k});XR.sort=XR_SORTS[(i+1)%3][0];xrRender();toast('排序：'+XR_SORTS[(i+1)%3][1])};
  window.xrToggleOrg=function(){XR.org=!XR.org;if(!XR.org)XR.sel={};XR.mode='list';xrRender()};
  window.xrExitOrg=function(){XR.org=false;XR.sel={};xrRender()};
  window.xrSel=function(id){XR.sel[id]=!XR.sel[id];xrRender()};
  window.xrPickEnt=function(id){
    var x=XR_ENTS.find(function(v){return v.id===id});if(!x)return;
    XR.cur=id;XR.mode='detail';
    if(BR_TOC_TAB!=='xr')brTocOpen('xr');
    xrRender();
    try{document.getElementById('xrScroll').scrollTo({top:0})}catch(e){}
  };
  window.xrBackList=function(){XR.mode='list';xrRender()};
  window.xrJumpTo=function(ch,para){
    try{
      brTocClose();
      if(!brV.b||brV.b!==CURBK||!document.getElementById('brBody').children.length)brOpen(CURBK);
      brShowChrome();
      var leaves=brLeaves(brV.b);
      brV.ci=Math.min(Math.max(ch-1,0),leaves.length-1);brV.pg=0;brRenderPage();
      var els=[].slice.call(document.querySelectorAll('#brBody [data-pi]'));
      var idx=Math.min(para,els.length-1);
      if(els[idx]){els[idx].classList.add('br-flash-xr');(function(el){setTimeout(function(){el.classList.remove('br-flash-xr')},1800)})(els[idx])}
      toast('已跳转 · '+xrChTitle(ch))
    }catch(err){toast('演示：跳转到 '+xrChTitle(ch))}
  };
  /* 上拉面板双段切换（目录｜X-Ray）· 搜索独占态（图1三等分→图2独占） */
  window.brTocTab=function(k){
    BR_TOC_TAB=k;
    var toc=document.getElementById('xrSegToc'),xr=document.getElementById('xrSegXr');
    if(toc)toc.classList.toggle('on',k==='toc');if(xr)xr.classList.toggle('on',k==='xr');
    var pane=document.getElementById('xrPane'),sc=document.getElementById('brDrScroll'),
        foldRow=document.getElementById('xrTocFoldRow'),pill=document.getElementById('brDrPill');
    var pl=document.querySelector('#xrSearchPill span'),qi=document.getElementById('xrHdrQ');
    if(pl)pl.textContent=k==='xr'?'搜词条':'搜本书';if(qi)qi.placeholder=k==='xr'?'搜词条':'搜本书';
    if(k==='xr'){
      if(pane){pane.classList.remove('hidden');pane.classList.add('flex')}
      if(sc)sc.classList.add('hidden');
      if(pill)pill.classList.add('hidden');
      if(foldRow){foldRow.classList.add('hidden');foldRow.classList.remove('flex')}
      var q=document.getElementById('xrHdrQ');XR.kw=q?q.value:'';
      xrRender()
    } else {
      if(pane){pane.classList.add('hidden');pane.classList.remove('flex')}
      if(sc)sc.classList.remove('hidden');
      var q2=document.getElementById('xrHdrQ'),inSearch=document.getElementById('xrHdrSearchRow')&&!document.getElementById('xrHdrSearchRow').classList.contains('hidden');
      if(foldRow&&!inSearch){foldRow.classList.remove('hidden');foldRow.classList.add('flex')}
      brDrTab((q2&&q2.value)?'search':'toc')
    }
  };
  window.xrSearchEnter=function(){
    var row=document.getElementById('xrHdrRow'),srow=document.getElementById('xrHdrSearchRow'),
        foldRow=document.getElementById('xrTocFoldRow');
    row.classList.add('hidden');row.classList.remove('flex');
    srow.classList.remove('hidden');srow.classList.add('flex');
    if(foldRow){foldRow.classList.add('hidden');foldRow.classList.remove('flex')}
    var q=document.getElementById('xrHdrQ');q&&q.focus()
  };
  window.xrSearchExit=function(){
    var row=document.getElementById('xrHdrRow'),srow=document.getElementById('xrHdrSearchRow');
    srow.classList.add('hidden');srow.classList.remove('flex');
    row.classList.remove('hidden');row.classList.add('flex');
    xrHdrClear();
    brTocTab(BR_TOC_TAB)
  };
  window.xrHdrClear=function(){
    var q=document.getElementById('xrHdrQ');if(q)q.value='';
    var c=document.getElementById('xrHdrClr');if(c){c.classList.add('hidden');c.classList.remove('flex')}
    xrHdrSearch('')
  };
  window.xrHdrSearch=function(v){
    var c=document.getElementById('xrHdrClr');if(c){c.classList.toggle('hidden',!v);if(v)c.classList.add('flex')}
    if(BR_TOC_TAB==='xr'){XR.kw=v;xrRender();return}
    var q=document.getElementById('brDrQ');if(q)q.value=v;
    brDrTab(v?'search':'toc');
    if(!v){var row=document.getElementById('xrHdrSearchRow');if(row&&!row.classList.contains('hidden')){var f=document.getElementById('xrTocFoldRow');if(f){f.classList.remove('hidden');f.classList.add('flex')}}}
  };
  window.xrFoldAll=function(){brDrFoldAll();var b=document.getElementById('xrFoldBtn');if(b)b.textContent=b.textContent==='全部折叠'?'全部展开':'全部折叠'};
  var XROLD_TOCOPEN=brTocOpen;
  brTocOpen=function(tab){XROLD_TOCOPEN.call(window,tab==='xr'?'toc':tab);try{brTocTab(tab==='xr'?'xr':'toc')}catch(e){}};
  /* 屏1 解析范围 */
  var xrScopeMode='all',xrScopeCh=3;
  window.xrScopeOpen=function(){
    xrScopeCh=xrCurCh();
    var box=document.getElementById('xrScopeOpts');
    box.innerHTML=[['cur','当前章 · '+xrChTitle(xrScopeCh)],['range','章节区间'],['all','全书 · '+XR.total+' 章']].map(function(o){
      return '<div class="xr-scope-opt'+(xrScopeMode===o[0]?' on':'')+'" id="xr-scope-'+o[0]+'" onclick="xrScopePick(\''+o[0]+'\')"><span class="w-4 h-4 rounded-full border flex items-center justify-center'+(xrScopeMode===o[0]?' !border-transparent grad text-white':' border-slate-300')+'">'+(xrScopeMode===o[0]?'<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M20 6 9 17l-5-5"/></svg>':'')+'</span>'+o[1]+'</div>'
    }).join('');
    var from=document.getElementById('xrFrom'),to=document.getElementById('xrTo');
    var opts='';for(var i=1;i<=XR.total;i++)opts+='<option value="'+i+'">第'+i+'章</option>';
    from.innerHTML=opts;to.innerHTML=opts;
    from.value=Math.max(1,xrScopeCh-1);to.value=Math.min(XR.total,xrScopeCh+3);
    document.getElementById('xrScopeRange').classList.toggle('hidden',xrScopeMode!=='range');
    xrScopeEst();openSheet('sheetXrScope')
  };
  window.xrScopePick=function(k){xrScopeMode=k;xrScopeOpen()};
  function xrChEst(ch){return 12000+((ch*373)%9000)}
  function xrFmtN(n){return n>=10000?((n/10000).toFixed(1)+' 万字'):(n+' 字')}
  window.xrScopeEst=function(){
    var n=0;
    if(xrScopeMode==='cur')n=xrChEst(xrScopeCh);
    else if(xrScopeMode==='all'){for(var i=1;i<=XR.total;i++)n+=xrChEst(i)}
    else{var a=+document.getElementById('xrFrom').value,b=+document.getElementById('xrTo').value;if(b<a){var t=a;a=b;b=t}for(var j=a;j<=b;j++)n+=xrChEst(j)}
    document.getElementById('xrScopeEst').textContent=xrFmtN(n);
    document.getElementById('xrScopeRange').classList.toggle('hidden',xrScopeMode!=='range')
  };
  window.xrScopeStart=function(){
    closeSheet('sheetXrScope');
    XR.status='run';XR.p=1;XR.done=0;xrSetBookXr('b1',{st:'run',p:1});renderShelf();
    toast('解析已启动 · 前台运行不锁阅读');
    if(brV&&brV.b){try{brTocOpen('xr')}catch(e){}}
  };
  /* 屏7 失败/中断 · F3 继续与重置 */
  window.xrContinue=function(){XR.status='run';XR.p=61;xrSetBookXr('b1',{st:'run',p:61});renderShelf();toast('增量解析 · 从第 13 章断点续跑');xrRender();setTimeout(function(){xrDoneAll()},600)};
  function xrDoneAll(){XR.status='ready';XR.done=XR.total;XR.p=100;xrSetBookXr('b1',{st:'ready',done:XR.total});renderShelf();xrRender();toast('全书索引完成 · '+XR_ENTS.length+' 个词条')}
  window.xrReset=function(){closeSheet('sheetXrFail');XR.done=0;XR.status='none';xrSetBookXr('b1',null);renderShelf();xrRender();toast('已重置 · 实体/出场/任务态已清空')};
  window.xrFailRetry=function(){closeSheet('sheetXrFail');XR.status='run';XR.p=66;xrSetBookXr('b1',{st:'run',p:66});renderShelf();toast('从断点续跑 · 第 13 章起')};
  /* 整理：合并与移除（F8） */
  function xrName(id){var x=XR_ENTS.find(function(v){return v.id===id});return x?x.name:id}
  window.xrMerge=function(){
    var s=Object.keys(XR.sel).filter(function(k){return XR.sel[k]});
    if(s.length<2){toast('合并至少选择 2 条');return}
    var canon=XR_ENTS.find(function(v){return v.id===s[0]});
    s.slice(1).forEach(function(id){var x=XR_ENTS.find(function(v){return v.id===id});if(x&&canon){canon.n+=x.n;canon.chs=Math.max(canon.chs,x.chs);if(!canon.aliases)canon.aliases=[];canon.aliases.push(x.name);if(x.ment)canon.ment=(canon.ment||[]).concat(x.ment)}});
    XR_ENTS=XR_ENTS.filter(function(v){return !(XR.sel[v.id]&&v.id!==s[0])});
    XR.org=false;XR.sel={};if(XR.cur&&s.indexOf(XR.cur)>=0)XR.cur=s[0];
    xrRender();
    toast('已合并为「'+canon.name+'」· aliases '+s.length+' · 出场归属已迁移')
  };
  window.xrMergeInto=function(id,target){
    var a=XR_ENTS.find(function(v){return v.id===id}),b=XR_ENTS.find(function(v){return v.id===target});
    if(!a||!b)return;
    b.n+=a.n;b.chs=Math.max(b.chs,a.chs);if(!b.aliases)b.aliases=[];b.aliases.push(a.name);
    if(a.ment)b.ment=(b.ment||[]).concat(a.ment);
    XR_ENTS=XR_ENTS.filter(function(v){return v.id!==id});
    if(XR.cur===id)XR.cur=b.id;
    xrRender();toast('已合并「'+a.name+'」入「'+b.name+'」· 出场归属已迁移')
  };
  var xrDelIds=[];
  window.xrDelOpen=function(){
    xrDelIds=Object.keys(XR.sel).filter(function(k){return XR.sel[k]});
    if(!xrDelIds.length){toast('先选择要移除的词条');return}
    var names=xrDelIds.map(xrName).join('、');
    document.getElementById('xrDelBody').innerHTML='移除「'+names+'」后不再出现在索引，阈值再低也不会复活。';
    xrDelPick='book';xrDelRenderScope();
    openSheet('sheetXrDel')
  };
  window.xrBan=function(id){
    xrDelIds=[id];var x=XR_ENTS.find(function(v){return v.id===id});
    document.getElementById('xrDelBody').innerHTML='移除「'+(x?x.name:id)+'」后不再出现在索引，阈值再低也不会复活。';
    xrDelPick='book';xrDelRenderScope();openSheet('sheetXrDel')
  };
  var xrDelPick='book';
  window.xrDelPickScope=function(k){xrDelPick=k;xrDelRenderScope()};
  function xrDelRenderScope(){
    document.getElementById('xrDelScope').innerHTML=[['book','仅本书'],['global','升级到全局黑名单（所有书生效）']].map(function(o){
      return '<div class="xr-scope-opt'+(xrDelPick===o[0]?' on':'')+'" id="xr-del-'+o[0]+'" onclick="xrDelPickScope(\''+o[0]+'\')"><span class="w-4 h-4 rounded-full border flex items-center justify-center'+(xrDelPick===o[0]?' !border-transparent grad text-white':' border-slate-300')+'">'+(xrDelPick===o[0]?'<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M20 6 9 17l-5-5"/></svg>':'')+'</span>'+o[1]+'</div>'
    }).join('')
  }
  window.xrDoDel=function(){
    XR_ENTS=XR_ENTS.filter(function(v){return xrDelIds.indexOf(v.id)<0});
    closeSheet('sheetXrDel');XR.org=false;XR.sel={};if(xrDelIds.indexOf(XR.cur)>=0){XR.cur=null;XR.mode='list'}
    xrRender();
    toast('已移除 '+xrDelIds.length+' 条 · '+(xrDelPick==='global'?'并加入全局黑名单':'仅本书生效'))
  };
  window.xrShowMergeSheet=function(id){
    var x=XR_ENTS.find(function(v){return v.id===id});if(!x)return;
    document.getElementById('xrMergeBody').innerHTML='<div class="flex items-center justify-between"><b class="text-[15px]">合并进…</b><span class="text-[9px] text-slate-400">整理词条</span></div><div class="mt-1.5 text-[10px] text-slate-400">「'+x.name+'」的出场将全部归入所选规范词条（aliases 记录曾用名）</div><div class="mt-2.5 space-y-2 max-h-[46vh] overflow-y-auto no-scrollbar">'+XR_ENTS.filter(function(v){return v.id!==id}).map(function(v){
      return '<div class="xr-clip flex items-center gap-2" id="xr-mg-'+v.id+'" onclick="xrMergeInto(\''+id+'\',\''+v.id+'\');closeSheet(\'sheetXrMerge\')"><span class="xr-tbadge '+(v.usr?'user':v.type)+'">'+(v.usr?'我的':XR_TL[v.type])+'</span><b class="text-[11px]">'+v.name+'</b><span class="ml-auto text-[9px] text-slate-400">'+v.n+' 次</span></div>'
    }).join('')+'</div>';
    openSheet('sheetXrMerge')
  };
  /* 屏5 阅读器入口 + 选区工具条动作（F1/F5/F6/F8） */
  BR_SEL_ALL.push('X-Ray');
  BR_SEL_TOOLS['X-Ray']=['<circle cx="11" cy="11" r="6"/><path d="m20 20-3.5-3.5M11 8v6M8 11h6"/>','xrSelTool()'];
  brSelActsRender();
  function xrGuessType(w){
    if(/^《.*》$/.test(w))return 'book';
    if(/^[A-Z]{2,}$/.test(w))return 'abbr';
    if(/先生|夫人|教授|博士|警司|上校|伯爵|爵士/.test(w))return 'per';
    if(/国$|市$|省$|河|山|岛|平原/.test(w))return 'loc';
    if(/公司|委员会|研究院|学院|协会|银行/.test(w))return 'org';
    return 'term'
  }
  window.xrSelTool=function(){
    var w='';
    try{
      var sel=brV.sel;
      if(sel){var arrX=brChText(brV.b,brLeaves(brV.b)[sel.ci]);
        var tX=(arrX[sel.p0]&&arrX[sel.p0].t)||'';
        w=tX.slice(sel.o0,sel.o1).trim()}
    }catch(e){}
    if(!w)w=(brV&&brV.selWord)||'';
    if(!w){toast('先选中文字');return}
    var hit=XR_ENTS.find(function(v){return v.name===w||w.indexOf(v.name)>=0||v.name.indexOf(w)>=0});
    if(hit)xrPeekOpen(hit.name)
    else xrAddOpen(w)
  };
  window.xrPeekOpen=function(word){
    var x=XR_ENTS.find(function(v){return v.name===word});
    if(!x){xrAddOpen(word);return}
    var h='<div class="flex items-center gap-2 flex-wrap"><b class="text-[15px]">'+x.name+'</b><span class="xr-tbadge '+(x.usr?'user':x.type)+'">'+(x.usr?'我的词条':XR_TL[x.type])+'</span>'+(x.toc?'<span class="xr-tbadge toc">目录词</span>':'')+'</div>';
    h+='<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5">'+x.n+' 次提及 · 跨 '+x.chs+' 章 · 置信 '+x.score.toFixed(2)+(x.dlg!=null?' · 台词 '+x.dlg+' 段':'')+'</div>';
    if(x.q)h+='<div class="mt-2 text-[10px] text-slate-500 dark:text-slate-400">'+x.q+'</div>';
    h+='<div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet(\'sheetXrPeek\')">关闭</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="xrPeekToPanel(\''+x.name+'\')">查看全部位置</button></div>';
    document.getElementById('xrPeekBody').innerHTML=h;
    openSheet('sheetXrPeek')
  };
  window.xrPeekToPanel=function(name){closeSheet('sheetXrPeek');var x=XR_ENTS.find(function(v){return v.name===name});if(x)xrPickEnt(x.id);else brTocOpen('xr')};
  var xrAddPick={word:'',type:'term',scope:'book'};
  window.xrAddOpen=function(word){
    xrAddPick={word:word||'',type:xrGuessType(word||''),scope:'book'};
    var wi=document.getElementById('xrAddWordIn');if(wi)wi.value=word||'';
    if(wi)wi.oninput=function(){xrAddPick.type=xrGuessType(this.value);xrAddRenderTypes()};
    xrAddRenderTypes();
    document.getElementById('xrAddScope').innerHTML=xrAddScopeHtml();
    openSheet('sheetXrAdd')
  };
  function xrAddRenderTypes(){
    document.getElementById('xrAddTypes').innerHTML=XR_TYPES.map(function(t){
      return '<div class="xr-tab'+(xrAddPick.type===t[0]?' on':'')+'" id="xr-add-'+t[0]+'" onclick="xrAddPickType(\''+t[0]+'\')">'+t[1]+'</div>'
    }).join('')
  }
  function xrAddScopeHtml(){
    return [['book','仅本书'],['global','加入全局词库']].map(function(o){
      return '<div class="chip !text-[10px]'+(xrAddPick.scope===o[0]?' chip-on':'')+'" id="xr-addsc-'+o[0]+'" onclick="xrAddPickScope(\''+o[0]+'\')">'+o[1]+'</div>'
    }).join('')
  }
  window.xrAddPickType=function(t){xrAddPick.type=t;xrAddRenderTypes()};
  window.xrAddPickScope=function(s){xrAddPick.scope=s;
    document.getElementById('xrAddScope').innerHTML=xrAddScopeHtml()
  };
  window.xrDoAdd=function(){
    var w=((document.getElementById('xrAddWordIn')||{}).value||'').trim()||'新词条';
    xrAddPick.word=w;
    var id='e_u'+Date.now()%100000;
    XR_ENTS.push(e(id,w,xrAddPick.type,0,0,1.0,0,null,null,null));
    XR_ENTS[XR_ENTS.length-1].usr=1;
    closeSheet('sheetXrAdd');XR.cur=id;XR.mode='detail';
    if(BR_TOC_TAB==='xr')xrRender();else brTocOpen('xr');
    var sc=xrAddPick.scope==='global'?' · 已入全局词库':'';
    toast('已加词「'+w+'」· 全书补扫中 · 出场 8 处（演示）'+sc)
  };
  /* 屏2 书架入口：长按菜单项 + 封面状态角标（F1/F7） */
  function xrSetBookXr(id,x){var b=bsBook(id);if(!b)return;if(x)b.xr=x;else delete b.xr}
  function xrLpLabel(b){var x=b.xr;
    if(!x)return '生成全书索引';
    if(x.st==='run')return '索引解析中 · '+x.p+'% · 管理';
    if(x.st==='pause')return '索引已暂停 · 管理';
    if(x.st==='fail')return '索引上次失败 · 重试';
    return '管理全书索引 · 已解析 '+x.done+'/'+XR.total}
  var XROLD_LM=shLongMenu;
  shLongMenu=function(id){XROLD_LM(id);
    try{const ops=document.getElementById('lpOps');if(!ops)return;
      ops.insertAdjacentHTML('afterbegin','<button class="w-full flex items-center gap-2.5 px-3 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-[13px] font-bold text-left mb-1" id="lpXrBtn" onclick="xrLpGo(\''+id+'\')"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="6"/><path d="m20 20-3.5-3.5"/></svg> '+xrLpLabel(bsBook(id))+'</button>')
    }catch(e){}};
  window.xrLpGo=function(id){CURBK=id;closeSheet('sheetLongPress');
    var b=bsBook(id);
    if(b&&b.xr&&b.xr.st!=='none'){brOpen(id);brShowChrome();brTocOpen('xr')}
    else xrScopeOpen()};
  function xrBadgesHtml(x){
    if(!x)return '';
    if(x.st==='run')return '解析中 '+x.p+'%';
    if(x.st==='pause')return '已暂停 '+x.p+'%';
    if(x.st==='fail')return '失败 · 重试';
    return '已索引'
  }
  window.xrPaintBadges=function(){
    try{
      BS_BOOKS.forEach(function(b){
        if(!b.xr)return;
        var cards=[].slice.call(document.querySelectorAll('#shBody [onclick*="shOpen(\''+b.id+'\')"]'));
        cards.forEach(function(c){
          var host=null;
          if(getComputedStyle(c).position==='relative')host=c;
          else if(c.parentElement&&getComputedStyle(c.parentElement).position==='relative')host=c.parentElement;
          if(!host)return;
          var old=host.querySelector(':scope > .xr-badge');if(old)old.remove();
          var span=document.createElement('span');
          span.className='xr-badge '+(b.xr.st==='run'?'':b.xr.st);
          span.id='xr-badge-'+b.id;
          span.textContent=xrBadgesHtml(b.xr);
          host.appendChild(span)
        })
      })
    }catch(e){}
  };
  var XROLD_RS=renderShelf;
  renderShelf=function(){XROLD_RS.apply(this,arguments);xrPaintBadges()};
  /* 屏6 设置-数据（阅读设置末组 + .xraybak） */
  var XROLD_RSET=renderReadSet;
  renderReadSet=function(){XROLD_RSET.apply(this,arguments);
    try{
      var host=document.getElementById('rsGroups');
      if(!host||document.getElementById('xrSetRow'))return;
      host.insertAdjacentHTML('beforeend','<div class="card mt-3 flex items-center gap-2 cursor-pointer" id="xrSetRow" onclick="openSheet(\'sheetXrBak\')"><div class="flex-1"><b class="text-xs">X-Ray 索引备份</b><div class="text-[9px] text-slate-400 mt-0.5">导出 .xraybak / 从备份导入 · MD5 校验</div></div><span class="text-slate-300">›</span></div>')
    }catch(e){}};
  window.xrBakGo=function(k){
    if(k==='exp')toast('已另存 xray-3books.xraybak · 12 索引 8.9 MB（模拟）');
    else toast('MD5 校验：9/10 通过 · 1 项内容不一致被拒收')
  };
  /* 阅读器菜单行（屏5 入口） */
  window.xrEntry=function(){
    var lbl=document.getElementById('brMoreXr');
    if(lbl)lbl.textContent=XR.status==='ready'?('已解析 '+XR.done+'/'+XR.total+' 章'):XR.status==='run'?('解析中 '+XR.p+'%'):XR.status==='pause'?'已暂停':XR.status==='fail'?'上次失败':'未解析';
    if(XR.status==='none'||(XR.status==='ready'&&XR.done===0))xrScopeOpen();
    else brTocOpen('xr')
  };
  /* 演示状态注入 */
  window.xrSeed=function(k){
    xrSetBookXr('b1',{st:'ready',done:12});
    if(k==='shelf'){
      var ids=BS_BOOKS.filter(function(b){return !b.deleted}).map(function(b){return b.id});
      if(ids[1])xrSetBookXr(ids[1],{st:'run',p:57});
      if(ids[2])xrSetBookXr(ids[2],{st:'pause',p:23});
      if(ids[3])xrSetBookXr(ids[3],{st:'fail',done:12})
    }
  };
  /* 深链 */
  function xrBootCh(){try{brV.ci=6;brV.pg=0;brRenderPage()}catch(e){}}
  (function xrBoot(){try{
    var m=(location.search.match(/xr=([a-z]+)/)||[])[1];if(!m)return;
    var b=bsBook('b1');if(b){CURBK='b1'}
    if(m==='shelf'){xrSeed('shelf');shSt='全部';setPage('p-bookshelf');renderShelf();return}
    if(m==='menu'){xrSeed();setPage('p-bookshelf');renderShelf();shLongMenu('b1');return}
    if(m==='scope'){brOpen('b1');brShowChrome();xrScopeOpen();return}
    if(m==='panel'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');return}
    if(m==='ent'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');xrPickEnt('e_kmn');return}
    if(m==='jump'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');xrPickEnt('e_kmn');xrJumpTo(1,2);return}
    if(m==='org'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');XR.org=true;XR.sel={'e_kmn':true,'e_dk':true};xrRender();return}
    if(m==='del'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');XR.org=true;XR.sel={'e_kmn':true};xrRender();xrDelOpen();return}
    if(m==='addword'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');xrAddOpen('');return}
    if(m==='merge'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');xrShowMergeSheet('e_s1');return}
    if(m==='bak'){navTo('p-readset');rsPickTab(RS_SEC.length-1);renderReadSet();openSheet('sheetXrBak');return}
    if(m==='more'){brOpen('b1');brShowChrome();openSheet('sheetBrMore');return}
    if(m==='peek'||m==='add'){
      brOpen('b1');brShowChrome();
      BS_SET.brSelOps=['X-Ray','复制','划线','书摘'];brSelActsRender();
      var els=[].slice.call(document.querySelectorAll('#brBody [data-pi]'));
      if(!els.length){xrPeekOpen('系统1');return}
      var pi=-1,st='';
      for(var i=0;i<els.length;i++){var el=els[i];var ppi=+el.dataset.pi;
        var arr=brChText(brV.b,brLeaves(brV.b)[brV.ci]);var t=(arr[ppi]&&arr[ppi].t)||'';
        var ix=t.indexOf('系统1');
        if(ix>=0){pi=ppi;st=t;break}
      }
      if(pi>=0){var ix2=st.indexOf('系统1');
        brSelect(pi,pi,ix2,ix2+3);brBindHandles();brHandlePlace();
        if(m==='peek')xrSelTool();else xrAddOpen('巧克力');
        var pk=document.getElementById('sheetXrPeek');
        if(m==='peek'&&pk.classList.contains('hidden'))xrPeekOpen('系统1');
      } else {
        if(m==='peek')xrPeekOpen('系统1');else xrAddOpen('巧克力')
      }
      return
    }
    if(m==='fail'){xrSeed();brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');openSheet('sheetXrFail');return}
  }catch(e){console.warn('xr',e)}})();
})();
