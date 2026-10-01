              <div class="px-4 pt-3.5 pb-2 shrink-0 flex items-center gap-2">
                <div class="flex-1 flex items-center gap-2 rounded-xl bg-slate-100 dark:bg-slate-800 px-3 py-2">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg>
                  <input id="xrHdrQ" class="xr-kw" placeholder="搜本书" oninput="xrHdrSearch(this.value)">
                </div>
                <div class="flex rounded-xl bg-slate-100 dark:bg-slate-800 p-1 gap-1 shrink-0">
                  <div class="xr-seg on" id="xrSegToc" onclick="brTocTab('toc')">目录</div>
                  <div class="xr-seg" id="xrSegXr" onclick="brTocTab('xr')">X-Ray</div>
                </div>
                <button id="xrFoldBtn" onclick="brDrFoldAll()" title="全部折叠" class="w-7 h-7 shrink-0 rounded-lg flex items-center justify-center text-slate-400"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 8.5 12 4l5 4.5M7 15.5 12 20l5-4.5"/></svg></button>
                <button onclick="brTocClose()" title="关闭" class="w-7 h-7 shrink-0 rounded-lg flex items-center justify-center text-slate-400"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
              </div>
