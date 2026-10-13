#!/usr/bin/env bash
# bootstrap_check.sh —— 换机 / 换工具「首次开机」自检（治理三轮 2026-10-13 立）
# 依据＝docs/archive/治理方案-20261013-规则与上下文与记忆治理.md §5.2 / §5.3（2026-10-13 收尾归档）
# 只读自检、不改任何文件；任一红项 exit 1（可接在开工第一步）。
# 用法：bash tools/bootstrap_check.sh [--python <解释器全路径>]
set -u
cd "$(dirname "$0")/.." || exit 1
PY="D:/app_workplace/python3.11/python.exe"
LIBS="D:/app_workplace/flutter"
[ "${1:-}" = "--python" ] && PY="${2:-$PY}"
red=0
ok() { printf '  [OK] %s\n' "$1"; }
no() { printf '  [!!] %s\n' "$1"; red=$((red + 1)); }
warn() { printf '  [~~] %s\n' "$1"; }

echo "== 1. 三件套行数预算（doclint 守护五）=="
check_lines() { n=$(wc -l < "$1" 2>/dev/null || echo 0); if [ "$n" -le "$2" ]; then ok "$1 = $n 行 ≤ $2"; else no "$1 = $n 行 超预算 $2"; fi; }
check_lines AGENTS.md 90
check_lines docs/STATUS.md 60
check_lines docs/INDEX.md 130

echo "== 2. 文档门禁 doclint（死链 + 守护全绿）=="
if [ -f "$PY" ] || command -v "$PY" >/dev/null 2>&1; then
  if "$PY" tools/doclint.py >"${TMPDIR:-/tmp}/bootstrap_doclint.log" 2>&1; then ok "doclint 全绿"; else no "doclint 红灯（详见 ${TMPDIR:-/tmp}/bootstrap_doclint.log）"; fi
else no "未找到 python：$PY（用 --python <路径> 指定）"; fi

echo "== 3. 机器本地件（不入仓，换机需重建）=="
LP=android/local.properties
if [ -f "$LP" ]; then
  ok "$LP 存在"
  if grep -qE 'flutter\.(versionCode|versionName)' "$LP"; then no "$LP 残留版本钉（会被构建吃掉）——清空这两个字段"; else ok "$LP 无版本钉"; fi
else no "$LP 缺失（按 docs/本机构建环境优化操作指导-20260930.md 生成 sdk.dir / flutter.sdk）"; fi

echo "== 4. 工具链可达 =="
[ -f "$LIBS/bin/flutter" ] && ok "flutter 在 $LIBS" || no "flutter 未在 $LIBS（见 AGENTS.md「环境事实」）"
command -v java >/dev/null 2>&1 && ok "java 可达" || warn "java 不在 PATH（本机用 jbr 全路径，属正常；见 AGENTS.md「环境事实」）"

echo "== 5. 规则件齐全（git clone 后应全在）=="
for f in AGENTS.md CLAUDE.md .cursorrules docs/STATUS.md docs/INDEX.md docs/agent笔记/经验坑.md; do
  if [ -f "$f" ]; then ok "$f"; else no "$f 缺失"; fi
done

echo
if [ "$red" -eq 0 ]; then echo "BOOTSTRAP OK（无红项）"; exit 0; else echo "BOOTSTRAP RED：$red 项待处理"; exit 1; fi
