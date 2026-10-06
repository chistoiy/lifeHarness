#!/usr/bin/env bash
# 真机走查工装：按 content-desc 语义标签点一屏中的元素（v1 只做点按，不做断言）。
# 用法：bash tools/walk_tap.sh "我的"            # dump → 找 desc 含「我的」→ 点中心
#       bash tools/walk_tap.sh --list            # 只列当前屏语义标签与 bounds
# 已知坑（本仓记忆）：MSYS 会改写 /sdcard 路径 → 全程 MSYS_NO_PATHCONV=1；
# 磁贴类节点 desc 会把标题与副行合并（含 &#10;），故用「包含」匹配而非全等。
set -u
DEV=${DEV:-ea028260}
D=/sdcard/walk.xml
dump() {
  MSYS_NO_PATHCONV=1 adb -s "$DEV" shell uiautomator dump "$D" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 adb -s "$DEV" shell cat "$D" > tmp/walk.xml 2>/dev/null
}
shot() { MSYS_NO_PATHCONV=1 adb -s "$DEV" exec-out screencap -p > "tempWork/attest-6077/$1.png"; }
dump
if [ "${1:-}" = "--list" ]; then
  node -e "
const fs=require('fs');const x=fs.readFileSync('tmp/walk.xml','utf8');
for(const m of x.matchAll(/<node[^>]*?content-desc=\"([^\"]{1,60})\"[^>]*?bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"/g)){
  const t=m[1].replace(/&#10;/g,'⏎');
  console.log(t+'  ['+m[2]+','+m[3]+'-'+m[4]+','+m[5]+']');
}"
  exit 0
fi
NEEDLE=${1:?用法：walk_tap.sh <语义标签子串>}
XY=$(node -e "
const fs=require('fs');const x=fs.readFileSync('tmp/walk.xml','utf8');
const want=process.argv[1];
for(const m of x.matchAll(/<node[^>]*?content-desc=\"([^\"]*)\"[^>]*?bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"/g)){
  if(!m[1].includes(want))continue;
  const cx=Math.round((+m[2]+ +m[4])/2), cy=Math.round((+m[3]+ +m[5])/2);
  console.log(cx+' '+cy); process.exit(0);
}
console.log('');process.exit(1);" "$NEEDLE") || { echo "TAP-NOT-FOUND $NEEDLE"; exit 2; }
[ -n "$XY" ] || { echo "TAP-NOT-FOUND $NEEDLE"; exit 2; }
adb -s "$DEV" shell input tap ${XY% *} ${XY#* } && echo "TAP $NEEDLE @ $XY"
[ -n "${2:-}" ] && shot "$2"
