import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, FileSystemException, HttpDate;

import 'package:http/http.dart' as http;

import '../logging/app_log.dart';
import 'credential_vault.dart';
import 'http_gate.dart';
import 'remote_store.dart';
import 'service_config.dart';

/// PROPFIND 请求体固定四属性（【云盘】§4.1：resourcetype / getcontentlength /
/// getetag / getlastmodified，坚果云 allprop 实测不含 quota-* 故自定义）。
const String webDavPropfindBody = '<?xml version="1.0" encoding="utf-8"?>\n'
    '<d:propfind xmlns:d="DAV:"><d:prop>'
    '<d:resourcetype/><d:getcontentlength/><d:getetag/>'
    '<d:getlastmodified/>'
    '</d:prop></d:propfind>';

/// 列举限深（R6：`1+D` 次请求的护栏；触发即 warn 并停止下钻）。
const int webDavMaxDepth = 10;

/// 清单缓存 TTL（P1：一轮同步里同目录被反复问到，靠 60s 缓存吸收）。
const Duration webDavListingTtl = Duration(seconds: 60);

/// 容量缓存 TTL（P1：容量 5min 缓存）。
const Duration webDavQuotaTtl = Duration(minutes: 5);

/// 一条 PROPFIND response 的解析原语（[parsePropfindXml] 与递归列举共用，
/// 保证「文件视图」和「下钻决策」出自同一份解析）。
class PropfindRecord {
  PropfindRecord({
    required this.path,
    required this.isCollection,
    this.size,
    this.etag,
    this.modified,
  });

  /// href 归一：绝对 URL 取 path、百分号解码、去尾斜杠。
  final String path;
  final bool isCollection;
  final int? size;

  /// 已去引号；弱 ETag 保留 `W/` 前缀原样（R8 判定侧再区分）。
  final String? etag;
  final DateTime? modified;

  /// href 末段（子项相对路径拼接用）。
  String get name => path.substring(path.lastIndexOf('/') + 1);
}

/// PROPFIND multistatus 解析（顶层纯函数导出供单测）。
///
/// 入参必须是 `utf8.decode(bodyBytes)` 后的文本（R12），本函数只认文本。
/// 返回**文件**条目（目录不入列），relativePath 语义 = href 解码归一后的完整
/// 路径（如 `/dav/我的 文件夹/a.txt`）；以 cloudDirName 为根的再归一由
/// [WebDavStore.list] 完成。
List<FileEntry> parsePropfindXml(String utf8Xml) {
  return parsePropfindRecords(utf8Xml)
      .where((r) => !r.isCollection)
      .map((r) => FileEntry(
          relativePath: r.path, size: r.size ?? 0, etag: r.etag, modified: r.modified))
      .toList();
}

/// multistatus → 逐条 response 记录（含目录，递归下钻用）。
List<PropfindRecord> parsePropfindRecords(String utf8Xml) {
  final xml = _xmlUnescape(utf8Xml);
  final records = <PropfindRecord>[];
  for (final m in _responseRe.allMatches(xml)) {
    final block = m.group(1)!;
    final href = _tagOf(block, 'href');
    if (href == null || href.isEmpty) continue;
    final rt = _tagOf(block, 'resourcetype') ?? '';
    records.add(PropfindRecord(
      path: _hrefToPath(href),
      isCollection: RegExp(r'<[\w.-]*:?collection\b', caseSensitive: false)
          .hasMatch(rt),
      size: int.tryParse(_tagOf(block, 'getcontentlength') ?? ''),
      etag: _normEtag(_tagOf(block, 'getetag')),
      modified: _parseHttpDate(_tagOf(block, 'getlastmodified')),
    ));
  }
  return records;
}

// —— 解析小件（纯函数）——

final RegExp _responseRe = RegExp(
    r'<(?:[\w.-]+:)?response\b[^>]*>([\s\S]*?)</(?:[\w.-]+:)?response\s*>',
    caseSensitive: false);

String? _tagOf(String block, String name) {
  final m = RegExp('<(?:[\\w.-]+:)?$name\\b[^>]*>([\\s\\S]*?)'
          '</(?:[\\w.-]+:)?$name\\s*>',
          caseSensitive: false)
      .firstMatch(block);
  return m?.group(1)?.trim();
}

/// href → 归一路径：绝对 URL 取 path 部分，再百分号解码，去尾斜杠。
String _hrefToPath(String href) {
  var s = href.trim();
  if (!s.startsWith('/') && s.contains('://')) {
    s = Uri.parse(s).path;
  }
  s = _safeDecode(s);
  while (s.length > 1 && s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 宽容百分号解码：仅含 `%` 时尝试；服务器/本地名混排非法转义（如字面
/// `100% done`、未编码中文）时原样返回，绝不让 decode 抛穿传输链路。
String _safeDecode(String s) {
  if (!s.contains('%')) return s;
  try {
    return Uri.decodeFull(s);
  } catch (_) {
    return s;
  }
}

/// getetag 规范化：去首尾双引号与换行，`W/` 弱前缀原样保留。
String? _normEtag(String? raw) {
  var s = raw?.replaceAll('\n', '').trim();
  if (s == null || s.isEmpty) return null;
  if (s.startsWith('W/')) {
    return 'W/${_stripQuotes(s.substring(2).trim())}';
  }
  return _stripQuotes(s);
}

String _stripQuotes(String s) =>
    s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1) : s;

DateTime? _parseHttpDate(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  try {
    return HttpDate.parse(s);
  } catch (_) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
}

/// XML 实体还原（&lt; &gt; &quot; &apos; 先化，&amp; 最后，防二次解码）。
String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 坚果云（WebDAV 路线，【云盘】§4.1）：PROPFIND 递归列举 / 逐级 MKCOL +
/// 流式 PUT / 流式 GET 落盘 / Depth:0 verify / 私有 getUserInfo 容量。
///
/// 出口纪律（R10/R5）：所有请求经注入的 [HttpGate]（缺省全局 httpGate）发出，
/// 本类不自建连接；label 只写方法+路径，凭据永不进日志原文。
///
/// 测试注入口（§9 单测不真连公网）：[client] 工厂（MockClient）、[gate]
/// （假 sleeper 不真等）、[vault]（内存保险箱）、[clock]（假时钟拨缓存）。
class WebDavStore implements RemoteStore {
  WebDavStore({
    HttpGate? gate,
    CredentialVault? vault,
    HttpClientFactory? client,
    DateTime Function()? clock,
  })  : gate = gate ?? httpGate,
        _vault = vault ?? CredentialVault(),
        _clientFactory = client,
        _clock = clock ?? DateTime.now;

  /// 唯一请求出口（R10）；字段名 gate 在 R5 守护的合法前驱白名单内。
  final HttpGate gate;

  final CredentialVault _vault;
  final HttpClientFactory? _clientFactory;
  final DateTime Function() _clock;

  http.Client? _client;

  /// 单点聚合的生产 client：R5 封死 `http.Client(` 散落防自建连接池，
  /// 此处以构造器 tear-off（`http.Client.new`，走包默认工厂）作为唯一
  /// 兜底位点；测试一律注入 [client] 工厂，不触达该分支。
  http.Client _ensureClient() =>
      _client ??= (_clientFactory ?? http.Client.new)();

  /// 已建集合记忆（R7/P1）：键 `{serviceId}|{云端全路径}`，进程内有效。
  final Set<String> _createdDirs = {};

  /// 清单缓存（D3 键 `{serviceId}|{cloudDirName}`，60s TTL）。
  final Map<String, (DateTime, CloudListing)> _listingCache = {};

  /// 容量缓存（D3 键 serviceId，5min TTL）。
  final Map<String, (DateTime, CloudQuota)> _quotaCache = {};

  // —— 六方法 ——

  @override
  Future<CloudListing> list(ServiceConfig c, String cloudDirName,
      {bool force = false}) async {
    final key = '${c.id}|$cloudDirName';
    final hit = _listingCache[key];
    if (!force && hit != null &&
        _clock().difference(hit.$1) < webDavListingTtl) {
      return hit.$2;
    }
    final files = <FileEntry>[];
    // Depth:1 逐层递归（R6）：队列里是「待 PROPFIND 的目录链」（云内完整段链，
    // 首段 = cloudDirName；同层批处理，depth 即当前层号）。
    var queue = <List<String>>[_joinDir(c, cloudDirName, '')];
    var depth = 0;
    while (queue.isNotEmpty) {
      final next = <List<String>>[];
      for (final chain in queue) {
        final records = await _propfindDir(c, chain);
        final selfPath = _safeDecode(_uriSegments(c, chain).path);
        final dirRel = chain.skip(c.cloudDirName.isEmpty ? 0 : 1).join('/');
        for (final r in records) {
          if (r.path == selfPath) continue; // response 含目录自身，跳过
          final rel = dirRel.isEmpty ? r.name : '$dirRel/${r.name}';
          if (r.isCollection) {
            if (depth + 1 > webDavMaxDepth) {
              // 限深护栏（R6）：触发即 warn 并停止该支下钻，不静默截断。
              AppLog.add(
                  '⚠️ WebDAV 列举限深($webDavMaxDepth层)：'
                  '停止下钻 $cloudDirName/$rel',
                  level: LhLevel.warn);
              continue;
            }
            next.add([...chain, r.name]);
          } else {
            files.add(FileEntry(
                relativePath: rel,
                size: r.size ?? 0,
                etag: r.etag,
                modified: r.modified));
          }
        }
      }
      queue = next;
      depth++;
    }
    final listing = CloudListing(files);
    _listingCache[key] = (_clock(), listing);
    return listing;
  }

  @override
  Future<void> put(ServiceConfig c, String localPath, String cloudRelative) async {
    final segments = _normSegments(cloudRelative);
    final fileName = segments.isEmpty ? '' : segments.last;
    // 传输前逐级 MKCOL（R7）：目标文件的每一级父目录先确保存在。
    if (segments.length > 1) {
      await ensureDirectory(c, segments.take(segments.length - 1).join('/'));
    }
    if (fileName.isEmpty) {
      throw StateError('PUT 目标必须是文件相对路径，收到：$cloudRelative');
    }
    final uri = _uriSegments(c, [..._dirChain(c, cloudRelative), fileName]);
    final label = 'PUT ${uri.path}';
    final size = await File(localPath).length();
    final auth = await _authHeader(c);
    final res = await gate.send(
      _ensureClient(),
      () {
        // 重发必重建（R10）：流式体只读一遍——每次工厂调用开新读流。
        final req = http.StreamedRequest('PUT', uri)..contentLength = size;
        req.headers['Authorization'] = auth;
        unawaited(() async {
          try {
            await req.sink.addStream(File(localPath).openRead());
          } finally {
            req.sink.close();
          }
        }());
        return req;
      },
      config: c,
      label: label,
    );
    if (!_isSuccess(res.statusCode, const {200, 201, 204})) {
      final body = await _bodyText(res);
      throw StateError('PUT $label 失败(${res.statusCode})：${_brief(body)}');
    }
    await res.stream.drain<void>();
  }

  @override
  Future<void> get(
      ServiceConfig c, String cloudRelative, String localPath) async {
    final uri = _uriFor(c, cloudRelative);
    final label = 'GET ${uri.path}';
    final auth = await _authHeader(c);
    final res = await gate.send(
      _ensureClient(),
      () {
        final req = http.Request('GET', uri);
        req.headers['Authorization'] = auth;
        return req;
      },
      config: c,
      label: label,
    );
    if (res.statusCode != 200) {
      final body = await _bodyText(res);
      throw StateError('GET $label 失败(${res.statusCode})：${_brief(body)}');
    }
    // 流式落盘（P4）：临时文件 + rename 原子放，半截下载永不污染目标。
    final part = File('$localPath.part');
    final sink = part.openWrite();
    try {
      await res.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      await _tryDelete(part);
      rethrow;
    }
    await sink.close();
    final target = File(localPath);
    if (await target.exists()) await target.delete();
    await part.rename(localPath);
  }

  @override
  Future<void> ensureDirectory(ServiceConfig c, String cloudRelativeDir) async {
    final chain = _dirChain(c, cloudRelativeDir);
    if (chain.isEmpty) return;
    for (var i = 1; i <= chain.length; i++) {
      final partial = chain.take(i).join('/');
      final memoKey = '${c.id}|$partial';
      if (_createdDirs.contains(memoKey)) continue; // 已建集合记忆（R7）
      await _mkcol(c, partial, memoKey);
    }
  }

  @override
  Future<VerifyResult> verify(ServiceConfig c) async {
    // 根目录一次 PROPFIND Depth:0（协议文档 §8 verify = 1 次极轻请求）。
    final uri = _uriFor(c, '');
    final auth = await _authHeader(c);
    final res = await gate.send(
      _ensureClient(),
      () => _propfindRequest(uri, '0', auth),
      config: c,
      label: 'PROPFIND ${uri.path}',
    );
    final body = await _bodyText(res);
    if (res.statusCode == 207) return VerifyResult(true);
    return VerifyResult(false, _verifyFailMessage(c, res.statusCode, body));
  }

  @override
  Future<CloudQuota> quota(ServiceConfig c, {bool force = false}) async {
    final hit = _quotaCache[c.id];
    if (!force && hit != null &&
        _clock().difference(hit.$1) < webDavQuotaTtl) {
      return hit.$2;
    }
    // 坚果云私有扩展 GET {scheme}://{host}/nsdav/getUserInfo（§4.1：
    // PROPFIND 路线拿不到容量，allprop 实测无 quota-*）。
    final base = _root(c);
    final uri = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        pathSegments: const ['nsdav', 'getUserInfo']);
    final auth = await _authHeader(c);
    final res = await gate.send(
      _ensureClient(),
      () {
        final req = http.Request('GET', uri);
        req.headers['Authorization'] = auth;
        return req;
      },
      config: c,
      label: 'GET ${uri.path}',
    );
    final bytes = await res.stream.toBytes();
    if (res.statusCode != 200) {
      throw StateError('getUserInfo 失败(${res.statusCode})：'
          '${_brief(utf8.decode(bytes, allowMalformed: true))}');
    }
    final q = parseGetUserInfo(utf8.decode(bytes));
    _quotaCache[c.id] = (_clock(), q);
    return q;
  }

  @override
  void close() {
    _client?.close();
    _client = null;
  }

  // —— 内部件 ——

  /// getUserInfo JSON → [CloudQuota]（collection.href 归一化：URL 解码 +
  /// 去尾斜杠 + 小写，之后按目录名命中）。顶层纯函数导出供单测。
  static CloudQuota parseGetUserInfo(String jsonText) {
    final decoded = jsonDecode(jsonText);
    final user = decoded is Map && decoded['user'] is Map
        ? Map<String, dynamic>.from(decoded['user'] as Map)
        : const <String, dynamic>{};
    final collections = <String, int>{};
    final list = user['collection'];
    if (list is List) {
      for (final e in list.whereType<Map>()) {
        final href = e['href']?.toString();
        final used = switch (e['used_storage']) {
          final num n => n.toInt(),
          final String s => int.tryParse(s),
          _ => null,
        };
        if (href != null && used != null) {
          collections[normalizeCollectionHref(href)] = used;
        }
      }
    }
    int? asInt(Object? v) => switch (v) {
          final num n => n.toInt(),
          final String s => int.tryParse(s),
          _ => null,
        };
    return CloudQuota(
      quotaBytes: asInt(user['storage_quota']),
      usedBytes: asInt(user['used_storage']),
      collectionUsed: collections,
    );
  }

  /// collection href 归一化（已知坑：URL 编码 + 尾斜杠，直接比目录名必取不到）。
  static String normalizeCollectionHref(String href) {
    var s = _safeDecode(href.trim());
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final segs = s.split('/').where((x) => x.isNotEmpty).toList();
    return (segs.isEmpty ? s : segs.last).toLowerCase();
  }

  Future<List<PropfindRecord>> _propfindDir(
      ServiceConfig c, List<String> chain) async {
    final uri = _uriSegments(c, chain);
    final auth = await _authHeader(c);
    final res = await gate.send(
      _ensureClient(),
      () => _propfindRequest(uri, '1', auth),
      config: c,
      label: 'PROPFIND ${uri.path}',
    );
    if (res.statusCode != 207) {
      final body = await _bodyText(res);
      throw StateError('PROPFIND ${uri.path} 失败(${res.statusCode})：'
          '${_brief(body)}');
    }
    // R12：XML 恒定 utf8.decode(bodyBytes)，绝不用 response.body 猜编码。
    final bytes = await res.stream.toBytes();
    return parsePropfindRecords(utf8.decode(bytes));
  }

  http.BaseRequest _propfindRequest(Uri uri, String depth, String auth) {
    final req = http.Request('PROPFIND', uri)
      ..headers['Depth'] = depth
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..headers['Authorization'] = auth
      ..body = webDavPropfindBody;
    return req;
  }

  Future<void> _mkcol(ServiceConfig c, String relInDir, String memoKey) async {
    final uri = _uriFor(c, relInDir);
    final auth = await _authHeader(c);
    final res = await gate.send(
      _ensureClient(),
      () {
        final req = http.Request('MKCOL', uri);
        req.headers['Authorization'] = auth;
        return req;
      },
      config: c,
      label: 'MKCOL ${uri.path}',
    );
    await res.stream.drain<void>();
    // 201/204/405 皆成功（R7：405 = 已存在）；成功才入记忆。
    if (!_isSuccess(res.statusCode, const {201, 204, 405})) {
      throw StateError('MKCOL ${uri.path} 失败(${res.statusCode})');
    }
    _createdDirs.add(memoKey);
  }

  /// Basic base64(account:secret)：secret 每次现从 vault 取（R11 凭据不进
  /// 明文配置，也不进任何日志原文）。
  Future<String> _authHeader(ServiceConfig c) async {
    final secret = await _vault.read(c.id) ?? '';
    return 'Basic ${base64Encode(utf8.encode('${c.account}:$secret'))}';
  }

  Uri _root(ServiceConfig c) {
    try {
      return Uri.parse(c.apiUrl);
    } catch (_) {
      return Uri.parse('https://dav.jianguoyun.com/dav/');
    }
  }

  /// WebDAV 根的 path 段（如 `https://h/dav/` → ['dav']；尾空段剔除）。
  List<String> _rootSegments(ServiceConfig c) {
    final segs = _root(c).pathSegments.toList();
    while (segs.isNotEmpty && segs.last.isEmpty) {
      segs.removeLast();
    }
    return segs;
  }

  /// 相对路径归一（去前导/空段）；逐段宽容解码（[safeDecode] 语义），
  /// 字面 `%`/未编码中文等非法转义形态原样保留。
  List<String> _normSegments(String rel) => rel
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .map(_safeDecode)
      .toList();

  /// 云内链：cloudDirName + 相对路径的目录段（不含文件名）。
  List<String> _dirChain(ServiceConfig c, String cloudRelative) {
    final segs = _normSegments(cloudRelative);
    if (segs.length > 1) segs.removeLast(); // 末段视为文件名
    if (c.cloudDirName.isNotEmpty) segs.insert(0, c.cloudDirName);
    return segs;
  }

  /// 目录相对路径（相对 cloudDirName）→ 云内完整段链。
  List<String> _joinDir(ServiceConfig c, String cloudDirName, String dirRel) =>
      [if (cloudDirName.isNotEmpty) cloudDirName, ..._normSegments(dirRel)];

  /// 云内完整段链 → 完整 URL（每段由 Uri 组件构造器独立 percent-encode，
  /// 中文/空格/& 的「构造编码」与「实际请求编码」天然一致——已知坑
  /// 「编码不一致」在 WebDAV 侧的免疫写法）。
  Uri _uriSegments(ServiceConfig c, List<String> segments) {
    final base = _root(c);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: [..._rootSegments(c), ...segments],
    );
  }

  /// 字符串相对路径便捷入口（内部仍走段链构造）。
  Uri _uriFor(ServiceConfig c, String relInCloud) =>
      _uriSegments(c, _normSegments(relInCloud));

  bool _isSuccess(int status, Set<int> allowed) => allowed.contains(status);

  Future<String> _bodyText(http.StreamedResponse res) async {
    final bytes = await res.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _brief(String body) =>
      body.replaceAll(RegExp(r'\s+'), ' ').trim().split('').take(200).join();

  String _verifyFailMessage(ServiceConfig c, int status, String body) {
    final reason = _brief(body);
    return switch (status) {
      // R13 文案分协议：WebDAV 侧 401/403 的头号成因是填了登录密码。
      401 || 403 => c.provider == StoreProviderKind.webdav
          ? '认证失败（$status）：账户请填注册邮箱 + 应用密码（不是登录密码）。'
              '网页端 → 账户信息 → 安全选项 → 添加应用密码'
          : '认证失败（$status）：请检查账户与密钥',
      404 => '路径不存在（404）：请确认云端目录已随客户端同步：$reason',
      _ => '连接验证失败（$status）：$reason',
    };
  }

  Future<void> _tryDelete(File f) async {
    try {
      await f.delete();
    } on FileSystemException {
      // 清理失败不掩盖主异常。
    }
  }
}
