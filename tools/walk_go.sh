#!/usr/bin/env bash
# 走查工装：语义节点驱动——dump → 按 label 找 tap 点 → 前台守护 → 点按 → 截图。
# 用法：bash tools/walk_go.sh <label正则> <截图名>     （匹配多个时取第一个；无匹配即失败退出）
set -u
cd "$(dirname "$0")/.."
top=$(adb shell "dumpsys activity activities | grep -m1 topResumedActivity" | tr -d '\r')
if ! echo "$top" | grep -q lifeharness; then
  adb shell monkey -p com.lifeharness.lifeharness -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 4
fi
adb shell "uiautomator dump /data/local/tmp/ui.xml" >/dev/null
adb shell "cat /data/local/tmp/ui.xml" > .walkthrough/ui.xml
pt=$(node tools/walk_nodes.js | grep -E "$1" | head -1 | grep -oE 'tap\([0-9]+,[0-9]+\)')
if [ -z "$pt" ]; then echo "NO-MATCH [$1]"; node tools/walk_nodes.js | head -30; exit 4; fi
xy=${pt#tap(}; xy=${xy%)}
adb shell input tap ${xy%,*} ${xy#*,}
sleep "${3:-3}"
bash tools/walk_shot.sh "$2" 2>&1 | tail -1
