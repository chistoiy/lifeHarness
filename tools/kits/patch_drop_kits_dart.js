// 小工具整模块下架 · Flutter 侧引用面摘除（产品负责人 2026-09-30 拍板）
// 每条编辑都先断言唯一命中；文件行尾按原样还原（本仓 Dart 文件 CRLF/LF 混存）。
const fs = require('fs');

function load(f) {
  const raw = fs.readFileSync(f, 'utf8');
  const crlf = raw.includes('\r\n');
  return { f, crlf, s: crlf ? raw.replace(/\r\n/g, '\n') : raw };
}
function save(b) {
  fs.writeFileSync(b.f, b.crlf ? b.s.replace(/\n/g, '\r\n') : b.s);
  console.log('written ' + b.f);
}
function dropLine(b, sub, why) {
  const lines = b.s.split('\n');
  const hits = lines.filter(l => l.includes(sub));
  if (hits.length !== 1) throw new Error(`${b.f} :: 行锚命中 ${hits.length}（需 1）: ${sub}  [${why}]`);
  b.s = lines.filter(l => !l.includes(sub)).join('\n');
}
function dropRange(b, startSub, endSub, why) {
  const lines = b.s.split('\n');
  const a = lines.findIndex(l => l.includes(startSub));
  if (a < 0) throw new Error(`${b.f} :: 区间首行未命中 ${startSub} [${why}]`);
  const z = lines.findIndex((l, i) => i >= a && l.includes(endSub));
  if (z < 0) throw new Error(`${b.f} :: 区间尾行未命中 ${endSub} [${why}]`);
  if (z - a > 200) throw new Error(`${b.f} :: 区间过长 ${a}-${z} [${why}]`);
  b.s = lines.slice(0, a).concat(lines.slice(z + 1)).join('\n');
  console.log(`  range ${a + 1}-${z + 1} (${z - a + 1} 行) ${why}`);
}
function sub(b, oldS, newS, why) {
  const n = b.s.split(oldS).length - 1;
  if (n !== 1) throw new Error(`${b.f} :: 锚点命中 ${n}（需 1）: ${why}`);
  b.s = b.s.replace(oldS, newS);
}

/* ───────── ① 路由注册 ───────── */
{
  const b = load('lib/core/router/app_router.dart');
  dropLine(b, "import '../../features/kits/presentation/kit_routes.dart';", 'import');
  dropLine(b, '...kitShellRoutes(),', 'shell 路由');
  dropLine(b, '...kitPageRoutes(),', '栈路由');
  save(b);
}

/* ─────────  底栏栏目池 ──────── */
{
  const b = load('lib/core/nav/nav_module.dart');
  dropLine(b, "kits('kits', '工具', Icons.grid_view_outlined, Icons.grid_view, '/kits'),", '枚举项');
  dropLine(b, '// V1.47 模块14：小工具合集（原型 NAV_MODS「工具」栏同位 · 底栏栏目池可挂载）。', '注释');
  save(b);
}

/* ───────── ③ 仪表盘宫格 ───────── */
{
  const b = load('lib/features/dashboard/presentation/dashboard_page.dart');
  dropLine(b, "('🧰', '小工具', '/kits', null),", '宫格枚');
  sub(b, '浅灰圆角底块 15 项', '浅灰圆角底块 14 项', '枚数注释');
  save(b);
}

/* ─────────  schema：版本 30 · 不再建表 · v29→v30 删表迁移 ───────── */
{
  const b = load('lib/core/database/schema.dart');
  dropLine(b, "import 'schema/kit.dart' as k;", 'import');
  dropLine(b, '    ...kitSchemaStatements,', '建表聚合');
  for (const t of ['tKitUsage', 'tKitLayout', 'tKitToolData', 'tKitPlugin']) {
    dropLine(b, `static const String ${t} = k.${t};`, t);
  }
  dropLine(b, 'static const List<String> kitTables = k.kitTables;', 'kitTables 转发');
  dropLine(b, 'static const List<String> kitSchemaStatements = k.kitSchemaStatements;', '建表转发');
  dropLine(b, '    ...k.mig,', 'kit 迁移聚合');
  sub(b, 'static const int version = 29;', 'static const int version = 30;', '版本号');
  sub(
    b,
    '  static final Map<int, List<String>> migrations = {',
    '  static final Map<int, List<String>> migrations = {\n' +
      '    // V1.58 小工具整模块下架（产品负责人 2026-09-30 拍板「模块价值太低」）：\n' +
      '    // v29→v30 删除 kit_* 四表。索引随表自动删除，无需单独 DROP；\n' +
      '    // DROP IF EXISTS 保证「新装库从未建过这四表」也走得通（onCreate 已不再建）。\n' +
      '    // 偏好键 lh.kit 由 SettingsRepository.load() 一次性清除（照 care.rm.lock 先例）。\n' +
      '    29: [\n' +
      "      'DROP TABLE IF EXISTS kit_usage',\n" +
      "      'DROP TABLE IF EXISTS kit_layout',\n" +
      "      'DROP TABLE IF EXISTS kit_tool_data',\n" +
      "      'DROP TABLE IF EXISTS kit_plugin',\n" +
      '    ],',
    'v30 迁移'
  );
  save(b);
}

/* ─────────  UserSettings：摘 KitSettings ───────── */
{
  const b = load('lib/core/settings/user_settings.dart');
  dropRange(b, '/// V1.47 批1 · 小工具合集模块开关（原型 `KITS.pset` 四项同源）。', 'class UserSettings {', 'KitSettings 类');
  // 上面把 `class UserSettings {` 一并删了：补回
  sub(b, '  const UserSettings({', 'class UserSettings {\n  const UserSettings({', '补回类声明');
  dropLine(b, '    this.kit = const KitSettings(),', '构造默认值');
  dropLine(b, '  /// V1.47 批1 · 小工具合集模块开关（原型 sheetKitSet 四项）。', '字段注释');
  dropLine(b, '  final KitSettings kit;', '字段');
  dropLine(b, '    kit: KitSettings(),', 'defaults');
  dropLine(b, '    KitSettings? kit,', 'copyWith 形参');
  dropLine(b, '        kit: kit ?? this.kit,', 'copyWith 透传');
  dropLine(b, "        'kit': jsonEncode(kit.toMap()),", 'toMap');
  dropLine(b, "        kit: KitSettings.fromMap(m['kit']),", 'fromMap');
  if (b.s.includes('KitSettings')) throw new Error('user_settings 仍有 KitSettings 残留');
  save(b);
}

/* ───────── ⑥ 仓储：lh.kit 读到即清 ───────── */
{
  const b = load('lib/core/settings/settings_repository.dart');
  dropLine(b, '  /// V1.47 批1·小工具合集模块开关（四项一 JSON，与 notify 同构）。', '键注释');
  dropLine(b, "  static const _kKit = 'lh.kit';", '键常量');
  sub(b, "        _prefs.getInt(_kTrashKeep) == null &&\n        _prefs.getString(_kKit) == null) {",
    '        _prefs.getInt(_kTrashKeep) == null) {', '有用户配置判定');
  dropLine(b, "      'kit': ?_prefs.getString(_kKit),", 'fromMap 入参');
  dropLine(b, "    await _prefs.setString(_kKit, m['kit']! as String);", 'save 落盘');
  sub(b, '  UserSettings load() {',
    '  UserSettings load() {\n' +
      '    // V1.58 小工具整模块下架：历史遗留 lh.kit（四项模块开关）读到即清，\n' +
      '    // 不留「有用户配置」假信号（照 care.rm.lock 先例）。\n' +
      "    if (_prefs.containsKey('lh.kit')) _prefs.remove('lh.kit');",
    '一次性清键');
  if (b.s.includes('_kKit')) throw new Error('repository 仍有 _kKit 残留');
  save(b);
}

/* ─────────  控制器：摘 setKit ──────── */
{
  const b = load('lib/core/settings/settings_controller.dart');
  sub(b,
    '  /// V1.47 批1 · 小工具合集模块开关（原型 sheetKitSet）。\n' +
    '  /// 只落 prefs（kit 四项属偏好）；足迹/收藏/编排/插件登记走 kit_* 表。\n' +
    '  Future<void> setKit(KitSettings k) async {\n' +
    '    state = state.copyWith(kit: k);\n' +
    '    await _persist();\n' +
    '  }\n' +
    '\n',
    '', 'setKit 方法');
  if (b.s.includes('setKit') || b.s.includes('KitSettings')) throw new Error('controller 仍有 setKit 残留');
  save(b);
}

/* ───────── ⑧ 门禁登记表：摘 kits 条目 ───────── */
{
  const b = load('test/catch_log_guard_test.dart');
  dropLine(b, "'features/kits/domain/kit_models.dart': 2,", 'catch 登记');
  save(b);
}

/* ─────────  轮5 用例：小工具枚改为「必须不存在」 ───────── */
{
  const b = load('test/journal_deeplink_test.dart');
  sub(b, "      // 宫格侧仍在册，摘的是重复入口而不是功能本身。\n" +
    "      final d = File(\n" +
    "              'lib/features/dashboard/presentation/dashboard_page.dart')\n" +
    "          .readAsStringSync();\n" +
    "      expect(d, contains(\"'小工具', '/kits'\"));",
    "      // V1.58 小工具整模块下架：宫格里也不再有这一枚。\n" +
    "      final d = File(\n" +
    "              'lib/features/dashboard/presentation/dashboard_page.dart')\n" +
    "          .readAsStringSync();\n" +
    "      expect(d, isNot(contains(\"'小工具'\")));", '轮5 断言改版');
  save(b);
}
console.log('ALL EDITS OK');
