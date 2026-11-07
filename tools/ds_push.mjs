// developSummary 双端推送工装（一次性，用完可留作同类沉淀复用）
//
// 用法：
//   node tools/ds_push.mjs gitee  <localFile> <repoPath> <commitMessage>   # Gitee 直传（token 走环境变量 GITEE_TOKEN）
//   node tools/ds_push.mjs ghpay  <localFile> <repoPath> <commitMessage> <outJson>  # 生成 gh --input 用的 payload（不含密钥）
//   node tools/ds_push.mjs readme <newReadmeFile> gitee|gh <repoSha> <commitMessage> [outJson]
//
// 约定：中文内容一律 base64 进 payload，commitMessage 用英文（两端互验时 blob sha 才可比）。
import fs from 'node:fs';

const REPO = 'chistoiy/developSummary';
const b64 = (p) => fs.readFileSync(p).toString('base64');

const [mode, a, b, c, d, e] = process.argv.slice(2);

if (mode === 'gitee') {
  const token = process.env.GITEE_TOKEN;
  if (!token) { console.log('NO-TOKEN'); process.exit(2); }
  const url = `https://gitee.com/api/v5/repos/${REPO}/contents/${b}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ access_token: token, content: b64(a), message: c }),
  });
  const t = await res.text();
  try {
    const j = JSON.parse(t);
    console.log('HTTP', res.status, 'sha', j?.sha, 'path', j?.content?.path ?? b);
  } catch { console.log('HTTP', res.status, 'RAW', t.slice(0, 300)); }
} else if (mode === 'ghpay') {
  fs.writeFileSync(d, JSON.stringify({ message: c, content: b64(a) }));
  console.log('payload written', d, 'bytes', fs.statSync(d).size);
} else if (mode === 'readme') {
  const payload = { message: d, content: b64(a), sha: c };
  if (b === 'gitee') {
    const token = process.env.GITEE_TOKEN;
    if (!token) { console.log('NO-TOKEN'); process.exit(2); }
    const res = await fetch(`https://gitee.com/api/v5/repos/${REPO}/contents/README.md`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, access_token: token }),
    });
    const t = await res.text();
    try { const j = JSON.parse(t); console.log('HTTP', res.status, 'sha', j?.sha); }
    catch { console.log('HTTP', res.status, 'RAW', t.slice(0, 300)); }
  } else {
    fs.writeFileSync(e, JSON.stringify(payload));
    console.log('payload written', e);
  }
} else {
  console.log('MODE?', 'gitee | ghpay | readme');
  process.exit(2);
}
