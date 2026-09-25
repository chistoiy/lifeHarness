import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifeharness/core/sync/s3_sigv4.dart';

/// Task 14 Step 1：手写 SigV4（【云盘】§4.3）。
///
/// 纪律（§9 单测不真连公网）：全程固定 clock + 结构断言钉死 canonical 构造；
/// 已知向量取 **AWS 官方 SigV4 test suite get-vanilla**（.creq/.sts/.authz 原文
/// 字节，推演过程见 task-14-report.md）——期望值不虚构：
/// 官方向量校验 HMAC/SHA 密码学核，自推小 GET 向量（PowerShell .NET 独立实现
/// 交叉复算）校验端到端签名链。
void main() {
  const ak = 'AKIDEXAMPLE';
  const sk = 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY';
  const empty = SigV4Signer.emptySha256;
  final fixedClock = DateTime.utc(2026, 9, 25, 3, 30, 0);

  SigV4Signer signerAt(DateTime utc,
          {String region = 'cn-east-1', String service = 's3'}) =>
      SigV4Signer(
          accessKey: ak,
          secretKey: sk,
          region: region,
          service: service,
          clock: () => utc);

  http.Request getRoot() => http.Request(
      'GET',
      SigV4Signer.toWireUri(
          Uri(scheme: 'https', host: 'photo.s3.bitiful.net')));

  group('canonical 构造钉死', () {
    test('uriEncode：中文/空格/+/=/斜杠/保留字符集（A-Za-z0-9-._~ 之外全编码）',
        () {
      expect(SigV4Signer.uriEncode('a b'), 'a%20b');
      expect(SigV4Signer.uriEncode('中'), '%E4%B8%AD');
      expect(SigV4Signer.uriEncode('w~x-y.z_'), 'w~x-y.z_');
      expect(SigV4Signer.uriEncode('a+b=c&d'), 'a%2Bb%3Dc%26d');
      expect(SigV4Signer.uriEncode('a/b'), 'a%2Fb');
      expect(SigV4Signer.uriEncode('a/b', encodeSlash: false), 'a/b');
      expect(SigV4Signer.uriEncode('100%*x'), '100%25%2Ax');
    });

    test('canonical URI：分段 percent-encode（encodeSlash:false），中文+空格+%2B+%3D',
        () {
      final s = signerAt(fixedClock);
      final req = http.Request(
          'GET',
          SigV4Signer.toWireUri(Uri(
              scheme: 'https',
              host: 'photo.s3.bitiful.net',
              pathSegments: ['中文 目录', 'a b+equals=.txt'])));
      s.sign(req, payloadHash: empty);
      final d = s.debugCanonical();
      expect(
          d.canonicalUri,
          '/%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95'
          '/a%20b%2Bequals%3D.txt');
      expect(req.url.path, d.canonicalUri,
          reason: '实际请求 URL 与 canonical 编码一致（§4.3：两处不一致是 403 头号成因）');
      expect(req.url.toString(),
          'https://photo.s3.bitiful.net/%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95/a%20b%2Bequals%3D.txt');
    });

    test('toWireUri 往返稳定：已编码 wire 再 canonical 化得同一串', () {
      final logical = Uri(
          scheme: 'https',
          host: 'photo.s3.bitiful.net',
          pathSegments: ['pct%20literal', '中文'],
          queryParameters: {'prefix': 'a b+c&d=e', 'marker': 'x/y'});
      final wire = SigV4Signer.toWireUri(logical);
      final again = SigV4Signer.toWireUri(wire);
      expect(again.path, wire.path);
      expect(again.query, wire.query);
      expect(wire.path, '/pct%2520literal/%E4%B8%AD%E6%96%87');
    });

    test('canonical query：按 key 排序、键值各自编码、query 侧 encodeSlash:true', () {
      final s = signerAt(fixedClock);
      final req = http.Request(
          'GET',
          SigV4Signer.toWireUri(Uri(
              scheme: 'https',
              host: 'photo.s3.bitiful.net',
              path: '/',
              queryParameters: {
                'prefix': 'my photo+s/x=1',
                'max-keys': '1000',
                'list-type': '2',
              })));
      s.sign(req, payloadHash: empty);
      final d = s.debugCanonical();
      expect(d.canonicalQuery,
          'list-type=2&max-keys=1000&prefix=my%20photo%2Bs%2Fx%3D1');
      expect(req.url.query, d.canonicalQuery,
          reason: 'wire query 与 canonical 完全一致（含顺序）');
    });

    test('未走 toWireUri 的逻辑 URL（path 含字面 &）→ sign 拒发 StateError', () {
      // Dart 组件编码器在 path 里保留 & + =，与 SigV4 严格编码不一致——
      // 若放任入签，服务端按收到的原串复算必 403；本守护把问题拦在本地。
      final s = signerAt(fixedClock);
      final req = http.Request(
          'GET',
          Uri(
              scheme: 'https',
              host: 'photo.s3.bitiful.net',
              pathSegments: ['a&b.txt']));
      expect(req.url.path, '/a&b.txt', reason: '前提钉死：Dart 未转义 &');
      expect(() => s.sign(req, payloadHash: empty), throwsStateError);
    });

    test('canonical headers/SignedHeaders 字典序 + credentialScope 形态 + 整体结构',
        () {
      final s = signerAt(fixedClock);
      final req = getRoot();
      s.sign(req, payloadHash: empty);
      final d = s.debugCanonical();
      expect(
          d.canonicalHeaders,
          'host:photo.s3.bitiful.net\n'
          'x-amz-content-sha256:$empty\n'
          'x-amz-date:20260925T033000Z\n');
      expect(d.signedHeaders, 'host;x-amz-content-sha256;x-amz-date');
      expect(d.credentialScope, '20260925/cn-east-1/s3/aws4_request');
      expect(
          d.canonicalRequest,
          'GET\n/\n\n'
          'host:photo.s3.bitiful.net\n'
          'x-amz-content-sha256:$empty\n'
          'x-amz-date:20260925T033000Z\n'
          '\n'
          'host;x-amz-content-sha256;x-amz-date\n'
          '$empty');
      expect(req.headers['x-amz-date'], '20260925T033000Z');
      expect(req.headers['x-amz-content-sha256'], empty);
      expect(
          req.headers['authorization'],
          'AWS4-HMAC-SHA256 Credential=$ak/20260925/cn-east-1/s3/aws4_request, '
          'SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
          'Signature=${d.signature}');
    });

    test('桶名含点：host 段进 canonical headers，path 编码不受影响（virtual-hosted）',
        () {
      final s = signerAt(fixedClock);
      final req = http.Request(
          'GET',
          SigV4Signer.toWireUri(Uri(
              scheme: 'https',
              host: 'my.bucket.s3.bitiful.net',
              pathSegments: ['a.txt'])));
      s.sign(req, payloadHash: empty);
      final d = s.debugCanonical();
      expect(d.host, 'my.bucket.s3.bitiful.net');
      expect(d.canonicalHeaders, contains('host:my.bucket.s3.bitiful.net\n'));
      expect(d.canonicalUri, '/a.txt');
      expect(req.url.host, 'my.bucket.s3.bitiful.net');
    });
  });

  group('PayloadHash 三态（§4.3）', () {
    test('空体 GET = SHA256("")', () {
      final s = signerAt(fixedClock);
      final req = getRoot();
      s.sign(req, payloadHash: SigV4Signer.emptySha256);
      expect(req.headers['x-amz-content-sha256'],
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(SigV4Signer.sha256Hex(''),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('流式 PUT = UNSIGNED-PAYLOAD，且进 canonical 末段', () {
      final s = signerAt(fixedClock);
      final req = http.Request(
          'PUT',
          SigV4Signer.toWireUri(Uri(
              scheme: 'https',
              host: 'photo.s3.bitiful.net',
              pathSegments: ['k.bin'])));
      s.sign(req, payloadHash: SigV4Signer.unsignedPayload);
      expect(req.headers['x-amz-content-sha256'], 'UNSIGNED-PAYLOAD');
      expect(s.debugCanonical().canonicalRequest.endsWith('\nUNSIGNED-PAYLOAD'),
          isTrue);
    });

    test('带体请求 = 实体 SHA256（hello 的公开已知摘要）', () {
      final s = signerAt(fixedClock);
      final body = http.Request('POST',
          SigV4Signer.toWireUri(
              Uri(scheme: 'https', host: 'photo.s3.bitiful.net')))
        ..body = 'hello';
      final hash = SigV4Signer.sha256Hex('hello');
      s.sign(body, payloadHash: hash);
      expect(hash, '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
      expect(body.headers['x-amz-content-sha256'], hash);
    });
  });

  test('签名日期取自注入 clock：拨 +20min 跨日 → X-Amz-Date 与 credentialScope 同步变',
      () {
    final t0 = DateTime.utc(2026, 9, 25, 23, 45, 0);
    final s = signerAt(t0);
    s.sign(getRoot(), payloadHash: empty);
    final d0 = s.debugCanonical();
    expect(d0.amzDate, '20260925T234500Z');
    expect(d0.credentialScope, '20260925/cn-east-1/s3/aws4_request');

    s.sign(getRoot(), payloadHash: empty); // 重签同对象也拿新时刻
    final s2 = signerAt(t0.add(const Duration(minutes: 20)));
    final req2 = getRoot();
    s2.sign(req2, payloadHash: empty);
    final d1 = s2.debugCanonical();
    expect(d1.amzDate, '20260926T000500Z');
    expect(d1.credentialScope, '20260926/cn-east-1/s3/aws4_request');
    expect(req2.headers['x-amz-date'], '20260926T000500Z');
    expect(d1.dateStamp, isNot(d0.dateStamp));
    expect(d1.signature, isNot(d0.signature),
        reason: '日期参与签名：scope 变则签名必变（退避重发必须重建的根因）');
  });

  group('已知向量（不虚构期望值）', () {
    test('AWS 官方 SigV4 test suite get-vanilla：密码学核逐字节复现', () {
      // 期望值出处：docs.aws.amazon.com《Signature Version 4 test suite》
      // get-vanilla.creq/.sts/.authz 原文（本次经 GitHub 镜像仓拉取，LF 行尾）。
      // 该向量签名头集为 host;x-amz-date（不含 x-amz-content-sha256），
      // 与本项目固定三元组不同形态，故直接校验密码学核 + canonical 哈希函数：
      // 若 creqHash 与最终 Signature 均命中官方值，则 SHA256/HMAC/推导链正确。
      const creq = 'GET\n/\n\n'
          'host:example.amazonaws.com\n'
          'x-amz-date:20150830T123600Z\n'
          '\n'
          'host;x-amz-date\n'
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(SigV4Signer.sha256Hex(creq),
          'bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63');
      const sts = 'AWS4-HMAC-SHA256\n'
          '20150830T123600Z\n'
          '20150830/us-east-1/service/aws4_request\n'
          'bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63';
      final key =
          SigV4Signer.deriveSigningKey(sk, '20150830', 'us-east-1', 'service');
      expect(SigV4Signer.hmacSha256Hex(key, sts),
          '5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31');
    });

    test('端到端全链：小 GET 的完整签名链（期望值经 PowerShell .NET 独立复算）', () {
      // 输入：GET https://photo.s3.bitiful.net/'report 1.txt'，无 query，
      // clock 2026-09-25T03:30:00Z，region cn-east-1，service s3。
      // 推演（详见 task-14-report.md）：
      //   canonicalRequest → sha256 = e067db93…
      //   stringToSign = AWS4-HMAC-SHA256\n20260925T033000Z\n
      //                  20260925/cn-east-1/s3/aws4_request\ne067db93…
      //   signingKey = HMAC 四段推导（AWS4+sk → 20260925 → cn-east-1 → s3
      //                → aws4_request），signature = c7193e5a…
      const handCreq = 'GET\n/report%201.txt\n\n'
          'host:photo.s3.bitiful.net\n'
          'x-amz-content-sha256:$empty\n'
          'x-amz-date:20260925T033000Z\n'
          '\n'
          'host;x-amz-content-sha256;x-amz-date\n'
          '$empty';
      expect(SigV4Signer.sha256Hex(handCreq),
          'e067db93b934bf0530f2a526533f3b3e90a76ba3d017319c381eb721b7844dc9');
      final s = signerAt(fixedClock);
      final req = http.Request(
          'GET',
          SigV4Signer.toWireUri(Uri(
              scheme: 'https',
              host: 'photo.s3.bitiful.net',
              pathSegments: ['report 1.txt'])));
      s.sign(req, payloadHash: empty);
      final d = s.debugCanonical();
      expect(d.canonicalRequest, handCreq);
      expect(
          d.stringToSign,
          'AWS4-HMAC-SHA256\n20260925T033000Z\n'
          '20260925/cn-east-1/s3/aws4_request\n'
          'e067db93b934bf0530f2a526533f3b3e90a76ba3d017319c381eb721b7844dc9');
      expect(d.signature,
          'c7193e5a4132bccaebfbd76ed6b2d88218990f558652374bf6c5d5f7cd10d46d');
      expect(
          req.headers['authorization'],
          'AWS4-HMAC-SHA256 Credential=$ak/20260925/cn-east-1/s3/aws4_request, '
          'SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
          'Signature=c7193e5a4132bccaebfbd76ed6b2d88218990f558652374bf6c5d5f7cd10d46d');
      expect(req.url.toString(), 'https://photo.s3.bitiful.net/report%201.txt');
    });
  });

  test('未 sign 前取 debugCanonical 抛 StateError（防拿陈旧中间串）', () {
    final s = signerAt(fixedClock);
    expect(s.debugCanonical, throwsStateError);
  });
}
