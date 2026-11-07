#!/usr/bin/env bash
# 走查辅助：截图到 .walkthrough/shots/ 并拉回；用法：bash tools/walk_shot.sh <名字>
set -u
cd "$(dirname "$0")/.."
mkdir -p .walkthrough/shots
n="${1:-shot_$(date +%H%M%S)}"
adb shell "screencap -p /sdcard/lh_walk.png"
adb pull //sdcard/lh_walk.png ".walkthrough/shots/${n}.png" >/dev/null
# 按 PNG 实际像素打印尺寸（Windows adb 坐标陷阱备忘：坐标换算必须按实际分辨率）
node -e "const b=require('fs').readFileSync('.walkthrough/shots/${n}.png');console.log('${n}.png',b.readUInt32BE(16)+'x'+b.readUInt32BE(20))"
