import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'remote_store.dart';

/// 台账单条记录：成功上传时的远端快照元数据（设计稿 §1 sync_ledger 行）。
class LedgerEntry {
  const LedgerEntry({required this.etag, required this.size, required this.ts});

  /// 上传成功时的远端 ETag（可为空串 = 服务端没给）。
  final String etag;

  /// 上传成功时的字节数。
  final int size;

  /// 记录时刻（epoch 毫秒）。
  final int ts;

  Map<String, dynamic> toJson() => {'etag': etag, 'size': size, 'ts': ts};

  static LedgerEntry? fromJson(Object? v) {
    if (v is! Map) return null;
    final size = v['size'];
    final ts = v['ts'];
    return LedgerEntry(
      etag: v['etag'] as String? ?? '',
      size: size is num ? size.toInt() : 0,
      ts: ts is num ? ts.toInt() : 0,
    );
  }
}

/// 同步台账（D2/D3）：某「服务 + 云端目录」下本机**上传成功过**的路径留痕。
///
/// 口径（Task 16 钉死 / 设计稿 §4.1）：
/// - prefs 键 `sync_ledger_{serviceId}|{cloudDirName}`（D3 缓存键统一前缀，
///   与 webdav/s3 清单缓存 `'${c.id}|$dir'` 同构）；值 JSON
///   `Map<relativePath, {etag,size,ts}>`；
/// - 消费位点：[knownPaths] 喂 `computeDiff(ledgerKnown:)`——`onlyRemote`
///   且台账命中 → `staleHint`（疑似本地删除的云端残留，E5 仅提示不删除）；
///   **台账空 = 不报残留**；元素必为非空 relativePath（[record] 拒收空串，
///   T15 评审 Minor 契约）；
/// - [prune] 语义 = **不清成功记录**：云端被外部删除仍留痕供残留判定；
///   整键删除只发生在删服务时（[clear]，配合 SyncConfigStore.removeService）。
class SyncLedger {
  SyncLedger(this._prefs, {required this.serviceId, required this.cloudDirName});

  /// D3 台账键前缀（设计稿 §1 边界规则）。
  static const keyPrefix = 'sync_ledger_';

  final SharedPreferences _prefs;
  final String serviceId;
  final String cloudDirName;

  /// 该「服务 + 目录」的 prefs 整键（测试/删服务清理用）。
  String get prefsKey => '$keyPrefix$serviceId|$cloudDirName';

  /// 上传成功回调：把这批 [FileEntry] 并入台账（合并写，不整体覆盖）。
  /// 空 relativePath 拒收——knownPaths 会直喂 computeDiff.ledgerKnown。
  Future<void> record(List<FileEntry> uploaded) async {
    final m = _read();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final f in uploaded) {
      if (f.relativePath.isEmpty) continue;
      m[f.relativePath] =
          LedgerEntry(etag: f.etag ?? '', size: f.size, ts: now);
    }
    await _prefs.setString(prefsKey, jsonEncode({
      for (final e in m.entries) e.key: e.value.toJson(),
    }));
  }

  /// 台账命中的相对路径集合（喂 computeDiff 的 ledgerKnown）。
  Set<String> knownPaths() => _read().keys.where((k) => k.isNotEmpty).toSet();

  /// 单路径查询：本机是否成功上传过该相对路径。
  bool recorded(String path) =>
      path.isNotEmpty && _read().containsKey(path);

  /// 该路径的台账记录（etag/size/ts），未记录 = null。
  LedgerEntry? entry(String path) => _read()[path];

  /// 云端清单刷新钩子：**故意不清任何成功记录**（钉死口径）——
  /// 「云端已不存在」≠「本机没传过」，留痕正是残留判定（D2 staleHint）的
  /// 唯一依据；清痕会让别人视角的本地删除被误判成「对方新传的新文件」。
  /// 整键清理只走 [clear]（删服务时）。
  Future<void> prune(Set<String> stillPresent) async {}

  /// 删服务：整键移除（由 SyncConfigStore.removeService 侧调用，T17/T18 接线）。
  Future<void> clear() => _prefs.remove(prefsKey);

  /// 容错读：坏 JSON / 类型漂移一律按空台账（不炸同步链路）。
  Map<String, LedgerEntry> _read() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return {};
      final out = <String, LedgerEntry>{};
      for (final e in data.entries) {
        if (e.key is! String) continue;
        final v = LedgerEntry.fromJson(e.value);
        if (v != null) out[e.key as String] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
