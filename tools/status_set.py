#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""tools/status_set.py — `docs/STATUS.md` 的体量守护与字段级读写工装（2026-10-08 治理批立）。

为什么要有它：STATUS 表头曾是一行超长行（瘦身前单行 7,960 字符、全文 94,528 字节），
每轮收尾只把「本批＝」标签下移一格、正文照抄不删，而行数预算（≤60 行）看不见这种滚存。
本工装把口径变成机器闸＋命令：批次叙事只许「本批／上一批」两级，各字段独占一行、
正文 ≤400 字符（细节留 `docs/handoff/` 工单），单行 ≤1200 字符，全文 ≤14,336 字节
（2026-10-14 棘轮：16,384 → 14,336＝首次瘦身后实测 12,304 × 1.15 取整，只降不升；
 口径＝`AGENTS.md`「文档体量治理」，黄线＝上限 90%）。

用法：
  python tools/status_set.py --check                 # 体量三检（doclint 守护七随跑，红灯 exit 1）
  python tools/status_set.py --fields                # 列出字段骨架（名·正文长·行号）
  python tools/status_set.py --get 本批               # 打印该字段正文（按锚点取段，不通读）
  python tools/status_set.py --set 本批 --text-file f # 整字段替换（f＝UTF-8 文本文件或 '-' 走 stdin）
  python tools/status_set.py --rotate                # 轮转：本批正文→上一批，本批改「（待填）」

护栏（超限一律红灯 exit 1，确需放行用 --force 并在工单写理由）：
  ① 字段正文 > MAX_FIELD_CHARS  ② 任一字段行 > MAX_LINE_CHARS  ③ 出现 本批／上一批 之外的第三级
  ④ 字段重名  ⑤ 全文字节 > MAX_FILE_BYTES  ⑥ --set／--rotate 后行数变化（本工装只改字段行，不动结构）
"""
import argparse, io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, 'docs', 'STATUS.md')

MAX_FIELD_CHARS = 400
MAX_LINE_CHARS = 1200
MAX_FILE_BYTES = 10752              # 10.5 KiB（2026-10-16 治理五轮 T1 再下调：瘦身后实测 9,721 × 1.10 取整；黄线＝9,677。**规则二＝默认面＋收窄，放宽须人审并写理由，禁止单向放宽**）
LEVELS = ['\u672c\u6279', '\u4e0a\u4e00\u6279']          # 本批 / 上一批（只许两级）
FIELD_RE = re.compile(r'^- \*\*([^*\n]{2,10})\uff1d\*\* ?(.*)$')


def read():
    return io.open(PATH, 'r', encoding='utf-8', newline='').read()


def write(s):
    io.open(PATH, 'w', encoding='utf-8', newline='').write(s)


def fields(lines):
    """返回 [(行号0基, 字段名, 正文)]，只认独占一行的「- **名＝** 正文」。"""
    out = []
    for i, l in enumerate(lines):
        m = FIELD_RE.match(l)
        if m:
            out.append((i, m.group(1), m.group(2)))
    return out


def check(text):
    """体量三检，返回红灯列表（空＝绿）。"""
    reds = []
    lines = text.split('\n')
    for i, l in enumerate(lines, 1):
        if len(l) > MAX_LINE_CHARS:
            reds.append('单行超长：L%d %d 字符 > %d（历史叙事请沉 docs/archive/）'
                        % (i, len(l), MAX_LINE_CHARS))
    nb = len(text.encode('utf-8'))
    if nb > MAX_FILE_BYTES:
        reds.append('全文体积：%d 字节 > %d（追加式写法已复发，请瘦身沉档）' % (nb, MAX_FILE_BYTES))
    fs = fields(lines)
    names = [n for _, n, _ in fs]
    if len(names) != len(set(names)):
        reds.append('字段重名（级数失控）：%s' % names)
    for n in names:
        if n not in LEVELS:
            reds.append('批次叙事出现第三级「%s」：只许 %s，更早历史沉 docs/archive/ 与 交接文档 变更日志'
                        % (n, '/'.join(LEVELS)))
    for _, n, body in fs:
        if len(body) > MAX_FIELD_CHARS:
            reds.append('字段「%s」正文 %d 字符 > %d：细节留工单，STATUS 只写一行结论＋指针'
                        % (n, len(body), MAX_FIELD_CHARS))
    if not fs:
        reds.append('STATUS 无「%s」字段行（格式＝`- **本批＝** 正文`）' % '/'.join(LEVELS))
    nl = len(lines) - (1 if lines and lines[-1] == '' else 0)
    if nl > 60:
        reds.append('行数 %d > 预算 60' % nl)
    return reds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--fields', action='store_true')
    ap.add_argument('--get', metavar='NAME')
    ap.add_argument('--set', metavar='NAME')
    ap.add_argument('--text-file', metavar='PATH')
    ap.add_argument('--rotate', action='store_true')
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()

    text = read()
    lines = text.split('\n')
    fs = fields(lines)

    if a.check:
        reds = check(text)
        if reds:
            print('STATUS 体量红灯 %d 处:' % len(reds))
            for r in reds:
                print('  ' + r)
            return 1
        print('STATUS 体量绿（%d 字节·%d 行·单行≤%d·字段两级·正文≤%d）'
              % (len(text.encode('utf-8')), len(lines) - 1, MAX_LINE_CHARS, MAX_FIELD_CHARS))
        return 0

    if a.fields or (not a.get and not a.set and not a.rotate):
        print('字段 %d 个（全文 %d 字节 / %d 行）:'
              % (len(fs), len(text.encode('utf-8')), len(lines) - 1))
        for i, n, body in fs:
            print('  L%-4d %-8s len=%-4d %s' % (i + 1, n, len(body), body[:48]))
        return 0

    if a.get:
        hit = [f for f in fs if f[1] == a.get]
        if not hit:
            print('红灯：无字段「%s」（--fields 看骨架）' % a.get)
            return 1
        print(hit[0][2])
        return 0

    if a.rotate:
        idx = {n: i for i, n, _ in fs}
        if '\u672c\u6279' not in idx:
            print('红灯：无「本批」字段，不轮转')
            return 1
        cur = [f for f in fs if f[1] == '\u672c\u6279'][0]
        lines[cur[0]] = '- **\u4e0a\u4e00\u6279\uff1d** ' + cur[2]
        nxt = [f for f in fs if f[1] == '\u4e0a\u4e00\u6279']
        if nxt and nxt[0][0] != cur[0]:
            lines[nxt[0][0]] = '- **\u672c\u6279\uff1d** \uff08\u5f85\u586b\uff09'
        new = '\n'.join(lines)
        reds = check(new)
        if reds and not a.force:
            print('红灯（轮转后超限）:\n  ' + '\n  '.join(reds))
            return 1
        write(new)
        print('OK 轮转完成：原「本批」正文（%d 字符）→「上一批」；「本批」置（待填）' % len(cur[2]))
        return 0

    # --set
    if a.set not in LEVELS:
        print('红灯：只允许替换 %s；更早历史应沉 docs/archive/ 与 交接文档 变更日志'
              % '/'.join(LEVELS))
        return 1
    hit = [f for f in fs if f[1] == a.set]
    if not hit:
        print('红灯：无字段「%s」（--fields 看骨架）' % a.set)
        return 1
    if not a.text_file:
        print('红灯：--set 需要 --text-file <路径|->')
        return 1
    body = sys.stdin.read() if a.text_file == '-' else io.open(
        a.text_file, encoding='utf-8').read()
    body = ' '.join(body.split())                       # 压成一行（字段行不许折行）
    body = body.strip().rstrip('\uff1b;').strip()
    lines[hit[0][0]] = '- **%s\uff1d** %s' % (a.set, body)
    new = '\n'.join(lines)
    reds = check(new)
    if reds and not a.force:
        print('红灯:\n  ' + '\n  '.join(reds))
        print('细节留工单（docs/handoff/*.md 落地记录），STATUS 只写一行结论＋指针；'
              '确需超限用 --force 并在工单写理由')
        return 1
    write(new)
    print('OK 字段「%s」正文 %d\u2192%d 字符；全文 %d 字节%s'
          % (a.set, len(hit[0][2]), len(body), len(new.encode('utf-8')),
             '（--force 放行超限）' if reds else ''))
    return 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.exit(main())
