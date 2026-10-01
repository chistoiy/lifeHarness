  <!-- V1.54 X-Ray 批2 弹层群（?xr=scope|ent|del|add|peek|bak|fail） -->
  <div id="sheetXrScope" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrScope')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">解析范围</b><span class="text-[9px] text-slate-400">全书索引 · X-Ray</span></div>
      <div id="xrScopeOpts" class="mt-3 space-y-2"></div>
      <div id="xrScopeRange" class="hidden mt-2.5 flex items-center gap-2 text-[11px]">
        <span class="text-slate-400 font-bold">起</span><select id="xrFrom" class="flex-1 rounded-xl bg-slate-100 dark:bg-slate-800 px-2.5 py-2 font-bold" onchange="xrScopeEst()"></select>
        <span class="text-slate-400 font-bold">止</span><select id="xrTo" class="flex-1 rounded-xl bg-slate-100 dark:bg-slate-800 px-2.5 py-2 font-bold" onchange="xrScopeEst()"></select>
      </div>
      <div class="mt-3 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5 flex items-center gap-2"><span class="text-slate-400">预估文本量</span><b id="xrScopeEst" class="ml-auto tabular-nums">—</b></div>
      <div class="mt-2 text-[9px] text-slate-400 text-center">前台轻抽取 · 解析期间书保持可读 · 断点可续</div>
      <div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet('sheetXrScope')">取消</button><button id="xrScopeGoBtn" class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="xrScopeStart()">开始解析</button></div>
    </div>
  </div>
  <div id="sheetXrDel" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrDel')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">移除词条</b><span class="text-[9px] text-slate-400">整理</span></div>
      <div id="xrDelBody" class="mt-2 text-[11px] leading-5 text-slate-500 dark:text-slate-400"></div>
      <div class="mt-2.5 space-y-1.5" id="xrDelScope"></div>
      <div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet('sheetXrDel')">取消</button><button class="flex-1 py-2.5 rounded-xl bg-rose-500 text-white text-xs font-bold" onclick="xrDoDel()">确认移除</button></div>
    </div>
  </div>
  <div id="sheetXrAdd" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrAdd')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">加为词条</b><span class="text-[9px] text-slate-400">全书索引 · X-Ray</span></div>
      <div class="mt-2.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] flex items-center gap-2"><span class="text-slate-400">词条</span><input id="xrAddWordIn" class="xr-kw !text-right !font-bold" placeholder="要加入的词"></div>
      <div class="mt-2.5 text-[10px] font-bold text-slate-400">类型</div>
      <div class="mt-1.5 flex gap-1.5 flex-wrap" id="xrAddTypes"></div>
      <div class="mt-2.5 text-[10px] font-bold text-slate-400">生效范围</div>
      <div class="mt-1.5 flex gap-1.5" id="xrAddScope"></div>
      <div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet('sheetXrAdd')">取消</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="xrDoAdd()">加为词条</button></div>
    </div>
  </div>
  <div id="sheetXrPeek" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrPeek')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">X-Ray</b><span class="text-[9px] text-slate-400">选区命中</span></div>
      <div id="xrPeekBody" class="mt-2"></div>
    </div>
  </div>
  <div id="sheetXrMerge" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrMerge')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8"><div id="xrMergeBody"></div></div>
  </div>
  <div id="sheetXrBak" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrBak')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">X-Ray 索引备份</b><span class="text-[9px] text-slate-400">数据</span></div>
      <div class="mt-2.5 space-y-2">
        <div id="xrBakExport" class="xr-mrow flex items-center gap-2" onclick="xrBakGo('exp')"><b class="text-xs">导出备份（.xraybak）</b><span class="ml-auto text-[10px] text-slate-400" id="xrBakLbl">12 个索引 · 8.9 MB</span></div>
        <div id="xrBakImport" class="xr-mrow flex items-center gap-2" onclick="xrBakGo('imp')"><b class="text-xs">从备份导入</b><span class="ml-auto text-[10px] text-slate-400">校验 MD5 · 覆盖需确认</span></div>
      </div>
      <div class="mt-2.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[10px] leading-4 text-slate-500 dark:text-slate-400" id="xrBakNote">整包备份已含索引数据 · 单书 .xraybak 供跨设备与分享</div>
    </div>
  </div>
  <div id="sheetXrFail" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrFail')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">解析中断</b><span class="text-[9px] text-rose-500 font-bold">失败</span></div>
      <div class="mt-2.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5" id="xrFailBody">《思考快与慢》解析到 <b>12/18</b> 章时中断 · 断点与已产出实体已保存<div class="text-slate-400 mt-0.5">原因：文件被移动 · 副本不可读</div></div>
      <div class="mt-3 space-y-2">
        <button id="xrFailRetryBtn" class="w-full py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="xrFailRetry()">从断点继续 · 第 13 章起</button>
        <button class="w-full py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="xrReset()">重置索引 · 清全书数据</button>
        <button class="w-full py-2.5 rounded-xl text-xs font-bold text-slate-400" onclick="closeSheet('sheetXrFail')">关闭</button>
      </div>
    </div>
  </div>

