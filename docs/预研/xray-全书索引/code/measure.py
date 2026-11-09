# -*- coding: utf-8 -*-
"""计量 demo 抽取核的资源画像：term 计数表规模、进程峰值内存、分段耗时、索引产物大小。"""
import os, sys, json, time, ctypes, ctypes.wintypes, hashlib

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import xray_extract as X

class MEMORYSTATUCTEX(ctypes.Structure):
    _fields_ = [("cb", ctypes.wintypes.DWORD), ("PageFaultCount", ctypes.wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]

def _mem():
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.GetCurrentProcess.restype = ctypes.c_void_p
    fn = k32.K32GetProcessMemoryInfo
    fn.restype = ctypes.wintypes.BOOL
    fn.argtypes = [ctypes.c_void_p, ctypes.POINTER(MEMORYSTATUCTEX), ctypes.wintypes.DWORD]
    m = MEMORYSTATUCTEX(); m.cb = ctypes.sizeof(m)
    if not fn(k32.GetCurrentProcess(), ctypes.byref(m), m.cb):
        return -1, -1
    return m.PeakWorkingSetSize / 1048576.0, m.WorkingSetSize / 1048576.0

def peak_mb():
    return _mem()[0]

only = sys.argv[1] if len(sys.argv) > 1 else None
for path, slug in [
    ("C:/Users/chist/Downloads/人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "sapiens"),
    ("C:/Users/chist/Downloads/阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "agatha85"),
]:
    if only and slug != only:
        continue
    t0 = time.time()
    md5 = hashlib.md5(open(path, "rb").read()).hexdigest()
    t_md5 = time.time() - t0
    t1 = time.time()
    meta, chapters, toc = X.load_epub(path)
    t_load = time.time() - t1
    pk1, cur1 = _mem()
    chars = sum(len(p) for ch in chapters for p in ch["paras"])
    t2 = time.time()
    limit = 4_000_000 if chars > 8_000_000 else chars + 1
    hits, MIN = X.extract(meta, chapters, toc, chars, limit)
    t_ext = time.time() - t2
    pk2, cur2 = _mem()
    # term 计数表规模
    nterms = sum(1 for (name, tp) in hits if tp == "term")
    total_mentions = sum(h["n"] for h in hits.values())
    out = os.path.join(BASE, "out", f"xray_{slug}.json")
    jsize = os.path.getsize(out) if os.path.exists(out) else 0
    print(f"[{slug}] md5={t_md5:.2f}s load={t_load:.1f}s extract={t_ext:.1f}s chars={chars/1e6:.1f}M "
          f"terms_counter={nterms} total_hits={total_mentions} json={jsize/1024:.0f}KB "
          f"mem_after_load={cur1:.0f}MB mem_after_extract={cur2:.0f}MB peak={pk2:.0f}MB", flush=True)
