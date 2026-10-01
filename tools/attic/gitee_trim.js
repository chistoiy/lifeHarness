// Gitee 旧版 release 附件清理（v0.1.x 及更早 · 只删 APK 附件，条目保留）
// 用法：TOK=<token> node tools/attic/gitee_trim.js [--apply]
const https = require('https');
const TOK = process.env.TOK;
if (!TOK) { console.log('缺 TOK 环境变量'); process.exit(2); }
const APPLY = process.argv.includes('--apply');
const API = p => new Promise(res => {
  const u = new URL('https://gitee.com/api/v5/' + p);
  const opt = { method: p.startsWith('__DEL__') ? 'DELETE' : 'GET' };
  https.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ code: r.statusCode, body: d })); })
    .on('error', e => res({ code: 0, body: String(e) }));
});
function del(p) {
  return new Promise(res => {
    const u = new URL('https://gitee.com/api/v5/' + p + '?access_token=' + TOK);
    const req = https.request(u, { method: 'DELETE' }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ code: r.statusCode, body: d.slice(0, 120) })); });
    req.on('error', e => res({ code: 0, body: String(e) })); req.end();
  });
}
(async () => {
  const list = JSON.parse((await API(`repos/chistoiy/lifeHarness/releases?per_page=100&access_token=${TOK}`)).body);
  const old = list.filter(r => /^v0\.1\./.test(r.tag_name));
  console.log(`旧版 release ${old.length} 个`);
  let freed = 0, n = 0;
  for (const r of old) {
    const det = JSON.parse((await API(`repos/chistoiy/lifeHarness/releases/${r.id}?access_token=${TOK}`)).body);
    const assets = (det.assets || []).filter(a => /\.apk$/.test(a.name || ''));
    for (const a of assets) {
      const size = Number(a.size || a.download_count && 0 || 0);
      console.log(`${APPLY ? 'DEL' : 'DRY'} rel=${r.tag_name} asset=${a.id} ${a.name} size=${a.size || '?'}`);
      if (APPLY) {
        const d = await del(`repos/chistoiy/lifeHarness/releases/assets/${a.id}?access_token=${TOK}`.replace('?access_token=' + TOK, '') );
        console.log(`  -> ${d.code} ${d.code !== 200 && d.code !== 204 ? d.body : ''}`);
        if (d.code === 200 || d.code === 204) { n++; freed += size; } else { console.log('端点疑似不对，停止并核对文档'); process.exit(1); }
      } else n++;
    }
  }
  console.log(`${APPLY ? '已删' : '将删'} ${n} 个附件 · 约 ${(freed / 1048576).toFixed(0)}MB`);
})();
