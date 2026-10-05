#!/usr/bin/env bash
# U1 对照实验：我的页「中部行」与「贴底行」各点一次，看谁不响应。
set -u
export ANDROID_SERIAL="${ANDROID_SERIAL:-ea028260}" MSYS_NO_PATHCONV=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; DIR="$ROOT/tools/uxwalk"; OUT="$ROOT/tmp/uxwalk"
PXML="$OUT/u1c.xml"; PXMLW="$(cygpath -w "$OUT")/u1c.xml"; JS="$(cygpath -w "$DIR/uxrows.js")"
ADB="adb -s $ANDROID_SERIAL"
read -r SW SH <<<"$($ADB shell wm size 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tr 'x' ' ')"
JSW() { node "$JS" "$PXMLW" "$@"; }
dump() { for t in 1 2 3; do $ADB shell "uiautomator dump /data/local/tmp/ui.xml" </dev/null >/dev/null 2>&1
  $ADB shell cat /data/local/tmp/ui.xml </dev/null > "$PXML" 2>/dev/null; [ -s "$PXML" ] && return 0; sleep 1; done; return 1; }
tap() { $ADB shell input tap "${1%,*}" "${1#*,}" </dev/null >/dev/null 2>&1; sleep "${2:-1.4}"; }
relaunch() { $ADB shell am force-stop com.lifeharness.lifeharness </dev/null >/dev/null 2>&1; sleep 0.6;
  $ADB shell monkey -p com.lifeharness.lifeharness -c android.intent.category.LAUNCHER 1 </dev/null >/dev/null 2>&1; sleep 5; }

go_profile() { relaunch; dump; tap "$(JSW at 我的)" 1.6; dump; }

try_tap() { # $1=行名  $2=说明
  local row pt sig0 sig1
  pt=$(JSW inc "$1")
  if [ -z "$pt" ]; then echo "  [$2] 屏上找不到「$1」"; return; fi
  sig0=$(JSW sig)
  tap "$pt" 1.6; dump; sig1=$(JSW sig)
  if [ "$sig0" = "$sig1" ]; then echo "  [$2] 「$1」@$pt 点不动"; else echo "  [$2] 「$1」@$pt 可点（已换屏）"; fi
}
echo "屏 ${SW}x${SH}"
go_profile
echo "底栏顶边 y=$(JSW navtop)；贴底行＝$(JSW gap "$(JSW navtop)")"
echo "── 行清单"; JSW rows | tail -8
echo "── 对照（未滚动，贴底态）"
try_tap 运行日志 "中部对照"
go_profile
try_tap 外观 "贴底"
echo "── 上滑一轮后再点贴底行"
$ADB shell input swipe $((SW/2)) $((SH*70/100)) $((SW/2)) $((SH*40/100)) 300 </dev/null >/dev/null 2>&1; sleep 1.0; dump
echo "底栏顶边 y=$(JSW navtop)；贴底行＝$(JSW gap "$(JSW navtop)")"
try_tap 外观 "上滑后贴底"
