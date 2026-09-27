// 收口核对：从 stdin 读 `gitee api "repos/{owner}/{repo}/releases?per_page=100"` 的 JSON，
// 按 tag 打印 release 上挂的附件名与体积，三个 APK 齐全才退出 0。
// 用法：gitee.exe api "repos/chistoiy/lifeHarness/releases?per_page=100" | node tools/check_gitee_assets.js <tag>
const TAG = process.argv[2];
if (!TAG) {
  console.error('用法：node tools/check_gitee_assets.js <tag>');
  process.exit(2);
}
let raw = '';
process.stdin.on('data', (c) => (raw += c)).on('end', () => {
  const json = JSON.parse(raw);
  const list = json.data || json;
  const rel = list.find((x) => x.tag_name === TAG);
  if (!rel) {
    console.error('未找到 release：' + TAG);
    process.exit(1);
  }
  const want = ['app-arm64-v8a-release.apk', 'app-armeabi-v7a-release.apk', 'app-x86_64-release.apk'];
  // 实测：`/releases` 列表里附件字段叫 `assets`（单个 release 的 GET 里另有
  // `attachments`，可能为空），两边都取一次再判。
  const att = (rel.attachments || []).concat(rel.assets || []);
  const got = att.map((a) => a.name);
  console.log(`release ${TAG} (id=${rel.id}) 资产 ${got.length} 个：`);
  att.forEach((a) => console.log(`  - ${a.name} ${((a.size || 0) / 1048576).toFixed(1)}MB`));
  const missing = want.filter((w) => !got.includes(w));
  if (missing.length) {
    console.error('缺附件：' + missing.join(', '));
    process.exit(1);
  }
  console.log('OK 三包齐全');
});
