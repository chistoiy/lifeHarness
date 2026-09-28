#!/usr/bin/env bash
# v0.1.33-reader-fix 收口：Gitee 优先建 prerelease 并挂三包 APK → 核对资产 → GitHub 同步。
# 与 release_v0131.sh 同序，差别只有 TAG/TITLE/BODY 与 OUT 指向本轮 worktree 产物目录
# （发版必须从自己的提交出包，见 memory: release-build-from-own-commit）。
# 用法：bash tools/release_v0133.sh   （前置：分支与 tag 已双端 push）
set -euo pipefail

TAG=v0.1.33-reader-fix
TITLE='v0.1.33-reader-fix（预发布）· 阅读器真机验收第一轮四条修复'
BODY_FILE=tools/release_body_v0133.md
BRANCH=feat/m0-skeleton
OUT=/d/dev_workplace/flutter_te/lifeHarness-rel/build/app/outputs/flutter-apk
GH="/c/Program Files/GitHub CLI/gh.exe"
GITEE="/d/app_workplace/gitee-cli/gitee.exe"
OWNER=chistoiy
REPO=lifeHarness

cd /d/dev_workplace/flutter_te/lifeHarness
APKS=("$OUT/app-arm64-v8a-release.apk" "$OUT/app-armeabi-v7a-release.apk" "$OUT/app-x86_64-release.apk")
for a in "${APKS[@]}"; do
  [ -f "$a" ] || { echo "缺 APK：$a"; exit 1; }
  echo "  $(basename "$a") $(stat -c %s "$a") bytes  mtime $(date -r "$a" '+%F %T')"
done
[ -f "$BODY_FILE" ] || { echo "缺发布正文"; exit 1; }

echo "=== ① Gitee release ==="
"$GITEE" release create -R "$OWNER/$REPO" --tag "$TAG" -n "$TITLE" \
  -b "$(cat "$BODY_FILE")" --prerelease --target "$BRANCH" --no-tui
NID=$("$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node -e "
let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
  const j=JSON.parse(d);const t=process.argv[1];
  const r=(j.data||j).find(x=>x.tag_name===t);
  if(!r){console.error('未找到 release '+t);process.exit(1)}
  console.log(r.id)})" "$TAG")
echo "  gitee release id=$NID"
TOK=$("$GITEE" auth token | grep -Eo '[A-Za-z0-9_-]{20,}' | head -1)   # 令牌只在内存里用，不落文件不外显
for a in "${APKS[@]}"; do
  code=$(curl -s -o "$OUT/.gitee_up.json" -w '%{http_code}' -X POST \
    "https://gitee.com/api/v5/repos/$OWNER/$REPO/releases/$NID/attach_files?access_token=$TOK" \
    -F "name=$(basename "$a")" -F "file=@$a")
  echo "  $(basename "$a") → HTTP $code"
  [ "$code" = 201 ] || { echo "  上传失败：$(head -c 300 "$OUT/.gitee_up.json")"; exit 1; }
done
rm -f "$OUT/.gitee_up.json"
# 核对走列表接口（附件字段叫 assets，且含两个自动源包 → 三包齐=5 个资产）
# 注意：check_gitee_assets.js 从 stdin 读 JSON，必须管道喂，直跑会读空 stdin 报错。
"$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node tools/check_gitee_assets.js "$TAG"

echo "=== ② GitHub release ==="
"$GH" release create "$TAG" "${APKS[@]}" \
  --repo "$OWNER/$REPO" --prerelease --title "$TITLE" --notes-file "$BODY_FILE" \
  || echo "!! GitHub 建 release 失败（Gitee 已挂好，稍后重试：gh release create $TAG …）"
