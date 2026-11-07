#!/usr/bin/env bash
# v0.2.15-note-mount 预发布收口：aapt 四条复验（对已出仓留档包）→ tag 打在钉版提交并双端推
# → Gitee 建 prerelease 挂一枚 arm64 → GitHub 同步。
# 序与 tools/release_v0215.sh 同；差别＝① worktree 已回收，复验对象换成出仓留档的 APK；
# ② check_gitee_assets.js 是**读 stdin** 的（上轮按位置参数调它＝空 JSON 崩，本轮接管道）。
# 用法：bash tools/release_v0215b.sh   （前置：分支已双端 push、包已留档）
set -uo pipefail

TAG=v0.2.15-note-mount
SHA=e1c45cf
TITLE='v0.2.15-note-mount（预发布）· 真机反馈批：边缘右滑开树 · 计数与列表同源 · 挂载目录双向写回（装机 6099）'
BODY_FILE=tools/release_body_v0215b.md
BRANCH=feat/m0-skeleton
ARCH=/d/dev_workplace/flutter_te/tempWork/retest-apks-20261011
APK=$ARCH/lifeHarness-6099-arm64.apk
PREV=$ARCH/lifeHarness-6098-arm64.apk
EXPECT_CODE=6099
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
say "  $(stat -c %s "$APK") 字节 · mtime $(date -r "$APK" '+%F %T')"

say "=== ① aapt 四条复验 ==="
BAD=$("$AAPT" dump badging "$APK" 2>/dev/null | head -3)
CODE=$(printf '%s' "$BAD" | grep -oE "versionCode='[0-9]+'" | grep -oE '[0-9]+')
NAME=$(printf '%s' "$BAD" | grep -oE "versionName='[^']+'" | sed "s/versionName='//; s/'//")
[ "$CODE" = "$EXPECT_CODE" ] && say "  ok versionCode=$CODE" || fail "versionCode=$CODE ≠ $EXPECT_CODE"
[ "$NAME" = "$EXPECT_NAME" ] && say "  ok versionName=$NAME" || fail "versionName=$NAME ≠ $EXPECT_NAME"
"$AAPT" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null | grep -q "android.permission.INTERNET" \
  && say "  ok INTERNET 在主清单" || fail "主清单缺 INTERNET"
unzip -l "$APK" | grep -oE "lib/arm64-v8a/[^ ]+" | sed 's#.*/##' | sort > tmp/relb_libs.txt
if [ -f "$PREV" ]; then
  unzip -l "$PREV" | grep -oE "lib/arm64-v8a/[^ ]+" | sed 's#.*/##' | sort > tmp/relb_libs_prev.txt
  diff -q tmp/relb_libs_prev.txt tmp/relb_libs.txt >/dev/null \
    && say "  ok 库集与 6098 逐条一致" || { say "  注 库集有差："; diff tmp/relb_libs_prev.txt tmp/relb_libs.txt | grep -E "^[<>]" | sed 's/^/    /'; }
fi
[ $RED -eq 0 ] || { say "STOP@aapt"; exit 1; }

say "=== ② tag 打在钉版提交 $SHA ==="
git rev-parse "$SHA^{commit}" >/dev/null || { say "STOP@无此提交"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || \
  git tag -a "$TAG" "$SHA" -m "预发布 $TAG：钉版 $SHA（0.2.15+4099）· arm64 装机 6099 · 真机反馈批三条"
git tag -l "$TAG" | grep -q "$TAG" || { say "STOP@tag 未建"; exit 1; }

say "=== ③ 双端推 tag ==="
git push gitee "$TAG" 2>&1 | tail -2
git push "$GITHUB_URL" "$TAG" 2>&1 | tail -2
say "  解引用回读：gitee=$(git ls-remote gitee "refs/tags/$TAG^{}" | cut -c1-12) github=$(git ls-remote "$GITHUB_URL" "refs/tags/$TAG^{}" | cut -c1-12) 期望=$(git rev-parse "$SHA^{commit}" | cut -c1-12)"

say "=== ④ Gitee prerelease + 附件 ==="
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
  -F "name=app-arm64-v8a-release.apk" -F "file=@$APK")
say "  app-arm64-v8a-release.apk → HTTP $code"
[ "$code" = 201 ] || fail "Gitee 附件上传失败：$(head -c 300 tmp/.gitee_up.json)"
rm -f tmp/.gitee_up.json
"$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node tools/check_gitee_assets.js "$TAG"
say "  （附件名用 app-arm64-v8a-release.apk 而非留档改名，与上枚一致便于装机脚本按名取）"

say "=== ⑤ GitHub prerelease ==="
"$GH" release create "$TAG" "$APK" --prerelease --title "$TITLE" --notes-file "$BODY_FILE" 2>&1 | tail -2 \
  || say "REMINDER：GitHub 建 release 失败（网络/证书），Gitee 已挂齐，需换时段重试"

say "=== 收尾 ==="
[ $RED -eq 0 ] && say "RELEASE-DONE $TAG 单枚 arm64 已挂双端" || say "RELEASE-HAS-RED（见上列 RED 行）"
exit $RED
