#!/usr/bin/env bash
# 走查辅助：前台守护 + 点按。用法：bash tools/walk_tap.sh <x> <y>
# 手机同时挂着 Qoder 会话端，误触其停止按钮会断会话——点按前必验前台包。
set -u
top=$(adb shell "dumpsys activity activities | grep -m1 topResumedActivity" | tr -d '\r')
if ! echo "$top" | grep -q lifeharness; then
  adb shell monkey -p com.lifeharness.lifeharness -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 4
  top=$(adb shell "dumpsys activity activities | grep -m1 topResumedActivity" | tr -d '\r')
  echo "$top" | grep -q lifeharness || { echo "FOREGROUND-FAIL $top"; exit 3; }
fi
adb shell input tap "$1" "$2"
