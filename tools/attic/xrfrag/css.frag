/* V1.54 X-Ray 全书索引（批2 原型 · ?xr= 深链） */
.xr-tab{padding:5px 11px;border-radius:999px;font-size:11px;font-weight:800;background:rgba(148,163,184,.16);color:#64748b;cursor:pointer;white-space:nowrap}
.xr-tab.on{background:var(--accent);color:#fff}
.xr-ent{padding:10px 12px;border-radius:14px;background:#fff;border:1px solid #e2e8f0;display:flex;align-items:center;gap:10px}
.dark .xr-ent{background:#0f172a;border-color:#1e293b}
.xr-ent.sel{outline:2px solid var(--accent)}
.xr-tbadge{font-size:8px;font-weight:900;padding:2px 6px;border-radius:999px;background:rgba(99,102,241,.12);color:#6366f1;white-space:nowrap}
.xr-tbadge.loc{background:rgba(16,185,129,.12);color:#059669}
.xr-tbadge.org{background:rgba(245,158,11,.14);color:#b45309}
.xr-tbadge.term{background:rgba(14,165,233,.12);color:#0284c7}
.xr-tbadge.abbr{background:rgba(100,116,139,.14);color:#475569}
.xr-tbadge.book{background:rgba(236,72,153,.12);color:#db2777}
.xr-tbadge.user{background:rgba(139,92,246,.14);color:#7c3aed}
.xr-tbadge.toc{background:transparent;border:1px solid rgba(99,102,241,.5);color:#6366f1}
.xr-sp{display:flex;align-items:flex-end;gap:2px;height:34px}
.xr-sp i{flex:1;background:rgba(99,102,241,.55);border-radius:2px 2px 0 0;min-height:2px}
.xr-mrow{padding:8px 10px;border-radius:11px;background:rgba(148,163,184,.10);font-size:11px;line-height:1.5;cursor:pointer}
.xr-jump{padding:8px 10px;border-radius:11px;background:rgba(148,163,184,.10);font-size:11px;line-height:1.5;cursor:pointer}
.br-flash-xr{box-shadow:0 0 0 3px rgba(16,185,129,.6);border-radius:10px}
.xr-badge{position:absolute;top:4px;right:4px;z-index:5;font-size:8px;font-weight:900;padding:2px 6px;border-radius:999px;background:rgba(15,23,42,.78);color:#fff;display:flex;align-items:center;gap:3px;line-height:1.4}
.xr-badge.ready{background:rgba(99,102,241,.92)}
.xr-badge.pause{background:rgba(148,163,184,.9)}
.xr-badge.fail{background:rgba(244,63,94,.92)}
.xr-scope-opt{padding:10px 12px;border-radius:14px;border:1px solid #e2e8f0;font-size:12px;font-weight:800;cursor:pointer;display:flex;align-items:center;gap:8px}
.dark .xr-scope-opt{border-color:#1e293b}
.xr-scope-opt.on{border-color:var(--accent);background:rgba(99,102,241,.08);color:var(--accent)}
.xr-kw{flex:1;min-width:0;border:0;background:transparent;outline:none;font-size:12px;font-weight:700;color:inherit}
.xr-chip{flex:0 0 auto;width:74px;display:flex;flex-direction:column;align-items:center;gap:4px;padding:8px 3px 7px;border-radius:16px;cursor:pointer;text-align:center}
.xr-chip.on{background:rgba(99,102,241,.10);outline:2px solid var(--accent)}
.xr-chip .xr-av{width:46px;height:46px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-weight:900;font-size:17px;background:#6366f1}
.xr-chip .xr-av.loc{background:#059669}.xr-chip .xr-av.org{background:#b45309}.xr-chip .xr-av.term{background:#0284c7}.xr-chip .xr-av.abbr{background:#64748b}.xr-chip .xr-av.book{background:#db2777}.xr-chip .xr-av.user{background:#7c3aed}
.xr-chip.low .xr-av{opacity:.55}
.xr-chip b{font-size:10px;max-width:70px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#334155}
.dark .xr-chip b{color:#cbd5e1}
.xr-chip .xr-cnt{font-size:8px;color:#94a3b8}
.xr-clip{padding:9px 11px;border-radius:12px;background:rgba(148,163,184,.10);font-size:11px;line-height:1.55;cursor:pointer}
.xr-clip b{color:var(--accent)}
.xr-clip .xr-chlabel{font-size:9px;font-weight:900;color:#94a3b8}
