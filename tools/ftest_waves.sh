#!/usr/bin/env bash
# ftest_waves.sh · 批内增量门禁「逐档拆波」跑法（2026-10-11 立，V1.64 批1 实伤归因）
#
# 为什么要这枚工具（当天两场实锤）：
#   ① 一次 `flutter test` 塞 8 个文件＝note_test/journal_test 这类大套件与快件混场，
#      isolate 挂死→40 分钟零输出，父 bash 被杀后 dart/flutter_tester 残骸仍占场
#      （native_assets 互抢），下一轮在毫无读数的重试里空转；
#   ② ftest.sh 聚合 stdout 走 grep 管道＝跑完才有字，中途不可观测。
# 本件口径：**一律一文件一波＋--timeout 90s**（首版轻件 3 合波当晚二次实锤同场挂死——
#   pump 套件跨文件同 isolate 互踩，与「全 app widget 测试拆独立文件」同族，2026-10-11 改口）、
#   每波日志**直写文件**（增量可 tail）、波毕即落一行 `rc＋尾行` 到 progress.txt、
#   开跑前先探场——场上有残留 dart/flutter_tester 直接 abort（先清残骸再开工）。
# 用法：bash tools/ftest_waves.sh <批次名> test/a_test.dart test/b_test.dart ...
#   读数：tail -f tmp/gate_<批次名>/progress.txt；判定行在末行 WAVES-DONE。
set -u
cd "$(dirname "$0")/.."
TAG="${1:?用法: ftest_waves.sh <批次名> test/xxx.dart ...}"; shift
[ $# -ge 1 ] || { echo "没有点名任何测试文件"; exit 2; }
LOGD="tmp/gate_$TAG"; mkdir -p "$LOGD"; : > "$LOGD/progress.txt"
DLL="build/native_assets/windows/sqlite3.dll"
NAJ="build/native_assets/windows/native_assets.json"

# —— 探场：残骸进程在场=上一场没死透，新场必互踩（HyperOS/Git Bash 读数口径见记忆）——
if powershell.exe -NoProfile -Command "Get-Process | Where-Object { \$_.ProcessName -match 'flutter_tester|dartaotruntime' }" 2>/dev/null | grep -qi "flutter_tester\|dartaotruntime"; then
  echo "FIELD-BUSY：场上仍有 flutter_tester/dartaotruntime 残骸，先用 powershell Stop-Process 清场再跑（勿硬闯）"
  exit 3
fi

# —— 分波：**一律一文件一波**（2026-10-11 二次实伤改口：轻件 3 合波在同场仍挂死——
#    pump 套件跨文件同 isolate 调度互踩，与「全 app widget 测试拆独立文件」同族；
#    首版按 3 合波的 note64b1 light1 卡 00:22 零增长即此）——
for f in "$@"; do
  [ -f "$f" ] || { echo "MISSING-FILE：$f 不存在（批跑前先核文件名，勿拿假红当回归）"; exit 2; }
done

run_wave() {
  local name="$1"; shift
  local i rc
  for i in 1 2 3 4; do
    rm -f "$DLL" "$NAJ"
    flutter test --timeout 90s "$@" > "$LOGD/$name.log" 2>&1
    rc=$?
    if grep -q "PathExistsException" "$LOGD/$name.log"; then
      echo "$name retry$i native_assets 抢占（并发会话），10s 后重试" >> "$LOGD/progress.txt"
      sleep 10; continue
    fi
    echo "$name rc=$rc | $(tail -1 "$LOGD/$name.log" | cut -c1-72)" >> "$LOGD/progress.txt"
    return $rc
  done
  echo "$name GATE-BUSY（连续 4 次被抢占）" >> "$LOGD/progress.txt"
  return 20
}

FAIL=0; N=0
for f in "$@"; do
  N=$((N+1))
  run_wave "w$N-$(basename "$f" .dart)" "$f" || FAIL=1
done

if [ $FAIL -eq 0 ]; then
  echo "WAVES-DONE $TAG ALL-GREEN $(date +%T)" >> "$LOGD/progress.txt"
else
  echo "WAVES-DONE $TAG HAS-RED（看各波 rc 与日志） $(date +%T)" >> "$LOGD/progress.txt"
fi
tail -12 "$LOGD/progress.txt"
exit $FAIL
