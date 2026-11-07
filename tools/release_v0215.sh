#!/usr/bin/env bash
# v0.2.15-note-local 预发布收口：aapt 四条复验 → 打 tag 双端推 → Gitee 建 prerelease 挂包 → GitHub 同步。
# 序与 tools/release_v0131.sh 同，差别＝按 2026-10-08 产品令「预发布只挂一枚 arm64」＋自 6097 起分包形态。
# 用法：bash tools/release_v0215.sh   （前置：worktree 构建已完成、分支已双端 push）
set -uo pipefail

TAG=v0.2.15-note-local
SHA=1bd4e99
TITLE='v0.2.15-note-local（预发布）· 笔记本地导入/系统打开/挂载移除（DB v42）＋影音游批6~8b＋健康批7'
BODY_FILE=tools/release_body_v0215.md
BRANCH=feat/m0-skeleton
WT=/d/dev_workplace/flutter_te/lh-rel$SHA
OUT=$WT/build/app/outputs/flutter-apk
APK=$OUT/app-arm64-v8a-release.apk
EXPECT_CODE=6098
EXPECT_NAME=0.2.15
GH="/c/Program Files/GitHub CLI/gh.exe"
GITEE="/d/app_workplace/gitee-cli/gitee.exe"
OWNER=chistoiy
REPO=lifeHarness
AAPT=$(ls /d/app_workplace/android_studio_sdk/build-tools/*/aapt2.exe 2>/dev/null | tail -1)
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

cd /d/dev_workplace/flutter_te/lifeHarness || exit 1
RED=0
say() { echo "$@"; }
fail() { say "RED: $*"; RED=1; }

say "=== ⓪ 产物在场 ==="
[ -f "$APK" ] || fail "缺 APK：$APK"
[ -n "$AAPT" ] || fail "找不到 aapt2（SDK build-tools）"
[ $RED -eq 0 ] || { say "STOP@产物"; exit 1; }
say "  $(stat -c %s "$APK") bytes · mtime $(date -r "$APK" '+%F %T')"

say "=== ① aapt 四条复验 ==="
BAD=$("$AAPT" dump badging "$APK" 2>/dev/null | head -3)
CODE=$(printf '%s' "$BAD" | grep -oE "versionCode='[0-9]+'" | grep -oE '[0-9]+')
NAME=$(printf '%s' "$BAD" | grep -oE "versionName='[^']+'" | sed "s/versionName='//; s/'//")
[ "$CODE" = "$EXPECT_CODE" ] && say "  ok versionCode=$CODE" || fail "versionCode=$CODE ≠ $EXPECT_CODE"
[ "$NAME" = "$EXPECT_NAME" ] && say "  ok versionName=$NAME" || fail "versionName=$NAME ≠ $EXPECT_NAME"
"$AAPT" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null | grep -q "android.permission.INTERNET" \
  && say "  ok INTERNET 在主清单" || fail "主清单缺 INTERNET（release 模板老坑）"
unzip -l "$APK" | grep -oE "lib/arm64-v8a/[^ ]+" | sed 's#.*/##' | sort > tmp/nb215_libs.txt
say "  本包库集：$(tr '\n' ' ' < tmp/nb215_libs.txt)"
# 库集对齐＝与上一枚已装机的 arm64 包（6093·v0.2.14 附件）逐条比；无参照物时只列不判。
PREV=/d/dev_workplace/flutter_te/tempWork/retest-apks-20261008/lifeHarness-6093-arm64.apk
if [ -f "$PREV" ]; then
  unzip -l "$PREV" | grep -oE "lib/arm64-v8a/[^ ]+" | sed 's#.*/##' | sort > tmp/nb215_libs_prev.txt
  say "  与 6093 库集差（左＝仅 6093 有／右＝仅本包有）："
  diff tmp/nb215_libs_prev.txt tmp/nb215_libs.txt | grep -E "^[<>]" | sed 's/^/    /' || say "    （无差异）"
else
  say "  跳过库集逐条比对（缺参照包 $PREV）"
fi
grep -q "libsqlite3.so" tmp/nb215_libs.txt \
  && say "  注：本包含 libsqlite3.so（sqlite3 3.x 原生库口径见记忆/发版必查项）" \
  || say "  注：本包不含 libsqlite3.so＝与 6093 同形态（sqflite 走系统库；若上一枚装机包含它则须查依赖变化）"

say "=== ② tag（打在钉版提交上）==="
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  say "  tag 已存在，跳过创建"
else
  git tag -a "$TAG" "$SHA" -m "预发布 $TAG：钉版 $SHA（0.2.15+4098）· arm64 装机 6098 · DB v42" || fail "打 tag 失败"
fi
git tag -l "$TAG" | grep -q "$TAG" || fail "tag 不在场"

say "=== ③ 双端推 tag（Gitee 优先，GitHub 走 ssh:443）==="
git push gitee "$TAG" 2>&1 | tail -2
git push ssh://git@ssh.github.com:443/chistoiy/lifeHarness.git "$TAG" 2>&1 | tail -2
say "  回读：gitee=$(git ls-remote gitee "refs/tags/$TAG" | cut -c1-12) github=$(git ls-remote ssh://git@ssh.github.com:443/chistoiy/lifeHarness.git "refs/tags/$TAG" | cut -c1-12) local=$(git rev-parse "$TAG^{commit}" | cut -c1-12)"

say "=== ④ Gitee prerelease + 附件 ==="
"$GITEE" release create -R "$OWNER/$REPO" --tag "$TAG" -n "$TITLE" \
  -b "$(cat "$BODY_FILE")" --prerelease --target "$BRANCH" --no-tui 2>&1 | tail -3
NID=$("$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node -e "
let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
  const j=JSON.parse(d);const t=process.argv[1];
  const r=(j.data||j).find(x=>x.tag_name===t);
  if(!r){console.error('未找到 release '+t);process.exit(1)}
  console.log(r.id)})" "$TAG")
say "  gitee release id=$NID"
TOK=$("$GITEE" auth token | grep -Eo '[A-Za-z0-9_-]{20,}' | head -1)   # 令牌只在内存里用，不落文件不外显
code=$(curl -s -o tmp/.gitee_up.json -w '%{http_code}' -X POST \
  "https://gitee.com/api/v5/repos/$OWNER/$REPO/releases/$NID/attach_files?access_token=$TOK" \
  -F "name=$(basename "$APK")" -F "file=@$APK")
say "  $(basename "$APK") → HTTP $code"
[ "$code" = 201 ] || fail "Gitee 附件上传失败：$(head -c 300 tmp/.gitee_up.json)"
rm -f tmp/.gitee_up.json
node tools/check_gitee_assets.js "$TAG" 2>&1 | tail -4

say "=== ⑤ GitHub prerelease ==="
"$GH" release create "$TAG" "$APK" --prerelease --title "$TITLE" --notes-file "$BODY_FILE" 2>&1 | tail -3 \
  || say "REMINDER：GitHub 建 release 失败（网络/证书），Gitee 已挂齐，需手动补或换时段重试"

say "=== 收尾 ==="
[ $RED -eq 0 ] && say "RELEASE-DONE $TAG 单枚 arm64 已挂双端" || say "RELEASE-HAS-RED（见上面 RED 行）"
exit $RED
