# LifeHarness

个人生活管理 Android 应用（Flutter + sqflite 离线优先，WebDAV/S3 双云同步已落地）。
单一应用收纳 待办 / 日程 / 记录（日记·笔记·阅读）/ 收集箱 / 记账 / 习惯 / 母婴呵护 / 日子·物品·目标 / X-Ray 全书索引 等生活模块。

## 安装（Release APK）

1. 打开仓库 [Releases](https://github.com/chistoiy/lifeHarness/releases) 页面，选择最新 **Pre-release**。
2. 按设备下载对应 ABI 的 APK（任选其一）：
   - `app-arm64-v8a-release.apk` — 近两年主流 64 位手机（推荐）
   - `app-armeabi-v7a-release.apk` — 老旧 32 位设备
   - `app-x86_64-release.apk` — 模拟器 / x86 设备
3. 安装前需允许「安装未知来源应用」。要求 Android 8.0+（minSdk 26）。
4. 应用为本地数据版：卸载会删除本机数据库，升级安装（同签名）不会丢数据。
5. 另有 Gitee 私有镜像同 tag 挂包（内网/国内下载更快）。

## 从源码运行

```bash
flutter pub get
# Windows 本机若设置了 FLUTTER_STORAGE_BASE_URL 镜像导致 download.flutter.io 404：
# PowerShell 先 Remove-Item Env:FLUTTER_STORAGE_BASE_URL 再执行构建
flutter run
```

- sqlite3 原生库离线预置在 `tools/sqlite3/`（构建 workaround，见其 README）。
- 测试：批内增量按点名文件跑（推荐 `bash tools/ftest.sh`，全仓单轨、勿并发）；
  收口/发版才跑全量 `bash tools/run_gate.sh`（独占资源约 12 分钟，内置文档门禁前置）。

## 仓库导览

| 路径 | 说明 |
|---|---|
| `AGENTS.md` + `CLAUDE.md` | **AI 协作者入口**：禁令/环境/门禁/会话口令（开工·收尾·记一下） |
| `docs/STATUS.md` | 唯一状态源：当前 HEAD/发版/DB/门禁基线/下一站/并行互斥面 |
| `docs/INDEX.md` | 文档地图：按任务路由该读哪几份，不通读 docs/ |
| `docs/需求清单.md` | 现行需求定义（逐版修订在 `docs/archive/需求修订史-*.md`） |
| `docs/开发计划书.md` | 流程口径：十道门 SOP、发版 §7.1、测试调度 §7.2、工程红线 §五 |
| `docs/UI组件规范.md` | LH-xx 组件词典（UI 微调指令的公共语言） |
| `prototype/index.html` | 高保真单文件原型（共享面 UI 唯一事实源；各模块另有专版） |
| `docs/handoff/` · `docs/archive/` | 活工单（批次规格） · 闭环归档（卷宗只进不出） |
| `tools/` | 门禁与工装：`run_gate.sh`、`ftest.sh`、`doclint.py`（文档死链+漂移守护） |
