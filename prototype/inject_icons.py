# -*- coding: utf-8 -*-
"""一次性脚本：把 prototype/icons/ 四张品牌图标压缩为 base64 并注入 prototype/index.html
   落点：favicon / 桌面侧栏品牌区+四变体展示条 / 设置页关于卡品牌行。用完可删。"""
import base64, io, sys
from PIL import Image

ROOT = "prototype"
HTML = f"{ROOT}/index.html"

def data_uri(src, size, q=82):
    im = Image.open(src).convert("RGB").resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=q, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()

main = data_uri(f"{ROOT}/icons/icon-main.jpg", 256)
fg   = data_uri(f"{ROOT}/icons/icon-fg.jpg", 256)
bg   = data_uri(f"{ROOT}/icons/icon-bg.jpg", 256)
mono = data_uri(f"{ROOT}/icons/icon-mono.jpg", 256)
fav  = data_uri(f"{ROOT}/icons/icon-main.jpg", 64, 78)

html = open(HTML, encoding="utf-8").read()
assert 'rel="icon"' not in html, "favicon 已存在？"

# 1) favicon
html = html.replace(
    '<title>LifeHarness · 高保真UI原型 V1.3</title>',
    '<title>LifeHarness · 高保真UI原型 V1.3</title>\n<link rel="icon" type="image/jpeg" href="' + fav + '">',
    1)

# 2) 桌面侧栏：标题加主图标 + 四变体展示条
tile_css = """
  .brand-tile{width:46px;height:46px;border-radius:13px;overflow:hidden;position:relative;flex-shrink:0;box-shadow:0 2px 8px rgba(0,0,0,.35)}
  .brand-tile img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
  .brand-cap{font-size:9px;line-height:1.4;color:#64748b;text-align:center}
"""
html = html.replace("  .glow-btn{", tile_css + "  .glow-btn{", 1)

old_side = """<div class="hidden md:flex flex-col items-center gap-3 mr-8 text-slate-400 select-none">
  <div class="text-lg font-bold text-slate-200">LifeHarness 交互原型</div>"""
new_side = ('<div class="hidden md:flex flex-col items-center gap-3 mr-8 text-slate-400 select-none">\n'
            '  <div class="flex items-center gap-2"><img src="' + main + '" class="w-9 h-9 rounded-xl shadow-lg" alt="LifeHarness">\n'
            '  <div class="text-lg font-bold text-slate-200">LifeHarness 交互原型</div></div>\n'
            '  <div class="grid grid-cols-4 gap-1.5 w-[220px] justify-items-center">\n'
            '    <div class="flex flex-col items-center gap-1"><div class="brand-tile"><img src="' + main + '" alt="主图标"></div><div class="brand-cap">主图标</div></div>\n'
            '    <div class="flex flex-col items-center gap-1"><div class="brand-tile"><img src="' + bg + '" alt=""><img src="' + fg + '" style="inset:16%;width:68%;height:68%;object-fit:contain"></div><div class="brand-cap">前景×背景</div></div>\n'
            '    <div class="flex flex-col items-center gap-1"><div class="brand-tile"><img src="' + bg + '" alt="背景"></div><div class="brand-cap">背景</div></div>\n'
            '    <div class="flex flex-col items-center gap-1"><div class="brand-tile"><img src="' + mono + '" alt="单色"></div><div class="brand-cap">单色版</div></div>\n'
            '  </div>')
assert old_side in html, "侧栏锚点未找到"
html = html.replace(old_side, new_side, 1)

# 3) 设置页关于卡：品牌行 + 单色版做「关于」标
old_about = """      <div class="card mt-4 text-[11px] text-slate-400 leading-6">
        <b class="text-slate-600 dark:text-slate-300 text-xs">关于</b><br>
        LifeHarness 原型 · 需求 V1.17 · 全模块导航演示<br>"""
new_about = ('      <div class="card mt-4 text-[11px] text-slate-400 leading-6">\n'
             '        <div class="flex items-center gap-2.5 mb-1.5">\n'
             '          <img src="' + main + '" class="w-10 h-10 rounded-xl shadow-sm" alt="LifeHarness">\n'
             '          <div class="text-left"><b class="text-slate-700 dark:text-slate-200 text-[13px]">LifeHarness</b>\n'
             '            <div class="text-[10px] text-slate-400">本地优先 · 自我记录 Harness</div></div>\n'
             '        </div>\n'
             '        <img src="' + mono + '" class="w-3.5 h-3.5 rounded-[4px] inline-block align-[-2px] mr-1" alt=""><b class="text-slate-600 dark:text-slate-300 text-xs">关于</b><br>\n'
             '        LifeHarness 原型 · 需求 V1.17 · 全模块导航演示<br>')
assert old_about in html, "关于卡锚点未找到"
html = html.replace(old_about, new_about, 1)

open(HTML, "w", encoding="utf-8").write(html)
kb = len(html.encode("utf-8")) / 1024
print(f"OK injected, index.html now {kb:.0f}KB")
