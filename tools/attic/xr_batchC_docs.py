# tools/attic/xr_batchC_docs.py — 批C + 实现批收口文档同步
import io

CRLF = chr(13) + chr(10)


def load(p):
    s = io.open(p, encoding='utf-8', newline='').read()
    return s, CRLF in s


def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def rep(s, crlf, a, b):
    a = a.replace(chr(10), CRLF) if crlf else a
    b = b.replace(chr(10), CRLF) if crlf else b
    assert s.count(a) == 1, (a[:50].encode('unicode_escape'), s.count(a))
    return s.replace(a, b)


p = 'docs/交接文档.md'
s, crlf = load(p)
s = rep(
    s, crlf,
    '· **批B 自学习已交付 `7ea9c52`**（F8 加词/移除/合并/建议回流 + F6 选区动作·xray_panel_test 16 例·本地未推）**',
    '· **批B 自学习已交付 `7ea9c52`**（F8+F6·16 例）· **批C 复用与备份已交付 `621d9f6`**（F9/F10+路径B核对）——**X-Ray 实现批 A/B/C 全部收口，真机批待合并执行**（本地未推）')
s = rep(
    s, crlf,
    '> **下一站**：**X-Ray 实现批 C（复用与备份 F9/F10）→ 真机批合并执行**（批A `6e9c520`：双段面板/调度/跳转；批B `7ea9c52`：写时物化 加词补扫/移除/合并/建议卡 + 选区「X-Ray」动作与迷你卡 + 整理模式底栏；批C 口径见 `docs/交棒话术-20261001-XRay实现批.md`）',
    '> **下一站**：**X-Ray 真机批合并执行**（⑥ 打开方式两态 + V1.53.4①~⑤ 选区复验 + R14 走查积压 + X-Ray 重点：当前页分组/剧透开关/跳转段高亮/500 词条面板流畅/阿加莎大书内存曲线·真机逐屏验收清单届时新开）；批A/B/C 实现链 `6e9c520`/`7ea9c52`/`621d9f6` 全部本地未推·**推送与预发布需用户点头**。')
row = ('| 2026-10-01 | **X-Ray 实现批C：复用与备份 · A/B/C 实现批收口（F9/F10 · 本地未推 `621d9f6`）** '
       'F9：commit 指纹落库后同 MD5 且已有任务 → `EpubImportService.lastReuseHits`，导入向导与 ⑥ 打开方式双入口提示「同文件索引已直接复用」（md5 归属＝零复制继承含用户整理）；'
       'F10：DAO `exportBundle/importBundle`（按 md5 分册·状态与 GLOBAL 词典原样随行；逐册 MD5 一致性校验，拼改册拒收；导入旧→新 id 重映射锚点）+ `XrayBackupService`（SAF 另存为/选文件钩子可替换）+ 阅读设置-数据「X-Ray 索引备份」行 → sheetXrBak 半屏（导出计数/导入覆盖确认）；'
       '§13 路径B核对用例：备份器 sqlite_master 动态枚举 + 排除组源码点名 xray 表即红。xray_backup_test 4 例；批内增量 56+20 全绿·analyze 零 error/warning·arch/size_budget 绿。'
       '至此 X-Ray 实现批 A（面板与跳转 `6e9c520`）/ B（自学习 `7ea9c52`）/ C（复用备份 `621d9f6`）全部交付，剩真机批合并执行与推送授权。 | '
       'lib/features/read/data/xray/{xray_dao,xray_backup}.dart, lib/features/read/data/epub_import.dart, lib/features/read/presentation/{read_providers,read_settings_page,open_with}.dart, '
       'lib/features/read/presentation/import/local_import_page.dart, lib/features/read/presentation/reader/reader_xray_learn_sheets.dart, test/xray_backup_test.dart, tools/attic/xr_batchC_*.py |')
lines = s.split(CRLF if crlf else chr(10))
i = [n for n, l in enumerate(lines)
     if l.startswith('| 2026-10-01 | **X-Ray 实现批B')][0]
lines.insert(i + 1, row)
save(p, (CRLF if crlf else chr(10)).join(lines))

p = 'docs/X-Ray全书索引开发设计说明书-20260928.md'
s, crlf = load(p)
s = rep(
    s, crlf,
    '余 批C 复用与备份；批B 自学习 **已交付 `7ea9c52`**：写时物化 加/删/合 + 补扫建议卡 + 选区 X-Ray 动作与迷你卡 + 整理模式）**',
    '批B 自学习 **已交付 `7ea9c52`**（写时物化 加/删/合 + 补扫建议卡 + 选区 X-Ray 动作与迷你卡 + 整理模式）· 批C 复用与备份 **已交付 `621d9f6`**（F9 复用提示 + F10 .xraybak 导出/导入 + §13 路径B核对）——**实现批 A/B/C 全部收口，剩真机批（批5）**）**')
save(p, s)

p = 'docs/需求清单.md'
s, crlf = load(p)
s = rep(
    s, crlf,
    '实现批进行中：批A `6e9c520`、批B `7ea9c52` 已交付，批C 待进）**',
    '实现批 A/B/C 已全量交付：`6e9c520`/`7ea9c52`/`621d9f6`，剩真机批）**')
s = rep(
    s, crlf,
    '批B 自学习已交付 `7ea9c52`（F8/F6）· 批C 复用备份待进**）',
    '批B 自学习已交付 `7ea9c52`（F8/F6）· 批C 复用与备份已交付 `621d9f6`（F9/F10）——**实现批收口，真机批与推送待发**）')
save(p, s)
print('docs ok')
