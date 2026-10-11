#!/usr/bin/env bash
# kotlin_check.sh · 只编 Kotlin 的快速校验段（2026-10-11 立，AGENTS 验证门禁点名）
#
# 为什么要它：`flutter analyze` 只看 dart，原生通道（MainActivity.kt 的 MethodChannel）写错
# 只有 Gradle 才抓得到；等全量出包才发现＝多烧一趟 4~6 分钟（当天实锤：可空串传进非空形参、
# `rel.isEmpty` 属性式写法两处，都是这种错）。本件跑 `:app:compileReleaseKotlin`，约 3~4 分钟，
# 不产 APK、不占复测包编号、不需要 prebuild_check。
#
# 用法：bash tools/kotlin_check.sh          # 绿＝exit 0 并打 KT-OK；红＝exit 1 打 KT-RED＋首条 e:
# 口径：判成败看日志里的 `BUILD SUCCESSFUL`，不信退出码（cmd/powershell 包装会把 pub 的 stderr
#       警告升级成非零，属本仓已落档的假红灯族）。
set -u
cd "$(dirname "$0")/.." || exit 2
ROOT="$PWD"
OUT="$ROOT/tmp/kotlin_check.log"   # 必须绝对路径：下面要 cd 进 android/，相对路径会写飞（首版实踩）
mkdir -p "$ROOT/tmp"
# 注意：cmd 跨盘 cd 要 `/d`，且把 cd 放进 bash 侧更稳（首版 `cmd //c "cd D:\... && gradlew.bat"`
# 静默零输出 rc=0＝假通过，判成败必须看日志里的 BUILD SUCCESSFUL 行在场）。
cd "$ROOT/android" || { echo "KT-RED 进不了 android/"; exit 1; }
# 注意②：不要用 `env -u VAR cmd //c ...` 包一层——MSYS 的 `//c` 转换经 env 会失效，
# 结果是 cmd 直接退出 rc=0 零输出＝第三种假成功（当天实踩）；本任务只编 Kotlin，
# 引擎镜像变量与它无关，不必去动。
JAVA_HOME="D:/app_workplace/android_studio/jbr" \
  cmd //c "gradlew.bat :app:compileReleaseKotlin --console=plain" > "$OUT" 2>&1
rc=$?
if [ ! -s "$OUT" ]; then
  echo "KT-NOOUT 零输出＝cmd 根本没跑起来（属工装失效，不是编译失败，别拿去当红灯）rc=$rc"
  exit 2
fi
if grep -q "BUILD SUCCESSFUL" "$OUT"; then
  echo "KT-OK :app:compileReleaseKotlin 过（$(grep -m1 'BUILD SUCCESSFUL' "$OUT")·日志 $OUT）"
  exit 0
fi
echo "KT-RED rc=$rc 日志=$OUT（行数 $(wc -l < "$OUT")）"
grep -m 6 -E "^e: |error:|What went wrong" "$OUT" | sed 's/^/  /'
exit 1
