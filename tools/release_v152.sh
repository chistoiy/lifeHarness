#!/usr/bin/env bash
# V1.52 时间模块预发布收口：双端（GitHub + Gitee）建 prerelease 并挂 split 三包 APK。
# 用法：TAG=v0.1.29-m1.time-v152 bash tools/release_v152.sh
# 依赖：gh（C:/Program Files/GitHub CLI/gh.exe）、gitee-cli（D:/app_workplace/gitee-cli/gitee.exe）、curl
set -euo pipefail

TAG="${TAG:?需要 TAG}"
GH="/c/Program Files/GitHub CLI/gh.exe"
GITEE="/d/app_workplace/gitee-cli/gitee.exe"
OWNER=chistoiy
REPO=lifeHarness
OUT=build/app/outputs/flutter-apk
BODY_FILE="${BODY_FILE:-tools/release_body_v152.md}"

APKS=("$OUT/app-arm64-v8a-release.apk" "$OUT/app-armeabi-v7a-release.apk" "$OUT/app-x86_64-release.apk")
for a in "${APKS[@]}"; do
  [ -f "$a" ] || { echo "缺 APK：$a"; exit 1; }
  echo "  $(basename "$a") $(stat -c %s "$a") bytes  mtime $(date -r "$a" '+%F %T')"
done
[ -f "$BODY_FILE" ] || { echo "缺发布说明 $BODY_FILE"; exit 1; }

echo "=== GitHub prerelease ==="
"$GH" release create "$TAG" "${APKS[@]}" \
  --title "$TAG 时间模块 V1.52（预发布）" \
  --notes-file "$BODY_FILE" \
  --prerelease || echo "!! GitHub 发布失败（按铁律仅提醒，不阻塞 Gitee）"

echo "=== Gitee release ==="
"$GITEE" release create --tag "$TAG" -n "$TAG 时间模块 V1.52（预发布）" \
  -b "$(cat "$BODY_FILE")" --prerelease --target feat/m0-skeleton
sleep 2
NID=$("$GITEE" api "repos/$OWNER/$REPO/releases" | node -e "
let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
  const j=JSON.parse(d);const t=process.argv[1];
  const r=(j.data||j).find(x=>x.tag_name===t);
  if(!r){console.error('未找到 release '+t);process.exit(1)}
  console.log(r.id)})" "$TAG")
echo "  gitee release id=$NID"
for a in "${APKS[@]}"; do
  TOK=$("$GITEE" auth token | grep -Eo '[A-Za-z0-9_-]{20,}' | head -1)
  code=$(curl -s -o /tmp/gitee_up.json -w '%{http_code}' -X POST \
    "https://gitee.com/api/v5/repos/$OWNER/$REPO/releases/$NID/attach_files?access_token=$TOK" \
    -F "name=$(basename "$a")" -F "file=@$a")
  echo "  $(basename "$a") → HTTP $code"
  [ "$code" = 201 ] || { echo "  上传失败：$(cat /tmp/gitee_up.json | head -c 300)"; exit 1; }
done

echo "=== 核对三资产已挂 ==="
"$GITEE" api "repos/$OWNER/$REPO/releases/$NID" | node -e "
let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
  const j=JSON.parse(d),r=j.data||j;
  const n=(r.attachments||[]).length;
  console.log('gitee assets =',n);
  (r.attachments||[]).forEach(a=>console.log('  -',a.name,a.size));
  process.exit(n===3?0:1)})"
echo "OK 双端预发布完成：$TAG"
