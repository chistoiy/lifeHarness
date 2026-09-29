/* 批1a-4：SettingsRepository 落 lh.kit 键（save/load/「有用户配置」守卫三处）
 * 护栏：每处命中数必须为 1 */
const fs = require('fs');
const F = 'lib/core/settings/settings_repository.dart';
let raw = fs.readFileSync(F, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
const e = (a, b) => [a.replace(/\n/g, NL), b.replace(/\n/g, NL)];
const EDITS = [
  e("  static const _kProfileBio = 'lh.profile_bio';",
    "  static const _kProfileBio = 'lh.profile_bio';\n\n  /// V1.47 批1·小工具合集模块开关（四项一 JSON，与 notify 同构）。\n  static const _kKit = 'lh.kit';"),
  e("        _prefs.getString(_kProfileNick) == null) {",
    "        _prefs.getString(_kProfileNick) == null &&\n        _prefs.getString(_kKit) == null) {"),
  e("      'profileBio': ?_prefs.getString(_kProfileBio),",
    "      'profileBio': ?_prefs.getString(_kProfileBio),\n      'kit': ?_prefs.getString(_kKit),"),
  e("    await _prefs.setString(_kProfileBio, m['profileBio']! as String);",
    "    await _prefs.setString(_kProfileBio, m['profileBio']! as String);\n    await _prefs.setString(_kKit, m['kit']! as String);"),
];
for (const [a, b] of EDITS) {
  const hits = raw.split(a).length - 1;
  if (hits !== 1) { console.error(`!! 命中 ${hits}（期望 1）：${JSON.stringify(a).slice(0, 60)}`); process.exit(1); }
  raw = raw.replace(a, b);
}
fs.writeFileSync(F, raw);
console.log('PASS settings_repository 已落 lh.kit 键');
