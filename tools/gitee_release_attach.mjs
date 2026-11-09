// Gitee 预发布挂附件（multipart 走 FormData，避免手搓 boundary）
// 用法：node tools/gitee_release_attach.mjs <owner/repo> <releaseId> <filePath> <token>
//
// 口径（产品令 2026-10-08·提交 c3d3db3）：**预发布只挂一枚 arm64 APK**；
// 附件名即文件名，收口核对走 `tools/check_gitee_assets.js`。Gitee 附件上限 100MB。
import fs from 'node:fs';
import path from 'node:path';

const [repo, releaseId, filePath, token] = process.argv.slice(2);
if (!repo || !releaseId || !filePath || !token) {
  console.log('ARGS-MISSING: <owner/repo> <releaseId> <filePath> <token>');
  process.exit(2);
}
if (!fs.existsSync(filePath)) {
  console.log('FILE-MISSING', filePath);
  process.exit(2);
}
const size = fs.statSync(filePath).size;
if (size > 100 * 1024 * 1024) {
  console.log('OVER-LIMIT', size, '（Gitee 附件上限 100MB）');
  process.exit(2);
}

const url = `https://gitee.com/api/v5/repos/${repo}/releases/${releaseId}/attach_files`;
const form = new FormData();
form.append('access_token', token);
form.append('file', await fs.openAsBlob(filePath), path.basename(filePath));

const res = await fetch(url, { method: 'POST', body: form });
const text = await res.text();
console.log('HTTP', res.status);
try {
  const j = JSON.parse(text);
  console.log('id', j.id, 'name', j.name, 'size', j.size, 'url', j.browser_download_url);
} catch {
  console.log('RAW', text.slice(0, 400));
}
