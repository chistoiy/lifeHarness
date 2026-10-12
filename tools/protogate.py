#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""protogate：原型屏单一归属四道闸（治理批 §4-3 / §8.4）。
闸1 双向归属：专版含他模块屏/弹层即红；index.html 含"家不在这"的细节屏即红；未登记 section/sheet id 即红。
闸2 注册表↔代码：status=current 且 dev=delivered 的模块必须有 lib/features/<id>；dropped 不得残留。
闸3 勿复活：dropped 模块的屏/标识出现在现行 lib/ 或现行原型即红（media 冻结文件豁免）。
闸4 别名非空：注册表每模块 aliases 非空；每屏登记 home 文件必须真实含该屏。
闸5 语法闸：现行原型全部内联 <script> 过 node vm.Script（tools/vm_script_check.js）——
   2026-10-12 emoji 批裸 SVG 事故补死（块级 hash 自证不查 JS 语法）。
模式：--report 只报不拦（默认读 _modules.json.gateMode）；--strict 红灯 exit 1。
变异自证：--dir <原型目录> --modules <注册表> 指到探针副本目录跑 strict，塞假屏必须红。
用法：python tools/protogate.py [--strict|--report] [--dir prototype] [--modules prototype/_modules.json]
"""
import json, os, re, subprocess, sys
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
argv = sys.argv[1:]
mdir = argv[argv.index('--dir') + 1] if '--dir' in argv else 'prototype'
mpath = argv[argv.index('--modules') + 1] if '--modules' in argv else os.path.join(mdir, '_modules.json')

reg = json.load(open(mpath, encoding='utf-8'))
mode = 'strict' if '--strict' in argv else ('report' if '--report' in argv else reg.get('gateMode', 'report'))
frozen = set(reg.get('frozen', []))
screens = reg['screens']
byid = {s['id']: s for s in screens}

def ids_in(fn):
    p = os.path.join(mdir, fn)
    if not os.path.exists(p):
        return None
    html = open(p, encoding='utf-8', errors='replace').read()
    out = set()
    for m in re.finditer(r'<(?:section|div)\b[^>]*\bid="([^"]+)"', html):
        tag = m.group(0).split()[0]
        if tag == '<div' and not (m.group(1).startswith('sheet') or m.group(1).startswith('drawer')):
            continue
        out.add(m.group(1))
    return out

red, warn = [], []
active_files = [f for f in os.listdir(mdir) if f.endswith('.html') and f not in frozen]
for f in active_files:
    got = ids_in(f)
    for i in sorted(got):
        s = byid.get(i)
        if s is None:
            red.append(f"闸1 未登记 id: {f}# {i}（新屏须先入 _modules.json）")
            continue
        if s.get('status') == 'dropped':
            red.append(f"闸3 勿复活: {f}# {i} 属已作废模块")
            continue
        if s.get('status') == 'collision':
            if f not in (s.get('homes') or {}):
                red.append(f"闸1 同物异名屏出现在第三处: {f}# {i}")
            continue
        home = s.get('home')
        if f != home and f not in (s.get('reps') or []):
            (red if mode == 'strict' else warn).append(f"闸1 越权副本: {f}# {i}（家={home}）")
    # 闸4：每屏的 home 文件存在该 id
    for s in screens:
        if s.get('status') in ('dropped', 'collision', 'deferred') or s.get('home') != f:
            continue
        if s['id'] not in got:
            # 拍板前过渡态（家已定、副本尚未迁入，如 sheetAddHabit）＝软提示，不算硬红
            warn.append(f"闸4(软) home 尚无此屏: 注册表称 {s['id']} 家在 {f}，动刀批须并入")
for s in screens:
    if s.get('home') and not os.path.exists(os.path.join(mdir, s['home'])):
        red.append(f"闸4 家文件不存在: {s['home']}# {s['id']}")

# 闸2：注册表↔代码
for m in reg['modules']:
    mid, st, dev = m['id'], m.get('status'), m.get('dev')
    if mid == 'shell':
        continue  # 壳无独立 features 目录（在 lib/core 与 lib/app 等）
    feat = os.path.exists(os.path.join('lib', 'features', mid))
    if st == 'current' and dev == 'delivered' and not feat:
        red.append(f"闸2 现行已交付模块无代码目录: lib/features/{mid}")
    if st == 'dropped':
        if feat:
            red.append(f"闸2 已作废模块残留代码: lib/features/{mid}")
        if m.get('file') and m['file'] not in frozen:
            red.append(f"闸2 已作废模块仍挂现行原型: {m['file']}")

# 闸4：别名非空
for m in reg['modules']:
    if not m.get('aliases'):
        red.append(f"闸4 别名空: 模块 {m['id']}")

# 闸5 语法闸（2026-10-12 事故补死）：每份现行原型的全部内联 <script> 过 node vm.Script。
# emoji 批实锤＝宫格 SVG 被写成裸标签（token 级语法错），块级 hash 自证（registry/doclint）
# 不查 JS 语法＝假绿漏过；本闸挂进 protogate 常驻，doclint 每跑必带。
vmck = subprocess.run(['node', os.path.join(ROOT, 'tools', 'vm_script_check.js'), mdir] + active_files,
                      capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
for line in (vmck.stdout or '').splitlines():
    if line.startswith('RED:'):
        red.append(line[4:])
    elif line.strip():
        print(line)
if vmck.returncode != 0:
    red.append(f"闸5 工装异常: vm_script_check exit {vmck.returncode} {(vmck.stderr or '').strip()[:120]}")

# 锚点存在性（§3-4）：docs 里 prototype/x.html#id 深链必须能落地（文件含该 id，或重定向表覆盖，或基 id＋_子段）
probe = mdir != 'prototype'
redoc = [] if probe else subprocess.run(['git', '-c', 'core.quotepath=off', 'ls-files', 'docs'], capture_output=True, text=True, encoding='utf-8').stdout.splitlines()
redirect_from = {r['from'] for r in reg.get('redirects', [])}
anchor_red = 0
for p in redoc:
    if not p.endswith('.md') or p.startswith(('docs/archive/', 'docs/预研/')):
        continue
    txt = open(p, encoding='utf-8', errors='replace').read()
    for m in re.finditer(r'prototype/([\w.-]+\.html)#([\w-]+)', txt):
        fn, anc = m.group(1), m.group(2)
        ok = anc in redirect_from or (fn + '#' + anc) in redirect_from
        if not ok:
            fp = os.path.join(mdir, fn)
            if os.path.exists(fp):
                ids = ids_in(fn)
                base = anc.split('_')[0]
                ok = anc in ids or base in ids or any(i == base for i in ids)
        if not ok:
            anchor_red += 1
            (red if mode == 'strict' else warn).append(f"锚点断链: {p} -> prototype/{fn}#{anc}")
print(f"锚点检查：断链 {anchor_red} 处")
label = '红灯' if mode == 'strict' else '报告（report 模式不拦）'

lst = red if mode == 'strict' else red + warn
print(f"protogate[{mode}] 现行 {len(active_files)} 份原型 · {len(screens)} 屏登记 · 违例 {len(lst)}（硬红 {len(red)}）")
if lst:
    print(f"{label} 明细（前 40）:")
    for x in lst[:40]:
        print('  ' + x)
    if len(lst) > 40:
        print(f'  … 另有 {len(lst)-40} 条')
if mode == 'strict' and red:
    sys.exit(1)
if mode == 'strict':
    print('PASS strict 全绿')
