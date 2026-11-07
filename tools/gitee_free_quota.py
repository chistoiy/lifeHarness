# 配额腾挪：从最旧 prerelease 起逐件删 APK 附件（保留条目与 tag），腾够 --need 字节即停。
# 用法：set GITEE_TOKEN=... && python tools/gitee_free_quota.py --need 80000000 [--apply]
# 缺省 --apply 时只打印计划（干跑）。删除判据：HTTP 204 才算真删（2026-10-01 实测口径）。
import json
import os
import sys
import urllib.request

BASE = "https://gitee.com/api/v5/repos/chistoiy/lifeHarness"
TOK = os.environ.get("GITEE_TOKEN", "")
if not TOK:
    sys.exit("GITEE_TOKEN 未设置（用 gitee.exe auth token 取，勿落文件）")


def req(url, method="GET"):
    r = urllib.request.Request(url, method=method, headers={"User-Agent": "lh-rel"})
    with urllib.request.urlopen(r, timeout=60) as f:
        body = f.read()
        return f.status, (json.loads(body) if body else None)


args = sys.argv[1:]
need = int(args[args.index("--need") + 1]) if "--need" in args else 80_000_000
apply = "--apply" in args

st, releases = req(f"{BASE}/releases?access_token={TOK}&per_page=100")
releases = sorted(releases, key=lambda x: x.get("created_at", ""))
freed = 0
for r in releases:
    if freed >= need:
        break
    rid, tag = r["id"], r.get("tag_name", "")
    try:
        st, atts = req(f"{BASE}/releases/{rid}/attach_files?access_token={TOK}")
    except Exception as e:
        print(f"skip {tag}: list failed {e}")
        continue
    if not atts:
        continue
    for a in atts:
        if freed >= need:
            break
        name, size, aid = a.get("name", ""), a.get("size", 0), a["id"]
        if not name.endswith(".apk"):
            continue
        if not apply:
            print(f"PLAN del {tag}/{name} ({size} B)")
            freed += size
            continue
        st, _ = req(f"{BASE}/releases/{rid}/attach_files/{aid}?access_token={TOK}", "DELETE")
        ok = st == 204
        print(f"{'DEL' if ok else 'FAIL'} {tag}/{name} -> {st}")
        if ok:
            freed += size
print(f"freed={freed} need={need} apply={apply}")
