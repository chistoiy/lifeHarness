import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, FileSystemException;

import 'package:http/http.dart' as http;

import '../logging/app_log.dart';
import 'credential_vault.dart';
import 'http_gate.dart';
import 'remote_store.dart';
import 's3_sigv4.dart';
import 'service_config.dart';

/// 单页列举对象数（R6：每 1000 个对象 1 次请求）。
const int s3MaxKeys = 1000;

/// 翻页硬顶（§4.2：翻页直到 IsTruncated=false，硬上限 200 页；触顶 warn）。
const int s3MaxPages = 200;

/// 清单缓存 TTL（P1，与 WebDAV 同口径 60s）。
const Duration s3ListingTtl = Duration(seconds: 60);

/// 容量缓存 TTL（P1：5min）。
const Duration s3QuotaTtl = Duration(minutes: 5);

/// 缤纷云缺省 region（§4.2：目前仅此一个；配置留空时兜底）。
const String s3DefaultRegion = 'cn-east-1';

/// ListObjectsV2 单个对象（Key 为服务端返回的逻辑名，非 URL 编码形态）。
class S3ObjectInfo {
  S3ObjectInfo({
    required this.key,
    required this.size,
    this.etag,
    this.lastModified,
  });

  final String key;
  final int size;

  /// 已去引号。
  final String? etag;
  final DateTime? lastModified;

  /// 目录占位对象（R7：Key 尾 `/`）。
  bool get isPlaceholder => key.endsWith('/');
}

/// ListObjectsV2 一页的解析结果。
class S3ListResult {
  S3ListResult({
    required this.contents,
    required this.isTruncated,
    this.nextToken,
  });

  /// 已剔除目录占位对象（R7）。
  final List<S3ObjectInfo> contents;
  final bool isTruncated;
  final String? nextToken;
}

/// ListObjectsV2 XML 解析（R12：入参必须 utf8.decode(bodyBytes) 后的文本）。
/// 顶层纯函数导出供单测。
S3ListResult parseListObjectsV2(String utf8Xml) {
  final xml = _xmlUnescape(utf8Xml);
  final contents = <S3ObjectInfo>[];
  for (final m in _contentsRe.allMatches(xml)) {
    final block = m.group(1)!;
    final key = _tagOf(block, 'Key');
    if (key == null || key.isEmpty) continue;
    contents.add(S3ObjectInfo(
      key: key,
      size: int.tryParse(_tagOf(block, 'Size') ?? '') ?? 0,
      etag: _stripQuotes(_tagOf(block, 'ETag')),
      lastModified: _parseIso(_tagOf(block, 'LastModified')),
    ));
  }
  final truncated =
      (_tagOf(xml, 'IsTruncated') ?? '').toLowerCase() == 'true';
  return S3ListResult(
    contents: contents.where((o) => !o.isPlaceholder).toList(),
    isTruncated: truncated,
    nextToken: _tagOf(xml, 'NextContinuationToken'),
  );
}

/// ListAllMyBuckets XML → [CloudQuota]（§4.2 容量行：缤纷云在标准
/// Name/CreationDate 外附带私有 `*Bytes` 字段；官方 SDK 模型会丢弃它们，
/// 故手写解析。usedBytes = Σ(Image+Tmp+Video+Audio+Other)，无配额字段 →
/// quotaBytes 恒 null（R9 第②态）。顶层纯函数导出供单测。
CloudQuota parseListAllMyBuckets(String utf8Xml) {
  const byteFields = ['ImageBytes', 'TmpBytes', 'VideoBytes', 'AudioBytes', 'OtherBytes'];
  final xml = _xmlUnescape(utf8Xml);
  final perBucket = <String, int>{};
  var used = 0;
  var sawBucket = false;
  for (final m in _bucketRe.allMatches(xml)) {
    sawBucket = true;
    final block = m.group(1)!;
    final name = _tagOf(block, 'Name') ?? '';
    var sum = 0;
    for (final f in byteFields) {
      sum += int.tryParse(_tagOf(block, f) ?? '') ?? 0;
    }
    if (name.isNotEmpty) perBucket[name] = (perBucket[name] ?? 0) + sum;
    used += sum;
  }
  if (!sawBucket) return CloudQuota(quotaBytes: null, usedBytes: null);
  return CloudQuota(quotaBytes: null, usedBytes: used, collectionUsed: perBucket);
}

/// 回包是否为 ListAllMyBuckets 形态：认根标签 `ListAllMyBucketsResult` 或任意
/// `<Bucket>` 元素二者其一即算（空桶账号有根标签无 Bucket，仍属正常形态）。
/// 用于把「误配 endpoint 拿到坚果云 `<s:user>`」这类错误响应甄别为降级，
/// 而非静默解析成 0 用量。
bool _isListAllMyBucketsShape(String utf8Xml) =>
    RegExp(r'ListAllMyBucketsResult', caseSensitive: false).hasMatch(utf8Xml) ||
    RegExp(r'<(?:[\w.-]+:)?Bucket\b', caseSensitive: false).hasMatch(utf8Xml);

final RegExp _contentsRe = RegExp(
    r'<(?:[\w.-]+:)?Contents\b[^>]*>([\s\S]*?)</(?:[\w.-]+:)?Contents\s*>',
    caseSensitive: false);
final RegExp _bucketRe = RegExp(
    r'<(?:[\w.-]+:)?Bucket\b[^>]*>([\s\S]*?)</(?:[\w.-]+:)?Bucket\s*>',
    caseSensitive: false);

String? _tagOf(String block, String name) => RegExp(
        '<(?:[\\w.-]+:)?$name\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?$name\\s*>',
        caseSensitive: false)
    .firstMatch(block)
    ?.group(1)
    ?.trim();

String? _stripQuotes(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  return s.length >= 2 && s.startsWith('"') && s.endsWith('"')
      ? s.substring(1, s.length - 1)
      : s;
}

DateTime? _parseIso(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// XML 实体还原（&amp; 最后，防二次解码；与 webdav 侧同规则）。
String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 缤纷云（S3 路线，【云盘】§4.2）：virtual-hosted 寻址 + 手写 SigV4（[SigV4Signer]）。
///
/// 协议要点钉死：
/// - 寻址 `https://{bucket}.{hostNoScheme}/{key}`；**ListAllMyBuckets 例外**，
///   只能打根 endpoint（R5：带桶前缀的 host 拿不到用量字段）；
/// - 列举 = 一次递归 ListObjectsV2 + prefix（R6：S3 按请求计费，逐层展开必炸）；
/// - 目录 = 扁平键空间（R7：[ensureDirectory] 空实现，列举尾 `/` 占位剔除）；
/// - 传输流式，Content-Length 必给（§4.2），put 走 UNSIGNED-PAYLOAD；
/// - 未使用的私有查询串/限速头形态一概不引入（协议文档「明确别用」表 + R5 守护）。
///
/// 出口纪律（R10/R5）：所有请求经注入 [HttpGate]，重发工厂内重建请求并
/// **重新签名**（签名含日期，已知坑）。凭据口径与 T11/T13 一致：AK 走
/// `ServiceConfig.account` 明文侧，SK 现从 [CredentialVault]（`sync_secret_{id}`）取，
/// 永不进日志原文。
class S3Store implements RemoteStore {
  S3Store({
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

  /// 单点聚合的生产 client（与 WebDavStore 同一口径）：R5 封死 `http.Client`
  /// 散落实例化，此处以构造器 tear-off 作为唯一兜底位点；测试一律注入
  /// [client] 工厂，不触达该分支。
  http.Client _ensureClient() =>
      _client ??= (_clientFactory ?? http.Client.new)();

  /// 清单缓存（D3 键 `{serviceId}|{cloudDirName}`，60s TTL）。
  final Map<String, (DateTime, CloudListing)> _listingCache = {};

  /// 容量缓存（D3 键 serviceId，5min TTL）。
  final Map<String, (DateTime, CloudQuota)> _quotaCache = {};

  /// 容量降级 warn 去重（V1.41 R2 项② + 评审修复轮1 Minor-1：**静态表按
  /// serviceId 去重、进程级生效**——过去是实例级 Set，store 每代新建都清零，
  /// warn 实际「每代一次」而非承诺的一次；改静态表后同服务全进程只 warn 一次）。
  static final Set<String> _quotaWarnedServices = {};

  void _warnQuotaDegraded(ServiceConfig c, String reason) {
    if (!_quotaWarnedServices.add(c.id)) return; // 已 warn 过（进程级）不再刷
    AppLog.add('⚠️ S3 容量降级：服务 ${c.id} $reason · 容量按未知（null）渲染',
        level: LhLevel.warn);
  }

  // —— 六方法 ——

  @override
  Future<CloudListing> list(ServiceConfig c, String cloudDirName,
      {bool force = false}) async {
    final cacheKey = '${c.id}|$cloudDirName';
    final hit = _listingCache[cacheKey];
    if (!force &&
        hit != null &&
        _clock().difference(hit.$1) < s3ListingTtl) {
      return hit.$2;
    }
    final prefix = _dirPrefixOf(cloudDirName);
    final files = <FileEntry>[];
    String? token;
    for (var page = 0; page < s3MaxPages; page++) {
      final uri = _uri(c, query: {
        'list-type': '2',
        if (prefix.isNotEmpty) 'prefix': prefix,
        'max-keys': '$s3MaxKeys',
        'continuation-token': ?token,
      });
      final body = await _getBody(c, uri, 'GET ${uri.host}/');
      final r = parseListObjectsV2(body);
      files.addAll(r.contents.map((o) => FileEntry(
            relativePath: _stripPrefix(o.key, prefix),
            size: o.size,
            etag: o.etag,
            modified: o.lastModified,
          )));
      if (!r.isTruncated || r.nextToken == null) {
        final listing = CloudListing(files);
        _listingCache[cacheKey] = (_clock(), listing);
        return listing;
      }
      token = r.nextToken;
    }
    // 硬顶触达：warn 后带已聚合结果返回，不静默截断（对齐 WebDAV 限深口径）。
    AppLog.add('⚠️ S3 列举翻页硬顶($s3MaxPages页)：停止翻页 $cloudDirName',
        level: LhLevel.warn);
    final listing = CloudListing(files);
    _listingCache[cacheKey] = (_clock(), listing);
    return listing;
  }

  @override
  Future<void> put(
      ServiceConfig c, String localPath, String cloudRelative) async {
    final segments = _normSegments(cloudRelative);
    if (segments.isEmpty) {
      throw StateError('PUT 目标必须是文件相对路径，收到：$cloudRelative');
    }
    final uri = _uri(c, keySegments: [..._dirSegments(c), ...segments]);
    final label = 'PUT ${uri.host}/${_keyFor(c, cloudRelative)}';
    final size = await File(localPath).length();
    final signer = await _signer(c);
    final res = await gate.send(
      _ensureClient(),
      () {
        // 重发必重建 + 重签（R10/已知坑）：流式体只读一遍，签名含日期。
        final req = http.StreamedRequest('PUT', uri)..contentLength = size;
        signer.sign(req, payloadHash: SigV4Signer.unsignedPayload);
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
    if (res.statusCode != 200) {
      final body = await _bodyText(res);
      throw StateError('PUT $label 失败(${res.statusCode})：${_brief(body)}');
    }
    await res.stream.drain<void>();
    // R4：与 WebDAV 同口径——上传成功即作废本服务清单缓存，防 60s TTL 内
    // compare 拿旧清单报「刚传完仍仅本地」的假差异。
    _listingCache.removeWhere((k, _) => k.startsWith('${c.id}|'));
  }

  @override
  Future<void> get(
      ServiceConfig c, String cloudRelative, String localPath) async {
    // cloudRelative 恒**相对 cloudDirName**（T13 钉死口径，list 直喂）：
    // key = {cloudDirName}/{relative}，与 [list] 剥前缀的产出互逆。
    final segments = _normSegments(cloudRelative);
    if (segments.isEmpty) {
      throw StateError('GET 目标必须是文件相对路径，收到：$cloudRelative');
    }
    final uri = _uri(c, keySegments: [..._dirSegments(c), ...segments]);
    final label = 'GET ${uri.host}/${_keyFor(c, cloudRelative)}';
    final signer = await _signer(c);
    final res = await gate.send(
      _ensureClient(),
      () => signer.sign(http.Request('GET', uri),
          payloadHash: SigV4Signer.emptySha256),
      config: c,
      label: label,
    );
    if (res.statusCode != 200) {
      final body = await _bodyText(res);
      throw StateError('GET $label 失败(${res.statusCode})：${_brief(body)}');
    }
    // 流式落盘（P4）：临时文件 + rename 原子放（与 WebDAV 同一保护）。
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
    // R7：S3 扁平键空间，key 里带 `/` 自然成目录——空实现零请求。
  }

  @override
  Future<void> move(
      ServiceConfig c, String fromRel, String toRel) async {
    // R5d：S3 无原生移动 = CopyObject（服务端复制，零本地流量）+ DELETE。
    final srcKey = _keyFor(c, fromRel);
    final dstUri = _uri(
        c, keySegments: [..._dirSegments(c), ..._normSegments(toRel)]);
    final signer = await _signer(c);
    final copyRes = await gate.send(
      _ensureClient(),
      () {
        final req = http.Request('PUT', dstUri)..bodyBytes = const [];
        // R5d 真云验证修正：x-amz-copy-source 必须在 sign **之前**写入——
        // 缤纷云要求该头进签名头集，签后追加会 403 SignatureDoesNotMatch。
        req.headers['x-amz-copy-source'] =
            '/${c.bucket}/${Uri.encodeComponent(srcKey).replaceAll('%2F', '/')}';
        signer.sign(req, payloadHash: SigV4Signer.emptySha256);
        return req;
      },
      config: c,
      label: 'COPY ${dstUri.host}/$srcKey',
    );
    final copyBody = await _bodyText(copyRes);
    if (copyRes.statusCode != 200) {
      throw StateError(
          'COPY ${dstUri.host} 失败(${copyRes.statusCode})：${_brief(copyBody)}');
    }
    await delete(c, fromRel);
  }

  @override
  Future<void> delete(ServiceConfig c, String cloudRelative) async {
    final uri = _uri(
        c, keySegments: [..._dirSegments(c), ..._normSegments(cloudRelative)]);
    final signer = await _signer(c);
    final res = await gate.send(
      _ensureClient(),
      () => signer.sign(http.Request('DELETE', uri),
          payloadHash: SigV4Signer.emptySha256),
      config: c,
      label: 'DELETE ${uri.host}/${_keyFor(c, cloudRelative)}',
    );
    await res.stream.drain<void>();
    // 204/200 成功；S3 对不存在对象也回 204（天然幂等）。
    if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 404) {
      throw StateError(
          'DELETE ${_keyFor(c, cloudRelative)} 失败(${res.statusCode})');
    }
  }

  @override
  Future<VerifyResult> verify(ServiceConfig c) async {
    // §4.2：GET /?list-type=2&max-keys=1，200 即凭证与桶权限全通。
    final uri = _uri(c, query: {'list-type': '2', 'max-keys': '1'});
    final res = await _get(c, uri, 'GET ${uri.host}/');
    final body = await _bodyText(res);
    if (res.statusCode == 200) return VerifyResult(true);
    return VerifyResult(false, _verifyFailMessage(c, res.statusCode, body));
  }

  @override
  Future<CloudQuota> quota(ServiceConfig c, {bool force = false}) async {
    final hit = _quotaCache[c.id];
    if (!force &&
        hit != null &&
        _clock().difference(hit.$1) < s3QuotaTtl) {
      return hit.$2;
    }
    // ListAllMyBuckets：**只能打根 endpoint**（R5），不带桶前缀。
    final uri = _uri(c, rootEndpoint: true);
    final res = await _get(c, uri, 'GET ${uri.host}/ (ListAllMyBuckets)');
    final body = await _bodyText(res);
    // V1.41 R2 项②：403 = 子账户常无 ListAllMyBuckets 全局列举权限（桶级操作
    // 仍可正常同步），这不是错误而是「容量不可见」——优雅降级为 null 配额，
    // 只 warn 一次，绝不让整条同步链因容量行报 StateError。
    // 评审修复轮1 Minor-1：降级结果同样进 5min 缓存（否则每次刷 UI 都重打
    // 网络），force 仍可穿透重拉。
    if (res.statusCode == 403) {
      _warnQuotaDegraded(c, 'ListAllMyBuckets 403（子账户无全局列举权限）');
      return _cacheQuotaDegraded(c);
    }
    if (res.statusCode != 200) {
      throw StateError('ListAllMyBuckets 失败(${res.statusCode})：'
          '${_brief(body)}');
    }
    // 200 但回包根本不是 ListAllMyBuckets 形态（如误把坚果云 endpoint 配成
    // S3 服务，返回 <s:user>）：同样降级 null + warn，不强喂 parseListAllMyBuckets
    // 得 0 用量误导用户。降级结果同进 5min 缓存（评审修复轮1 Minor-1）。
    if (!_isListAllMyBucketsShape(body)) {
      _warnQuotaDegraded(c, '回包非 ListAllMyBuckets 形态');
      return _cacheQuotaDegraded(c);
    }
    final q = parseListAllMyBuckets(body);
    _quotaCache[c.id] = (_clock(), q);
    return q;
  }

  /// 降级 null 配额写入 5min 容量缓存并返回（评审修复轮1 Minor-1）。
  CloudQuota _cacheQuotaDegraded(ServiceConfig c) {
    final degraded = CloudQuota(quotaBytes: null, usedBytes: null);
    _quotaCache[c.id] = (_clock(), degraded);
    return degraded;
  }

  @override
  void close() {
    _client?.close();
    _client = null;
  }

  // —— 内部件 ——

  Future<String> _getBody(
      ServiceConfig c, Uri uri, String label) async {
    final res = await _get(c, uri, label);
    final body = await _bodyTextChecked(res, label);
    return body;
  }

  Future<http.StreamedResponse> _get(
      ServiceConfig c, Uri uri, String label) async {
    final signer = await _signer(c);
    return gate.send(
      _ensureClient(),
      () => signer.sign(http.Request('GET', uri),
          payloadHash: SigV4Signer.emptySha256),
      config: c,
      label: label,
    );
  }

  Future<String> _bodyTextChecked(
      http.StreamedResponse res, String label) async {
    final body = await _bodyText(res);
    if (res.statusCode != 200) {
      throw StateError('$label 失败(${res.statusCode})：${_brief(body)}');
    }
    // R12：XML 恒定 utf8.decode(bodyBytes)，绝不用 response.body 猜编码。
    return body;
  }

  /// SigV4 签名器构造（T18 携带修复：SK 缺失 **fail-fast**——空钥签名只会拿到
  /// 服务端 403 误导性回包，抛明确配置异常，让 S2 连接验证能显示人话原因）。
  Future<SigV4Signer> _signer(ServiceConfig c) async {
    final sk = await _vault.read(c.id);
    if (sk == null || sk.isEmpty) {
      throw StateError('Secret Key 缺失：请在「服务配置」为该服务存入密钥'
          '（保险箱键 ${CredentialVault.keyFor(c.id)} 为空，拒绝以空钥签名）');
    }
    return SigV4Signer(
      accessKey: c.account,
      secretKey: sk,
      region: c.region.isEmpty ? s3DefaultRegion : c.region,
      service: 's3',
      clock: _clock,
    );
  }

  /// apiUrl → 根 URI（T18 携带修复：解析失败/缺 scheme **不再静默回落缺省
  /// host**——落错 host 的请求会被服务端以误导文案拒绝，掩盖配置错误；
  /// 直接抛配置异常，经 S2 连接验证显示给用户）。
  Uri _root(ServiceConfig c) {
    final uri = Uri.tryParse(c.apiUrl.trim());
    final httpScheme = uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    if (uri == null || !httpScheme || uri.host.isEmpty) {
      throw StateError('服务地址无效：apiUrl="${c.apiUrl}"'
          '（需含 http(s):// 方案与主机名，不再回落缺省 host）');
    }
    return uri;
  }

  /// virtual-hosted URL（§4.2）：`https://{bucket}.{hostNoScheme}/{key}`；
  /// [rootEndpoint] 时退回裸 host（ListAllMyBuckets 专用，R5）。
  /// 逻辑段/逻辑 query 经 [SigV4Signer.toWireUri] 统一 canonical 化，
  /// 保证「签名用的」与「发出去的」逐字节一致（§4.3 编码一致性，403 头号成因）。
  Uri _uri(ServiceConfig c,
      {List<String> keySegments = const [],
      Map<String, String>? query,
      bool rootEndpoint = false}) {
    final base = _root(c);
    final host = rootEndpoint || c.bucket.isEmpty
        ? base.host
        : '${c.bucket}.${base.host}';
    return SigV4Signer.toWireUri(Uri(
      scheme: base.scheme,
      host: host,
      port: base.hasPort ? base.port : null,
      pathSegments: keySegments,
      queryParameters: query,
    ));
  }

  /// cloudDirName（归一去首尾 `/`）的非空段链；空则不加前缀。
  List<String> _dirSegments(ServiceConfig c) => _normSegments(c.cloudDirName);

  String _dirPrefixOf(String cloudDirName) {
    final segs = _normSegments(cloudDirName);
    return segs.isEmpty ? '' : '${segs.join('/')}/';
  }

  /// 相对路径 → S3 key：`{cloudDirName}/{relative}`（T13 钉死口径）。
  String _keyFor(ServiceConfig c, String cloudRelative) {
    final dir = _dirSegments(c);
    final rel = _normSegments(cloudRelative);
    return [...dir, ...rel].join('/');
  }

  static String _stripPrefix(String key, String prefix) =>
      prefix.isNotEmpty && key.startsWith(prefix)
          ? key.substring(prefix.length)
          : key;

  List<String> _normSegments(String rel) =>
      rel.split('/').where((s) => s.isNotEmpty && s != '.').toList();

  Future<String> _bodyText(http.StreamedResponse res) async {
    final bytes = await res.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _brief(String body) =>
      body.replaceAll(RegExp(r'\s+'), ' ').trim().split('').take(200).join();

  String _verifyFailMessage(ServiceConfig c, int status, String body) {
    final reason = _brief(body);
    // R14 文案分协议：缤纷云 403 / 400 MissingFields 的头号成因是子账户未分配
    // 该桶权限或桶名/Endpoint 填错（V1.41 R2 项③——给出可操作控制台路径）。
    const permHint = '缤纷云：子账户可能未分配该桶权限，或桶名/Endpoint 有误'
        '（控制台→子账户→分配桶权限）';
    return switch (status) {
      401 => '认证失败（401）：缤纷云需用控制台创建的**子账户** '
          'Access Key/Secret Key（主账户密钥不可直连）。$reason',
      403 => '认证失败（403）：$permHint；并使用子账户（非主账户）密钥。$reason',
      400 => body.contains('MissingFields')
          ? '字段缺失（400 MissingFields）：$permHint。$reason'
          // R3④：400 InvalidRequest 头号成因同 MissingFields（桶名/权限/
          // Endpoint 配置面）；附实际请求主机便于肉眼核对桶名是否填错。
          : '连接验证失败（400）：$permHint。'
              '当前请求 ${_uri(c, query: const {'list-type': '2', 'max-keys': '1'}).host}。$reason',
      404 => '桶不存在（404）：请核对桶名与 endpoint：$reason',
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
