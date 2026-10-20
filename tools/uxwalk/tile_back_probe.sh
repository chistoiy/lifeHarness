#!/usr/bin/env bash
# U2 复现探针 v3：磁贴标签是「emoji\n名称」合并节点，必须用尾锚 `名称$`；
# 逐条宫格进模块→一次返回→判定落点（今天 / 仍在模块 / 退 app）。
# 用法：ANDROID_SERIAL=127.0.0.1:5555 bash tmp/u2probe3.sh [tile...]
set -u
export ANDROID_SERIAL="${ANDROID_SERIAL:-127.0.0.1:5555}" MSYS_NO_PATHCONV=1
OUT="$(cd "$(dirname "$0")/../.." && pwd)/tmp/uxwalk"
mkdir -p "$OUT"
PXML="$(cygpath -w "$OUT")/u2p3.xml"
ADB="adb -s $ANDROID_SERIAL"
LOG="$OUT/u2probe3.log"
# 屏幕几何按实际分辨率取（雷电 720x1280；真机 1200x2670）
read -r SW SH <<<"$($ADB shell wm size 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tr 'x' ' ')"
CX=$((SW/2)); S_TOP=$((SH*78/100)); S_BOT=$((SH*30/100))

dump() {
  for t in 1 2 3; do
    $ADB shell "uiautomator dump /data/local/tmp/ui.xml" </dev/null >/dev/null 2>&1
    $ADB shell "cat /data/local/tmp/ui.xml" </dev/null > "$PXML" 2>/dev/null
    [ -s "$PXML" ] && return 0
    sleep 1
  done
  return 1
}
labels() {
  node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8");const a=[];
  for(const m of s.matchAll(/<node[^>]*>/g)){const tag=m[0];
    const d=((tag.match(/content-desc="([^"]*)"/)||[])[1]||"").trim();
    const t=((tag.match(/text="([^"]*)"/)||[])[1]||"").trim();
    const v=(t||d); if(v)a.push(v.replace(/\s+/g," ").slice(0,20));}
  console.log(a.slice(0,12).join(" | "))' "$PXML"
}
findpt() {
  node -e '
  const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8");
  const re=new RegExp(process.argv[2]);
  for(const m of s.matchAll(/<node[^>]*>/g)){const tag=m[0];
    const d=((tag.match(/content-desc="([^"]*)"/)||[])[1]||"").trim();
    const t=((tag.match(/text="([^"]*)"/)||[])[1]||"").trim();
    const b=(tag.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/)||[]).slice(1).map(Number);
    if(!b.length)continue;
    const lab=(d+" "+t).trim(); if(re.test(lab)){console.log(((b[0]+b[2])>>1)+","+((b[1]+b[3])>>1));process.exit(0);}
  }' "$PXML" "$1"
}
tap() { $ADB shell input tap "${1%,*}" "${1#*,}" </dev/null >/dev/null 2>&1; sleep "${2:-1.1}"; }
focus3() {
  for t in 1 2 3; do
    f=$($ADB shell "dumpsys window | grep mCurrentFocus | head -1" </dev/null 2>/dev/null | tr -d "\r")
    if echo "$f" | grep -q lifeharness; then echo "lifeharness"; return; fi
    if echo "$f" | grep -qE "u0 [a-z]"; then echo "other:$(echo "$f" | grep -oE "u0 [a-zA-Z0-9._]+/" | tr -d 'u0 /')"; return; fi
    sleep 1
  done
  echo "unknown"
}
# 今天页专属标记（宫格卡标题／心情行／待办卡；模块页都不会有这些）
DASH_RE="今日心情|全部功能|今日待办|今日持有成本"
MODULE_RE="本地账|快速记一笔|重要日子|目标 OKR|物品价值|今日打卡|呵护 ·|记录 ·"
relaunch() { $ADB shell am force-stop com.lifeharness.lifeharness </dev/null >/dev/null 2>&1; sleep 0.6; $ADB shell monkey -p com.lifeharness.lifeharness -c android.intent.category.LAUNCHER 1 </dev/null >/dev/null 2>&1; sleep 5; }

probe() {
  local name="$1"
  echo "── $name"
  relaunch; dump || { echo "  RESULT=$name NO-DUMP" >> "$LOG"; return; }
  # 冷启动必须在今天页（宫格所在屏）；落别处直接判作废，避免盲 back 退 app 的假信号
  if ! grep -qE "$DASH_RE" "$PXML"; then echo "  RESULT=$name NOT-ON-DASH($(labels))" >> "$LOG"; return; fi
  p=""
  for k in 1 2 3 4 5 6; do
    $ADB shell input swipe "$CX" "$S_TOP" "$CX" "$S_BOT" 300 </dev/null >/dev/null 2>&1; sleep 0.7
    dump; p=$(findpt "&#10;${name}\$")
    [ -n "$p" ] && { echo "  磁贴@$p（第${k}滚）"; break; }
  done
  [ -z "$p" ] && { echo "  RESULT=$name NO-TILE" >> "$LOG"; return; }
  tap "$p" 1.8
  dump
  if grep -qE "$DASH_RE" "$PXML"; then echo "  RESULT=$name NO-ARRIVE($(labels))" >> "$LOG"; return; fi
  echo "  [到达] $(labels)"
  $ADB shell input keyevent 4 </dev/null >/dev/null 2>&1; sleep 1.6
  f=$(focus3)
  if [ "$f" != "lifeharness" ]; then echo "  RESULT=$name EXIT-APP($f)" >> "$LOG"; return; fi
  dump
  echo "  [返回后] $(labels)"
  if grep -qE "$DASH_RE" "$PXML"; then echo "  RESULT=$name OK→今天" >> "$LOG"
  else echo "  RESULT=$name LANDS-WRONG" >> "$LOG"; fi
}

: > "$LOG"
TILES="${*:-记账 日子 目标 物品 习惯 呵护 阅读}"
for t in $TILES; do probe "$t"; done
echo "==== 汇总（$ANDROID_SERIAL · ${SW}x${SH}）===="; cat "$LOG"
