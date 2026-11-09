#!/usr/bin/env bash
# UX 机械 lint 棘轮闸：在活 8 份原型跑 ux-skill 引擎四规则组（emoji 族 / placeholder-as-label /
# select-without-label / outline-none-no-focus-visible），与 tools/uxlint_baseline.json 比较，命中上升即红。
# 依赖：~/.qoder/skills/ux-skill（laith0003/ux-skill 封装件）；python 用全路径（商店桩坑）。
# 用法：bash tools/uxlint.sh            ＝跑闸（接复测包验收轮）
#       bash tools/uxlint.sh --baseline ＝用当前值重写基线（整改降档后随批执行）
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$HOME/.qoder/skills/ux-skill"
PY="D:/app_workplace/python3.11/python.exe"
BASE="$REPO/tools/uxlint_baseline.json"
TMP="$REPO/tmp/uxlint_report.json"
[ -d "$SKILL/engine" ] || { echo "RED: ux-skill 引擎未安装（$SKILL）"; exit 2; }
mkdir -p "$REPO/tmp"
cd "$SKILL"
# rc=1 是「有命中」的正常语义，成败以 eval 棘轮判定为准
PYTHONIOENCODING=utf-8 "$PY" -m engine.cli.main --no-pretty lint "$REPO/prototype" --threshold low > "$TMP" 2>/dev/null
cd "$REPO"
"$PY" -X utf8 tools/uxlint_eval.py "$TMP" "$BASE" "$@"
