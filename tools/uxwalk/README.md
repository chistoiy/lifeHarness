# tools/uxwalk — 真机语义树采集与返回栈探针（UX 审计工装）

来源＝2026-10-05 六轮 UX 审计（工单 `docs/handoff/交棒话术-20261005-UX审计真机批-贴底行吞点击与工装转正.md` U7）。
产物一律落 `tmp/uxwalk/`（gitignored）；无障碍服务依赖机上既有 SelectToSpeak（gkd 自带），脚本不改设备设置。

## 组成

| 文件 | 用途 |
|---|---|
| `walk_all.sh` | 逐屏采集驱动：按 `routes.tsv`（id<TAB>到达regex<TAB>steps）冷启动复位→语义锚点导航→语义树+截图落盘；已采屏自动跳过（节点数≥8 判有效）。steps 语法：`tab:` `tile:` `row:` `back:` `raw:x,y` `scroll` `scroll2`。**状态＝转正待修**：6070 量产原版可用（在 `%TEMP%/lhwalk/`），本版冒烟两条宫格路由落位抖动（滚动位置×磁贴可见性重试仍不足）；使用前必须按下方自证定式先跑通，或参考 back_probe 的 open_tile 重试逻辑再修 |
| `back_probe.sh` | 返回栈探针：进屏→单次系统返回→判 `EXIT-APP` / `OK→父页` / `LANDS-WRONG` / `NO-ARRIVE`；用例＝文末 probe 行（id<TAB>父页regex<TAB>steps），按当轮目标增删。到达铁证＝push 页必有 `content-desc="Back"` 节点。**状态＝已双向自证**（t-report OK→父页 ✓；t-ledgermain EXIT-APP ✓ 复现宫格退出） |
| `analyze.py` | 离线分析 `tmp/uxwalk/*.xml`：逐屏 emoji 朗读流命中、教学句式、V1.x 泄漏、<44dp 可点节点、无标签可点节点、空采集标记；输出矩阵 txt/json 到指定目录 |
| `routes_template.tsv` / `back_probe_template.tsv` | 6070 轮实测过的屏表/用例表模板（含宫格 7 连退出与贴底行吞点击两组既有结论） |

## 自证定式（红灯比脚本更早信任，四坑实录）

1. **量产前双向自证**：先跑一条已知 OK 用例与一条已知 BAD 用例，双向符合预期才准跑全量。
2. 已知四坑（全部踩过）：① bash 循环内 `adb shell` 吃 stdin → 读表用 fd3；② `dumpsys | grep -m1` 撞 broken pipe 读空 **≠** 退出 app，focus 判定必须三次重试、unknown 不判 EXIT；③ MSYS `/tmp` 与 node 的 `C:\tmp` 是两个世界，传 node 的路径必须 `cygpath -w`；④ 语义标签 `content-desc+text` 拼接有尾随空格，`^X$` 锚定前先 trim；带角标的底栏 desc 是「2⏎待办」，等值匹配必失配（用 `endsWith && y>2400`）。
3. **uiautomator bounds 不是热区证据**（Flutter 命中区可大于语义边界）：小尺寸命中只作线索，定性必须真机 tap 复核。
4. Read 工具展示的截图是缩放的，一切坐标按 PNG 原始像素（1200×2670）。
