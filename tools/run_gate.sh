#!/usr/bin/env bash
# run_gate.sh · 治理门禁全量测试 + 进度页（先按端口清僵尸，再起新实例）
# 用法：bash tools/run_gate.sh [concurrency=N 由环境变量 CONC 传入]
set -u
cd "$(dirname "$0")/.."
PORT=${PORT:-8765}
for p in $(netstat -ano | grep ":$PORT" | grep LISTENING | awk '{print $5}' | sort -u); do
  node -e "try{process.kill($p)}catch(e){}" || true
done
sleep 1
if netstat -ano | grep -q ":$PORT.*LISTENING"; then echo "PORT-BUSY"; exit 1; fi
CONC_ARGS=()
[ -n "${CONC:-}" ] && CONC_ARGS=(--concurrency="$CONC")
# Windows 陷阱（实测两条，顺序不能反）：
# ① hooks_runner 把 sqlite3.dll 拷到 build/native_assets/windows/ 用的是「目标存在即失败」
#    语义（errno 183 PathExistsException），崩在启动阶段，表现为成片「找不到 dll」；
# ② 但**预先删掉**该 dll 也不行——最早并发起来的若干 test 文件会在重拷贝完成前解析
#    sqlite3_initialize 而报 errno 126（本脚本 2026-09-29 一度这样埋了 8 个假红）。
# 正确姿势：默认不动它；只有 gate-err.log 里出现 PathExistsException 时，
# 才 `rm -f build/native_assets/windows/sqlite3.dll` 后重跑一次。
if grep -q PathExistsException tools/gate-err.log 2>/dev/null; then
  echo "NOTE: 上次因 sqlite3.dll 拷贝冲突崩溃，已摘除陈旧产物后重跑"
  rm -f build/native_assets/windows/sqlite3.dll
fi
( flutter test --reporter json "${CONC_ARGS[@]}" 2>tools/gate-err.log | node tools/testwatch.js json $PORT & )
sleep 8
node -e "fetch('http://127.0.0.1:$PORT/status').then(r=>r.json()).then(j=>{if(!(j.elapsed<'00:01:00'&&j.pass<50))throw 0;console.log('FRESH elapsed='+j.elapsed)}).catch(()=>{console.log('STALE-OR-DEAD');process.exit(2)})"
