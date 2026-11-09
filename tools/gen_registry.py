#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""gen_registry.py：从 prototype/_modules.json 生成人读注册表 docs/模块注册表.md。
JSON 是源，md 是产物——手改 md 无效且会被本脚本覆盖。用法：python tools/gen_registry.py"""
import json, os, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
reg = json.load(open('prototype/_modules.json', encoding='utf-8'))
home_count = {}
for s in reg['screens']:
    if s.get('home'):
        home_count[s['home']] = home_count.get(s['home'], 0) + 1
L = [
    '# 模块注册表（人读产物 · 禁止手改）',
    '',
    '> 由 `python tools/gen_registry.py` 从 `prototype/_modules.json` 生成（JSON 是源）。',
    f"> 数据时点：{reg['updated']} · 闸模式：{reg['gateMode']} · 屏/弹层登记 {len(reg['screens'])} 个 · 待删越权副本 {len([v for v in reg['violations'] if not v.get('exempt')])} 处",
    '',
    '| 模块 | 需求编号 | 专版原型 | 状态 | 开发 | 代表屏 | 屏/弹层(家) | 人话别名 |',
    '|---|---|---|---|---|---|---|---|',
]
for m in reg['modules']:
    f = m.get('file') or '（壳内/无专版）'
    L.append('| {}（{}） | {} | {} | {} | {} | {} | {} | {} |'.format(
        m['id'], m.get('name', ''), m.get('req', '-'), f, m['status'], m.get('dev', '-'),
        m.get('rep') or '-', home_count.get(m.get('file'), '-') if m.get('file') else '-',
        '、'.join(m['aliases'])))
L += ['', '屏×家全清单见 `prototype/_modules.json`（screens 段）；每文件切片索引用 `node tools/pslice.js <file> --list`。', '']
open('docs/模块注册表.md', 'w', encoding='utf-8').write('\n'.join(L))
print('docs/模块注册表.md 已生成（' + str(len(reg['modules'])) + ' 模块）')
