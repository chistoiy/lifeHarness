import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/logging/app_log.dart';
import '../domain/kit_models.dart';

/// 小工具合集仓储（V1.47 模块14 · 计划 §1 四表）。
///
/// 口径：
/// - `kit_usage` 是使用足迹唯一真源，统计页/hero/最近条全部由它实算；
/// - `kit_layout` 存收藏与编排（fav/hidden/order/hero），值为 JSON；
/// - `kit_tool_data` 存工具私有参数与留痕（一工具一行，值为 JSON 对象）；
/// - `kit_plugin` 存插件登记与权限授予，审计时间线随行走 JSON；
/// - 四项模块开关属用户偏好，走 UserSettings，不在本仓储。
class KitRepository {
  KitRepository(this.db);

  final Database db;

  // ---- 足迹流水 ----

  /// 记一次使用（工具屏进出即写；插件工具 kind=plugin）。
  /// 同步把工具键推到「最近使用」表头（原型 `KITS.recent` 同构，上限 12）。
  Future<void> logUse(String tool, {String kind = kKitKindBuiltin}) async {
    try {
      await db.insert(
        DbSchema.tKitUsage,
        KitUsage(
          tool: tool,
          ts: DateTime.now().millisecondsSinceEpoch,
          kind: kind,
        ).toRow(),
      );
      final r = await recent();
      r.remove(tool);
      r.insert(0, tool);
      await setRecent(r.take(12).toList());
    } catch (e) {
      AppLog.add('小工具足迹写入失败：$e', src: '小工具');
    }
  }

  /// 全量足迹（ts 升序；[sinceMs] 可截断窗口）。
  Future<List<KitUsage>> usage({int? sinceMs}) async {
    final rows = await db.query(
      DbSchema.tKitUsage,
      where: sinceMs == null ? null : 'ts >= ?',
      whereArgs: sinceMs == null ? null : [sinceMs],
      orderBy: 'ts ASC',
    );
    return [for (final r in rows) KitUsage.fromRow(r)];
  }

  /// 清空足迹（界面侧二次确认后才调；收藏与编排不受影响）。
  Future<void> clearUsage() => db.delete(DbSchema.tKitUsage);

  // ---- 收藏与编排 ----

  /// 读一个编排键（缺失返回 [fallback]；JSON 损坏按缺失处理，不炸界面）。
  Future<Object?> layout(String key, {Object? fallback}) async {
    final rows = await db.query(
      DbSchema.tKitLayout,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return fallback;
    try {
      return jsonDecode(rows.first['value'] as String);
    } catch (e) {
      AppLog.add('小工具编排解析失败（$key）：$e', src: '小工具');
      return fallback;
    }
  }

  /// 写一个编排键（同 key 覆盖）。
  Future<void> setLayout(String key, Object value) =>
      db.insert(DbSchema.tKitLayout, {
        'key': key,
        'value': jsonEncode(value),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// 收藏键（`kit_layout.key='fav'`）。
  static const String kFav = 'fav';
  static const String kHidden = 'hidden';
  static const String kOrder = 'order';
  static const String kHero = 'hero';
  static const String kRecent = 'recent';

  Future<List<String>> favorites() async {
    final v = await layout(kFav, fallback: const <String>[]);
    return v is List ? [for (final e in v) '$e'] : const [];
  }

  Future<void> setFavorites(List<String> fav) => setLayout(kFav, fav);

  Future<List<String>> hidden() async {
    final v = await layout(kHidden, fallback: const <String>[]);
    return v is List ? [for (final e in v) '$e'] : const [];
  }

  Future<void> setHidden(List<String> ids) => setLayout(kHidden, ids);

  /// 最近使用（表头=最近一次；由 [logUse] 维护，界面可整表清空）。
  Future<List<String>> recent() async {
    final v = await layout(kRecent, fallback: const <String>[]);
    return v is List ? [for (final e in v) '$e'] : const [];
  }

  Future<void> setRecent(List<String> keys) => setLayout(kRecent, keys);

  /// 自定义顺序（null=未编排，按默认序展示）。
  Future<List<String>?> order() async {
    final v = await layout(kOrder);
    return v is List ? [for (final e in v) '$e'] : null;
  }

  Future<void> setOrder(List<String>? ids) => ids == null
      ? db.delete(DbSchema.tKitLayout, where: "key = 'order'")
      : setLayout(kOrder, ids);

  /// 四枚数据位（存枚举名，解析失败回落默认）。
  Future<List<KitMetric>> heroSlots() async {
    final v = await layout(kHero, fallback: const <String>[]);
    if (v is! List || v.length != 4) return kKitHeroDefault;
    return [for (final e in v) KitMetric.fromId('$e')];
  }

  Future<void> setHeroSlots(List<KitMetric> slots) =>
      setLayout(kHero, [for (final s in slots) s.name]);

  // ---- 工具私有参数与留痕 ----

  /// 取某工具的私有数据（无记录返回空 map，调用侧自带默认）。
  Future<Map<String, Object?>> toolData(String tool) async {
    final rows = await db.query(
      DbSchema.tKitToolData,
      where: 'tool = ?',
      whereArgs: [tool],
      limit: 1,
    );
    if (rows.isEmpty) return {};
    try {
      final d = jsonDecode(rows.first['data'] as String);
      return d is Map<String, Object?> ? d : {};
    } catch (e) {
      AppLog.add('小工具数据解析失败（$tool）：$e', src: '小工具');
      return {};
    }
  }

  Future<void> setToolData(String tool, Map<String, Object?> data) =>
      db.insert(DbSchema.tKitToolData, {
        'tool': tool,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- 插件登记 ----

  Future<List<KitPlugin>> plugins() async {
    final rows = await db.query(
      DbSchema.tKitPlugin,
      orderBy: 'installed_at ASC',
    );
    return [for (final r in rows) KitPlugin.fromRow(r)];
  }

  Future<void> upsertPlugin(KitPlugin p) => db.insert(
    DbSchema.tKitPlugin,
    p.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> setPluginEnabled(String id, bool enabled) => db.update(
    DbSchema.tKitPlugin,
    {
      'enabled': enabled ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> removePlugin(String id) =>
      db.delete(DbSchema.tKitPlugin, where: 'id = ?', whereArgs: [id]);
}
