// Gitee 预发布建条目（JSON body 走文件，避免 shell 引号/多行转义坑）
// 用法：node tools/gitee_release_create.mjs <owner/repo> <tag> <commitish> <name> <bodyFile> <token>
import fs from 'node:fs';

const [repo, tag, commitish, name, bodyFile, token] = process.argv.slice(2);
if (!repo || !tag || !token) {
  console.log('ARGS-MISSING');
  process.exit(2);
}
const body = fs.readFileSync(bodyFile, 'utf8');
const url = `https://gitee.com/api/v5/repos/${repo}/releases`;
const res = await fetch(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    access_token: token,
    tag_name: tag,
    target_commitish: commitish,
    name,
    body,
    prerelease: true,
  }),
});
const text = await res.text();
console.log('HTTP', res.status);
try {
  const j = JSON.parse(text);
  console.log('id', j.id, 'tag', j.tag_name, 'prerelease', j.prerelease, 'html', j.html_url);
} catch {
  console.log('RAW', text.slice(0, 400));
}
