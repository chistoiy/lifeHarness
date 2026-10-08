// 收口核对：从 stdin 读 `gitee api "repos/{owner}/{repo}/releases?per_page=100"` 的 JSON，
// 按 tag 打印 release 上挂的附件名与体积，齐了才退出 0。
// 用法：gitee.exe api "repos/chistoiy/lifeHarness/releases?per_page=100" | node tools/check_gitee_assets.js <tag> [arm64|three]
//   · 默认 arm64 ＝预发布只挂一枚（产品令 2026-10-08·提交 c3d3db3）
//   · `three` ＝正式发版三包齐全判定
const TAG = process.argv[2];
if (!TAG) {
  console.error('用法：node tools/check_gitee_assets.js <tag> [arm64|three]');
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
  // 实测：`/releases` 列表里附件字段叫 `assets`（单个 release 的 GET 里另有
  // `attachments`，可能为空），两边都取一次再判；列表里的附件项**不带 size**，
  // 所以体积等长要靠 attach 接口返回与 GitHub 侧 `gh release view --json assets` 对。
  const att = (rel.attachments || []).concat(rel.assets || []);
  const got = att.map((a) => a.name);
  const pkgs = (process.argv[3] || 'arm64').toLowerCase();
  // 名字两种都收：构建产物原名 `app-arm64-v8a-release.apk`，或带装机编号的留档名
  // `lifeHarness-6093-arm64.apk`（编号进名更利于「别挂错旧包」这条审计）。
  const arm64Pat = /(^app-arm64-v8a-release\.apk$)|(-arm64(\.v8a)?(-release)?\.apk$)/;
  const want = pkgs === 'three'
    ? ['app-arm64-v8a-release.apk', 'app-armeabi-v7a-release.apk', 'app-x86_64-release.apk']
    : [];
  console.log(`release ${TAG} (id=${rel.id}) 资产 ${got.length} 个：${got.join(' / ')}`);
  const missing = want.filter((w) => !got.includes(w));
  if (missing.length) {
    console.error('缺附件：' + missing.join(', '));
    process.exit(1);
  }
  if (pkgs !== 'three' && !got.some((n) => arm64Pat.test(n))) {
    console.error('缺 arm64 附件（应挂 app-arm64-v8a-release.apk 或 <编号>-arm64.apk）');
    process.exit(1);
  }
  console.log(`OK 附件齐全（模式=${pkgs}，应挂 ${want.length || 1} 枚）`);
});
