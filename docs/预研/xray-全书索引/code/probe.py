# -*- coding: utf-8 -*-
"""EPUB 结构摸底：OPF/spine/nav/文本量。只读，不改任何项目文件。"""
import sys, zipfile, re, posixpath

def probe(path):
    print("=" * 70)
    print("FILE:", path)
    z = zipfile.ZipFile(path)
    names = z.namelist()
    print("entries:", len(names))
    container = z.read("META-INF/container.xml").decode("utf-8", "ignore")
    m = re.search(r'full-path="([^"]+)"', container)
    opf_path = m.group(1)
    opf = z.read(opf_path).decode("utf-8", "ignore")
    base = posixpath.dirname(opf_path)

    manifest = dict(re.findall(r'<item[^>]*\bid="([^"]+)"[^>]*href="([^"]+)"', opf))
    # 有些属性顺序不同，补充解析
    manifest = {}
    for it in re.findall(r'<item\b[^>]*/?>', opf):
        i = re.search(r'id="([^"]+)"', it)
        h = re.search(r'href="([^"]+)"', it)
        mt = re.search(r'media-type="([^"]+)"', it)
        if i and h:
            manifest[i.group(1)] = (posixpath.normpath(posixpath.join(base, h.group(1))), mt.group(1) if mt else "")
    spine = re.findall(r'<itemref[^>]*idref="([^"]+)"', opf)
    print("opf:", opf_path, "| manifest items:", len(manifest), "| spinerefs:", len(spine))

    html_bytes = 0
    miss = 0
    for sid in spine:
        if sid in manifest:
            p, mt = manifest[sid]
            if mt.startswith("image"):
                continue
            try:
                html_bytes += len(z.read(p))
            except KeyError:
                miss += 1
    print("spine html bytes: %.1f MB, missing: %d" % (html_bytes / 1e6, miss))

    # TOC
    ncx = [p for p, mt in manifest.values() if mt == "application/x-dtbncx+xml" or p.endswith(".ncx")]
    nav = [p for p, mt in manifest.values() if "nav" in posixpath.basename(p).lower()]
    toc_src = "none"
    toc_n = 0
    if ncx:
        try:
            t = z.read(ncx[0]).decode("utf-8", "ignore")
            toc_n = len(re.findall(r'<navPoint\b', t))
            toc_src = "ncx:" + ncx[0]
        except Exception:
            pass
    if toc_n == 0 and nav:
        try:
            t = z.read(nav[0]).decode("utf-8", "ignore")
            toc_n = len(re.findall(r'<a\b', t))
            toc_src = "nav:" + nav[0]
        except Exception:
            pass
    print("toc:", toc_src, "points:", toc_n)

    # 抽样第一章文本
    for sid in spine:
        if sid in manifest:
            p, mt = manifest[sid]
            if mt.startswith("image"):
                continue
            try:
                raw = z.read(p).decode("utf-8", "ignore")
            except KeyError:
                continue
            txt = re.sub(r"<[^>]+>", "", re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", "", raw))
            txt = re.sub(r"\s+", " ", txt).strip()
            if len(txt) > 200:
                print("sample chapter:", p)
                print("sample text head:", txt[:180])
                break
    z.close()

for f in sys.argv[1:]:
    try:
        probe(f)
    except Exception as e:
        print("ERROR", f, repr(e))
