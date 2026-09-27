#!/usr/bin/env bash
# V1.52 时间模块预发布收口：双端建 prerelease 并挂 split 三包 APK（**Gitee 优先·GitHub 失败仅提醒**）。
# 用法：TAG=v0.1.30-m2.xxx TITLE='…' BODY_FILE=tools/release_body_xxx.md bash tools/release_v152.sh
# 依赖：gh（C:/Program Files/GitHub CLI/gh.exe）、gitee-cli（D:/app_workplace/gitee-cli/gitee.exe）、curl、node
# 前置：`git push gitee <branch>` + `git push gitee <tag>` 已完成（release 必须挂在远端已有的 tag 上）。
#
# ⚠️ 本脚本已在 v0.1.29-m1.time-v152 手工按此序执行完毕（Gitee id=1170958·三包 201·GitHub 见 tag），
#    **勿对该 tag 重跑**（会重复建 release / 重挂附件）；留作后续批次的收口模板。
set -euo pipefail

TAG="${TAG:?需要 TAG}"
TITLE="${TITLE:-$TAG（预发布）}"
BODY_FILE="${BODY_FILE:?需要 BODY_FILE}"
BRANCH="${BRANCH:-feat/m0-skeleton}"
GH="/c/Program Files/GitHub CLI/gh.exe"
GITEE="/d/app_workplace/gitee-cli/gitee.exe"
OWNER=chistoiy
REPO=lifeHarness
OUT=build/app/outputs/flutter-apk

APKS=("$OUT/app-arm64-v8a-release.apk" "$OUT/app-armeabi-v7a-release.apk" "$OUT/app-x86_64-release.apk")
for a in "${APKS[@]}"; do
  [ -f "$a" ] || { echo "缺 APK：$a"; exit 1; }
  echo "  $(basename "$a") $(stat -c %s "$a") bytes  mtime $(date -r "$a" '+%F %T')"
done
[ -f "$BODY_FILE" ] || { echo "缺发布正文 $BODY_FILE"; exit 1; }

echo "=== ① Gitee release（第一通道）==="
"$GITEE" release create -R "$OWNER/$REPO" --tag "$TAG" -n "$TITLE" \
  -b "$(cat "$BODY_FILE")" --prerelease --target "$BRANCH" --no-tui
# attach_files 要的是 numericId（不是 tag）；列表接口不带 per_page 只回旧版。
NID=$("$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node -e "
let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
  const j=JSON.parse(d);const t=process.argv[1];
  const r=(j.data||j).find(x=>x.tag_name===t);
  if(!r){console.error('未找到 release '+t);process.exit(1)}
  console.log(r.id)})" "$TAG")
echo "  gitee release id=$NID"
TOK=$("$GITEE" auth token | grep -Eo '[A-Za-z0-9_-]{20,}' | head -1)  # 令牌不落文件、不外显
for a in "${APKS[@]}"; do
  code=$(curl -s -o "$OUT/.gitee_up.json" -w '%{http_code}' -X POST \
    "https://gitee.com/api/v5/repos/$OWNER/$REPO/releases/$NID/attach_files?access_token=$TOK" \
    -F "name=$(basename "$a")" -F "file=@$a")
  echo "  $(basename "$a") → HTTP $code"
  [ "$code" = 201 ] || { echo "  上传失败：$(head -c 300 "$OUT/.gitee_up.json")"; exit 1; }
done
rm -f "$OUT/.gitee_up.json"

echo "=== ② 核对 Gitee 三包（附件字段在列表接口叫 assets）==="
"$GITEE" api "repos/$OWNER/$REPO/releases?per_page=100" | node tools/check_gitee_assets.js "$TAG"

echo "=== ③ GitHub prerelease（失败仅提醒，不阻塞）==="
"$GH" release create "$TAG" "${APKS[@]}" \
  --title "$TITLE" --notes-file "$BODY_FILE" --prerelease \
  || echo "!! GitHub 发布失败：HTTPS 443 时好时坏，重试或改走 ssh://git@ssh.github.com:443；按铁律只提醒不阻塞"

echo "=== ④ 核对 GitHub 三资产 ==="
"$GH" release view "$TAG" --json assets,prerelease --jq '{prerelease:.prerelease,assets:[.assets[].name]}'
echo "OK 双端预发布收口：$TAG"
