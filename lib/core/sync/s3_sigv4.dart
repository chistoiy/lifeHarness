import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 一次签名的全部中间串（【云盘】§4.3；brief 钉死的 `debugCanonical()` 载荷）。
/// 测试据此钉死 canonical URI/query/headers/scope 的结构，端到端向量比对逐字节。
class SigV4Canonical {
  const SigV4Canonical({
    required this.method,
    required this.host,
    required this.amzDate,
    required this.dateStamp,
    required this.credentialScope,
    required this.canonicalUri,
    required this.canonicalQuery,
    required this.canonicalHeaders,
    required this.signedHeaders,
    required this.payloadHash,
    required this.canonicalRequest,
    required this.stringToSign,
    required this.signature,
  });

  final String method;
  final String host;

  /// `yyyyMMddTHHmmssZ`（UTC）。
  final String amzDate;

  /// `yyyyMMdd`（amzDate 的日期段，进 credentialScope）。
  final String dateStamp;
  final String credentialScope;
  final String canonicalUri;
  final String canonicalQuery;
  final String canonicalHeaders;
  final String signedHeaders;
  final String payloadHash;
  final String canonicalRequest;
  final String stringToSign;
  final String signature;
}

/// 手写 AWS Signature V4（【云盘】§4.3，缤纷云 service 段固定 `s3`）。
///
/// 钉死口径：
/// - canonical URI 分段 percent-encode（encodeSlash:false），与实际请求 URL
///   **完全一致**——[sign] 会直接把 `req.url` 重写为 canonical 形态，杜绝
///   「Dart Uri 组件编码器保留 `& + =`」与 SigV4 严格编码的分歧（403 头号成因）；
/// - canonical query 按编码后 key 排序（同 key 再按 value），键值各自编码
///   （encodeSlash:true）；
/// - SignedHeaders 字典序固定三元组：`host;x-amz-content-sha256;x-amz-date`；
/// - credentialScope = `{yyyyMMdd}/{service}/{region}/aws4_request`；
/// - PayloadHash 三态（空体 GET=SHA256("") / 流式 PUT=UNSIGNED-PAYLOAD /
///   其他=实体 SHA256）由调用方传入，本类只负责入签与落头；
/// - 时间戳取注入 clock 的 UTC（退避重发经 HttpGate 工厂重建 → 每次 sign
///   重读时钟，日期参与签名，已知坑「复用旧请求必签名过期」的解法侧）。
class SigV4Signer {
  SigV4Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.service = 's3',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String accessKey;
  final String secretKey;
  final String region;
  final String service;
  final DateTime Function() _clock;

  SigV4Canonical? _last;

  /// SHA256("")（空体 GET 的 payloadHash，协议文档 §4.3 三态之一）。
  static const emptySha256 =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  /// 流式 PUT 的 payloadHash（算不出实体摘要，缤纷云实测接受）。
  static const unsignedPayload = 'UNSIGNED-PAYLOAD';

  /// 固定签名头集（字典序）。
  static const signedHeadersTriple = 'host;x-amz-content-sha256;x-amz-date';

  /// 最近一次 [sign] 的全部中间串；未签过抛 [StateError]（防陈旧串误判）。
  SigV4Canonical debugCanonical() {
    final last = _last;
    if (last == null) {
      throw StateError('debugCanonical 需先调用 sign()：无中间串可取');
    }
    return last;
  }

  /// 就地为 [req] 附加 x-amz-date / x-amz-content-sha256 / Authorization。
  ///
  /// 前置约束（§4.3 编码一致性）：`req.url` 必须已是 canonical wire 形态
  /// ——由 [toWireUri] 从逻辑组件构造。sign 前逐字节校验
  /// `url.path == CanonicalURI && url.query == CanonicalQueryString`，
  /// 不一致直接抛 [StateError]（「规范请求与实际请求不一致」是 403 头号成因，
  /// 宁可本地拒发也不让服务端回 SignatureDoesNotMatch）。返回同一对象。
  http.BaseRequest sign(http.BaseRequest req, {required String payloadHash}) {
    final uri = req.url;
    final now = _clock().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = '$dateStamp'
        'T${_two(now.hour)}${_two(now.minute)}${_two(now.second)}Z';
    final credentialScope = '$dateStamp/$service/$region/aws4_request';

    final canonicalUri = _canonicalUriFor(uri);
    final canonicalQuery = _canonicalQueryFor(uri);
    if (uri.path != canonicalUri || uri.query != canonicalQuery) {
      throw StateError('SigV4 编码不一致：wire "${uri.path}?${uri.query}" ≠ '
          'canonical "$canonicalUri?$canonicalQuery"——'
          '请求 URL 必须经 SigV4Signer.toWireUri 构造');
    }
    final host = _hostHeaderFor(uri);
    // R5d 真云验证修正：x-amz-copy-source（CopyObject）必须在签名头集内，
    // 且按头名字典序插在 content-sha256 与 date 之间；缺失该头时行为不变。
    final copySource = req.headers['x-amz-copy-source'];
    final canonicalHeaders = 'host:$host\n'
        'x-amz-content-sha256:$payloadHash\n'
        '${copySource != null ? 'x-amz-copy-source:$copySource\n' : ''}'
        'x-amz-date:$amzDate\n';
    final signedHeaders = copySource == null
        ? signedHeadersTriple
        : 'host;x-amz-content-sha256;x-amz-copy-source;x-amz-date';
    final canonicalRequest = '${req.method}\n'
        '$canonicalUri\n$canonicalQuery\n'
        '$canonicalHeaders\n' // 自带尾 \n，再补模板 \n → 头块与 SignedHeaders 间的空行
        '$signedHeaders\n$payloadHash';
    final stringToSign = 'AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n'
        '${sha256Hex(canonicalRequest)}';
    final signature = hmacSha256Hex(
        deriveSigningKey(secretKey, dateStamp, region, service), stringToSign);

    req.headers['x-amz-date'] = amzDate;
    req.headers['x-amz-content-sha256'] = payloadHash;
    req.headers['authorization'] = 'AWS4-HMAC-SHA256 '
        'Credential=$accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    _last = SigV4Canonical(
      method: req.method,
      host: host,
      amzDate: amzDate,
      dateStamp: dateStamp,
      credentialScope: credentialScope,
      canonicalUri: canonicalUri,
      canonicalQuery: canonicalQuery,
      canonicalHeaders: canonicalHeaders,
      signedHeaders: signedHeadersTriple,
      payloadHash: payloadHash,
      canonicalRequest: canonicalRequest,
      stringToSign: stringToSign,
      signature: signature,
    );
    return req;
  }

  // —— canonical 构造（纯函数，测试直钉）——

  /// 逻辑组件（pathSegments/queryParameters 均为**真实段名与真实值**）→
  /// canonical wire Uri：path 逐段 percent-encode（encodeSlash:false）、
  /// query 按编码后 key 排序且键值各自编码。往返稳定（wire 解码再 canonical 化
  /// 得同一串），[sign] 的一致性校验据此不会误伤；构造 S3 请求 URL 的唯一入口。
  static Uri toWireUri(Uri logical) {
    final query = _canonicalQueryFor(logical);
    return Uri(
      scheme: logical.scheme,
      host: logical.host,
      port: logical.hasPort ? logical.port : null,
      path: _canonicalUriFor(logical),
      query: query.isEmpty ? null : query,
    );
  }

  /// AWS URI-encode：A-Za-z0-9-._~ 之外全部 %XX（大写十六进制、UTF-8 字节）；
  /// `encodeSlash:false` 时 `/` 保留（path 分段用），query 侧保留会破坏定界。
  static String uriEncode(String raw, {bool encodeSlash = true}) {
    final out = StringBuffer();
    for (final byte in utf8.encode(raw)) {
      final isUnreserved = (byte >= 0x41 && byte <= 0x5A) || // A-Z
          (byte >= 0x61 && byte <= 0x7A) || // a-z
          (byte >= 0x30 && byte <= 0x39) || // 0-9
          byte == 0x2D || // -
          byte == 0x2E || // .
          byte == 0x5F || // _
          byte == 0x7E || // ~
          (byte == 0x2F && !encodeSlash); // /（仅不编码斜杠时保留）
      if (isUnreserved) {
        out.write(String.fromCharCode(byte));
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  static String sha256Hex(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static String hmacSha256Hex(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).toString();

  /// 派生签名密钥四段链：AWS4+SK → dateStamp → region → service → aws4_request。
  static List<int> deriveSigningKey(
    String secretKey,
    String dateStamp,
    String region,
    String service,
  ) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$secretKey'), dateStamp);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, service);
    return hmac(kService, 'aws4_request');
  }

  // —— 内部件 ——

  /// path 分段编码（每段 uriEncode(encodeSlash:false) 再拼 '/'）；空 path → '/'。
  static String _canonicalUriFor(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return '/';
    return '/${segments.map((s) => uriEncode(s, encodeSlash: false)).join('/')}';
  }

  /// 按编码后 key 排序（同 key 按编码后 value），键值各自 uriEncode。
  static String _canonicalQueryFor(Uri uri) {
    final params = uri.queryParameters;
    if (params.isEmpty) return '';
    final pairs = <(String, String)>[];
    params.forEach((k, v) => pairs.add((uriEncode(k), uriEncode(v))));
    pairs.sort((a, b) {
      final byKey = a.$1.compareTo(b.$1);
      return byKey != 0 ? byKey : a.$2.compareTo(b.$2);
    });
    return pairs.map((e) => '${e.$1}=${e.$2}').join('&');
  }

  /// host 头：小写主机名；仅当端口偏离 scheme 缺省时追加 `:port`。
  static String _hostHeaderFor(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!uri.hasPort) return host;
    final defaultPort = uri.scheme == 'http' ? 80 : 443;
    return uri.port == defaultPort ? host : '$host:${uri.port}';
  }

  static String _dateStamp(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}${_two(utc.month)}${_two(utc.day)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}
