/* 健康 V2 注入器：档案 / 体征 / 症状 / 报告 / 提醒 / AI 小结
   用法：cp prototype/index-health.html prototype/.ih.bak && node tools/health/patch2.js
   幂等：已注入过则直接跳过（靠 HP_V2 标记判定） */
const fs=require('fs'),P='prototype/index-health.html';
const rd=p=>fs.readFileSync(p,'utf8');
const css=rd('tools/health/v2_css.html'),pages=rd('tools/health/v2_pages.html'),
      sheets=rd('tools/health/v2_sheets.html'),js=rd('tools/health/v2_js.js');
let s=rd(P).replace(/\r\n/g,'\n');   /* 工作副本可能被 autocrlf 转成 CRLF，统一按 LF 处理 */
if(s.includes('/* HP_V2 */')){console.log('SKIP already patched');process.exit(0)}
const rep=(a,b,label)=>{const n=s.split(a).length-1;
  if(n!==1)throw new Error('anchor「'+(label||a.slice(0,40))+'」命中 '+n+' 次（需恰好 1 次）');
  s=s.replace(a,b)};

/* 1) CSS */
rep('  .sheet>.sheet-panel{max-height:88vh;overflow-y:auto;-webkit-overflow-scrolling:touch}',
    '  .sheet>.sheet-panel{max-height:88vh;overflow-y:auto;-webkit-overflow-scrolling:touch}\n'+css,'CSS');

/* 2) 屏 */
rep('    <!-- ===== P10 目标 OKR ===== -->','    <!-- HP_V2 屏组 -->\n'+pages+'    <!-- ===== P10 目标 OKR ===== -->','PAGES');

/* 3) 弹层 */
rep('  <!-- ===== 插件详情弹层 ===== -->','  <!-- HP_V2 弹层组 -->\n'+sheets+'\n  <!-- ===== 插件详情弹层 ===== -->','SHEETS');

/* 4) JS 段（放在 hBoot 之前，保证 const 先于初始化求值） */
rep('function hBoot(){','/* HP_V2 */\n'+js+'\nfunction hBoot(){','JS');

/* 5) 初始化行 */
rep('renderHealth(); renderOkr(); hBoot();','renderHealth(); renderOkr(); hBoot(); hpBoot();','INIT');

/* 6) TITLES */
rep("'p-hSet':['健康设置','单位 · 提醒 · 备份与导出'],",
    "'p-hSet':['健康设置','单位 · 提醒 · 备份与导出'],\n"
   +" 'p-hProfile':['健康档案','多档案 · 基线 · 病史与过敏'],'p-vitals':['体征记录','血压 · 心率 · 血氧 · 血糖 · 体温'],\n"
   +" 'p-symptom':['症状与不适','疼痛分级 · 部位 · 照片 · 词云'],'p-report':['检查报告','图片 / PDF · 指标参考范围'],",
    'TITLES');

/* 7) 工作台入口宫格 7 → 12 */
rep("grid grid-cols-7 gap-1 text-center text-[9px]","grid grid-cols-6 gap-1 text-center text-[9px]",'ENTRYGRID');
rep("[['p-body','body','身体数据'],['p-sleepLog','sleep','睡眠'],['p-exLog','ex','运动'],['p-med','drug','用药'],['p-trends','trend','趋势'],['p-goalsH','goal','目标'],['p-hSet','set','设置']]",
    "[['p-hProfile','body','档案'],['p-vitals','care','体征'],['p-symptom','wave','症状'],['p-report','report','报告'],['p-body','body','身体数据'],['p-sleepLog','sleep','睡眠'],['p-exLog','ex','运动'],['p-med','drug','用药'],['p-trends','trend','趋势'],['p-goalsH','goal','目标'],['p-hSet','set','设置'],['p-health','goal','概览']]",'ENTRYROW');

/* 8) 工作台体征条 */
rep('      <div class="card mt-3 !p-0 overflow-hidden">\n        <div class="flex items-center justify-between px-4 pt-3 pb-1">\n          <b class="text-[13px]">近 14 天达标概览</b>',
    '      <div class="card mt-3 !p-3 flex gap-1" id="hpStrip"></div>\n'
   +'      <div class="card mt-3 !p-0 overflow-hidden">\n        <div class="flex items-center justify-between px-4 pt-3 pb-1">\n          <b class="text-[13px]">近 14 天达标概览</b>','STRIP');

/* 9) 记录入口弹层补三类 + 提醒/AI */
rep('      </div>\n      <button class="mini-btn w-full mt-3" onclick="closeSheet(\'sheetHAdd\');htNav(\'p-hSet\')">健康设置</button>',
    '        <button class="card w-full flex items-center gap-3 text-left active:scale-[.99]" onclick="closeSheet(\'sheetHAdd\');vtOpen()"><span class="w-9 h-9 rounded-xl bg-rose-500/10 text-rose-500 flex items-center justify-center">'+''+'</span><span class="flex-1"><b class="text-[13px]">记体征</b><div class="text-[10px] text-slate-400">血压 · 心率 · 血氧 · 血糖 · 体温</div></span><span class="text-slate-300">›</span></button>\n'
   +'        <button class="card w-full flex items-center gap-3 text-left active:scale-[.99]" onclick="closeSheet(\'sheetHAdd\');syOpen()"><span class="w-9 h-9 rounded-xl bg-violet-500/10 text-violet-500 flex items-center justify-center"></span><span class="flex-1"><b class="text-[13px]">记症状</b><div class="text-[10px] text-slate-400">疼痛分级 · 部位 · 照片</div></span><span class="text-slate-300">›</span></button>\n'
   +'        <button class="card w-full flex items-center gap-3 text-left active:scale-[.99]" onclick="closeSheet(\'sheetHAdd\');rpaOpen()"><span class="w-9 h-9 rounded-xl bg-teal-500/10 text-teal-500 flex items-center justify-center"></span><span class="flex-1"><b class="text-[13px]">传检查报告</b><div class="text-[10px] text-slate-400">图片 / PDF · 检验项与参考范围</div></span><span class="text-slate-300">›</span></button>\n'
   +'      </div>\n'
   +'      <div class="flex gap-2 mt-3"><button class="flex-1 mini-btn" onclick="closeSheet(\'sheetHAdd\');hrmOpen()">健康提醒</button><button class="flex-1 mini-btn" onclick="closeSheet(\'sheetHAdd\');aisOpen()">AI 健康小结</button></div>\n'
   +'      <button class="mini-btn w-full mt-2" onclick="closeSheet(\'sheetHAdd\');htNav(\'p-hSet\')">健康设置</button>','ADDROWS');

/* 10) 设置页补三行 + 修坏引号 + 去教学文案 */
rep('<span class="text-xs font-semibold>分类映射</span>','<span class="text-xs font-semibold">分类映射</span>','QUOTE');
rep('<div class="text-[9px] text-slate-400 mt-0.5">按 ml 记账时用于换算</div>','','CUPSUB');
rep('<div class="text-[9px] text-slate-400 mt-0.5">关闭时只记起止与质量</div>','','STAGESUB');
rep("onclick=\"hTg(this,'仪表盘健康卡已切换 · 变更单 S-11 待回灌 index.html')\"","onclick=\"hTg(this,'仪表盘健康卡已切换')\"",'DASHTG');
rep('        <div class="px-4 py-3 flex items-center justify-between"><span class="text-xs font-semibold">健康数据随本地备份</span>',
    '        <div class="px-4 py-3 flex items-center justify-between" onclick="htNav(\'p-hProfile\')"><span class="text-xs font-semibold">健康档案与多档案</span><span class="text-slate-300">›</span></div>\n'
   +'        <div class="px-4 py-3 flex items-center justify-between" onclick="hrmOpen()"><span class="text-xs font-semibold">健康提醒排程</span><span class="text-[11px] text-slate-400">服药 · 测量 · 复诊</span></div>\n'
   +'        <div class="px-4 py-3 flex items-center justify-between" onclick="aisOpen()"><span class="text-xs font-semibold">AI 健康小结</span><span class="text-[11px] text-slate-400">仅文本整理</span></div>\n'
   +'        <div class="px-4 py-3 flex items-center justify-between"><span class="text-xs font-semibold">健康数据随本地备份</span>','SETROWS');

/* 11) htNav 渲染派发补四屏 */
rep("'p-body':hBodyChart,'p-exLog':hRenderExLog,'p-med':hRenderMeds,'p-sleepLog':hRenderSleep,'p-trends':hTrends,'p-goalsH':hRenderGoals,'p-hSet':hRenderSet",
    "'p-body':hBodyChart,'p-exLog':hRenderExLog,'p-med':hRenderMeds,'p-sleepLog':hRenderSleep,'p-trends':hTrends,'p-goalsH':hRenderGoals,'p-hSet':hRenderSet,"
   +"'p-hProfile':hpRender,'p-vitals':vtRender,'p-symptom':syRender,'p-report':rpRender,'p-health':hpStrip",'NAVMAP');

fs.writeFileSync(P,s);
console.log('OK HP_V2 applied. lines =',s.split('\n').length);
