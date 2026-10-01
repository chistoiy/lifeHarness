/* V1.54 X-Ray 全书索引（批2 原型 · ?xr= 深链 · 上拉面板「目录｜X-Ray」双段 · Kindle 图2/3 形态） */
.xr-tab{padding:5px 11px;border-radius:999px;font-size:11px;font-weight:800;background:rgba(148,163,184,.16);color:#64748b;cursor:pointer;white-space:nowrap}
.xr-tab.on{background:var(--accent);color:#fff}
.xr-tbadge{font-size:8px;font-weight:900;padding:2px 6px;border-radius:999px;background:rgba(99,102,241,.12);color:#6366f1;white-space:nowrap}
.xr-tbadge.loc{background:rgba(16,185,129,.12);color:#059669}
.xr-tbadge.org{background:rgba(245,158,11,.14);color:#b45309}
.xr-tbadge.term{background:rgba(14,165,233,.12);color:#0284c7}
.xr-tbadge.abbr{background:rgba(100,116,139,.14);color:#475569}
.xr-tbadge.book{background:rgba(236,72,153,.12);color:#db2777}
.xr-tbadge.user{background:rgba(139,92,246,.14);color:#7c3aed}
.xr-tbadge.toc{background:transparent;border:1px solid rgba(99,102,241,.5);color:#6366f1}
.xr-clip{padding:9px 11px;border-radius:12px;background:rgba(148,163,184,.10);font-size:11px;line-height:1.55;cursor:pointer}
.xr-clip b{color:var(--accent)}
.xr-clip .xr-chlabel{font-size:9px;font-weight:900;color:#94a3b8}
.xr-mrow{padding:8px 10px;border-radius:11px;background:rgba(148,163,184,.10);font-size:11px;line-height:1.5;cursor:pointer}
.br-flash-xr{box-shadow:0 0 0 3px rgba(16,185,129,.6);border-radius:10px}
.xr-badge{position:absolute;top:4px;right:4px;z-index:5;font-size:8px;font-weight:900;padding:2px 6px;border-radius:999px;background:rgba(15,23,42,.78);color:#fff;display:flex;align-items:center;gap:3px;line-height:1.4}
.xr-badge.ready{background:rgba(99,102,241,.92)}
.xr-badge.pause{background:rgba(148,163,184,.9)}
.xr-badge.fail{background:rgba(244,63,94,.92)}
.xr-scope-opt{padding:10px 12px;border-radius:14px;border:1px solid #e2e8f0;font-size:12px;font-weight:800;cursor:pointer;display:flex;align-items:center;gap:8px}
.dark .xr-scope-opt{border-color:#1e293b}
.xr-scope-opt.on{border-color:var(--accent);background:rgba(99,102,241,.08);color:var(--accent)}
.xr-kw{flex:1;min-width:0;border:0;background:transparent;outline:none;font-size:12px;font-weight:700;color:inherit}
/* 上拉全屏面板（目录｜X-Ray） */
.xr-sheet{position:absolute;inset:0;z-index:76;display:flex;align-items:flex-end}
.xr-sheet>div{transition:transform .24s ease}
.xr-sheet.out>div{transform:translateY(105%)}
.xr-seg{padding:6px 12px;border-radius:10px;font-size:11px;font-weight:800;color:#64748b;cursor:pointer;white-space:nowrap}
.xr-seg.on{background:#fff;color:#0f172a;box-shadow:0 1px 4px rgba(15,23,42,.10)}
.dark .xr-seg{color:#94a3b8}
.dark .xr-seg.on{background:#1e293b;color:#f1f5f9}
/* X-Ray 词条行 + 行内迷你分布条（图3） */
.xr-row{padding:10px 12px;border-radius:14px;background:#fff;border:1px solid #e8edf3;cursor:pointer}
.dark .xr-row{background:#0f172a;border-color:#1e293b}
.xr-row.sel{outline:2px solid var(--accent)}
.xr-row.curg{border-color:rgba(99,102,241,.55);background:rgba(99,102,241,.05)}
.xr-ck{width:18px;height:18px;border-radius:6px;flex:none;display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:900;background:#e2e8f0;color:transparent}
.xr-ck.on{background:var(--accent);color:#fff}
.xr-bar{position:relative;display:inline-block;width:118px;height:14px;border-radius:4px;background:rgba(148,163,184,.18);vertical-align:middle;flex:none}
.xr-bar i{position:absolute;top:2px;bottom:2px;width:3px;border-radius:2px;background:#6366f1;transform:translateX(-50%)}
.xr-bar i.unread{opacity:.3}
.xr-bar i.now{width:2px;background:#f59e0b;top:0;bottom:0}
.xr-bar.lg{width:100%;height:22px}
.xr-bar.lg i{width:4px;top:4px;bottom:4px}
.xr-grplbl{font-size:10px;font-weight:900;color:#94a3b8;padding:4px 2px 0}
.xr-sortrow{display:flex;justify-content:center;padding:8px 0 2px}
