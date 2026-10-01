# tools/attic/xr_batchB_docs.py — 批B 文档同步（交接文档头部/下一站/变更日志行 · 设计书状态行 · 需求清单标注）
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
    '批A 面板骨架与跳转已交付 `6e9c520`（xray_panel_test 10 例·批内增量池全绿·本地未推）**',
    '批A 面板骨架与跳转已交付 `6e9c520` · **批B 自学习已交付 `7ea9c52`**（F8 加词/移除/合并/建议回流 + F6 选区动作·xray_panel_test 16 例·本地未推）**')
s = rep(
    s, crlf,
    '> **下一站**：**X-Ray 实现批 B（自学习）→ C（复用与备份）**（批A 已交付 `6e9c520`：上拉面板双段/头部三态/X-Ray 段与详情子页/F12 剧透保护/MD5 接线/调度器 isolate 乒乓协议/范围与失败半屏/三入口+书架四态角标/跳转段闪烁）',
    '> **下一站**：**X-Ray 实现批 C（复用与备份 F9/F10）→ 真机批合并执行**（批A `6e9c520`：双段面板/调度/跳转；批B `7ea9c52`：写时物化 加词补扫/移除/合并/建议卡 + 选区「X-Ray」动作与迷你卡 + 整理模式底栏；批C 口径见 `docs/交棒话术-20261001-XRay实现批.md`）')
row = ('| 2026-10-01 | **X-Ray 实现批B：自学习全链交付（F8/F6 · 本地未推 `7ea9c52`）** '
       'DAO 写时物化三件（同事务）：`markDeleted` 状态位+本书 forbid（可升 GLOBAL 黑名单）/ `mergeInto` mention 整批迁移+aliases 并名+n/chs/首锚点现算回写 / `registerUserWord`+`applyScanResult`；'
       '加词全书补扫走 `XrayWordScan`（worker 与测试假通道单实现）+ ≥30% 称谓形态回流建议卡（采纳→全局词库），调度器 `scanWord` 不落任务态；'
       '面板段头「＋加词｜整理词条」+ 整理底栏（合并≥2/移除≥1）+ 详情并词候选卡/合并进…/不再显示该词/AI 二期预留位（xrDetailHtml 尾段 1:1）；'
       'F6 选区工具条「X-Ray」名单驱动（kBrSelDefaultTools 8→9）：命中 peek 卡→「查看全部位置」接力直达详情，未命中接力预填加词弹层；'
       '体积：panel 超线按 extension part 拆 `reader_xray_panel_learn.dart`（纯搬移）；'
       '门禁：xray_panel_test 16 例 + reader_select 名单断言更新，批内增量池 90 全绿、analyze 零 error/warning。'
       '两坑过闸留档：守护正则 `tXray[A-Z]` 会撞驼峰名（`actXraySel` 改名过）；`scrollUntilVisible` 对 List-delegate ListView 触发 sliver 断言，长详情改垫高视口。 | '
       'lib/features/read/data/xray/{xray_dao,xray_scheduler}.dart, lib/features/read/presentation/reader/{reader_xray_panel*,reader_xray_learn_sheets,reader_xray_sheets,reader_sel_layer,reader_page,reader_xray}.dart, '
       'lib/features/read/presentation/read_providers.dart, test/xray_panel_test.dart, test/reader_select_test.dart, tools/attic/xr_batchB_*.py |')
lines = s.split(CRLF if crlf else chr(10))
i = [n for n, l in enumerate(lines) if l.startswith('| 2026-10-01 | **X-Ray 实现批A')][0]
lines.insert(i + 1, row)
s = (CRLF if crlf else chr(10)).join(lines)
save(p, s)

p = 'docs/X-Ray全书索引开发设计说明书-20260928.md'
s, crlf = load(p)
s = rep(
    s, crlf,
    '余 批B 自学习 / 批C 复用与备份）**',
    '余 批C 复用与备份；批B 自学习 **已交付 `7ea9c52`**：写时物化 加/删/合 + 补扫建议卡 + 选区 X-Ray 动作与迷你卡 + 整理模式）**')
save(p, s)

p = 'docs/需求清单.md'
s, crlf = load(p)
s = rep(
    s, crlf,
    '实现批进行中：批A 已交付 `6e9c520`，批B/C 待进）**',
    '实现批进行中：批A `6e9c520`、批B `7ea9c52` 已交付，批C 待进）**')
s = rep(
    s, crlf,
    '实现批A（面板与跳转）已交付 `6e9c520`（F1/F4/F5/F7+MD5 接线+调度器）· 批B 自学习/批C 复用备份待进**）',
    '实现批A（面板与跳转）已交付 `6e9c520`（F1/F4/F5/F7+MD5 接线+调度器）· 批B 自学习已交付 `7ea9c52`（F8/F6）· 批C 复用备份待进**）')
save(p, s)
print('docs ok')
