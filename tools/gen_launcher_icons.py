# -*- coding: utf-8 -*-
"""从 prototype/icons/ 四张品牌图生成 Android 启动图标全套（可重跑）：
   1) 前景抠图：从边缘泛洪填充近白背景→透明（保留火焰内部白色对勾不被打穿）
   2) Adaptive：ic_launcher_{foreground,background,monochrome}.png @ mipmap-xxhdpi(432px·内容88%安全区)
   3) Legacy：ic_launcher.png / ic_launcher_round.png 五档密度（主图标）
   4) XML：mipmap-anydpi-v26（前景+背景）与 mipmap-anydpi-v33（追加 monochrome 主题图标层）
   用法：python tools/gen_launcher_icons.py"""
import os
from collections import deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "prototype", "icons")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

def load(name, size):
    return Image.open(os.path.join(SRC, name)).convert("RGB").resize((size, size), Image.LANCZOS)

def flood_transparent(img, tol=16):
    """纯白背景从边缘泛洪 → alpha=0；保留火焰内部白对勾与浅色螺旋条不被打穿。"""
    w, h = img.size
    px = img.load()
    a = Image.new("L", (w, h), 255)
    ap = a.load()
    visited = [[False] * w for _ in range(h)]
    q = deque()
    def near_white(x, y):
        r, g, b = px[x, y][:3]
        return (255 - r) <= tol and (255 - g) <= tol and (255 - b) <= tol
    for x in range(w):
        for y in (0, h - 1):
            if not visited[y][x] and near_white(x, y):
                visited[y][x] = True; ap[x, y] = 0; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x] and near_white(x, y):
                visited[y][x] = True; ap[x, y] = 0; q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx] and near_white(nx, ny):
                visited[ny][nx] = True; ap[nx, ny] = 0; q.append((nx, ny))
    out = img.convert("RGBA"); out.putalpha(a)
    return out

def adaptive_canvas(fg, canvas=432, scale=0.88):
    """前景内容缩至画布 scale 居中（108dp 画布·66dp 圆形安全区留量）。"""
    inner = int(canvas * scale)
    im = fg.resize((inner, inner), Image.LANCZOS)
    c = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    c.paste(im, ((canvas - inner) // 2, (canvas - inner) // 2), im)
    return c

def mono_from(img):
    """单色版：距白越远越不透明，统一染白（monochrome 层由系统着色）。"""
    img = img.convert("RGB"); px = img.load(); w, h = img.size
    a = Image.new("L", (w, h))
    ap = a.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            d = (255 - min(r, g, b))
            ap[x, y] = min(255, int(d * 1.6))
    base = Image.new("RGB", (w, h), (255, 255, 255))
    base.putalpha(a)
    return base

# ---- 生成 ----
FG = flood_transparent(load("icon-fg.jpg", 1024))            # 透明前景
MONO_A = mono_from(load("icon-mono.jpg", 1024))              # 单色(白)层
BG = load("icon-bg.jpg", 432).convert("RGBA")                # 背景层
MAIN = load("icon-main.jpg", 512)                            # 主图标(legacy 源)

os.makedirs(os.path.join(RES, "mipmap-xxhdpi"), exist_ok=True)
adaptive_canvas(FG).save(os.path.join(RES, "mipmap-xxhdpi", "ic_launcher_foreground.png"), optimize=True)
adaptive_canvas(MONO_A).save(os.path.join(RES, "mipmap-xxhdpi", "ic_launcher_monochrome.png"), optimize=True)
BG.save(os.path.join(RES, "mipmap-xxhdpi", "ic_launcher_background.png"), optimize=True)

for dens, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    d = os.path.join(RES, f"mipmap-{dens}"); os.makedirs(d, exist_ok=True)
    ic = MAIN.resize((size, size), Image.LANCZOS)
    ic.save(os.path.join(d, "ic_launcher.png"), optimize=True)
    rnd = ic.convert("RGBA")
    mask = Image.new("L", (size * 4, size * 4), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4, size * 4), fill=255)
    rnd.putalpha(mask.resize((size, size), Image.LANCZOS))
    rnd.save(os.path.join(d, "ic_launcher_round.png"), optimize=True)

XML_V26 = ('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n')
XML_V33 = ('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n</adaptive-icon>\n')
for v, xml in (("mipmap-anydpi-v26", XML_V26), ("mipmap-anydpi-v33", XML_V33)):
    d = os.path.join(RES, v); os.makedirs(d, exist_ok=True)
    for f in ("ic_launcher.xml", "ic_launcher_round.xml"):
        open(os.path.join(d, f), "w", encoding="utf-8").write(xml)

print("OK: adaptive(v26/v33) + legacy 5档 + round 生成完毕")
