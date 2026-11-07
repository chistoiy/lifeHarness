# Legado 书源探针（仓库内证据快照）

这是预研探针的**只读快照**，用于留存决策证据。它**不属于 lifeHarness 构建**：不在 `lib/`、不在 `pubspec.yaml` 依赖链里，`flutter test` / `dart analyze` 均不扫它。
可执行的工作副本在项目外：`D:\dev_workplace\flutter_te\_lh_srcprobe\probe\`（含 `dl_real/` 产物、`qjs/` 引擎二进制、仿真站 `..\site\`）。

## 内容

| 文件 | 作用 |
|---|---||
| `probe/lib/legado_lite.dart` | Legado 规则子集引擎（1388 行）：搜索/详情/目录/正文四段、`ruleExplore`、`replaceRegex`/`extraFilter` 净化、`nextTocUrl`/`nextContentUrl` 翻页、chapterList 反转、JSON 通道、`@js:` 派发 |
| `probe/lib/jsbridge.dart` | `@js:` 桥：优先 qjs.exe、回落 node 子进程，注入 `java.*` / `cookie.*` |
| `probe/bin/probe.dart` | CLI：`subscribe` / `sources` / `search` / `allsearch` / `match` / `info` / `toc` / `chapter` / `discover` / `download` / `update` / `export` / `meta` / `pagcheck` / `cache` |
| `probe/bin/qjs_parity.mjs` | qjs 与 node 双引擎 8 条真实源 `@js` 片段一致性对照 |
| `probe/pubspec.yaml` | 依赖：`html` `xml` `http` `gbk_codec` `fast_gbk` `quickjs` `path`（Dart SDK ^3.10.8） |
| `biqumo_src.json` | 真站 biqumo.com（笔趣阁系）**现场手写纯规则源**，四段全通的主证 |
| `fake_source.json` | 本地仿真站源定义（规则受控验证用） |

## 运行方式

```bash
# 1) 起本地仿真站（在项目外）
cd /d/dev_workplace/flutter_te/_lh_srcprobe/site && node server.js   # :8123

# 2) 订阅 → 四段 → 抓取
cd /d/dev_workplace/flutter_te/_lh_srcprobe/probe
dart pub get
dart run bin/probe.dart subscribe ../site/fake_source.json
dart run bin/probe.dart search 剑来
dart run bin/probe.dart info    <bookUrl>
dart run bin/probe.dart toc     <bookUrl>
dart run bin/probe.dart chapter <bookUrl> 0
dart run bin/probe.dart download <bookUrl> --limit 3
```

真站复验（无需仿真站）：`dart run bin/probe.dart subscribe biqumo_src.json` 后同样四段跑「剑来」。

## 已知环境坑（复现前先读）

- GBK 用 `fast_gbk`；**`encoding` 包已从 pub 下架勿用**。
- Windows 下 `Process.runSync` 默认按系统码页（GBK）解码子进程 UTF-8 stdout → 中文乱码，**必须 `stdoutEncoding: utf8`**（两处踩过）。
- 多层 shell 转义会吞正则 `\d` → 探针内改用字符类 `[0-9]+` 写法免疫。
- pub `quickjs` 1.0.1 本机**不可用**（无 C 工具链 + native-assets 在 Dart 3.10 未启用）；JS 桥实测用 qjs.exe（`_lh_srcprobe/probe/qjs/`）。
- 真站会老化：XIU2 纯规则 5 源在验证当日已全部搜索失效，真站主证以 biqumo 为准。

合规：第三方书源集合 `shuyuan.json` 与真站抓取正文 `dl_real/*` **不入库**（见《预研结论-20260929.md》§8）。
