// 治理G5 域库：kit（V1.47 模块14 小工具合集）· 新模块直接按域文件落库
//
// 四表口径见 docs/小工具模块开发计划-20260929.md §1：
// 足迹流水 / 收藏与编排 / 工具私有参数 / 插件登记。
// 四项模块开关（自动扫描 · Wi-Fi 检查更新 · 插件随备份 · 足迹随备份）
// 属用户偏好，走 UserSettings + prefs，不进本域表。

const String tKitUsage = 'kit_usage';
const String tKitLayout = 'kit_layout';
const String tKitToolData = 'kit_tool_data';
const String tKitPlugin = 'kit_plugin';

/// 本域全部表（供备份/统计等跨模块引用，照 careTables 先例）。
const List<String> kitTables = [
  tKitUsage,
  tKitLayout,
  tKitToolData,
  tKitPlugin,
];

const List<String> kitSchemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS $tKitUsage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'builtin',
    ts INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_kit_usage_ts ON $tKitUsage(ts)',
  'CREATE INDEX IF NOT EXISTS idx_kit_usage_tool ON $tKitUsage(tool)',
  '''
  CREATE TABLE IF NOT EXISTS $tKitLayout (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tKitToolData (
    tool TEXT PRIMARY KEY,
    data TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tKitPlugin (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    ver TEXT NOT NULL,
    src TEXT NOT NULL DEFAULT 'local',
    size INTEGER NOT NULL DEFAULT 0,
    perms TEXT,
    granted TEXT,
    enabled INTEGER NOT NULL DEFAULT 0,
    installed_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    audit TEXT
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_kit_plugin_en ON $tKitPlugin(enabled)',
];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
  27: [...kitSchemaStatements],
};
