# tools/attic/xr_release_docs.py — v0.2.6-xray-impl 发版登记（头部状态行 + 下一站四红挂账）
import io

CRLF = chr(13) + chr(10)


def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    crlf = CRLF in s

    def n(x):
        return x.replace(chr(10), CRLF) if crlf else x

    for a, b in pairs:
        a, b = n(a), n(b)
        assert s.count(a) == 1, (p, a[:50].encode('unicode_escape'), s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


p = 'docs/交接文档.md'
s, crlf = load = None, None
s = io.open(p, encoding='utf-8', newline='').read()
crlf = CRLF in s
patch(p, [
    ("""| 事项 | 状态 |""",
     """| 事项 | 状态 |"""),  # no-op guard anchor safety
])

# 头部「最近更新」行与「当前 HEAD」段推进为已推送+已发预发布
s = io.open(p, encoding='utf-8', newline='').read()


def rep2(a, b):
    global s
    aa = a.replace(chr(10), CRLF) if CRLF in s else a
    bb = b.replace(chr(10), CRLF) if CRLF in s else b
    assert s.count(aa) == 1, (aa[:60].encode('unicode_escape'), s.count(aa))
    s = s.replace(aa, bb)


rep2(
    '批A 面板骨架与跳转已交付 `6e9c520` · **批B 自学习已交付 `7ea9c52`**（F8+F6·16 例）· **批C 复用与备份已交付 `621d9f6`**（F9/F10+路径B核对）——**X-Ray 实现批 A/B/C 全部收口，真机批待合并执行**（本地未推）',
    '批A 面板骨架与跳转已交付 `6e9c520` · **批B 自学习已交付 `7ea9c52`**（F8+F6·16 例）· **批C 复用与备份已交付 `621d9f6`**（F9/F10+路径B核对）——**X-Ray 实现批 A/B/C 已收口并发预发布 `v0.2.6-xray-impl`（0.2.6+4038 · 钉版 `bdeca6b` · 双端挂三包 · GitHub 走 ssh-on-443）**；收口整改 `7793e7a` 清零 catch 守护 14 处')
rep2(
    '｜ 当前 HEAD：分支 `feat/m0-skeleton` tip（本会话链 `1a13b11..156e2fc` + 钉版 `f149c2e` 已全部推送双端：Gitee 与 GitHub 均到 `f149c2e`，tag `v0.2.5-open-xray` 双端在位；后续新提交仍需按流程请示推送）',
    '｜ 当前 HEAD：分支 `feat/m0-skeleton` tip（`cc47bf6` 起 8 提交已推送双端：Gitee 与 GitHub（ssh-on-443）均到 `bdeca6b`，tag `v0.2.6-xray-impl` 双端在位并各挂三包 APK 201；工作区并行会话在飞文件仍未提交、归属各自批次）')
rep2(
    '> **下一站**：**X-Ray 真机批合并执行**（⑥ 打开方式两态 + V1.53.4①~⑤ 选区复验 + R14 走查积压 + X-Ray 重点：当前页分组/剧透开关/跳转段高亮/500 词条面板流畅/阿加莎大书内存曲线·真机逐屏验收清单届时新开）；批A/B/C 实现链 `6e9c520`/`7ea9c52`/`621d9f6` 全部本地未推·**推送与预发布需用户点头**。',
    '> **下一站**：**X-Ray 真机批合并执行**（⑥ 打开方式两态 + V1.53.4①~⑤ 选区复验 + R14 走查积压 + X-Ray 重点：当前页分组/剧透开关/跳转段高亮/500 词条面板流畅/阿加莎大书内存曲线·真机逐屏验收清单届时新开）· **存量四红挂账**（在发版基线 `f149c2e` 同样复现、非 X-Ray 批引入）：`ai_core_test`「提示词包 11→12 能力点」计数漂移、`read_data_test` 5-5 本月摘录（种子 `DateTime(2026,9,22)` 写死月份＝时间炸弹）、`habit_backfill_page_test` 两条跨月边界——归各批次会话或另立修单，正式版门禁前必须清零。')

io.open(p, 'w', encoding='utf-8', newline='').write(s)

# 变更日志表末补发版登记行
s2 = io.open(p, encoding='utf-8', newline='').read()
lines = s2.split(CRLF if CRLF in s2 else chr(10))
i = [n for n, l in enumerate(lines)
     if l.startswith('| 2026-10-01 | **X-Ray 实现批C')][0]
row = ('| 2026-10-01 | **预发布 `v0.2.6-xray-impl`（0.2.6+4038 · DB v32）双端挂三包** | '
       '钉版提交 `bdeca6b`（批A `6e9c520`/批B `7ea9c52`/批C `621d9f6`/catch 守护整改 `7793e7a` 之上的版本钉）；'
       '发版 worktree `lh-relbdeca6b` 从自己提交构建（全新出包 373s·三包 arm64 35.7MB/x86_64 38.3MB/armeabi 32.9MB·versionCode 6038/8038/5038 分包形态·aapt 核 INTERNET 在位）；'
       'worktree 干净链全量 1883 过/4 红（**4 红在 `f149c2e` 基线同样复现＝存量**：提示词包计数/本月摘录时间炸弹/习惯补卡跨月×2·已挂账下一站）；'
       '推送：Gitee 分支+tag 直推、GitHub https 重置→`ssh://git@ssh.github.com:443` 成功；gh（`C:\\Program Files\\GitHub CLI` 不在 PATH）建 release+三资产；Gitee 条目 CLI 建、`attach_files` API 三包 201、两端逐字节对齐（37474094/40161065/34539936）。 | '
       'pubspec.yaml, docs/交接文档.md, tools/attic/release-notes-v0.2.6-xray-impl.md |')
lines.insert(i + 1, row)
io.open(p, 'w', encoding='utf-8', newline='').write(
    (CRLF if CRLF in s2 else chr(10)).join(lines))
print('release docs ok')
