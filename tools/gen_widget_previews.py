# -*- coding: utf-8 -*-
"""生成四枚小组件的 previewImage（浅/深两档）。

为什么要这个脚本：MIUI 桌面**只认 `previewImage`**，「添加小部件」列表里没有真实
预览图就回落成应用图标（四枚长得一模一样，用户分不清哪枚是哪枚）。
`previewLayout` 是 Android 12+ 的标准口径，但 MIUI 实测忽略，所以两个都给：
  - `previewLayout` 给标准桌面用；
  - `previewImage` 给 MIUI 这类只看图的桌面用。

图按 `lh_widget_*.xml` 的真实结构/字号/色值画（不截用户数据，用示例内容）。
输出：
  res/drawable-nodpi/lh_widget_<name>_preview.png         （浅色档）
  res/drawable-night-nodpi/lh_widget_<name>_preview.png   （深色档 · C6 跟随系统）
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = 'android/app/src/main/res'
S = 4          # px per dp（设备密度 3.0 的 1.3 倍；缩略图约 250px，够清晰又不臃肿）
SS = 4         # 超采样倍率，边缘抗锯齿
SCALE = S * SS

LIGHT = dict(bg=(255, 255, 255, 255), fg=(15, 23, 42, 255), sub=(100, 116, 139, 255),
             acc=(99, 102, 241, 255), btn_fg=(255, 255, 255, 255),
             stroke=(100, 116, 139, 26), track=(100, 116, 139, 46))
DARK = dict(bg=(30, 41, 59, 255), fg=(241, 245, 249, 255), sub=(148, 163, 184, 255),
            acc=(129, 140, 248, 255), btn_fg=(30, 41, 59, 255),
            stroke=(148, 163, 184, 26), track=(148, 163, 184, 46))

REG = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
_fonts = {}


def font(size_dp, bold=False):
    key = (size_dp, bold)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(BOLD if bold else REG, int(size_dp * SCALE))
    return _fonts[key]


def dp(v):
    return int(round(v * SCALE))


def canvas(w_dp, h_dp):
    return Image.new('RGBA', (dp(w_dp), dp(h_dp)), (0, 0, 0, 0))


def card(img, c, radius=16):
    """圆角卡片底 + 1dp 描边（对应 @drawable/lh_wg_card）。"""
    d = ImageDraw.Draw(img)
    w, h = img.size
    r = dp(radius)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=c['bg'],
                        outline=c['stroke'], width=max(1, dp(1)))


def text(d, xy, s, size_dp, color, bold=False, anchor='la'):
    d.text((dp(xy[0]), dp(xy[1])), s, font=font(size_dp, bold), fill=color, anchor=anchor)


def circle(d, cx, cy, radius_dp, color, width_dp):
    d.ellipse([dp(cx - radius_dp), dp(cy - radius_dp),
               dp(cx + radius_dp), dp(cy + radius_dp)],
              outline=color, width=max(1, dp(width_dp)))


def bar(d, x, y, w, h, ratio, c):
    """进度条（槽 + 已填），对应 @drawable/lh_wg_progress。"""
    r = dp(h / 2)
    d.rounded_rectangle([dp(x), dp(y), dp(x + w), dp(y + h)], radius=r, fill=c['track'])
    if ratio > 0:
        d.rounded_rectangle([dp(x), dp(y), dp(x + w * ratio), dp(y + h)], radius=r, fill=c['acc'])


# ── 四枚卡的画法 ────────────────────────────────────────────────
W22, H22 = 153, 125      # 2×2 实测尺寸（桌面截图 459×375 @3x）
W41, H41 = 336, 117      # 4×1 实测尺寸（桌面截图 1008×351 @3x）


def draw_overview(c):
    img = canvas(W22, H22)
    card(img, c)
    d = ImageDraw.Draw(img)
    pad = 12
    text(d, (pad, pad + 1), 'LifeHarness · 今日概览', 9, c['sub'])
    base = 40
    text(d, (pad, base), '待办', 12, c['sub'])
    text(d, (pad, base + 15), '3', 24, c['fg'], bold=True)
    text(d, (W22 - pad, base), '打卡', 12, c['sub'], anchor='ra')
    text(d, (W22 - pad, base + 15), '/4', 13, c['sub'], anchor='ra')
    text(d, (W22 - pad - 13, base + 15), '2', 24, c['fg'], bold=True, anchor='ra')
    bar(d, pad, H22 - pad - 22, W22 - pad * 2, 6, 0.5, c)
    text(d, (pad, H22 - pad - 12), '还差 2 项就全勤', 10, c['sub'])
    return img


def draw_quick(c):
    img = canvas(W41, H41)
    card(img, c)
    d = ImageDraw.Draw(img)
    half = W41 / 2
    # 左半：强调色按钮（仅左侧圆角）
    d.rounded_rectangle([0, 0, dp(half), dp(H41)], radius=dp(16), fill=c['acc'])
    d.rectangle([dp(half - 20), 0, dp(half), dp(H41)], fill=c['acc'])
    # 加号
    cx, cy = half / 2 - 24, H41 / 2
    d.line([dp(cx - 5), dp(cy), dp(cx + 5), dp(cy)], fill=c['btn_fg'], width=dp(1.3))
    d.line([dp(cx), dp(cy - 5), dp(cx), dp(cy + 5)], fill=c['btn_fg'], width=dp(1.3))
    text(d, (cx + 10, cy), '记一笔', 13, c['btn_fg'], bold=True, anchor='lm')
    # 右半
    rx = half + 13
    text(d, (rx, 26), 'LifeHarness · 快捷记录', 9, c['sub'])
    text(d, (rx, 48), '今日支出', 10, c['sub'])
    text(d, (W41 - 12, 40), '¥128', 20, c['fg'], bold=True, anchor='ra')
    return img


def draw_todo(c):
    img = canvas(W22, H22)
    card(img, c)
    d = ImageDraw.Draw(img)
    pad = 12
    text(d, (pad, pad + 1), 'LifeHarness · 今日待办', 9, c['sub'])
    rows = ['整理周报', '买牛奶', '预约体检']
    y = 32
    for i, t in enumerate(rows):
        circle(d, pad + 8.5, y + 8.5, 7, c['sub'], 1.3)
        text(d, (pad + 21, y + 8.5), t, 12, c['fg'], anchor='lm')
        y += 24
    text(d, (pad, y + 2), '还有 2 条', 10, c['sub'])
    return img


def draw_ledger(c):
    img = canvas(W22, H22)
    card(img, c)
    d = ImageDraw.Draw(img)
    pad = 12
    text(d, (pad, pad + 1), 'LifeHarness · 记账概览', 9, c['sub'])
    rows = [('今日支出', '¥36', c['fg']),
            ('本月支出', '¥1,286', c['fg']),
            ('本月结余', '-¥225', c['acc'])]
    y = 36
    for label, val, col in rows:
        text(d, (pad, y + 4), label, 11, c['sub'], anchor='lm')
        text(d, (W22 - pad, y + 4), val, 19, col, bold=True, anchor='rm')
        y += 27
    text(d, (pad, y + 6), '点一下记一笔', 10, c['sub'])
    return img


CARDS = {
    'overview': draw_overview,
    'quick': draw_quick,
    'todo': draw_todo,
    'ledger': draw_ledger,
}


def main():
    for theme, colors, sub in (('day', LIGHT, 'drawable-nodpi'),
                               ('night', DARK, 'drawable-night-nodpi')):
        out = os.path.join(ROOT, sub)
        os.makedirs(out, exist_ok=True)
        for name, fn in CARDS.items():
            img = fn(colors)
            img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
            p = os.path.join(out, 'lh_widget_%s_preview.png' % name)
            img.save(p, 'PNG', optimize=True)
            print('%-8s %-52s %s' % (theme, p, img.size))


if __name__ == '__main__':
    main()
