#!/usr/bin/env bash
# v0.2.15-tree-follow 预发布收口（树手感批2·装机 6101）：
# ⓪ 分支双端推＋逐头回读 → ① aapt 四条复验（对留档包）→ ② tag 打在钉版提交 → ③ 双端推 tag
# → ④ Gitee 建 prerelease 挂一枚 arm64 → ⑤ GitHub 同步 prerelease。
# 序与 tools/release_v0215b.sh 同；前置＝包已留档、收口提交已落。
# 用法：bash tools/release_v0215c.sh
set -uo pipefail

TAG=v0.2.15-tree-follow
SHA=6c50401
TITLE='v0.2.15-tree-follow（预发布）· 笔记树手感批2：右滑开树全程跟手 · 面板左滑跟手收起 · 长按文件夹改就地动作（装机 6101）'
BODY_FILE=tools/release_body_v0215c.md
BRANCH=feat/m0-skeleton
ARCH=/d/dev_workplace/flutter_te/tempWork/retest-apks-20261011
APK=$ARCH/lifeHarness-6101-arm64.apk
PREV=$ARCH/lifeHarness-6099-arm64.apk
EXPECT_CODE=6101
EXPECT_NAME=0.2.15
GH="/c/Program Files/GitHub CLI/gh.exe"
GITEE="/d/app_workplace/gitee-cli/gitee.exe"
OWNER=chistoiy
REPO=lifeHarness
AAPT=$(ls /d/app_workplace/android_studio_sdk/build-tools/*/aapt2.exe 2>/dev/null | tail -1)
GITHUB_URL=ssh://git@ssh.github.com:443/chistoiy/lifeHarness.git

cd /d/dev_workplace/flutter_te/lifeHarness || exit 1
RED=0
say() { echo "$@"; }
fail() { say "RED: $*"; RED=1; }

say "=== ⓪ 产物在场 ==="
[ -f "$APK" ] || fail "缺 APK：$APK"
[ -n "$AAPT" ] || fail "找不到 aapt2"
[ $RED -eq 0 ] || { say "STOP@产物"; exit 1; }
say "  $(stat -c %s "$APK") 字节 · mtime $(date -r "$APK" '+%F %T') · md5 $(md5sum "$APK" | cut -c1-32)"

say "=== ① aapt 四条复验 ==="
BAD=$("$AAPT" dump badging "$APK" 2>/dev/null | head -3)
CODE=$(printf '%s' "$BAD" | grep -oE "versionCode='[0-9]+'" | grep -oE '[0-9]+')
NAME=$(printf '%s' "$BAD" | grep -oE "versionName='[^']+'" | sed "s/versionName='//; s/'//")
[ "$CODE" = "$EXPECT_CODE" ] && say "  ok versionCode=$CODE" || fail "versionCode=$CODE ≠ $EXPECT_CODE"
[ "$NAME" = "$EXPECT_NAME" ] && say "  ok versionName=$NAME" || fail "versionName=$NAME ≠ $EXPECT_NAME"
"$AAPT" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null | grep -q "android.permission.INTERNET" \
  && say "  ok INTERNET 在主清单" || fail "主清单缺 INTERNET"
"$AAPT" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null | grep -q "android.permission.VIBRATE" \
  && say "  ok VIBRATE 在主清单" || fail "主清单缺 VIBRATE"
unzip -l "$APK" | grep -oE "lib/arm64-v8a/[^ ]+" | sed 's#.*/##' | sort > tmp/relc_libs.txt
if [ -f "$PREV" ]; then
  unzip -l "$PREV" | grep -oE "lib/arm64-v8a/[^ ]+" | sed 's#.*/##' | sort > tmp/relc_libs_prev.txt
  diff -q tmp/relc_libs_prev.txt tmp/relc_libs.txt >/dev/null \
    && say "  ok 库集与 6099 逐条一致（$(wc -l < tmp/relc_libs.txt) 项）" \
    || { say "  注 库集有差："; diff tmp/relc_libs_prev.txt tmp/relc_libs.txt | grep -E "^[<>]" | sed 's/^/    /'; }
  "$AAPT" dump xmltree --file AndroidManifest.xml "$APK" > tmp/relc_tree_new.txt 2>/dev/null
  "$AAPT" dump xmltree --file AndroidManifest.xml "$PREV" > tmp/relc_tree_prev.txt 2>/dev/null
  say "  manifest xmltree 行数 new=$(wc -l < tmp/relc_tree_new.txt) prev=$(wc -l < tmp/relc_tree_prev.txt) 差异行=$(diff tmp/relc_tree_prev.txt tmp/relc_tree_new.txt | grep -c '^[<>]')"
fi
[ $RED -eq 0 ] || { say "STOP@aapt"; exit 1; }

say "=== ② 分支双端推（Gitee 优先） ==="
git push gitee "$BRANCH" 2>&1 | tail -2
git push "$GITHUB_URL" "$BRANCH" 2>&1 | tail -2
say "  逐头回读：本地=$(git rev-parse HEAD | cut -c1-12) gitee=$(git ls-remote gitee "refs/heads/$BRANCH" | cut -c1-12) github=$(git ls-remote "$GITHUB_URL" "refs/heads/$BRANCH" | cut -c1-12)"
[ "$(git ls-remote gitee "refs/heads/$BRANCH" | cut -f1)" = "$(git rev-parse HEAD)" ] \
  || fail "Gitee 分支头 ≠ 本地 HEAD"

say "=== ③ tag 打在钉版提交 $SHA ==="
git rev-parse "$SHA^{commit}" >/dev/null || { say "STOP@无此提交"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || \
  git tag -a "$TAG" "$SHA" -m "预发布 $TAG：钉版 $SHA（0.2.15+4101）· arm64 装机 6101 · 树手感批2 跟手抽屉＋就地动作"
git tag -l "$TAG" | grep -q "$TAG" || { say "STOP@tag 未建"; exit 1; }

say "=== ④ 双端推 tag ==="
git push gitee "$TAG" 2>&1 | tail -2
git push "$GITHUB_URL" "$TAG" 2>&1 | tail -2
say "  解引用回读：gitee=$(git ls-remote gitee "refs/tags/$TAG^{}" | cut -c1-12) github=$(git ls-remote "$GITHUB_URL" "refs/tags/$TAG^{}" | cut -c1-12) 期望=$(git rev-parse "$SHA^{commit}" | cut -c1-12)"

say "=== ⑤ Gitee prerelease + 附件 ==="
"$GITEE" release create -R "$OWNER/$REPO" --tag "$TAG" -n "$TITLE" \
  -b "$(cat "$BODY_FILE")" --prerelease --target "$BRANCH" --no-tui 2>&1 | tail -2
NID=$("$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node -e "
let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
  const j=JSON.parse(d);const t=process.argv[1];
  const r=(j.data||j).find(x=>x.tag_name===t);
  if(!r){console.error('未找到 release '+t);process.exit(1)}
  console.log(r.id)})" "$TAG")
say "  gitee release id=$NID"
TOK=$("$GITEE" auth token | grep -Eo '[A-Za-z0-9_-]{20,}' | head -1)   # 令牌只在内存里用
code=$(curl -s -o tmp/.gitee_up.json -w '%{http_code}' -X POST \
  "https://gitee.com/api/v5/repos/$OWNER/$REPO/releases/$NID/attach_files?access_token=$TOK" \
  -F "file=@$APK")
say "  附件上传 → HTTP $code（实测附件名＝留档文件名 lifeHarness-6101-arm64.apk，按 tag 页取包）"
[ "$code" = 201 ] || fail "Gitee 附件上传失败：$(head -c 300 tmp/.gitee_up.json)"
rm -f tmp/.gitee_up.json
"$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node tools/check_gitee_assets.js "$TAG"

say "=== ⑥ GitHub prerelease ==="
"$GH" release create "$TAG" "$APK" --prerelease --title "$TITLE" --notes-file "$BODY_FILE" 2>&1 | tail -2 \
  || say "REMINDER：GitHub 建 release 失败（网络/证书），Gitee 已挂齐，需换时段重试"

say "=== 收尾 ==="
[ $RED -eq 0 ] && say "RELEASE-DONE $TAG 单枚 arm64 已挂双端" || say "RELEASE-HAS-RED（见上列 RED 行）"
exit $RED
