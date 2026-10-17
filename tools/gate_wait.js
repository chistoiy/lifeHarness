/* 轮询 run_gate 进度页直到 done（单次调用·内部等待·超时 12 分钟） */
const PORT = Number(process.env.PORT || 8765);
const DEADLINE = Date.now() + 12 * 60 * 1000;
async function status() {
  try {
    const r = await fetch('http://127.0.0.1:' + PORT + '/status');
    return await r.json();
  } catch (e) { return null; }
}
(async () => {
  let last = '';
  for (;;) {
    const j = await status();
    if (j) {
      const line = j.elapsed + ' pass=' + j.pass + ' fail=' + j.fail + ' skip=' + j.skip + ' ' + (j.done || j.file || '');
      if (line !== last) { console.log(line); last = line; }
      if (j.done) {
        console.log((j.fails || []).slice(0, 12).join('\n---\n'));
        process.exit(/ALL PASSED/.test(j.done) ? 0 : 1);
      }
    } else {
      console.log('no-server（可能已结束或端口未起）');
    }
    if (Date.now() > DEADLINE) { console.log('TIMEOUT'); process.exit(2); }
    await new Promise((r) => setTimeout(r, 5000));
  }
})();
