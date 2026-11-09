#!/usr/bin/env bash
# 全量真机采集 v3（提速版）：跳过已采屏；盲 back 复位；短睡眠。
set -u
# 用法：ANDROID_SERIAL=<serial> bash tools/uxwalk/walk_all.sh  （屏表=routes.tsv：id<TAB>到达regex<TAB>steps；已采屏自动跳过）
export ANDROID_SERIAL="${ANDROID_SERIAL:-ea028260}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(cd "$DIR/../.." && pwd)/tmp/uxwalk"
mkdir -p "$OUT"
UIXML="$(cygpath -w "$OUT")/ui.xml"
PXML="$OUT/p.xml"
ADB="adb"

dump() {
  $ADB shell "uiautomator dump /data/local/tmp/ui.xml" </dev/null >/dev/null 2>&1
  $ADB shell "cat /data/local/tmp/ui.xml" </dev/null > "$UIXML" 2>/dev/null
  n=$(grep -o "<node" "$UIXML" | wc -l)
  if [ "$n" -lt 8 ]; then sleep 0.8; $ADB shell "uiautomator dump /data/local/tmp/ui.xml" </dev/null >/dev/null 2>&1; $ADB shell "cat /data/local/tmp/ui.xml" </dev/null > "$UIXML" 2>/dev/null; fi
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
    const lab=(d+" "+t);
    if(re.test(lab)){console.log(((b[0]+b[2])>>1)+","+((b[1]+b[3])>>1));process.exit(0);}
  }' "$UIXML" "$1"
}

tap() { $ADB shell input tap "${1%,*}" "${1#*,}" </dev/null >/dev/null 2>&1; sleep "${2:-1.0}"; }
keyb() { $ADB shell input keyevent 4 </dev/null >/dev/null 2>&1; sleep 0.35; }

back_to_tabs() {
  dump
  [ -n "$(findpt 'content-desc=\"今天\"')" ] && return 0
  for i in 1 2 3 4 5; do keyb; done
  dump
  [ -n "$(findpt 'content-desc=\"今天\"')" ] && return 0
  $ADB shell monkey -p com.lifeharness.lifeharness -c android.intent.category.LAUNCHER 1 </dev/null >/dev/null 2>&1
  for t in 1 2 3 4 5 6 7 8 9 10; do sleep 0.8; dump; [ -n "$(findpt 'content-desc=\"今天\"')" ] && return 0; done
  return 1
}

goto_grid() { # $1=目标磁贴 regex（滚动到目标可见为止，治冷启动落位与滚动复位抖动）
  back_to_tabs
  p=$(findpt '^今天$'); [ -n "$p" ] && tap "$p" 0.8
  p=""
  for k in 1 2 3 4; do
    $ADB shell input swipe 600 1900 600 700 350 </dev/null >/dev/null 2>&1; sleep 0.6
    dump; p=$(findpt "$1"); [ -n "$p" ] && break
  done
}

run_route() {
  local id="$1" arrive="$2" steps="$3"
  if [ -s "$OUT/$id.xml" ] && [ "$(grep -o '<node' "$OUT/$id.xml" | wc -l)" -ge 8 ]; then return 0; fi
  back_to_tabs
  IFS=';' read -ra SS <<< "$steps"
  for st in "${SS[@]}"; do
    case "$st" in
      tab:*)  dump; p=$(findpt "${st#tab:}"); [ -n "$p" ] && tap "$p" || echo "$id STEP-FAIL $st" >> "$OUT/fail.log";;
      tile:*) goto_grid "${st#tile:}"; p=$(findpt "${st#tile:}"); [ -n "$p" ] && tap "$p" || echo "$id STEP-FAIL $st" >> "$OUT/fail.log";;
      row:*)  dump; p=$(findpt "${st#row:}"); [ -n "$p" ] && tap "$p" || echo "$id STEP-FAIL $st" >> "$OUT/fail.log";;
      back:*) for i in $(seq 1 "${st#back:}"); do keyb; done;;
      raw:*)  tap "${st#raw:}" 1.0;;
      scroll)  $ADB shell input swipe 600 1900 600 700 350 </dev/null >/dev/null 2>&1; sleep 0.5;;
      scroll2) $ADB shell input swipe 600 1900 600 700 350 </dev/null >/dev/null 2>&1; sleep 0.4; $ADB shell input swipe 600 1900 600 700 350 </dev/null >/dev/null 2>&1; sleep 0.5;;
    esac
  done
  dump
  cp "$UIXML" "$OUT/$id.xml"
  $ADB shell "screencap -p /sdcard/lh_walk.png" </dev/null >/dev/null 2>&1
  $ADB pull //sdcard/lh_walk.png "$OUT/$id.png" >/dev/null 2>&1
  if [ -n "$arrive" ] && ! grep -qE "$arrive" "$OUT/$id.xml"; then echo "$id ARRIVE-FLAG($arrive)" >> "$OUT/fail.log"; fi
  echo "done $id" >> "$OUT/progress.log"
}

while IFS=$'\t' read -r id arrive steps <&3; do
  [ -z "$id" ] && continue
  case "$id" in \#*) continue;; esac
  run_route "$id" "$arrive" "$steps"
done 3< "$DIR/routes.tsv"
echo ALL-FINISH >> "$OUT/progress.log"
