# CLAUDE.md — 入口别名（唯一事实源是 AGENTS.md）

本仓库的 agent 规则、开工必读路径、验证门禁与禁令**全部在 [`AGENTS.md`](AGENTS.md)**，请先完整阅读并遵守。

三条不可让步的入口事实：

1. 当前状态只看 `docs/STATUS.md`（唯一状态源）。
2. 读任何文档前先查 `docs/INDEX.md`（文档地图），按任务只读命中行指向的文件，不通读 `docs/`。
3. 文档域收口必跑 `python tools/doclint.py`（死链 + 漂移守护五检），红灯必须清零；`tools/run_gate.sh` 已内置该前置。
