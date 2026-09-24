import 'remote_store.dart';

/// 差异引擎（【云盘】§8 same() 片段 + R8 三档一致性 + D2 残留 + D5 双侧忽略）。
///
/// 纯函数、不碰网络不碰磁盘：两份清单进，差异出。绝不用 mtime 兜底
/// （已知坑：PUT 后云端 LastModified 是服务端写入时间，同 mtime 必误判）。

/// 单文件差异状态（协议文档 §4 DiffStatus）。
enum DiffStatus { onlyLocal, onlyRemote, modified, inSync }

/// 一条差异：路径 + 状态 + 双侧条目（下载/上传编排要用）+ 残留提示。
class FileDiff {
  FileDiff({
    required this.relativePath,
    required this.status,
    this.local,
    this.remote,
    this.staleHint = false,
  });

  String relativePath;
  DiffStatus status;
  FileEntry? local;
  FileEntry? remote;

  /// D2 残留提示：onlyRemote 且台账同步成功过该路径（别人新传的没有此标记）。
  bool staleHint;
}

/// getetag 归一化（§8 口径，与 T13 webdav 私有实现同语义）：去换行/首尾
/// 空白/双引号；`W/` 弱前缀判定后**原样保留**，供 [sameEntry] 区分强弱。
/// null/空归一为 `''`。
String normEtag(String? raw) {
  var s = raw?.replaceAll('\n', '').trim();
  if (s == null || s.isEmpty) return '';
  if (s.startsWith('W/')) {
    final inner = _stripQuotes(s.substring(2).trim());
    return inner.isEmpty ? '' : 'W/$inner';
  }
  return _stripQuotes(s);
}

String _stripQuotes(String s) => s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1) : s;

/// 「服务端 ETag 就是内容 MD5」判据（R8 第③档门槛）：归一后 32 位 hex。
/// 分片上传对象形如 `d41d…-7`，不满足 → 摘要档不启用（已知坑：启用必误报）。
final _md5Hex = RegExp(r'^[0-9a-f]{32}$');

/// 一致性判定（R8 三档，默认最保守档）：两份 [FileEntry] 进，布尔出。
/// ① size 不等直接 false；② 本地已算 digest 且远端 etag 归一后为 32 位
/// hex → 摘要比对（严格校验档）；③ 双端均为非 W/ 前缀强 ETag → ETag 比对；
/// ④ 都不满足退回默认档：size 相等即 true。绝不引用 modified。
bool sameEntry(FileEntry l, FileEntry r) {
  if (l.size != r.size) return false;
  final remote = normEtag(r.etag), local = normEtag(l.etag);
  final remoteHex = remote.toLowerCase();
  if (l.digest != null && _md5Hex.hasMatch(remoteHex)) {
    return l.digest == remoteHex; // 严格校验档（R8③）
  }
  if (remote.isNotEmpty &&
      local.isNotEmpty &&
      !remote.startsWith('W/') &&
      !local.startsWith('W/')) {
    return remote == local; // 双强 ETag 档（R8②）
  }
  return true; // 只比大小（R8①）；绝不用 mtime 兜底
}

String _basename(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// 忽略规则（本期两类，够用了）：`*.ext` 后缀档与 `prefix*` 前缀档，
/// 对 basename 与全相对路径都试；其他形态的模式不参与匹配。
bool _isIgnored(String path, Set<String> patterns) {
  final base = _basename(path);
  for (final pat in patterns) {
    if (pat.startsWith('*') && pat.length > 1) {
      final suffix = pat.substring(1);
      if (path.endsWith(suffix) || base.endsWith(suffix)) return true;
    } else if (pat.endsWith('*') && pat.length > 1) {
      final prefix = pat.substring(0, pat.length - 1);
      if (path.startsWith(prefix) || base.startsWith(prefix)) return true;
    }
  }
  return false;
}

List<FileEntry> _keep(List<FileEntry> entries, Set<String> patterns) =>
    patterns.isEmpty
        ? entries
        : entries.where((f) => !_isIgnored(f.relativePath, patterns)).toList();

/// 差异计算：两侧清单**先同时**按 [ignorePatterns] 剔除（D5——只剔本地会把
/// 云端 `.DS_Store` 误报成 onlyRemote），再按相对路径**原文精确**配对
/// （大小写敏感，不 lower）。
///
/// [ledgerKnown] 为该目录同步成功过的路径台账（D2）：onlyRemote 且台账命中
/// → `staleHint=true`（疑似本地删除的云端残留）；台账空 = known 空 = 不报残留。
/// 输出按 relativePath 字典序稳定排序，方便 UI 渲染与快照比对。
List<FileDiff> computeDiff({
  required List<FileEntry> local,
  required List<FileEntry> remote,
  required Set<String> ignorePatterns,
  Set<String> ledgerKnown = const {},
}) {
  final lMap = {
    for (final f in _keep(local, ignorePatterns)) f.relativePath: f,
  };
  final rMap = {
    for (final f in _keep(remote, ignorePatterns)) f.relativePath: f,
  };
  final paths = <String>{...lMap.keys, ...rMap.keys}.toList()
    ..sort();
  return [
    for (final path in paths)
      () {
        final l = lMap[path];
        final r = rMap[path];
        final DiffStatus status;
        if (l == null) {
          status = DiffStatus.onlyRemote;
        } else if (r == null) {
          status = DiffStatus.onlyLocal;
        } else {
          status = sameEntry(l, r) ? DiffStatus.inSync : DiffStatus.modified;
        }
        return FileDiff(
          relativePath: path,
          status: status,
          local: l,
          remote: r,
          staleHint: status == DiffStatus.onlyRemote && ledgerKnown.contains(path),
        );
      }(),
  ];
}
