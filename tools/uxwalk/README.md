# tools/uxwalk — 真机语义树采集与返回栈探针（UX 审计工装）

来源＝2026-10-05 六轮 UX 审计（工单 `docs/handoff/交棒话术-20261005-UX审计真机批-贴底行吞点击与工装转正.md` U7）。
产物一律落 `tmp/uxwalk/`（gitignored）；无障碍服务依赖机上既有 SelectToSpeak（gkd 自带），脚本不改设备设置。

## 组成

| 文件 | 用途 |
|---|---|
| `walk_all.sh` | 逐屏采集驱动：按 `routes.tsv`（id<TAB>到达regex<TAB>steps）冷启动复位→语义锚点导航→语义树+截图落盘；已采屏自动跳过（节点数≥8 判有效）。steps 语法：`tab:` `tile:` `row:` `back:` `raw:x,y` `scroll` `scroll2`。**状态＝转正待修**：6070 量产原版可用（在 `%TEMP%/lhwalk/`），本版冒烟两条宫格路由落位抖动（滚动位置×磁贴可见性重试仍不足）；使用前必须按下方自证定式先跑通，或参考 back_probe 的 open_tile 重试逻辑再修 |
| `back_probe.sh` | 返回栈探针：进屏→单次系统返回→判 `EXIT-APP` / `OK→父页` / `LANDS-WRONG` / `NO-ARRIVE`；用例＝文末 probe 行（id<TAB>父页regex<TAB>steps），按当轮目标增删。到达铁证＝push 页必有 `content-desc="Back"` 节点。**状态＝已双向自证**（t-report OK→父页 ✓；t-ledgermain EXIT-APP ✓ 复现宫格退出） |
| `tile_back_probe.sh` | **宫格磁贴→一次返回落点探针**（2026-10-06 批1 转正；`ANDROID_SERIAL=ea028260 bash tools/uxwalk/tile_back_probe.sh [磁贴名...]`）。每例冷启动复位→确认在今天页→滚动找磁贴（尾锚 `⏎名称`）→点→验到达→`keyevent 4`→判 `OK→今天`/`EXIT-APP`/`LANDS-WRONG`/`NOT-ON-DASH`/`NO-ARRIVE`。**U2 的验收判据就用它跑**（默认七条＝记账 日子 目标 物品 习惯 呵护 阅读） |
| `bottom_row_probe.sh` | **贴底行吞点击对照探针**（同期转正）。进「我的」→打印行清单与底栏顶边→点**中部行**（对照）→点**贴底行**→上滑一格再点同一条。只有「中部可点＋贴底点不动＋上滑后可点」三条同时成立才算 U1 现象坐实；单点一条就下结论会踩坑 ⑦ |
| `uxrows.js` | 上面两条共用语义树读取器：`rows`（y1 y2 标签）/`navtop`（底栏顶边，取 tab 节点 y1 **最大值**——页面标题也可能叫「我的」）/`at <标签>`（等值优先，回落「以该词结尾」取最靠下一枚）/`inc <片段>`/`lowest <navtop>`/`gap <navtop>`/`sig` |
| `analyze.py` | 离线分析 `tmp/uxwalk/*.xml`：逐屏 emoji 朗读流命中、教学句式、V1.x 泄漏、<44dp 可点节点、无标签可点节点、空采集标记；输出矩阵 txt/json 到指定目录 |
| `routes_template.tsv` / `back_probe_template.tsv` | 6070 轮实测过的屏表/用例表模板（含宫格 7 连退出与贴底行吞点击两组既有结论） |

## 自证定式（红灯比脚本更早信任，八坑实录）

1. **量产前双向自证**：先跑一条已知 OK 用例与一条已知 BAD 用例，双向符合预期才准跑全量。
2. 已知四坑（全部踩过）：① bash 循环内 `adb shell` 吃 stdin → 读表用 fd3；② `dumpsys | grep -m1` 撞 broken pipe 读空 **≠** 退出 app，focus 判定必须三次重试、unknown 不判 EXIT；③ MSYS `/tmp` 与 node 的 `C:\tmp` 是两个世界，传 node 的路径必须 `cygpath -w`；④ 语义标签 `content-desc+text` 拼接有尾随空格，`^X$` 锚定前先 trim；带角标的底栏 desc 是「2⏎待办」，等值匹配必失配（用 `endsWith && y>2400`）。
3. **uiautomator bounds 不是热区证据**（Flutter 命中区可大于语义边界）：小尺寸命中只作线索，定性必须真机 tap 复核。
4. Read 工具展示的截图是缩放的，一切坐标按 PNG 原始像素（1200×2670）。
5. **宫格磁贴在语义树里是「emoji⏎名称」合并节点**（`💰&#10;记账`），所以 `^记账` 这类**头锚永远匹配不到磁贴**；找磁贴要用尾锚或「含 `&#10;` 前缀」的形状（`tile_back_probe.sh` 用 `⏎名称$`）。反过来，底栏 tab 是独立节点（等值匹配），带角标时变 `2&#10;待办`（等值失配，取「以该词结尾且最靠下」那枚）。
6. **adb dump 出来的标签里换行是 `&#10;` 实体不是真空白**，emoji 是 `&#128176;` 数字实体；`\s` 类正则匹配不到它们，判「页面身份」的正则要按实体文本写。
7. **贴底行判定必须带对照**：单看「最底下一行点了没反应」不算证据——语义节点边界与 Flutter 命中区不是一回事（本轮实测：贴底行**文字区** y2370/2400 无效、行下部 y2430/2450 有效）。要同时给出「同屏中部行可点」＋「同一条上滑一格后可点」两条对照才算坐实。
8. **widget 测试的字体是 1em 方块**：窄视口跑全 app 用例会虚报「横向溢出 N 像素」（`¥ 0.00` 被放大），真机 Inter/Noto 下并不溢出——别跟着这种红去改布局（本批差点误改今天页成本卡）。

> 结论修正记录（两条都记着，别再抄错）：6070 轮「宫格 7/7 EXIT-APP」**观察是真的**（6071/6072 两轮复现，侧滑手势与注入 keyevent 同现象）。但工单 §1 当时的根因「`context.go` 断历史」**不成立**（`shellBackAction` 三分支本就与拍板一致）；本会话加的第二个假设「清单缺 `android:enableOnBackInvokedCallback`」**也被 6072 否证**（`aapt2 dump xmltree` 已核属性在 `<application>` 上，一次返回仍退 app）。**已证的只有一条**：`tile_back_probe` 之外另跑的 push 路由对照（记账→统计报表 `/ledger/report`）返回正常弹回、留在 app ⇒ 返回确实进了 Dart，差异缩到「壳层根路由的 `PopScope(canPop:false)` 拦不住系统默认动作」这一格；下一步＝`onPopInvokedWithResult` 里留一行痕装机看「进没进回调」，别再靠猜下结论。详见工单 §4「真机门结果」。
