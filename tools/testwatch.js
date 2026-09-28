/* testwatch.js · flutter test 实时进度页（治理 G 批次门禁配套）
   用法一（旁听 expanded 日志，零打扰）：
     node tools/testwatch.js watch tools/g0-test.log [端口=8765]
     浏览器打开 http://127.0.0.1:8765
   用法二（精确 JSON 管道，推荐门禁批用）：
     flutter test --reporter json | node tools/testwatch.js json [端口=8765]
   说明：页面每 1.5s 轮询 /status；只监听 127.0.0.1；Ctrl+C 退出即释放端口，
   重启前先用 netstat 确认旧实例已退出，防止「200 来自旧服务」。 */
const http = require('http');
const fs = require('fs');

const mode = process.argv[2] || 'watch';
const arg2 = process.argv[3];
const PORT = +(process.argv[4] || process.argv[3] || 8765) || 8765;
const st = { pass: 0, fail: 0, skip: 0, total: null, current: '', file: '', started: Date.now(), done: '', fails: [], last: '' };

function html() {
  return `<!doctype html><html lang="zh"><head><meta charset="utf-8"><title>testwatch</title>
<style>body{font-family:system-ui,sans-serif;background:#111;color:#eee;margin:2rem}
b{font-size:3rem;font-weight:700}span{font-size:.8rem;color:#888;display:block}
.ok b{color:#4c4}.bad b{color:#e55}.cur{margin-top:1.5rem;color:#aaa;word-break:break-all}
.f{margin-top:1rem;color:#e99;white-space:pre-wrap;font:.8rem/1.4 monospace}
h1{font-size:1rem;color:#777}</style></head><body>
<h1 id="h">flutter test · <span id="mode"></span></h1>
<div style="display:flex;gap:3rem">
<div class="ok"><b id="p">0</b><span>通过</span></div>
<div class="bad"><b id="f">0</b><span>失败</span></div>
<div><b id="s" style="color:#999">0</b><span>跳过</span></div>
<div><b id="t" style="color:#666">-</b><span>总数</span></div>
</div>
<div class="cur" id="cur"></div><div class="f" id="fl"></div>
<script>setInterval(async()=>{const r=await(await fetch('/status')).json();
p.textContent=r.pass;f.textContent=r.fail;s.textContent=r.skip;t.textContent=r.total??'-';
h.textContent='flutter test · '+r.mode+' · '+r.elapsed;
cur.textContent=r.done?('完成：'+r.done):('进行中：'+r.file+' — '+r.current);
fl.textContent=(r.fails||[]).join('\\n');},1500);</script></body></html>`;
}

function serve() {
  http.createServer((q, s) => {
    if (q.url === '/status') {
      s.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      s.end(JSON.stringify({ ...st, mode, elapsed: new Date(Date.now() - st.started).toISOString().slice(11, 19) }));
    } else { s.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); s.end(html()); }
  }).listen(PORT, '0.0.0.0', () => { const ifs = Object.values(require('os').networkInterfaces()).flat().filter(i => i.family === 'IPv4' && !i.internal).map(i => i.address); console.log('testwatch mode=' + mode + ' -> ' + ['127.0.0.1', ...ifs].map(a => 'http://' + a + ':' + PORT).join(' | ')); });
}

if (mode === 'json') { /* flutter test --reporter json 的标准输入逐行事件 */
  const names = {}; let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', d => { buf += d; const ls = buf.split('\n'); buf = ls.pop(); for (const l of ls) if (l) ev(l); });
  process.stdin.on('end', () => { if (buf) ev(buf); });
  function ev(line) {
    let m; try { m = JSON.parse(line); } catch (e) { return; }
    if (m.type === 'testStart') { names[m.test.id] = m.test.name; if (!m.test.name.includes('loading ')) { st.current = m.test.name; st.file = (m.test.url || '').split('/').pop() || m.test.name; } }
    else if (m.type === 'testDone') { if (m.skipped) st.skip++; else if (m.result === 'success') st.pass++; else if (m.result !== 'skipped') { st.fail++; st.fails.push('FAIL ' + (names[m.testID] || m.testID)); } }
    else if (m.type === 'error') { const w = (m.error || '').split('\n').slice(0, 4).join('\n'); if (!st.fails.includes(w)) st.fails.push(w); }
    else if (m.type === 'done') st.done = m.success ? 'ALL PASSED' : 'SOME FAILED';
    else if (m.type === 'count') st.total = m.count;
    else if (m.type === 'suite') st.file = m.suite.path ? m.suite.path.split(/[\\/]/).pop() : st.file;
  }
  serve();
} else { /* watch：只读旁听 expanded 报告日志 */
  const FILE = arg2 && arg2 !== String(PORT) ? arg2 : 'tools/g0-test.log';
  let pos = 0;
  const re = /^\d+:\d+\s+\+(\d+)(?:\s+-(\d+))?(?:\s+~(\d+))?:\s*(.*)$/;
  setInterval(() => {
    if (!fs.existsSync(FILE)) return;
    const sz = fs.statSync(FILE).size; if (sz < pos) pos = 0;
    const fd = fs.openSync(FILE, 'r'); const b = Buffer.alloc(sz - pos);
    fs.readSync(fd, b, 0, b.length, pos); fs.closeSync(fd); pos = sz;
    for (const line of b.toString('utf8').split(/\r?\n/)) {
      const m = line.match(re);
      if (m) {
        st.pass = +m[1]; st.fail = +(m[2] || 0); st.skip = +(m[3] || 0); st.last = line;
        const body = m[4] || ''; const i = body.indexOf(': ');
        if (i > 0) { st.file = body.slice(0, i).split(/[\\/]/).pop(); st.current = body.slice(i + 2).replace(' [E]', ''); }
        if (/All tests passed|Some tests failed/.test(body)) st.done = body;
        continue;
      }
      if (/^ *Expected:|^ *Actual:|^ *Which:|database_closed/.test(line) && !st.fails.includes(line.trim())) st.fails.push(line.trim());
    }
  }, 800);
  serve();
}
