import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/sync/credential_vault.dart';
import 'package:lifeharness/core/sync/http_gate.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/s3_sigv4.dart';
import 'package:lifeharness/core/sync/s3_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/webdav_store.dart';

/// Task 14 Step 3：S3Store（缤纷云，【云盘】§4.2）。
///
/// 纪律（§9）：MockClient 假 client + 假 sleeper + 内存保险箱，不真连公网；
/// 每个请求都断言 virtual-hosted host 与 SigV4 Authorization 头真实附着。
void main() {
  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  ServiceConfig cfg(
          {String id = 'svcS3',
          String dir = 'sync',
          String bucket = 'photo',
          String region = 'cn-east-1'}) =>
      ServiceConfig(
        id: id,
        provider: StoreProviderKind.s3,
        apiUrl: 'https://s3.bitiful.net',
        account: 'AKIA-TEST',
        region: region,
        bucket: bucket,
        cloudDirName: dir,
        requestIntervalMs: 0,
      );

  Future<CredentialVault> vaultWith(String id, [String secret = 'sk&1']) async {
    final v = CredentialVault.inMemory();
    await v.write(id, secret);
    return v;
  }

  S3Store storeOf(http.Client client,
          {required CredentialVault vault, DateTime Function()? clock}) =>
      S3Store(
        gate: HttpGate(sleeper: (d) async {}),
        vault: vault,
        client: () => client,
        clock: clock,
      );

  /// 断言请求已带 SigV4 头（三元组 + 缤纷云 region 缺省档不参与——这里给全）。
  void expectSigned(http.Request req, {String? payloadHash}) {
    expect(req.headers['authorization'],
        startsWith('AWS4-HMAC-SHA256 Credential=AKIA-TEST/'));
    expect(req.headers['authorization'],
        contains(', SignedHeaders=host;x-amz-content-sha256;x-amz-date, '));
    expect(req.headers['authorization'], contains('/s3/cn-east-1/aws4_request'));
    expect(req.headers['x-amz-date'], isNotNull);
    expect(req.headers['x-amz-content-sha256'],
        payloadHash ?? SigV4Signer.emptySha256);
  }

  // —— ListObjectsV2 XML 夹具 ——

  String contentsXml(String key, {int size = 1, String etag = 'e1'}) =>
      '<Contents><Key>$key</Key>'
      '<LastModified>2026-09-25T08:00:00.000Z</LastModified>'
      '<ETag>&quot;$etag&quot;</ETag><Size>$size</Size></Contents>';

  String listXml(List<String> contents,
          {bool truncated = false, String? nextToken}) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<ListObjectsV2Result xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
      '<Name>photo</Name><Prefix>sync/</Prefix><MaxKeys>1000</MaxKeys>'
      '<IsTruncated>${truncated ? 'true' : 'false'}</IsTruncated>'
      '${contents.join()}'
      '${nextToken == null ? '' : '<NextContinuationToken>$nextToken</NextContinuationToken>'}'
      '</ListObjectsV2Result>';

  // —— ListAllMyBuckets（含缤纷云私有 *Bytes 字段）样例 XML ——

  const bucketsXml = '''<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Owner><ID>abc</ID><DisplayName>me</DisplayName></Owner>
  <Buckets>
    <Bucket><Name>photos</Name><CreationDate>2026-09-01T00:00:00.000Z</CreationDate>
      <ImageBytes>1000</ImageBytes><ImageFiles>3</ImageFiles>
      <TmpBytes>10</TmpBytes><TmpFiles>1</TmpFiles>
      <VideoBytes>200</VideoBytes>
      <AudioBytes>20</AudioBytes>
      <OtherBytes>5</OtherBytes>
      <Folders>2</Folders>
    </Bucket>
    <Bucket><Name>videos</Name><CreationDate>2026-09-02T00:00:00.000Z</CreationDate>
      <ImageBytes>0</ImageBytes>
      <TmpBytes>30</TmpBytes>
      <VideoBytes>70</VideoBytes>
    </Bucket>
  </Buckets>
</ListAllMyBucketsResult>''';

  group('list：递归 ListObjectsV2（R6）', () {
    test('两页 IsTruncated 聚合 + 尾 `/` 占位剔除 + canonical query 顺序 + 虚拟主机',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        expect(req.method, 'GET');
        expect(req.url.host, 'photo.s3.bitiful.net');
        expect(req.url.path, '/');
        expectSigned(req);
        final token = req.url.queryParameters['continuation-token'];
        if (token == null) {
          expect(
              req.url.query, 'list-type=2&max-keys=1000&prefix=sync%2F',
              reason: 'wire query = canonical（按 key 排序、值内 / 编码为 %2F，§4.3）');
          return http.Response.bytes(
              utf8.encode(listXml([
                contentsXml('sync/a.txt', size: 11, etag: 'e-a'),
                contentsXml('sync/dir/'), // 目录占位（尾 /），必须剔除
                contentsXml('sync/sub/b 中文&amp;c.lhbak', size: 7, etag: 'e-b'),
              ], truncated: true, nextToken: 'tok+1&x')),
              200);
        }
        expect(token, 'tok+1&x', reason: '翻页 token 原样回传（编码由签名侧重写）');
        expect(
            req.url.query,
            'continuation-token=tok%2B1%26x'
            '&list-type=2&max-keys=1000&prefix=sync%2F');
        return http.Response.bytes(
            utf8.encode(listXml([
              contentsXml('sync/c.txt', size: 3, etag: 'e-c'),
              contentsXml('sync/'), // 根占位，同样剔除
            ])),
            200);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      final listing = await store.list(cfg(), 'sync');

      expect(listing.files.map((f) => f.relativePath),
          ['a.txt', 'sub/b 中文&c.lhbak', 'c.txt'],
          reason: 'relativePath 剥掉 {cloudDirName}/ 前缀；占位不入列');
      expect(listing.files[0].size, 11);
      expect(listing.files[0].etag, 'e-a', reason: 'ETag 去 &quot; 引号');
      expect(listing.files[1].modified, DateTime.utc(2026, 9, 25, 8));
      expect(requests, hasLength(2));
      store.close();
    });

    test('200 页硬顶：恒 IsTruncated 也止步 200 次请求并 warn', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        return http.Response.bytes(
            utf8.encode(listXml([contentsXml('sync/f$n.txt')],
                truncated: true, nextToken: 't$n')),
            200);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      final listing = await store.list(cfg(), 'sync');
      expect(n, 200, reason: 'R6 翻页硬顶 200 页');
      expect(listing.files, hasLength(200));
      expect(
        AppLog.lines.where((l) => l.level == LhLevel.warn),
        isNotEmpty,
        reason: '触发硬顶必须 warn，不静默截断',
      );
      store.close();
    });

    test('清单缓存 60s + 键带 serviceId + force 穿透', () async {
      var n = 0;
      var t = DateTime.utc(2026, 9, 25, 12);
      final client = MockClient((req) async {
        n++;
        return http.Response.bytes(
            utf8.encode(listXml([contentsXml('sync/a.txt')])), 200);
      });
      // T18 携带修复后 SK 缺失 fail-fast：跨 serviceId 用例先补记第二把密钥。
      final v = await vaultWith('svcS3');
      await v.write('other', 'sk-other');
      final store = storeOf(client, vault: v, clock: () => t);
      final c = cfg();
      await store.list(c, 'sync');
      expect(n, 1);
      await store.list(c, 'sync');
      expect(n, 1, reason: '60s 内命中缓存零请求');
      await store.list(cfg(id: 'other'), 'sync');
      expect(n, 2, reason: 'D3：缓存键 {serviceId}|{dir}');
      await store.list(c, 'sync', force: true);
      expect(n, 3);
      t = t.add(const Duration(seconds: 61));
      await store.list(c, 'sync');
      expect(n, 4, reason: '假时钟过 TTL 自动重拉');
      store.close();
    });

    test('R4：put 成功即作废本服务清单缓存（与 WebDAV 同口径，防同步后'
        'compare 拿旧清单报假差异）', () async {
      var lists = 0;
      final tmp = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}lhw_r4_s3.lhbak');
      tmp.writeAsStringSync('payload');
      addTearDown(() => tmp.deleteSync());
      final client = MockClient((req) async {
        if (req.method == 'PUT') return http.Response('', 200);
        lists++;
        return http.Response.bytes(
            utf8.encode(listXml([contentsXml('sync/z.lhbak')])), 200);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      final c = cfg();
      await store.list(c, 'sync');
      expect(lists, 1);
      await store.list(c, 'sync');
      expect(lists, 1, reason: '前置：60s 内命中缓存');
      await store.put(c, tmp.path, 'z.lhbak');
      await store.list(c, 'sync');
      expect(lists, 2, reason: 'put 成功后缓存作废，list 必重拉');
      store.close();
    });
  });

  test('list→get 直喂：key 前缀 {cloudDirName}/{relative} 两侧一致（T17 链路钉）',
      () async {
    final dir = Directory.systemTemp.createTempSync('lhw_s3_get');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gets = <http.Request>[];
    final client = MockClient((req) async {
      if (req.url.queryParameters.containsKey('list-type')) {
        return http.Response.bytes(
            utf8.encode(listXml([
              contentsXml('sync/文档 x&amp;y.lhbak', size: 4),
              contentsXml('sync/pct%20name.lhbak', size: 5),
            ])),
            200);
      }
      gets.add(req);
      expectSigned(req);
      return http.Response.bytes(utf8.encode('s3-内容-中文'), 200);
    });
    final store = storeOf(client, vault: await vaultWith('svcS3'));
    final c = cfg();

    final listing = await store.list(c, 'sync');
    expect(listing.files.map((f) => f.relativePath),
        ['文档 x&y.lhbak', 'pct%20name.lhbak'],
        reason: 'ListObjects key 是逻辑名（&amp; 实体还原；%20 属名字本身不解码）');

    final t1 = '${dir.path}${Platform.pathSeparator}f1.lhbak';
    await store.get(c, listing.files[0].relativePath, t1);
    expect(gets.last.url.host, 'photo.s3.bitiful.net');
    expect(
        gets.last.url.path,
        '/sync/%E6%96%87%E6%A1%A3%20x%26y.lhbak',
        reason: 'wire path = canonical：中文→percent、空格→%20、&→%26');
    expect(gets.last.url.pathSegments, ['sync', '文档 x&y.lhbak']);
    expect(File(t1).readAsStringSync(), 's3-内容-中文');
    expect(File('$t1.part').existsSync(), isFalse, reason: '.part 被 rename 消耗');

    final t2 = '${dir.path}${Platform.pathSeparator}f2.lhbak';
    await store.get(c, listing.files[1].relativePath, t2);
    expect(gets.last.url.path, '/sync/pct%2520name.lhbak',
        reason: '字面 %20 的名字：% 转义为 %25，与 list key 往返一致');
    expect(gets.last.url.pathSegments, ['sync', 'pct%20name.lhbak']);
    store.close();
  });

  group('put/get 流式（P4/§4.2）', () {
    test('put：virtual-hosted 路径 + Content-Length 必给 + UNSIGNED-PAYLOAD 入签',
        () async {
      final tmp = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}lhw_s3_put.bin');
      tmp.writeAsStringSync('put-payload-中文');
      addTearDown(() => tmp.deleteSync());
      http.Request? put;
      final client = MockClient((req) async {
        expect(req.method, 'PUT');
        put = req;
        return http.Response('', 200);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));

      await store.put(cfg(), tmp.path, 'sub dir/报告 &x.txt');

      expect(put!.url.host, 'photo.s3.bitiful.net');
      expect(put!.url.path, '/sync/sub%20dir/%E6%8A%A5%E5%91%8A%20%26x.txt');
      expect(put!.url.pathSegments, ['sync', 'sub dir', '报告 &x.txt']);
      expect(put!.contentLength, tmp.lengthSync(),
          reason: '流式 PUT 必带 Content-Length（§4.2 传输行）');
      expectSigned(put!, payloadHash: SigV4Signer.unsignedPayload);
      expect(put!.bodyBytes, tmp.readAsBytesSync());
      store.close();
    });

    test('put 非 200 抛 StateError（带状态码与人话摘要）', () async {
      final tmp = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}lhw_s3_put403.bin');
      tmp.writeAsStringSync('x');
      addTearDown(() => tmp.deleteSync());
      final client = MockClient((req) async => http.Response('<Error/>', 403));
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      await expectLater(store.put(cfg(), tmp.path, 'a.bin'),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              allOf(contains('403'), contains('PUT')))));
      store.close();
    });
  });

  test('ensureDirectory：S3 扁平键空间，空实现零请求（R7）', () async {
    var n = 0;
    final client = MockClient((req) async {
      n++;
      return http.Response('', 200);
    });
    final store = storeOf(client, vault: await vaultWith('svcS3'));
    await store.ensureDirectory(cfg(), 'a/b');
    expect(n, 0);
    store.close();
  });

  group('verify：GET /?list-type=2&max-keys=1', () {
    test('200 → ok', () async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/');
        expect(req.url.query, 'list-type=2&max-keys=1');
        expect(req.url.host, 'photo.s3.bitiful.net');
        expectSigned(req);
        return http.Response.bytes(utf8.encode(listXml([])), 200);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      final v = await store.verify(cfg());
      expect(v.ok, isTrue);
      expect(v.message, isNull);
      store.close();
    });

    test('403 → 文案提示子账户 AK/SK + 桶权限（R14）', () async {
      final client = MockClient(
          (req) async => http.Response('<AccessDenied/>', 403));
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      final v = await store.verify(cfg());
      expect(v.ok, isFalse);
      expect(v.message, contains('子账户'));
      expect(v.message, contains('桶权限'));
      store.close();
    });

    test('R2③：403 / 400 MissingFields → 文案含「分配桶权限」控制台指引', () async {
      final s403 = S3Store(
        gate: HttpGate(sleeper: (d) async {}),
        vault: await vaultWith('svcS3'),
        client: () => MockClient(
            (req) async => http.Response('<AccessDenied/>', 403)),
      );
      expect((await s403.verify(cfg())).message, contains('分配桶权限'));
      s403.close();

      final s400 = S3Store(
        gate: HttpGate(sleeper: (d) async {}),
        vault: await vaultWith('svcS3'),
        client: () => MockClient((req) async => http.Response(
            '<Error><Code>MissingFields</Code></Error>', 400)),
      );
      expect((await s400.verify(cfg())).message, contains('分配桶权限'));
      s400.close();
    });

    test('R3④：400 InvalidRequest（非 MissingFields）→ 文案也带桶权限指引 + '
        '实际请求主机（肉眼核对桶名）', () async {
      final s = S3Store(
        gate: HttpGate(sleeper: (d) async {}),
        vault: await vaultWith('svcS3'),
        client: () => MockClient((req) async => http.Response(
            '<Error><Code>InvalidRequest</Code><Message>Invalid Request</Message></Error>',
            400)),
      );
      final msg = (await s.verify(cfg())).message ?? '';
      expect(msg, contains('分配桶权限'));
      expect(msg, contains('${cfg().bucket}.s3.bitiful.net'),
          reason: '400 头号成因是桶名/权限面，附 host 便于核对填写');
      s.close();
    });
  });

  group('quota：根 endpoint ListAllMyBuckets 私有字段（R5/§4.2）', () {
    test('打根 host（无桶前缀）；usedBytes=Σ(Image+Tmp+Video+Audio+Other)；quotaBytes=null；'
        '5min 缓存键带 serviceId，force 穿透', () async {
      final requests = <http.Request>[];
      var t = DateTime.utc(2026, 9, 25, 12);
      final client = MockClient((req) async {
        requests.add(req);
        expect(req.method, 'GET');
        expect(req.url.host, 's3.bitiful.net',
            reason: 'ListAllMyBuckets 只能打根 endpoint，带桶前缀的 host 拿不到（R5）');
        expect(req.url.path, '/');
        expectSigned(req);
        return http.Response.bytes(utf8.encode(bucketsXml), 200);
      });
      // T18 携带修复后 SK 缺失 fail-fast：跨 serviceId 用例先补记第二把密钥。
      final v2 = await vaultWith('svcS3');
      await v2.write('otherSvc', 'sk-other');
      final store = storeOf(client, vault: v2, clock: () => t);

      final q = await store.quota(cfg());
      expect(q.usedBytes, 1000 + 10 + 200 + 20 + 5 + 0 + 30 + 70,
          reason: '缤纷云私有 *Bytes 字段求和（缺失字段按 0）');
      expect(q.quotaBytes, isNull, reason: '按量付费无配额（R9 第②态）');
      expect(q.collectionUsed['photos'], 1235);
      expect(q.collectionUsed['videos'], 100);
      expect(requests, hasLength(1));

      await store.quota(cfg());
      expect(requests, hasLength(1), reason: '5min 内缓存命中零请求（P1）');
      await store.quota(cfg(id: 'otherSvc'));
      expect(requests, hasLength(2), reason: 'D3：缓存键带 serviceId，跨服务不串用');
      await store.quota(cfg(), force: true);
      expect(requests, hasLength(3), reason: 'force 穿透缓存');
      t = t.add(const Duration(minutes: 6));
      await store.quota(cfg());
      expect(requests, hasLength(4), reason: '假时钟过 5min TTL 自动重拉');
      store.close();
    });

    test('quota 非 200 抛 StateError', () async {
      final client = MockClient((req) async => http.Response('<Error/>', 500));
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      await expectLater(store.quota(cfg()), throwsStateError);
      store.close();
    });

    test('quota 403（子账户无 ListAllMyBuckets 权限）→ CloudQuota(null,null) '
        '不抛 + warn 一次（按 serviceId 静态去重）+ 降级结果进 5min 缓存、'
        'force 穿透（评审修复轮1 Minor-1）', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        return http.Response('<AccessDenied/>', 403);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));

      final q = await store.quota(cfg());
      expect(q.quotaBytes, isNull);
      expect(q.usedBytes, isNull);
      final warns = AppLog.lines.where((l) => l.level == LhLevel.warn).toList();
      expect(warns, hasLength(1), reason: '首次降级 warn 一次');
      expect(warns.first.text, contains('容量'));

      // 降级结果同样进 5min 缓存：二次调用零请求（过去每次刷 UI 重打网络）。
      await store.quota(cfg());
      expect(requests, hasLength(1), reason: '降级 CloudQuota(null,null) 也缓存');
      // force 穿透缓存重拉；warn 静态按 serviceId 去重，仍只一条。
      await store.quota(cfg(), force: true);
      expect(requests, hasLength(2), reason: 'force 穿透缓存重拉');
      expect(AppLog.lines.where((l) => l.level == LhLevel.warn), hasLength(1),
          reason: 'warn 去重：同 serviceId 进程级只一条');
      store.close();
    });

    test('quota 200 但非 ListAllMyBuckets 形态（<s:user>）→ null 不抛 + warn '
        '（独立 serviceId，验证静态去重按服务粒度）', () async {
      final client = MockClient((req) async => http.Response.bytes(
          utf8.encode('<s:user xmlns:s="http://ns.jianguoyun.com">'
              '<s:storage_quota>100</s:storage_quota></s:user>'),
          200));
      final store =
          storeOf(client, vault: await vaultWith('svcWeirdShape'));

      final q = await store.quota(cfg(id: 'svcWeirdShape'));
      expect(q.quotaBytes, isNull);
      expect(q.usedBytes, isNull);
      expect(
          AppLog.lines.where((l) => l.level == LhLevel.warn), hasLength(1),
          reason: '新 serviceId 首见仍 warn——去重表按服务粒度而非全局一条');
      store.close();
    });
  });

  test('RemoteStore.forConfig：isS3 分发到 S3Store（T13 占位收口），webdav 不受影响',
      () async {
    final s = RemoteStore.forConfig(cfg(),
        gate: HttpGate(sleeper: (d) async {}),
        vault: CredentialVault.inMemory());
    expect(s, isA<S3Store>());
    s.close();
    final w = RemoteStore.forConfig(
        ServiceConfig(id: 'w', apiUrl: 'https://dav.jianguoyun.com/dav/'),
        gate: HttpGate(sleeper: (d) async {}),
        vault: CredentialVault.inMemory());
    expect(w, isA<WebDavStore>());
    w.close();
  });

  group('R5d move/delete', () {
    test('move = CopyObject(x-amz-copy-source 源键) + DELETE 源', () async {
      final seq = <String>[];
      http.Request? copy;
      final client = MockClient((req) async {
        seq.add(req.method);
        if (req.method == 'PUT') {
          copy = req;
          return http.Response('<CopyResult/>', 200);
        }
        return http.Response('', 204);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      await store.move(cfg(), 'attachments/a.jpg', 'media_archive/attachments/a.jpg');
      expect(seq, ['PUT', 'DELETE']);
      expect(copy!.headers['x-amz-copy-source'], '/photo/sync/attachments/a.jpg');
      expect(copy!.url.path, '/sync/media_archive/attachments/a.jpg');
      store.close();
    });

    test('delete：DELETE 源键；204/404 均幂等成功；403 抛', () async {
      var status = 204;
      final client = MockClient((req) async {
        expect(req.method, 'DELETE');
        return http.Response('', status);
      });
      final store = storeOf(client, vault: await vaultWith('svcS3'));
      await store.delete(cfg(), 'attachments/a.jpg');
      status = 404;
      await store.delete(cfg(), 'attachments/a.jpg');
      status = 403;
      await expectLater(store.delete(cfg(), 'attachments/a.jpg'),
          throwsA(isA<StateError>()));
      store.close();
    });
  });
}
