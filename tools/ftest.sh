#!/usr/bin/env bash
# ftest.sh · 单跑/批跑 flutter test，绕开「另一会话同时在跑测试」导致的
# native_assets sqlite3.dll 硬链冲突（Flutter tool 崩溃 PathExistsException errno 183）。
# 用法：bash tools/ftest.sh test/a_test.dart test/b_test.dart
set -u
cd "$(dirname "$0")/.."
DLL=build/native_assets/windows/sqlite3.dll
try() {
  rm -f "$DLL" build/native_assets/windows/native_assets.json
  out=$(flutter test "$@" 2>&1); rc=$?
  echo "$out" | grep -q "PathExistsException" && return 20
  echo "$out" | grep -E "^0[0-9]:[0-9]+ \+[0-9]+.*(-[0-9]+)?: (All tests|Some tests)|Error:|error -" | tail -8
  return $rc
}
for i in 1 2 3 4; do
  try "$@"
  rc=$?
  [ $rc -eq 0 ] && exit 0
  [ $rc -eq 20 ] && { echo "[retry $i] native_assets 冲突（并发跑测试），10s 后重试"; sleep 10; continue; }
  echo "[fail rc=$rc]"; exit $rc
done
echo "GATE-BUSY：flutter test 连续 4 次被并发抢占，请等另一会话跑完再试"
exit 20
