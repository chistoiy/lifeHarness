#!/usr/bin/env bash
# 返回栈探针 v2：focus 判定三次重试+读空=UNKNOWN 不算 EXIT；到达判定要求页面专属标题（push 页以 Back 节点为铁证）。
# 用法：ANDROID_SERIAL=<serial> bash tools/uxwalk/back_probe.sh   （用例=文末 probe 行：id<TAB>父页regex<TAB>steps，按当轮目标增删）
# 自证定式：量产前必须先跑一条已知 OK 与一条已知 BAD，双向绿才可信（六轮审计四坑见 README.md）。
# 默认设备 ea028260（真机），可 ANDROID_SERIAL 覆盖
set -u
export ANDROID_SERIAL="${ANDROID_SERIAL:-ea028260}" MSYS_NO_PATHCONV=1
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(cd "$DIR/../.." && pwd)/tmp/uxwalk"
mkdir -p "$OUT"
PXML="$(cygpath -w "$OUT")/p.xml"
ADB="adb"

dump() {
  $ADB shell "uiautomator dump /data/local/tmp/ui.xml" </dev/null >/dev/null 2>&1
  $ADB shell "cat /data/local/tmp/ui.xml" </dev/null > "$PXML" 2>/dev/null
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
alltext() { node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8");console.log(s)' "$PXML"; }
tap() { $ADB shell input tap "${1%,*}" "${1#*,}" </dev/null >/dev/null 2>&1; sleep "${2:-1.1}"; }
keyb() { $ADB shell input keyevent 4 </dev/null >/dev/null 2>&1; sleep 0.35; }
# focus: 三次重试；输出 lifeharness | other:<pkg> | unknown
focus3() {
  for t in 1 2 3; do
    f=$($ADB shell "dumpsys window | grep mCurrentFocus | head -1" </dev/null 2>/dev/null | tr -d "\r")
    if echo "$f" | grep -q lifeharness; then echo "lifeharness"; return; fi
    if echo "$f" | grep -qE "u0 [a-z]"; then echo "other:$(echo "$f" | grep -oE "u0 [a-zA-Z0-9._]+/" | tr -d 'u0 /')"; return; fi
    sleep 1
  done
  echo "unknown"
}
relaunch() { $ADB shell am force-stop com.lifeharness.lifeharness </dev/null >/dev/null 2>&1; sleep 0.6; $ADB shell monkey -p com.lifeharness.lifeharness -c android.intent.category.LAUNCHER 1 </dev/null >/dev/null 2>&1; sleep 4; }

goto_tabs() {
  relaunch   # 冷启动确定性：每用例从 dashboard 出发
  dump
  [ -n "$(findpt '^今天$')" ] && return 0
  return 1
}
open_tile() { # $1=tile regex  $2=可选第二跳 regex
  goto_tabs
  p=$(findpt '^今天$'); [ -n "$p" ] && tap "$p" 0.8
  p=""
  for k in 1 2 3 4; do
    $ADB shell input swipe 600 1900 600 700 350 </dev/null >/dev/null 2>&1; sleep 0.6
    dump; p=$(findpt "$1"); [ -n "$p" ] && break
  done
  [ -n "$p" ] && tap "$p" 1.6
  if [ -n "${2:-}" ]; then dump; p=$(findpt "$2"); [ -n "$p" ] && tap "$p" 1.6; fi
}

# 用例：id | 进入方式 | 期望返回后落点regex
probe() {
  local id="$1" enter="$2" expect="$3"
  case "$enter" in
    tile2:*) IFS='>' read -r a b <<< "${enter#tile2:}"; open_tile "$a" "$b" ;;
    tile:*) open_tile "${enter#tile:}" ;;
    row:*)  goto_tabs; IFS='>' read -r a b <<< "${enter#row:}"
            dump; p=$(findpt "$a"); [ -n "$p" ] && tap "$p" 1.0
            if [ -n "${b:-}" ]; then dump; p=$(findpt "$b"); [ -n "$p" ] && tap "$p" 1.4; fi ;;
  esac
  dump
  txt=$(alltext)
  # 到达判定：屏上有期望子页特征（由 expect 的第二段给出，格式 expect=子页特征@@父页特征）
  local child="${expect%%@@*}" parent="${expect##*@@}"
  if ! echo "$txt" | grep -qE "$child"; then echo "$id NO-ARRIVE" >> "$OUT/backprobe2.log"; return; fi
  $ADB shell input keyevent 4 </dev/null >/dev/null 2>&1; sleep 1.5
  f=$(focus3)
  if [ "$f" != "lifeharness" ]; then echo "$id EXIT-APP($f)" >> "$OUT/backprobe2.log"; relaunch; return; fi
  dump
  if grep -qE "$parent" "$PXML"; then echo "$id OK→父页" >> "$OUT/backprobe2.log"
  else echo "$id LANDS-WRONG" >> "$OUT/backprobe2.log"; fi
}

rm -f "$OUT/backprobe2.log"
probe t-ledgermain-from-grid "tile:记账" "本地账本|快速记一笔@@今天&#10;|全部功能"
probe t-days-from-grid "tile:日子" "重要日子|倒数@@今天&#10;|全部功能"
probe t-goals-from-grid "tile:目标" "目标 OKR|计划 → 执行@@今天&#10;|全部功能"
probe t-items-from-grid "tile:物品" "物品价值|每日摊薄@@今天&#10;|全部功能"
probe t-habit-from-grid "tile:习惯" "今日打卡|新建习惯@@今天&#10;|全部功能"
probe t-care-from-grid "tile:呵护" "呵护 · 周期|今日感受@@今天&#10;|全部功能"
probe t-read-from-grid "tile:阅读" "记录 · 阅读|今日阅读@@今天&#10;|全部功能"
probe t-report-under-ledger "tile2:记账>报表" "统计报表@@本地账本|快速记一笔"
probe t-trash-from-profile "row:^我的\$>回收站" "回收站@@数据与同步|提醒通知"
probe t-log-from-profile "row:^我的\$>运行日志" "运行日志|环形缓冲@@数据与同步|提醒通知"
probe t-sync-from-profile "row:^我的\$>数据与同步" "立即同步|差异对比@@回收站|运行日志|提醒通知"
probe t-appearance-from-profile "row:^我的\$>外观" "主题|深色@@回收站|运行日志|提醒通知"
echo PROBE2-DONE >> "$OUT/backprobe2.log"
