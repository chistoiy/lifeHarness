              <div class="px-4 pt-3.5 pb-2 shrink-0">
                <div id="xrHdrRow" class="flex items-center gap-2">
                  <div class="flex-1 flex items-center gap-2 rounded-xl bg-slate-100 dark:bg-slate-800 px-3 py-2 cursor-pointer" id="xrSearchPill" onclick="xrSearchEnter()">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg>
                    <span class="text-[11px] font-bold text-slate-400 truncate">搜本书</span>
                  </div>
                  <div class="xr-seg flex-1 text-center on" id="xrSegToc" onclick="brTocTab('toc')">目录</div>
                  <div class="xr-seg flex-1 text-center" id="xrSegXr" onclick="brTocTab('xr')">X-Ray</div>
                  <button onclick="brTocClose()" title="收起" class="w-7 h-7 shrink-0 rounded-lg flex items-center justify-center text-slate-400"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 9 5-5 5 5M7 15l5 5 5-5"/></svg></button>
                </div>
                <div id="xrHdrSearchRow" class="hidden items-center gap-2">
                  <div class="flex-1 flex items-center gap-2 rounded-xl bg-slate-100 dark:bg-slate-800 px-3 py-2">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg>
                    <input id="xrHdrQ" class="xr-kw" placeholder="搜本书" oninput="xrHdrSearch(this.value)">
                    <button id="xrHdrClr" class="hidden w-5 h-5 rounded-full bg-slate-300 text-white text-[10px] font-black flex items-center justify-center" onclick="xrHdrClear()">✕</button>
                  </div>
                  <span class="text-[11px] font-bold text-slate-400 cursor-pointer shrink-0 px-1" id="xrHdrCancel" onclick="xrSearchExit()">取消</span>
                </div>
                <div id="xrTocFoldRow" class="hidden justify-end pt-1.5">
                  <button class="text-[10px] font-bold text-slate-400" id="xrFoldBtn" onclick="xrFoldAll()">全部折叠</button>
                </div>
              </div>
