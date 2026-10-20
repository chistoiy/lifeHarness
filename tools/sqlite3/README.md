# sqlite3 预编译库（构建钩子离线源）

`sqflite_common_ffi`（本机 DB 单测）与 dart 构建钩子在编译期需要 sqlite3 原生库。
默认由 sqlite3 pub 包从 GitHub releases 下载，本开发环境 GitHub 不可达，
故 pubspec 配置：

```yaml
hooks:
  user_defines:
    sqlite3:
      source: test-sqlite3
      directory: tools/sqlite3/
```

钩子将按当前构建目标平台在本目录查找同名产物：

| 文件 | 用途 |
|---|---|
| `sqlite3.x64.windows.dll` | Windows 主机 `flutter test` |
| `libsqlite3.arm.android.so` / `libsqlite3.arm64.android.so` | Android APK 构建 |

来源：sqlite3 pub 包 3.5.2 对应 GitHub release 官方产物，经 ghproxy.net 镜像获取
（ELF/MZ 魔数已验证）。

注意：
- 升级 sqlite3 包版本时需同步替换本目录文件（文件名含版本号无关，产物须匹配）。
- Android x86/x86_64 产物该 release 未提供；如需 x86_64 模拟器构建，另行放置。
- 应用**运行时不依赖这些库**（Android 上 sqflite 使用系统 SQLite），它们只在构建/测试链出现。
- 网络恢复后删除 pubspec 的 hooks 段即回落官方下载。
