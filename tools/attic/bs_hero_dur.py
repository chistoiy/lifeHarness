# tools/attic/bs_hero_dur.py — 阅读首页 hero 时长自动换算（分钟 → bsFmt）
# 护栏：改前拍快照 · 每条锚点命中数断言 · 改后体积校验（原型曾被覆盖事故）
import io, os, shutil

P = 'prototype/index-bookshelf.html'
BAK = 'tools/attic/index-bookshelf.bak-20261001-herodur.html'

s = io.open(P, encoding='utf-8', newline='').read()
if not os.path.exists(BAK):
    shutil.copyfile(P, BAK)
before = len(s)

PAIRS = [
    # 环内大数字：两屏 hero 同形（阅读 tab 与书架 hub）
    ('font-black">${today}′</div>',
     'font-black">${bsFmt(today)}</div>', 2),
    # 紧凑写法那一屏
    ("今日阅读 ${today} / ${BS_GOAL.dayMin} 分钟 ${today>=BS_GOAL.dayMin?'已达成':'· 还差 '+(BS_GOAL.dayMin-today)+' 分钟'}",
     "今日阅读 ${bsFmt(today)} / 目标 ${bsFmt(BS_GOAL.dayMin)} ${today>=BS_GOAL.dayMin?'已达成':'· 还差 '+bsFmt(BS_GOAL.dayMin-today)}", 1),
    # 带空格写法那一屏
    ("今日阅读 ${today} / ${BS_GOAL.dayMin} 分钟 ${today >= BS_GOAL.dayMin ? '已达成' : '· 还差 ' + (BS_GOAL.dayMin - today) + ' 分钟'}",
     "今日阅读 ${bsFmt(today)} / 目标 ${bsFmt(BS_GOAL.dayMin)} ${today >= BS_GOAL.dayMin ? '已达成' : '· 还差 ' + bsFmt(BS_GOAL.dayMin - today)}", 1),
]

for a, b, n in PAIRS:
    got = s.count(a)
    assert got == n, (a[:40], 'expect', n, 'got', got)
    s = s.replace(a, b)

assert len(s) > before - 200 and abs(len(s) - before) < 2000, (before, len(s))
io.open(P, 'w', encoding='utf-8', newline='').write(s)
print('hero dur ok', before, '->', len(s))
