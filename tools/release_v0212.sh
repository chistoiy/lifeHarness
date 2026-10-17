#!/usr/bin/env bash
# v0.2.12-ux2 预发布收口（正式版口径 · release split-per-abi 三包）。
# 与 release_v0211ux.sh 同序同式；差别＝本轮补回三包（arm64/v7a/x86_64），
# 且产物在发版 worktree lh-rel0212（从钉版提交 54fd65a 检出构建）。
# 前提：分支与 tag 已双端推送（本脚本不含 git push，避免与并行会话抢暂存/引用）。
set -euo pipefail

TAG=v0.2.12-ux2
TITLE='v0.2.12-ux2（预发布）· UX审计实现批四件＋备份文件管理屏 B-1'
BODY_FILE=tools/release_body_v0212.md
BRANCH=feat/m0-skeleton   # 分支 tip＝钉版提交，Gitee 建 tag 时以它为 commitish
GITEE="/d/app_workplace/gitee-cli/gitee.exe"
GH="/c/Program Files/GitHub CLI/gh.exe"
OWNER=chistoiy
REPO=lifeHarness

cd /d/dev_workplace/flutter_te/lifeHarness
OUT=/d/dev_workplace/lh-rel0212/build/app/outputs/flutter-apk
APKS=("$OUT/app-arm64-v8a-release.apk" "$OUT/app-armeabi-v7a-release.apk" "$OUT/app-x86_64-release.apk")
for a in "${APKS[@]}"; do
  [ -f "$a" ] || { echo "缺 APK：$a"; exit 1; }
  echo "  $(basename "$a") $(stat -c %s "$a") bytes  mtime $(date -r "$a" '+%F %T')"
done
[ -f "$BODY_FILE" ] || { echo "缺发布正文 $BODY_FILE"; exit 1; }

echo "=== ① Gitee release（第一通道）==="
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
  [ "$code" = 201 ] || { echo "  上传失败：$(head -c 300 "$OUT/.gitee_up.json")（配额？跑 tools/gitee_free_quota.py）"; exit 1; }
done
rm -f "$OUT/.gitee_up.json"
"$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node tools/check_gitee_assets.js "$TAG"

echo "=== ② GitHub release ==="
"$GH" release create "$TAG" "${APKS[@]}" \
  --repo "$OWNER/$REPO" --prerelease --title "$TITLE" --notes-file "$BODY_FILE" \
  || echo "  GH release 可能已存在，重试：gh release upload $TAG --clobber <apk>"
