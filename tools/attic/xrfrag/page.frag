    <!-- ═══ X-Ray 批2 · 屏3 全书索引面板（?xr=panel）═══ -->
    <section id="p-xray" class="page px-5 safe-pb no-scrollbar">
      <div id="xrHead" class="pt-1"></div>
      <div class="mt-2 flex items-center gap-2">
        <div class="flex-1 flex items-center gap-2 rounded-xl bg-slate-100 dark:bg-slate-800 px-3 py-2">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg>
          <input id="xrQ" class="xr-kw" placeholder="类内搜索" oninput="xrQ=this.value;xrRender()">
          <button id="xrQClear" class="hidden text-slate-400 text-xs px-1" onclick="xrQ='';this.classList.add('hidden');var i=document.getElementById('xrQ');if(i)i.value='';xrRender()">✕</button>
        </div>
        <button id="xrSortBtn" class="px-3 py-2 rounded-xl text-[11px] font-bold bg-slate-100 dark:bg-slate-800" onclick="xrSortCycle()">按出场</button>
      </div>
      <div id="xrTabs" class="mt-2.5 flex gap-1.5 overflow-x-auto no-scrollbar"></div>
      <div id="xrList" class="mt-2.5 space-y-2"></div>
      <div id="xrBar" class="hidden mt-3 rounded-2xl bg-white dark:bg-slate-900 border border-slate-100 dark:border-slate-800 p-2.5 space-y-2"></div>
      <div id="xrFoot" class="mt-3 text-[10px] text-slate-400 text-center"></div>
    </section>
