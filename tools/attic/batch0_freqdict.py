# -*- coding: utf-8 -*-
"""批0 · 通用高频词表生成（X-Ray 词条质量治理计划 §3 · 一次性脚本入 attic）。

口径（docs/X-Ray词条质量治理计划-20261002.md）：
- 源 = jieba dict.txt（tuna PyPI 镜像取包），列：词 频次 词性；
- 只留 2~4 字纯汉字、词性非实体向（排除 nr/nrt/nrfg 人名、ns 地名、nt 机构名、
  j 缩略、x 串）——实体向词有自己的通道（gazetteer/正则/称谓），进噪声表会误杀；
- 减法防误伤：扣除既有八张词表全部词 + 引擎 GT 用例断言为实体的守护名单；
- 频次降序取 top 8000 追加进 common_nouns.txt（`#` 注释头，parse 跳注释）；
- 快照先行动：目标文件先拷 tools/attic/，命中断言（六词在场）+ 体积校验（<200KB）。
"""
import io
import os
import re
import shutil
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..'))
DICT_DIR = os.path.join(ROOT, 'assets', 'xray', 'dicts')
TARGET = os.path.join(DICT_DIR, 'common_nouns.txt')
SNAP = os.path.join(ROOT, 'tools', 'attic', 'common_nouns.bak-20261002-batch0.txt')
TMP = os.path.join(ROOT, 'tools', 'attic', '_jieba_dl')
TUNA = 'https://pypi.tuna.tsinghua.edu.cn/simple'

TOP_N = 8000
CJK = re.compile(r'^[\u4e00-\u9fa5]+$')
# 实体向与不可靠词性：人名(nr/nrt/nrfg)·地名(ns)·机构(nt)·缩略(j)·串(x)
EXCLUDE_POS = {'nr', 'nrt', 'nrfg', 'ns', 'nt', 'j', 'x'}
# 引擎 GT 断言为实体的守护名单（防频率表误杀，人工核对 xray_engine_test.dart）
GUARD = {
    '查尔斯·布朗', '查尔斯', '布朗', '李伟', '赵强', '李伟探长', '船长莫尔温',
    '莫尔温', '河北省', '地中海', '恒信公司', '人类简史', '革命火种', '革命',
    '罕见合金', '李德', '伦敦',
}


def read_words(path):
    out = set()
    with io.open(path, 'r', encoding='utf-8') as f:
        for line in f:
            t = line.strip()
            if t and not t.startswith('#'):
                out.add(t)
    return out


def fetch_jieba_dict():
    import subprocess
    import sys
    subprocess.check_call([sys.executable, '-m', 'pip', 'download', 'jieba',
                           '--no-deps', '-d', TMP, '--index-url', TUNA, '-q'])
    whl = [os.path.join(TMP, n) for n in os.listdir(TMP)
           if n.endswith(('.whl', '.zip', '.tar.gz'))][0]
    if whl.endswith('.tar.gz'):
        import tarfile
        with tarfile.open(whl, 'r:gz') as z:
            name = [n for n in z.getnames() if n.endswith('dict.txt')][0]
            f = z.extractfile(name)
            return f.read().decode('utf-8')
    with zipfile.ZipFile(whl) as z:
        name = [n for n in z.namelist() if n.endswith('dict.txt')][0]
        with z.open(name) as f:
            return f.read().decode('utf-8')


def main():
    existing = set()
    for n in ('func_words', 'common_nouns', 'titles', 'surnames', 'loc_suffix',
              'org_suffix', 'stop_en', 'gazetteer'):
        existing |= read_words(os.path.join(DICT_DIR, n + '.txt'))
    existing |= GUARD
    print('既有八表+守护词数: %d' % len(existing))

    text = fetch_jieba_dict()
    picked = []
    for line in text.splitlines():
        parts = line.strip().split(' ')
        if len(parts) < 2:
            continue
        w, freq = parts[0], parts[1]
        pos = parts[2] if len(parts) > 2 else ''
        if not (2 <= len(w) <= 4) or not CJK.match(w):
            continue
        if pos in EXCLUDE_POS:
            continue
        if w in existing:
            continue
        picked.append((int(freq), w))
    picked.sort(key=lambda x: -x[0])
    words, seen = [], set()
    for _, w in picked:
        if w not in seen:
            seen.add(w)
            words.append(w)
        if len(words) >= TOP_N:
            break
    assert len(words) == TOP_N, '词量不足: %d' % len(words)
    for must in ('几乎', '概念', '造成', '种种', '信仰', '原本'):
        assert must in words, '真机榜首词 %s 未入表' % must

    shutil.copyfile(TARGET, SNAP)
    body = ''.join(w + '\n' for w in words)
    header = ('\n# ==== 批0 通用高频词表 · jieba dict.txt 频次 top%d · '
              '扣除 nr/ns/nt/j/x 与既有八表+GT 守护名单 · 2026-10-02 ====\n'
              % len(words))
    with io.open(TARGET, 'a', encoding='utf-8', newline='\n') as f:
        f.write(header + body)
    size = os.path.getsize(TARGET)
    assert size < 200 * 1024, '体积超预算: %d bytes' % size
    print('追加 %d 词, 文件 %d bytes, 快照 %s' % (len(words), size, SNAP))


if __name__ == '__main__':
    main()
