# LifeHarness

个人生活管理 Android 应用（Flutter + sqflite 离线优先，规划 WebDAV 多设备同步）。
单一应用收纳 待办 / 日程 / 记录（日记·笔记·阅读·影音游）/ 收集箱 / 记账 / 健康 等生活模块。

## 安装（Release APK）

1. 打开仓库 [Releases](https://github.com/chistoiy/lifeHarness/releases) 页面，选择最新 **Pre-release**。
2. 按设备下载对应 ABI 的 APK（任选其一）：
   - `app-arm64-v8a-release.apk` — 近两年主流 64 位手机（推荐）
   - `app-armeabi-v7a-release.apk` — 老旧 32 位设备
   - `app-x86_64-release.apk` — 模拟器 / x86 设备
3. 安装前需允许「安装未知来源应用」。要求 Android 8.0+（minSdk 26）。
4. 应用为本地数据版：卸载会删除本机数据库，升级安装（同签名）不会丢数据。

## 从源码运行

```bash
flutter pub get
# Windows 本机若设置了 FLUTTER_STORAGE_BASE_URL 镜像导致 download.flutter.io 404：
# PowerShell 先 Remove-Item Env:FLUTTER_STORAGE_BASE_URL 再执行构建
flutter run
```

- sqlite3 原生库离线预置在 `tools/sqlite3/`（构建 workaround，见其 README）。
- 测试：`flutter test --no-pub`（全 app 用例须独立文件，见 `test/helpers.dart` 注释）。

## 仓库导览

| 路径 | 说明 |
|---|---|
| `prototype/index.html` | 高保真单文件原型（UI 唯一事实源，双击浏览器即可体验） |
| `docs/需求清单.md` | 需求唯一依据（含版本决策记录） |
| `docs/开发计划书.md` | 里程碑、SOP 门序、两档批次流程 |
| `docs/交接文档.md` | 当前状态 / 下一步 / 完整变更日志（接手人先读） |
| `docs/UI组件规范.md` | LH 编号组件词典 |
| `lib/` | Flutter 源码（core / features / shared，架构守护测试 R1~R4） |
