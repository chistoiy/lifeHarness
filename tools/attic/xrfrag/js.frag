/* ================= V1.54 X-Ray 全书索引 · 批2（面板与跳转 · ?xr= 深链） =================
   屏1 解析范围 ?xr=scope ｜ 屏2 书架入口+角标 ?xr=shelf / ?xr=menu
   屏3 面板 ?xr=panel（折叠/搜索/整理）｜ 屏4 实体详情 ?xr=ent（出场跳转 ?xr=jump）
   屏5 阅读器菜单入口+选区工具条 ?xr=more / ?xr=peek / ?xr=add
   屏6 设置-数据 备份 ?xr=bak ｜ 屏7 失败/中断 ?xr=fail / 移除确认 ?xr=del */
(function xrInit(){
  Object.assign(TITLES,{'p-xray':['全书索引','']});
  var XR_TYPES=[['per','人名'],['loc','地点'],['org','机构'],['term','术语'],['abbr','缩写'],['book','书名']];
  var XR_TL={};XR_TYPES.forEach(function(t){XR_TL[t[0]]=t[1]});
  var XR_CHS=['理解的起点','行得快','跳板','直觉型判断的可靠性','基础比率','相似性','可得性','质量与信念','预测与判断','小错误与影响','稳健的错觉','专家预测 vs 公式','回归均值','因果关系','选择与框架','惊奇与情绪','双系统案例','尾声'];
  function xrChTitle(ch){return XR_CHS[ch-1]||('第'+ch+'章')}
  var XR={total:18,done:12,status:'ready',kw:'',type:'term',sort:'score',org:false,sel:{},expanded:{}};
  function e(id,name,type,n,chs,score,toc,dist,ment,dlg,q){return {id:id,name:name,type:type,n:n,chs:chs,score:score,toc:toc,dist:dist,ment:ment,dlg:dlg,q:q}}
  var XR_ENTS=[
    e('e_kmn','卡尼曼','per',143,12,0.96,1,[2,5,9,14,18,12,7,10,16,11,6,4],[[1,2,'卡尼曼在讲座上第一次提出了双系统框架。'],[3,1,'按照卡尼曼的说法，直觉只是识别。'],[7,4,'卡尼曼与特沃斯基在耶路撒冷开始了合作。'],[12,0,'卡尼曼坚持：公式胜过专家的直觉判断。']],34,'「直觉只是识别。」'),
    e('e_dk','丹尼尔·卡尼曼','per',18,5,0.88,0,[1,3,4,2,1,3,2,1,2,1,0,1,1,0,2,1,0,1],[[2,1,'全名丹尼尔·卡尼曼出现在传记脚注。']],null,null),
    e('e_tvs','特沃斯基','per',112,10,0.94,1,[1,4,8,15,17,12,9,6,8,5,3,2,4,3,5,2,1,3],[[1,3,'特沃斯基是他毕日的合作者。'],[5,2,'特沃斯基设计的问卷显示锚定效应稳定复现。'],[9,1,'『人们相信随机世界』是特沃斯基的主题。']],21,'「人们相信随机世界。」'),
    e('e_slv','斯洛曼','per',46,6,0.86,0,[0,2,3,5,8,6,4,3,2,1,2,1,0,1,0,0,1,0],[[4,2,'斯洛曼对心智模块化的解释最清楚。']],7,null),
    e('e_lgh','吉格伦泽','per',31,5,0.81,0,[0,1,2,4,3,2,1,1,2,1,0,0,1,0,0,1,0,0],[[5,3,'吉格伦泽的生态理性研究补充了实验线。']],4,null),
    e('e_lp','拉普斯','per',18,4,0.72,0,[0,0,1,2,1,3,2,1,0,0,1,0,0,0,1,0,0,0],[[6,1,'拉普斯对锚定做了商业谈判复验。']],1,null),
    e('e_lov','洛瓦洛','per',12,3,0.64,0,[0,0,1,1,2,1,3,2,1,0,0,0,1,0,0,0,0,0],null,null,null),
    e('e_kli','克莱因','per',9,3,0.58,0,[0,1,0,1,1,0,2,1,0,1,0,0,0,0,1,0,0,0],null,null,null),
    e('e_pri','普林斯顿','loc',24,4,0.79,0,[1,0,2,3,5,4,2,1,2,3,1,0,1,2,0,0,0,0],[[2,0,'高等研究院所在的普林斯顿。']],null,null),
    e('e_jer','耶路撒冷','loc',14,3,0.71,0,[2,1,1,0,1,2,3,1,0,0,0,1,0,0,0,0,0,0],[[7,4,'他们在耶路撒冷的课堂拍摄了那部著名影片。']],null,null),
    e('e_cai','开罗','loc',6,2,0.55,0,[0,0,0,1,2,1,0,0,1,0,0,0,0,1,0,0,0,0],null,null,null),
    e('e_rand','兰德公司','org',11,3,0.74,0,[0,1,2,1,0,1,0,1,2,1,0,0,1,0,0,0,0,0],[[11,2,'兰德公司的项目资助了这批判断研究。']],null,null),
    e('e_nob','诺贝尔委员会','org',8,2,0.68,0,[0,0,0,0,1,0,0,0,1,1,0,0,0,0,2,1,0,0],null,null,null),
    e('e_s1','系统1','term',287,16,0.99,1,[8,16,22,20,18,14,16,18,20,15,10,8,10,12,9,7,5,4],[[1,0,'系统1几乎在暗中决定一切。'],[2,3,'系统1的判断来自联想记忆网络。'],[5,1,'锚定效应：系统1被起点数值拖动。'],[9,2,'系统1喜欢连贯，不在乎证据量。']],null,null),
    e('e_s2','系统2','term',264,15,0.98,1,[6,12,18,16,15,13,12,14,16,12,9,8,9,10,7,6,4,3],[[1,1,'系统2把输入转化为行动。'],[3,2,'注意力预算由系统2分配。']],null,null),
    e('e_anc','锚定效应','term',96,9,0.90,1,[2,5,10,12,9,7,6,8,7,5,4,3,2,3,2,1,1,0],[[5,2,'锚定效应在随机轮盘下依然生效。']],null,null),
    e('e_avai','可得性','term',78,8,0.87,0,[1,3,6,9,11,10,8,6,7,5,3,2,2,3,1,1,0,0],[[7,1,'可得性启发：容易想起的更容易相信。']],null,null),
    e('e_loss','损失厌恶','term',64,7,0.85,0,[0,1,2,4,7,9,10,8,7,5,4,3,2,2,1,1,0,0],null,null,null),
    e('e_fram','框架效应','term',41,6,0.80,0,[0,0,1,2,3,4,6,7,5,4,3,2,1,2,1,0,0,0],null,null,null),
    e('e_reg','均值回归','term',22,4,0.66,0,[0,0,0,1,2,3,2,4,3,2,1,1,0,1,0,0,0,0],null,null,null),
    e('e_wys','WYSIATI','abbr',26,5,0.83,0,[0,2,4,6,5,4,3,2,3,2,1,1,0,0,1,0,0,0],[[4,1,'WYSIATI：眼见即全部。']],null,null),
    e('e_hce','HCE','abbr',14,3,0.69,0,[0,0,1,1,2,2,1,3,2,1,0,0,1,0,0,0,0,0],null,null,null),
    e('e_mtm','《模型思维》','book',7,2,0.75,0,[0,0,0,0,1,0,0,1,0,1,0,0,0,0,1,0,0,0],null,null,null),
    e('e_rtm','《不确定世界的理性选择》','book',5,2,0.71,0,[0,0,0,0,0,1,0,0,1,0,0,0,0,0,1,0,0,0],null,null,null)
  ];
  var XR_LOW=0.7;
  function xrTypeCount(t){return XR_ENTS.filter(function(x){return x.type===t}).length}
  function xrList(t){
    var kw=XR.kw.trim();
    var a=XR_ENTS.filter(function(x){return x.type===t&&(!kw||x.name.indexOf(kw)>=0)});
    if(XR.sort==='score')a=a.slice().sort(function(p,q){return q.score-p.score});
    else if(XR.sort==='n')a=a.slice().sort(function(p,q){return q.n-p.n});
    else a=a.slice().sort(function(p,q){return p.name.localeCompare(q.name,'zh')});
    return a
  }
  function xrHeadHtml(){
    var st=XR.status;
    var lbl=st==='run'?('解析中 '+XR.p+'%'):st==='pause'?'已暂停 · 断点已存':st==='fail'?'上次失败':('已解析 '+XR.done+'/'+XR.total+' 章');
    var btns='';
    if(st==='ready'&&XR.done<XR.total)btns+='<button class="chip !text-[10px]" id="xrBarContinue" onclick="xrContinue()">继续生成</button>';
    if(st==='ready'||st==='fail')btns+='<button class="chip !text-[10px]" onclick="xrScopeOpen()">重新解析</button>';
    btns+='<button class="chip !text-[10px]" onclick="xrReset()">重置索引</button>';
    btns+='<button class="chip !text-[10px]'+(XR.org?' !grad text-white':'')+'" id="xrOrgBtn" onclick="xrToggleOrg()">整理</button>';
    return '<div class="pt-2 flex items-center gap-2 flex-wrap"><b class="text-[12px]">'+lbl+'</b><span class="flex-1"></span>'+btns+'</div>'
  }
  function xrTabsHtml(){
    return XR_TYPES.filter(function(t){return xrTypeCount(t[0])>0}).map(function(t){
      return '<div class="xr-tab'+(XR.type===t[0]?' on':'')+'" id="xr-tab-'+t[0]+'" onclick="xrPickTab(\''+t[0]+'\')">'+t[1]+' · '+xrTypeCount(t[0])+'</div>'
    }).join('')
  }
  function xrRowHtml(x){
    var badges='<span class="xr-tbadge '+(x.usr?'user':x.type)+'">'+(x.usr?'我的词条':XR_TL[x.type])+'</span>';
    if(x.toc)badges+='<span class="xr-tbadge toc">目录词</span>';
    var check=XR.org?'<div class="shrink-0 w-5 h-5 rounded-lg border flex items-center justify-center text-[10px] font-black '+(XR.sel[x.id]?'grad text-white border-transparent':'border-slate-300 text-transparent')+'" id="xr-s-'+x.id+'" onclick="xrSel(\''+x.id+'\')">✓</div>':'';
    return '<div class="xr-ent'+(XR.org&&XR.sel[x.id]?' sel':'')+'" id="'+x.id+'" onclick="'+(XR.org?'xrSel(\''+x.id+'\')':'xrEntOpen(\''+x.id+'\')')+'">'
      +check+'<div class="flex-1 min-w-0"><div class="flex items-center gap-1.5 flex-wrap"><b class="text-xs">'+x.name+'</b>'+badges+'</div>'
      +'<div class="text-[9px] text-slate-400 mt-0.5">'+x.n+' 次 · 跨 '+x.chs+' 章 · 置信 '+x.score.toFixed(2)+(x.dlg!=null?' · 台词 '+x.dlg:'')+'</div></div>'
      +'<span class="text-slate-300">›</span></div>'
  }
  function xrListHtml(){
    var a=xrList(XR.type),hi=[],lo=[];
    a.forEach(function(x){(x.score<XR_LOW?lo:hi).push(x)});
    var h=hi.map(xrRowHtml).join('');
    if(!hi.length&&!lo.length)h='<div class="text-[10px] text-slate-400 py-6 text-center">该类没有词条</div>';
    if(lo.length){
      var open=!!XR.expanded[XR.type];
      h+='<div class="mt-2 text-[10px] font-bold text-slate-400 flex items-center gap-1.5 cursor-pointer" id="xr-lowtoggle" onclick="xrToggleLow(\''+XR.type+'\')"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="'+(open?'m6 9 6 6 6-9':'m6 15 6-6 6 9')+'"/></svg>低置信 · '+lo.length+' 条'+(open?' ▾':' ▸')+'</div>';
      if(open)h+='<div class="mt-1.5 space-y-2" id="xr-lowzone">'+lo.map(xrRowHtml).join('')+'</div>';
    }
    return h
  }
  window.xrToggleLow=function(t){XR.expanded[t]=!XR.expanded[t];xrRender()};
  window.xrEnts=function(){return XR_ENTS};
  window.xrState=function(){return XR};
  window.xrRender=function(){
    var hd=document.getElementById('xrHead');if(hd)hd.innerHTML=xrHeadHtml();
    var tb=document.getElementById('xrTabs');if(tb)tb.innerHTML=xrTabsHtml();
    var ls=document.getElementById('xrList');if(ls)ls.innerHTML='<div class="space-y-2">'+xrListHtml()+'</div>';
    var q=document.getElementById('xrQ');if(q&&q.value!==XR.kw)q.value=XR.kw;
    var qc=document.getElementById('xrQClear');if(qc)qc.classList.toggle('hidden',!XR.kw);
    var ft=document.getElementById('xrFoot');
    if(ft)ft.textContent=XR_ENTS.length+' 个词条 · 出场锚点全量 · 上下文截断（每实体前 N 条）';
    var bar=document.getElementById('xrBar');
    if(bar){
      if(XR.org){
        var s=Object.keys(XR.sel).filter(function(k){return XR.sel[k]});
        bar.classList.remove('hidden');
        var h='<div class="text-[10px] font-bold text-slate-400 flex items-center"><span>已选 '+s.length+' 条</span><span class="flex-1"></span><button class="text-slate-400" onclick="xrExitOrg()">退出整理</button></div><div class="flex gap-2">';
        h+='<button class="flex-1 py-2 rounded-xl grad text-white text-[11px] font-bold'+(s.length<2?' opacity-40':'')+'" onclick="xrMerge()">合并</button>';
        h+='<button class="flex-1 py-2 rounded-xl bg-rose-500 text-white text-[11px] font-bold'+(s.length<1?' opacity-40':'')+'" onclick="xrDelOpen()">移除</button></div>';
        bar.innerHTML=h
      } else {bar.classList.add('hidden');bar.innerHTML=''}
    }
  };
  window.xrPickTab=function(t){XR.type=t;xrRender()};
  window.xrToggleOrg=function(){XR.org=!XR.org;if(!XR.org)XR.sel={};xrRender()};
  window.xrExitOrg=function(){XR.org=false;XR.sel={};xrRender()};
  window.xrSel=function(id){XR.sel[id]=!XR.sel[id];xrRender()};
  var XR_SORTS=[['score','按置信'],['n','按出场'],['name','按名称']];
  window.xrToggleSort=function(){var i=0;XR_SORTS.forEach(function(s,k){if(s[0]===XR.sort)i=k});XR.sort=XR_SORTS[(i+1)%3][0];xrRender();toast('排序：'+XR_SORTS[(i+1)%3][1])};
  document.getElementById('xrQ')&&document.getElementById('xrQ').addEventListener('input',function(){this.value=XR.kw});
  var xrQHost=document.getElementById('xrQ');
  if(xrQHost)xrQHost.oninput=function(){XR.kw=this.value;xrRender()};
  /* 屏4 实体详情 */
  window.xrEntOpen=function(id){
    var x=XR_ENTS.find(function(v){return v.id===id});if(!x)return;
    var dist=x.dist.slice();while(dist.length<XR.total)dist.push(0);dist=dist.slice(0,XR.total);
    var max=Math.max.apply(null,dist)||1;
    var spark=dist.map(function(v){return '<i style="height:'+Math.max(2,Math.round(v/max*34))+'px" data-xr-bar="'+x.id+'"></i>'}).join('');
    var h='<div class="flex items-center gap-2 flex-wrap"><b class="text-[15px]">'+x.name+'</b><span class="xr-tbadge '+(x.usr?'user':x.type)+'">'+(x.usr?'我的词条':XR_TL[x.type])+'</span>'+(x.toc?'<span class="xr-tbadge toc">目录词</span>':'')+'<span class="flex-1"></span><span class="text-[10px] text-slate-400">置信 '+x.score.toFixed(2)+'</span></div>';
    h+='<div class="mt-2 text-[10px] text-slate-400">'+x.n+' 次提及 · 跨 '+x.chs+' 章'+(x.dlg!=null?' · 台词 '+x.dlg+' 段':'')+'</div>';
    if(x.q)h+='<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5"><span class="text-slate-400">代表语录</span><div class="mt-0.5">'+x.q+'</div></div>';
    h+='<div class="mt-3 text-[10px] font-bold text-slate-400">章节频次分布</div><div class="xr-sp mt-1.5" id="xr-spark-'+x.id+'">'+spark+'</div><div class="text-[8px] text-slate-400 mt-1">第1章 → 第'+XR.total+'章</div>';
    h+='<div class="mt-3 text-[10px] font-bold text-slate-400">出场 · 点按跳转到阅读位置</div><div class="mt-1.5 space-y-2" id="xr-ments-'+x.id+'">';
    var m=x.ment||[];
    if(!m.length)h+='<div class="text-[10px] text-slate-400">出场锚点已存 · 上下文未截取</div>';
    m.forEach(function(mm,k){
      h+='<div class="xr-jump" id="xr-ment-'+x.id+'-'+k+'" onclick="xrJumpTo('+mm[0]+','+mm[1]+')"><div class="flex items-center gap-2"><b class="text-[11px]">'+xrChTitle(mm[0])+'</b><span class="text-slate-400 text-[9px]">段 '+(mm[1]+1)+'</span></div><div class="text-slate-500 dark:text-slate-400 mt-0.5">'+mm[2]+'</div></div>'
    });
    h+='</div>';
    h+='<div class="mt-3 rounded-xl border border-dashed border-slate-200 dark:border-slate-700 p-2.5 text-[10px] text-slate-400 flex items-center gap-2" id="xr-aihold">AI 释义 · 二期占位<span class="flex-1"></span></div>';
    document.getElementById('xrEntBody').innerHTML=h;
    openSheet('sheetXrEnt')
  };
  window.xrJumpTo=function(ch,para){
    try{
      closeSheet('sheetXrEnt');
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
  /* 屏1 解析范围 */
  var xrScopeMode='all',xrScopeCh=3;
  window.xrScopeOpen=function(){
    xrScopeCh=(brV&&brV.b&&brV.ci!=null&&brV.b)?Math.min(brV.ci+1,XR.total):3;
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
    if(xrScopeMode==='all')navTo('p-xray')
  };
  /* 屏7 失败/中断 · F3 继续与重置 */
  window.xrContinue=function(){XR.status='run';XR.p=61;xrSetBookXr('b1',{st:'run',p:61});renderShelf();toast('增量解析 · 从第 13 章断点续跑');xrRender();setTimeout(function(){xrDoneAll()},600)};
  function xrDoneAll(){XR.status='ready';XR.done=XR.total;XR.p=100;xrSetBookXr('b1',{st:'ready',done:XR.total});renderShelf();xrRender();toast('全书索引完成 · '+XR_ENTS.length+' 个词条')}
  window.xrReset=function(){closeSheet('sheetXrFail');XR.done=0;XR.status='none';xrSetBookXr('b1',null);renderShelf();if(curPage==='p-xray')xrRender();toast('已重置 · 实体/出场/任务态已清空')};
  window.xrFailRetry=function(){closeSheet('sheetXrFail');XR.status='run';XR.p=66;xrSetBookXr('b1',{st:'run',p:66});renderShelf();toast('从断点续跑 · 第 13 章起')};
  /* 整理：合并与移除（F8） */
  function xrName(id){var x=XR_ENTS.find(function(v){return v.id===id});return x?x.name:id}
  window.xrMerge=function(){
    var s=Object.keys(XR.sel).filter(function(k){return XR.sel[k]});
    if(s.length<2){toast('合并至少选择 2 条');return}
    var canon=XR_ENTS.find(function(v){return v.id===s[0]});
    s.slice(1).forEach(function(id){var x=XR_ENTS.find(function(v){return v.id===id});if(x&&canon){canon.n+=x.n;canon.chs=Math.max(canon.chs,x.chs);if(!canon.aliases)canon.aliases=[];canon.aliases.push(x.name)}});
    XR_ENTS=XR_ENTS.filter(function(v){return !(XR.sel[v.id]&&v.id!==s[0])});
    XR.org=false;XR.sel={};xrRender();
    toast('已合并为「'+canon.name+'」· aliases '+s.length+' · 出场归属已迁移')
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
  var xrDelPick='book';
  window.xrDelPickScope=function(k){xrDelPick=k;xrDelRenderScope()};
  function xrDelRenderScope(){
    document.getElementById('xrDelScope').innerHTML=[['book','仅本书'],['global','升级到全局黑名单（所有书生效）']].map(function(o){
      return '<div class="xr-scope-opt'+(xrDelPick===o[0]?' on':'')+'" id="xr-del-'+o[0]+'" onclick="xrDelPickScope(\''+o[0]+'\')"><span class="w-4 h-4 rounded-full border flex items-center justify-center'+(xrDelPick===o[0]?' !border-transparent grad text-white':' border-slate-300')+'">'+(xrDelPick===o[0]?'<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M20 6 9 17l-5-5"/></svg>':'')+'</span>'+o[1]+'</div>'
    }).join('')
  }
  window.xrDoDel=function(){
    XR_ENTS=XR_ENTS.filter(function(v){return xrDelIds.indexOf(v.id)<0});
    closeSheet('sheetXrDel');XR.org=false;XR.sel={};xrRender();
    toast('已移除 '+xrDelIds.length+' 条 · '+(xrDelPick==='global'?'并加入全局黑名单':'仅本书生效'))
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
    var h='<div class="flex items-center gap-2 flex-wrap"><b class="text-[15px]">'+x.name+'</b><span class="xr-tbadge '+x.type+'">'+XR_TL[x.type]+'</span>'+(x.toc?'<span class="xr-tbadge toc">目录词</span>':'')+'</div>';
    h+='<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5">'+x.n+' 次提及 · 跨 '+x.chs+' 章 · 置信 '+x.score.toFixed(2)+(x.dlg!=null?' · 台词 '+x.dlg+' 段':'')+'</div>';
    if(x.q)h+='<div class="mt-2 text-[10px] text-slate-500 dark:text-slate-400">'+x.q+'</div>';
    h+='<div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet(\'sheetXrPeek\')">关闭</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="xrPeekToPanel(\''+x.name+'\')">面板中查看</button></div>';
    document.getElementById('xrPeekBody').innerHTML=h;
    openSheet('sheetXrPeek')
  };
  window.xrPeekToPanel=function(name){closeSheet('sheetXrPeek');var x=XR_ENTS.find(function(v){return v.name===name});XR.type=x?x.type:'term';XR.kw=name;navTo('p-xray');xrRender()};
  var xrAddPick={word:'',type:'term',scope:'book'};
  window.xrAddOpen=function(word){
    xrAddPick={word:word,type:xrGuessType(word),scope:'book'};
    document.getElementById('xrAddWord').textContent=word;
    document.getElementById('xrAddTypes').innerHTML=XR_TYPES.map(function(t){
      return '<div class="xr-tab'+(xrAddPick.type===t[0]?' on':'')+'" id="xr-add-'+t[0]+'" onclick="xrAddPickType(\''+t[0]+'\')">'+t[1]+'</div>'
    }).join('');
    document.getElementById('xrAddScope').innerHTML=xrAddScopeHtml();
    openSheet('sheetXrAdd')
  };
  function xrAddScopeHtml(){
    return [['book','仅本书'],['global','加入全局词库']].map(function(o){
      return '<div class="chip !text-[10px]'+(xrAddPick.scope===o[0]?' chip-on':'')+'" id="xr-addsc-'+o[0]+'" onclick="xrAddPickScope(\''+o[0]+'\')">'+o[1]+'</div>'
    }).join('')
  }
  window.xrAddPickType=function(t){xrAddPick.type=t;xrAddOpen(xrAddPick.word)};
  window.xrAddPickScope=function(s){xrAddPick.scope=s;
    document.getElementById('xrAddScope').innerHTML=xrAddScopeHtml()
  };
  window.xrDoAdd=function(){
    var id='e_u'+Date.now()%100000;
    XR_ENTS.push(e(id,xrAddPick.word,xrAddPick.type,0,0,1.0,0,XR_CHS.map(function(){return 0}),null,null,null));
    XR_ENTS[XR_ENTS.length-1].usr=1;
    closeSheet('sheetXrAdd');XR.type=xrAddPick.type;XR.kw='';
    if(curPage==='p-xray')xrRender();
    var sc=xrAddPick.scope==='global'?' · 已入全局词库':'';
    toast('已加词「'+xrAddPick.word+'」· 全书补扫中 · 出场 8 处（演示）'+sc)
  };
  /* 补扫建议规则（F8 回流 · 提示条形态） */
  window.xrSuggestCard=function(){
    var el=document.getElementById('xrBar');if(!el)return;
    el.classList.remove('hidden');
    el.innerHTML='<div class="text-[10px] leading-4"><b>建议规则</b>：你新增的词多与「X+探长」同现，是否把该模式加入词库？</div><div class="flex gap-2"><button class="flex-1 py-2 rounded-xl grad text-white text-[11px] font-bold" onclick="toast(\'规则已加入全局词库\');xrRender()">采纳</button><button class="flex-1 py-2 rounded-xl border border-slate-200 dark:border-slate-700 text-[11px] font-bold" onclick="xrRender()">暂不</button></div>'
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
    if(b&&b.xr&&b.xr.st!=='none')navTo('p-xray');
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
  /* 阅读器菜单行（屏5 入口）状态文案 */
  window.xrEntry=function(){
    var lbl=document.getElementById('brMoreXr');
    if(lbl)lbl.textContent=XR.status==='ready'?('已解析 '+XR.done+'/'+XR.total+' 章'):XR.status==='run'?('解析中 '+XR.p+'%'):XR.status==='pause'?'已暂停':XR.status==='fail'?'上次失败':'未解析';
    if(XR.status==='none'||XR.status==='ready'&&XR.done===0)xrScopeOpen();
    else navTo('p-xray')
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
  (function xrBoot(){try{
    var m=(location.search.match(/xr=([a-z]+)/)||[])[1];if(!m)return;
    var b=bsBook('b1');if(b){CURBK='b1'}
    if(m==='shelf'){xrSeed('shelf');shSt='全部';setPage('p-bookshelf');renderShelf();return}
    if(m==='menu'){xrSeed();setPage('p-bookshelf');renderShelf();shLongMenu('b1');return}
    if(m==='scope'){brOpen('b1');brShowChrome();xrScopeOpen();return}
    if(m==='panel'){navTo('p-xray');xrRender();return}
    if(m==='ent'){navTo('p-xray');xrRender();xrEntOpen('e_kmn');return}
    if(m==='jump'){navTo('p-xray');xrRender();xrEntOpen('e_kmn');xrJumpTo(1,2);return}
    if(m==='org'){navTo('p-xray');XR.org=true;XR.sel={'e_kmn':true,'e_dk':true};xrRender();return}
    if(m==='del'){navTo('p-xray');XR.org=true;XR.sel={'e_kmn':true,'e_dk':true};xrRender();xrDelOpen();return}
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
    if(m==='fail'){xrSeed();navTo('p-xray');xrRender();openSheet('sheetXrFail');return}
  }catch(e){console.warn('xr',e)}})();
})();
