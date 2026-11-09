/* 批1a-1：UserSettings 增 KitSettings（小工具四项模块开关）
 * 与 NotifySettings 同构：进 prefs、随整包备份带走，不建表。
 * 护栏：每处命中数必须为 1（按各文件实际行尾还原 \n），任一处不符即整体零写入 */
const fs = require('fs');
const F = 'lib/core/settings/user_settings.dart';
let raw = fs.readFileSync(F, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
const e = (a, b) => [a.replace(/\n/g, NL), b.replace(/\n/g, NL)];

const KIT_CLASS = `/// V1.47 批1 · 小工具合集模块开关（原型 \`KITS.pset\` 四项同源）。
///
/// 口径：属用户偏好而非业务数据——与 [NotifySettings] 同构走 prefs，
/// 随整包备份/WebDAV 同步带走；足迹流水、收藏编排、插件登记另有 kit_* 表。
class KitSettings {
  const KitSettings({
    this.scan = true,
    this.wifiCheck = false,
    this.backupPlugins = true,
    this.backupFootprint = true,
  });

  /// 自动扫描私有 plugins/ 目录（启动时热加载符合规范的工具包）。
  final bool scan;

  /// Wi-Fi 下自动检查更新（每周一次 · 仅请求索引清单）。
  final bool wifiCheck;

  /// 插件列表随备份导出（换机恢复时按清单重装 · 数据各随其主）。
  final bool backupPlugins;

  /// 使用足迹随备份导出（关闭后 .lhbak 不含足迹流水 · 收藏与编排仍导出）。
  final bool backupFootprint;

  KitSettings copyWith({
    bool? scan,
    bool? wifiCheck,
    bool? backupPlugins,
    bool? backupFootprint,
  }) =>
      KitSettings(
        scan: scan ?? this.scan,
        wifiCheck: wifiCheck ?? this.wifiCheck,
        backupPlugins: backupPlugins ?? this.backupPlugins,
        backupFootprint: backupFootprint ?? this.backupFootprint,
      );

  Map<String, Object?> toMap() => {
        'scan': scan,
        'wifiCheck': wifiCheck,
        'backupPlugins': backupPlugins,
        'backupFootprint': backupFootprint,
      };

  factory KitSettings.fromMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return const KitSettings();
    Object? d;
    try {
      d = jsonDecode(raw);
    } catch (_) {
      return const KitSettings();
    }
    if (d is! Map) return const KitSettings();
    bool b(String k, bool def) => d[k] is bool ? d[k] as bool : def;
    const def = KitSettings();
    return KitSettings(
      scan: b('scan', def.scan),
      wifiCheck: b('wifiCheck', def.wifiCheck),
      backupPlugins: b('backupPlugins', def.backupPlugins),
      backupFootprint: b('backupFootprint', def.backupFootprint),
    );
  }
}

`;

const EDITS = [
  e('class UserSettings {', KIT_CLASS + 'class UserSettings {'),
  e("    this.profileBio = '',\n  });", "    this.profileBio = '',\n    this.kit = const KitSettings(),\n  });"),
  e('  final String profileBio;', '  final String profileBio;\n\n  /// V1.47 批1 · 小工具合集模块开关（原型 sheetKitSet 四项）。\n  final KitSettings kit;'),
  e("    navIds: ['today', 'todo', 'calendar', 'journal', 'settings'],\n  );", "    navIds: ['today', 'todo', 'calendar', 'journal', 'settings'],\n    kit: KitSettings(),\n  );"),
  e('    String? profileBio,\n  }) =>', '    String? profileBio,\n    KitSettings? kit,\n  }) =>'),
  e('        profileBio: profileBio ?? this.profileBio,\n      );', '        profileBio: profileBio ?? this.profileBio,\n        kit: kit ?? this.kit,\n      );'),
  e("        'profileBio': profileBio,\n      };", "        'profileBio': profileBio,\n        'kit': jsonEncode(kit.toMap()),\n      };"),
  e("            defaults.navIds,", "            defaults.navIds,\n        kit: KitSettings.fromMap(m['kit']),"),
];
for (const [oldS, newS] of EDITS) {
  const hits = raw.split(oldS).length - 1;
  if (hits !== 1) {
    console.error(`!! 命中 ${hits}（期望 1）：${JSON.stringify(oldS).slice(0, 70)}`);
    process.exit(1);
  }
  raw = raw.replace(oldS, newS);
}
fs.writeFileSync(F, raw);
console.log('PASS user_settings.dart 已加 KitSettings');
