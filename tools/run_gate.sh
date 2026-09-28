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
( flutter test --reporter json "${CONC_ARGS[@]}" 2>tools/gate-err.log | node tools/testwatch.js json $PORT & )
sleep 8
node -e "fetch('http://127.0.0.1:$PORT/status').then(r=>r.json()).then(j=>{if(!(j.elapsed<'00:01:00'&&j.pass<50))throw 0;console.log('FRESH elapsed='+j.elapsed)}).catch(()=>{console.log('STALE-OR-DEAD');process.exit(2)})"
