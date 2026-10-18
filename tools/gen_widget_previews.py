# -*- coding: utf-8 -*-
"""生成五枚小组件的 previewImage（浅/深两档）。

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


def draw_habit(c):
    """打卡-单习惯 2×2 · 四件套（标题／习惯名／状态行／主按钮）。

    坐标按 `lh_widget_habit.xml` 实算：padding 13dp；标题 9sp → 习惯名 16sp bold
    （marginTop 4）→ 状态行（marginTop 5，状态点 8dp 垂直居中）→ gap 撑开 → 按钮 40dp 贴底。
    """
    img = canvas(W22, H22)
    card(img, c)
    d = ImageDraw.Draw(img)
    pad = 13
    text(d, (pad, pad + 1), 'LifeHarness · 打卡', 9, c['sub'])
    text(d, (pad, 29), '早起', 16, c['fg'], bold=True)
    # 状态行：实心状态点（未打卡＝off 档，用 track 色）+ 连击副文案
    cy = 63.5
    d.ellipse([dp(pad), dp(cy - 4), dp(pad + 8), dp(cy + 4)], fill=c['track'])
    text(d, (pad + 14, cy), '连击 12 天 · 今日未打卡', 10, c['sub'], anchor='lm')
    # 主按钮：强调色实心、圆角 12dp、贴底
    by, bh = H22 - pad - 40, 40
    d.rounded_rectangle([dp(pad), dp(by), dp(W22 - pad), dp(by + bh)],
                        radius=dp(12), fill=c['acc'])
    text(d, (W22 / 2, by + bh / 2), '打卡', 13, c['btn_fg'], bold=True, anchor='mm')
    return img


CARDS = {
    'overview': draw_overview,
    'quick': draw_quick,
    'todo': draw_todo,
    'ledger': draw_ledger,
    'habit': draw_habit,
}

# ── 批C · 1×1 模块瓦片 ─────────────────────────────────────────
#
# 1×1 瓦片在桌面上约 72×72dp（各桌面略有差异，取常见值）。缩略图必须**每枚不同**：
# MIUI 只认 previewImage，缺图一律回落应用图标 ⇒ 17 枚长得一模一样（2026-10-15
# 装机实锤）。故每枚按「模块色块 + 标签」画——色块与标签两项都不同，一眼可分。
#
# ⚠ 缩略图不画字形（字形由真实布局的 `ic_lh_*` 矢量图出）：这里只表达
#   「这是哪一枚」——色块形状、颜色、标签。真实布局见 `res/layout/lh_tile.xml`。
W11, H11 = 72, 72

# 模块色块（与对应 `ic_lh_<id>.xml` 的底色同值；新增瓦片时在此登记一行）。
TILE_COLORS = {
    'todo': (99, 102, 241, 255),
}


def draw_tile(c, label, color):
    """1×1 模块瓦片缩略图（真机二修后版：固定 55dp 图标＋整列居中）。

    真实布局＝`lh_tile.xml`（**透明底**，图标固定 55dp 见方、整列 `gravity=center`，
    标签 9sp、白字带阴影）。缩略图这里仍画一层卡片底：小部件库的列表底不一定是浅色，
    透明 PNG 在深/浅两种列表底上必有一边看不清标签；卡片只作缩略图衬底，
    桌面上那枚瓦片本身是透明的。缩略图的字色仍跟主题走（衬底是受控的），
    真机瓦片才需要「白字＋阴影」那套不跟主题的硬色。
    """
    img = canvas(W11, H11)
    card(img, c, radius=20)
    d = ImageDraw.Draw(img)
    # 图标块：55dp 见方（＝真机布局里的固定尺寸），与标签一起整列居中
    isz = 55
    ix = (W11 - isz) / 2
    iy = (H11 - isz - 13) / 2
    d.rounded_rectangle([dp(ix), dp(iy), dp(ix + isz), dp(iy + isz)],
                        radius=dp(11), fill=color)
    # 标签：9sp 单行居中，压在图标下方 2dp
    text(d, (W11 / 2, iy + isz + 2), label, 9, c['fg'], anchor='ma')
    return img


TILES = {
    # id → (瓦片标签, 色块)。标签与 `strings.xml` 的 `lh_tile_label_<id>` 同字。
    # 17 枚共用同一个底色（#6366F1，与七枚既有 `ic_lh_*` 矢量图一致）；
    # 缩略图靠**标签**分辨——色块相同是照实画，别为了好认改色（桌面那枚不是这个色）。
    'today': ('今天', TILE_COLORS['todo']),
    'todo': ('待办', TILE_COLORS['todo']),
    'calendar': ('时间', TILE_COLORS['todo']),
    'journal': ('记录', TILE_COLORS['todo']),
    'habit': ('习惯', TILE_COLORS['todo']),
    'inbox': ('收集箱', TILE_COLORS['todo']),
    'ledger': ('记账', TILE_COLORS['todo']),
    'items': ('物品', TILE_COLORS['todo']),
    'days': ('日子', TILE_COLORS['todo']),
    'goals': ('目标', TILE_COLORS['todo']),
    'settings': ('我的', TILE_COLORS['todo']),
    'care': ('呵护', TILE_COLORS['todo']),
    'read': ('阅读', TILE_COLORS['todo']),
    'media': ('影音', TILE_COLORS['todo']),
    'health': ('健康', TILE_COLORS['todo']),
    'mindmap': ('导图', TILE_COLORS['todo']),
    'nfc': ('卡片', TILE_COLORS['todo']),
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
        for name, (label, color) in TILES.items():
            img = draw_tile(colors, label, color)
            img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
            p = os.path.join(out, 'lh_tile_%s_preview.png' % name)
            img.save(p, 'PNG', optimize=True)
            print('%-8s %-52s %s' % (theme, p, img.size))


if __name__ == '__main__':
    main()
