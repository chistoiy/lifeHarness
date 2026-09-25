import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/sync/credential_vault.dart';
import 'package:lifeharness/core/sync/http_gate.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/s3_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/webdav_store.dart';

/// Task 13：RemoteStore 抽象 + WebDavStore（坚果云）。
///
/// 纪律（协议文档 §9）：单测不真连公网——MockClient 按请求路径路由喂固定 XML，
/// 假时钟驱动 60s 清单缓存，假 sleeper 保证节流/退避不真等。
void main() {
  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  const root = 'https://dav.jianguoyun.com/dav/';

  ServiceConfig cfg({String id = 'svc1', String dir = 'sync'}) => ServiceConfig(
        id: id,
        apiUrl: root,
        account: 'me@example.com',
        cloudDirName: dir,
        requestIntervalMs: 0,
      );

  /// 内存保险箱 + 预写凭据（既定坑：真实加密存储无测试平台通道）。
  Future<CredentialVault> vaultWith(String id, [String secret = 'pw&1']) async {
    final v = CredentialVault.inMemory();
    await v.write(id, secret);
    return v;
  }

  /// 请求路径（编码态）→ 与 mock 路由键对齐。
  String pathOf(List<String> segments) => Uri(
        scheme: 'https',
        host: 'dav.jianguoyun.com',
        pathSegments: ['dav', ...segments],
      ).path;

  /// 单条 PROPFIND response XML（href 需已按 URL 形态编码）。
  String resXml(String href, {bool dir = false, int? size, String? etag}) =>
      '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
      '<d:resourcetype>${dir ? '<d:collection/>' : ''}</d:resourcetype>'
      '<d:getcontentlength>${size ?? 0}</d:getcontentlength>'
      '<d:getetag>${etag ?? '"E-${href.hashCode}"'}</d:getetag>'
      '<d:getlastmodified>Fri, 25 Sep 2026 08:00:00 GMT</d:getlastmodified>'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '</d:response>';

  String msXml(List<String> resps) =>
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<d:multistatus xmlns:d="DAV:">${resps.join()}</d:multistatus>';

  bytesXml207(List<String> resps) => http.Response.bytes(
      utf8.encode(msXml(resps)), 207,
      headers: {'content-type': 'application/xml'});

  /// 坚果云形态深目录路由：/dav/sync[/d1[/d2…]]，每层回 1 文件 + 1 子目录，
  /// 子目录一直挂到 d13（远超限深 10，用来触发 warn）。
  Future<http.Response> deepTree(http.Request req) async {
    final depth = req.url.pathSegments.length - 2; // dav/sync 以下层数
    String child(String name) => 'https://dav.jianguoyun.com${req.url.path}/$name';
    return bytesXml207([
      resXml(req.url.path, dir: true),
      resXml(child('file-$depth.txt'), size: 10 + depth),
      if (depth < 13) resXml('${child('d${depth + 1}')}/', dir: true),
    ]);
  }

  WebDavStore storeOf(
    http.Client client, {
    required CredentialVault vault,
    DateTime Function()? clock,
  }) =>
      WebDavStore(
        gate: HttpGate(sleeper: (d) async {}),
        vault: vault,
        client: () => client,
        clock: clock,
      );

  group('parsePropfindXml 纯函数', () {
    test('中文+空格+& 转义文件名解码；getetag 去引号、W/ 前缀原样保留；'
        '集合不计入文件；绝对 URL href 归一到 path', () {
      final xml = msXml([
        resXml('/dav/%E6%88%91%E7%9A%84%20%E6%96%87%E4%BB%B6%E5%A4%B9',
            dir: true),
        resXml(
          '/dav/%E6%88%91%E7%9A%84%20%E6%96%87%E4%BB%B6%E5%A4%B9/'
          '%E4%B8%AD%E6%96%87%20%E6%8A%A5%E5%91%8A%20%26%20%E5%9B%BE.txt',
          size: 123,
          etag: '"1A2b"',
        ),
        resXml('https://dav.jianguoyun.com/dav/root.md', etag: 'W/"xyz-7"'),
        // 无前缀命名空间形态（部分服务器）也须可解析。
        '<response><href>/dav/plain%20dir/notes%20%26%20todo.md</href>'
        '<prop><resourcetype></resourcetype><getcontentlength>7</getcontentlength>'
        '<getetag>"p1"</getetag>'
        '<getlastmodified>Fri, 25 Sep 2026 08:00:00 GMT</getlastmodified>'
        '</prop></response>',
      ]);
      final entries = parsePropfindXml(xml);
      expect(entries, hasLength(3));
      expect(entries[0].relativePath, '/dav/我的 文件夹/中文 报告 & 图.txt');
      expect(entries[0].size, 123);
      expect(entries[0].etag, '1A2b', reason: 'getetag 去引号');
      expect(entries[0].modified, DateTime.utc(2026, 9, 25, 8));
      expect(entries[1].etag, 'W/xyz-7', reason: 'W/ 弱 ETag 前缀原样保留');
      expect(entries[1].relativePath, '/dav/root.md');
      expect(entries[2].relativePath, '/dav/plain dir/notes & todo.md');
    });

    test('latin1 陷阱字节：响应体恒走 utf8.decode(bodyBytes) 不乱码', () async {
      // 前提钉死：'报告' 的 UTF-8 字节按 latin1 猜必乱码（R12 封死的坑）。
      final bytes = utf8.encode('报告-Ω');
      expect(latin1.decode(bytes, allowInvalid: true), isNot('报告-Ω'));
      // list 走 store 内部 utf8.decode：content-type 不带 charset，
      // 若按响应头猜编码即乱码——断言中文文件名录入正确即判别器。
      final client = MockClient((req) async => bytesXml207([
            resXml('/dav/sync', dir: true),
            resXml('/dav/%E6%8A%A5%E5%91%8A%2D%CE%A9.md', size: 3),
          ]));
      final store = storeOf(client, vault: await vaultWith('svc1'));
      final listing = await store.list(cfg(), 'sync');
      expect(listing.files.single.relativePath, '报告-Ω.md');
      store.close();
    });
  });

  test('list：Depth:1 逐层递归 + 相对路径以 cloudDirName 为根归一 + '
      'Basic 认证 + 四属性请求体', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      expect(req.headers['Depth'], '1');
      final dir = req.url.path; // 已编码形态，直接做 href 前缀
      if (dir == pathOf(['我的 文件夹'])) {
        expect(req.body, contains('<d:resourcetype/>'));
        expect(req.body, contains('<d:getcontentlength/>'));
        expect(req.body, contains('<d:getetag/>'));
        expect(req.body, contains('<d:getlastmodified/>'));
        return bytesXml207([
          resXml(dir, dir: true),
          resXml(
              '$dir/%E4%B8%AD%E6%96%87%20%E6%8A%A5%E5%91%8A%20%26%20%E5%9B%BE.txt',
              size: 42,
              etag: '"F1"'),
          resXml('$dir/%E8%B5%84%E6%96%99%20%E5%BA%93%26x/', dir: true),
        ]);
      }
      if (dir == pathOf(['我的 文件夹', '资料 库&x'])) {
        return bytesXml207([
          resXml(dir, dir: true),
          resXml('$dir/b.txt', size: 2),
        ]);
      }
      return http.Response('not found', 404);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    final listing = await store.list(cfg(dir: '我的 文件夹'), '我的 文件夹');

    expect(listing.files.map((f) => f.relativePath),
        ['中文 报告 & 图.txt', '资料 库&x/b.txt'],
        reason: '相对路径去前导/、以 cloudDirName 为根、解码后中文+空格+& 不乱码');
    expect(listing.files.first.size, 42);
    expect(listing.files.first.etag, 'F1');
    expect(calls, hasLength(2), reason: '根 + 一层子目录各 1 次 PROPFIND');
    expect(calls.every((c) => c.startsWith('PROPFIND ')), isTrue);
  });

  test('list：限深 10 层触发 AppLog warn 并停止下钻（请求数=11）', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.path);
      return deepTree(req);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    final listing = await store.list(cfg(), 'sync');

    expect(calls, hasLength(11),
        reason: 'sync(深度0)…d10(深度10) 共 11 次 PROPFIND，d11 起不再请求');
    expect(listing.files, hasLength(11));
    expect(listing.files.last.relativePath,
        '${List.generate(10, (i) => 'd${i + 1}').join('/')}/file-10.txt');
    expect(
      AppLog.lines.where((l) => l.level == LhLevel.warn),
      isNotEmpty,
      reason: '触发限深必须 warn（【云盘】R6 限深 10）',
    );
    expect(AppLog.lines.map((l) => l.text).join('\n'), contains('限深'));
  });

  test('put：逐级 MKCOL(405 视为成功)+流式 PUT 转义文件名；'
      '第二次同目录 0 次 MKCOL（进程内记忆）', () async {
    final calls = <String>[];
    http.Request? putReq;
    final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lhw_put_中文 &a.txt');
    tmp.writeAsStringSync('hello-sync');
    addTearDown(() => tmp.deleteSync());
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.method == 'MKCOL') return http.Response('', 405);
      if (req.method == 'PUT') {
        putReq = req;
        return http.Response('', 201);
      }
      return http.Response('x', 500);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    final c = cfg();

    await store.put(c, tmp.path, '中文 目录 &a/报告 副本&.txt');

    expect(calls, [
      'MKCOL ${pathOf(['sync'])}',
      'MKCOL ${pathOf(['sync', '中文 目录 &a'])}',
      'PUT ${pathOf(['sync', '中文 目录 &a', '报告 副本&.txt'])}',
    ]);
    expect(putReq!.url.pathSegments.last, '报告 副本&.txt',
        reason: 'put URL 解码后中文+空格+& 不乱码');
    expect(putReq!.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('me@example.com:pw&1'))}',
        reason: 'Basic base64(account:secret)，secret 从 vault 现取');
    expect(putReq!.contentLength, tmp.lengthSync(),
        reason: '流式 PUT 必带 Content-Length');
    expect(putReq!.headers['x-bitiful-limit-rate'], isNull);

    calls.clear();
    await store.put(c, tmp.path, '中文 目录 &a/另一个文件.txt');
    expect(
        calls.where((l) => l.startsWith('MKCOL')), isEmpty,
        reason: '已建集合进程内记忆：第二次同目录不再发 MKCOL');
    expect(calls, hasLength(1));
  });

  test('get：URL 中文+空格+& 转义正确、路径落在 cloudDirName 前缀下；'
      '流式落盘走临时文件+rename 原子放', () async {
    final dir = Directory.systemTemp.createTempSync('lhw_get');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = '${dir.path}${Platform.pathSeparator}下载 结果 & ok.txt';
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.pathSegments, ['dav', 'sync', '中文 目录 &a', '报告 副本&.txt'],
          reason: 'get 与 put 同口径：cloudRelative 相对 cloudDirName 解析');
      return http.Response.bytes(utf8.encode('content-中文'), 200);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));

    await store.get(
        cfg(), '中文 目录 &a/报告 副本&.txt', target);

    expect(File(target).readAsStringSync(), 'content-中文');
    expect(File('$target.part').existsSync(), isFalse,
        reason: '临时文件必须被 rename 消耗，不残留');
    expect(dir.listSync().map((e) => e.path), [target]);
  });

  test('get/list/put 目录语义统一：list 的 relativePath 直喂 get，'
      '请求 URL 落在 cloudDirName 前缀下且内容落盘正确（T17 下载链路回归钉）',
      () async {
    final dir = Directory.systemTemp.createTempSync('lhw_rt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final getPaths = <String>[];
    final client = MockClient((req) async {
      if (req.method == 'PROPFIND') {
        return bytesXml207([
          resXml('/dav/%E5%90%8C%E6%AD%A5', dir: true),
          // href 编码态：/同步/文档 x&y.lhbak（中文+空格+&）
          resXml('/dav/%E5%90%8C%E6%AD%A5/%E6%96%87%E6%A1%A3%20x%26y.lhbak',
              size: 14),
        ]);
      }
      expect(req.method, 'GET');
      getPaths.add(req.url.path);
      return http.Response.bytes(utf8.encode('roundtrip-内容'), 200);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    const dirName = '同步';
    final c = cfg(dir: dirName);

    final listing = await store.list(c, dirName);
    final rel = listing.files.single.relativePath;
    expect(rel, '文档 x&y.lhbak');

    final target = '${dir.path}${Platform.pathSeparator}fetched.lhbak';
    await store.get(c, rel, target); // 直喂：不经任何再归一

    expect(getPaths, [pathOf([dirName, rel])],
        reason: 'get 必须与 list/put 一致地按相对 cloudDirName 解析补前缀');
    expect(File(target).readAsStringSync(), 'roundtrip-内容');
    store.close();
  });

  test('ensureDirectory("a/b")：全链含末段——MKCOL 两级 /sync/a/ 与 /sync/a/b/ '
      '（回归：剥末段致嵌套目录漏建）', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return http.Response('', 405); // 405 = 已存在，亦成功（R7）
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));

    await store.ensureDirectory(cfg(), 'a/b');

    expect(calls, [
      'MKCOL ${pathOf(['sync'])}',
      'MKCOL ${pathOf(['sync', 'a'])}',
      'MKCOL ${pathOf(['sync', 'a', 'b'])}',
    ], reason: '目录路径的末段是目录本身，必须建（含两级 a、a/b）');
    store.close();
  });

  test('put("x/y/z.lhbak")：MKCOL 只发父目录链——含 /sync/x/、/sync/x/y/，'
      '不含文件路径；PUT 命中三级目标', () async {
    final calls = <String>[];
    http.Request? putReq;
    final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lhw_fix_put.lhbak');
    tmp.writeAsStringSync('payload');
    addTearDown(() => tmp.deleteSync());
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.method == 'PUT') {
        putReq = req;
        return http.Response('', 200);
      }
      return http.Response('', 405);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));

    await store.put(cfg(), tmp.path, 'x/y/z.lhbak');

    final mkcols = calls.where((l) => l.startsWith('MKCOL')).toList();
    expect(mkcols, [
      'MKCOL ${pathOf(['sync'])}',
      'MKCOL ${pathOf(['sync', 'x'])}',
      'MKCOL ${pathOf(['sync', 'x', 'y'])}',
    ], reason: 'R7：文件直接父目录 /x/y/ 也必须在 MKCOL 链内');
    expect(mkcols.any((l) => l.contains('z.lhbak')), isFalse,
        reason: '末段是文件名，绝不对其发 MKCOL');
    expect(putReq!.url.pathSegments, ['dav', 'sync', 'x', 'y', 'z.lhbak']);
    store.close();
  });

  test('本地文件名含字面 %20 往返：入参是逻辑路径不再解码，'
      'URL 构造把 % 转义为 %25，解码回读即原名', () async {
    final calls = <String>[];
    http.Request? putReq;
    final dir = Directory.systemTemp.createTempSync('lhw_fix_pct');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tmp = File('${dir.path}${Platform.pathSeparator}src.bin');
    tmp.writeAsStringSync('pct-payload');
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.method == 'PUT') {
        putReq = req;
        return http.Response('', 200);
      }
      return http.Response('', 405);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    const rel = '目录a%20b/报告%20final.lhbak'; // %20 是名字的一部分，非空格转义

    await store.put(cfg(), tmp.path, rel);

    // 判别器：若入参被误解码，'a%20b' 会变成 'a b'（编码里只剩单个 %25）；
    // 正确行为是 % 本身转义（%2520），字面 %20 原样进 URL 再原样解回。
    expect(calls, [
      'MKCOL ${pathOf(['sync'])}',
      'MKCOL ${pathOf(['sync', '目录a%20b'])}',
      'PUT ${pathOf(['sync', '目录a%20b', '报告%20final.lhbak'])}',
    ]);
    expect(calls[2], contains('%25'),
        reason: '字面 % 必须转义为 %25（逻辑名与编码形态不混排）');
    expect(putReq!.url.pathSegments,
        ['dav', 'sync', '目录a%20b', '报告%20final.lhbak'],
        reason: 'URL 解码回读 == 本地逻辑名（往返一致，%20 未被吞成空格）');
    store.close();
  });

  test('list：根 PROPFIND 404（云端目录不存在）→ 空清单 + info 日志，'
      '不再让同步链整链报错（R2 项⑥）', () async {
    final client = MockClient((req) async => http.Response('not found', 404));
    final store = storeOf(client, vault: await vaultWith('svc1'));
    final listing = await store.list(cfg(), 'sync');
    expect(listing.files, isEmpty);
    final infos = AppLog.lines.where((l) => l.level == LhLevel.info).toList();
    expect(infos.map((l) => l.text).join('\n'), contains('云端目录不存在'),
        reason: '根目录 404 记 info「首次上传将自动创建」');
    store.close();
  });

  test('verify：207→ok；401→凭据错文案（WebDAV 提示应用密码）', () async {
    var status = 207;
    final client = MockClient((req) async {
      expect(req.method, 'PROPFIND');
      expect(req.headers['Depth'], '0');
      expect(req.url.path, '/dav');
      return http.Response.bytes(
          status == 207 ? utf8.encode(msXml([])) : utf8.encode('nope'), status);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    final c = cfg();

    final ok = await store.verify(c);
    expect(ok.ok, isTrue);
    expect(ok.message, isNull);

    status = 401;
    final bad = await store.verify(c);
    expect(bad.ok, isFalse);
    expect(bad.message, contains('应用密码'),
        reason: 'R13：坚果云填登录密码稳定 401/403，文案必须提示应用密码');
  });

  test('verify：404→ok=false 且文案「云端目录不存在，首次同步将自动创建」（R2 项⑥）',
      () async {
    final client =
        MockClient((req) async => http.Response('not found', 404));
    final store = storeOf(client, vault: await vaultWith('svc1'));
    final v = await store.verify(cfg());
    expect(v.ok, isFalse);
    expect(v.message, contains('云端目录不存在'));
    expect(v.message, contains('首次同步将自动创建'));
    // 评审修复轮1 Minor-2：ok=false 态开头改「服务可达」，不再「连接成功」。
    expect(v.message, contains('服务可达'));
    expect(v.message, isNot(contains('连接成功')),
        reason: 'ok=false 与「连接成功」语义矛盾，必须去掉');
    store.close();
  });

  /// 真机 getUserInfo 实测回 XML（协议文档 §4.1），非 JSON——旧 jsonDecode 直
  /// 接 FormatException。夹具以真机样例：子元素形态 + collection 嵌套元素。
  const userInfoXml = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<s:user xmlns:s="http://ns.jianguoyun.com">'
      '<s:email>me@example.com</s:email>'
      '<s:storage_quota>3221225472</s:storage_quota>'
      '<s:used_storage>1288490189</s:used_storage>'
      '<s:account_state>normal</s:account_state>'
      '<s:collection><s:href>/My%20%E5%90%8C%E6%AD%A5%20Dir/</s:href>'
      '<s:used_storage>22600</s:used_storage></s:collection>'
      '<s:collection><s:href>/other/</s:href>'
      '<s:used_storage>100</s:used_storage></s:collection>'
      '</s:user>';

  test('quota：GET {scheme}://{host}/nsdav/getUserInfo 解析 XML 容量；'
      'collection href 归一化（解码+去尾斜杠+小写）命中目录名', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url}');
      return http.Response.bytes(
        utf8.encode(userInfoXml),
        200,
        headers: {'content-type': 'application/xml'},
      );
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));

    final q = await store.quota(cfg());
    expect(calls, ['GET https://dav.jianguoyun.com/nsdav/getUserInfo']);
    expect(q.quotaBytes, 3221225472);
    expect(q.usedBytes, 1288490189);
    expect(q.collectionUsed['my 同步 dir'.toLowerCase()], 22600,
        reason: 'URL 解码+去尾斜杠+小写归一后按目录名命中');
    expect(q.collectionUsed['other'], 100);

    // 5min 容量缓存（P1）：同实例第二次 0 请求，force 穿透。
    final before = calls.length;
    await store.quota(cfg());
    expect(calls, hasLength(before), reason: 'quota 缓存命中不再请求');
    await store.quota(cfg(), force: true);
    expect(calls, hasLength(before + 1), reason: 'force 穿透缓存');
    store.close();
  });

  test('parseGetUserInfo 容忍属性形态（storage_quota="…" / collection '
      'href="…" used_storage="…"）', () {
    const attrForm = '<user storage_quota="1073741824" used_storage="23089664" '
        'account_state="normal">'
        '<collection href="/Docs/" used_storage="4242"/>'
        '</user>';
    final q = WebDavStore.parseGetUserInfo(attrForm);
    expect(q.quotaBytes, 1073741824);
    expect(q.usedBytes, 23089664);
    expect(q.collectionUsed['docs'], 4242);
  });

  test('parseGetUserInfo 异常格式返回 null 字段，绝不抛 FormatException', () {
    // 真机偶发 HTML 错误页 / 半截响应：解析器宽容降级，不再 jsonDecode 炸穿。
    final junk = WebDavStore.parseGetUserInfo('<html>502 Bad Gateway</html>');
    expect(junk.quotaBytes, isNull);
    expect(junk.usedBytes, isNull);
    expect(junk.collectionUsed, isEmpty);
    final notXml = WebDavStore.parseGetUserInfo('total garbage');
    expect(notXml.quotaBytes, isNull);
    expect(notXml.usedBytes, isNull);
  });

  test('清单缓存 60s：命中不发请求、force 穿透、假时钟过期重拉', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      return bytesXml207([
        resXml('/dav/sync', dir: true),
        resXml('/dav/sync/a.txt', size: 1),
      ]);
    });
    var t = DateTime.utc(2026, 9, 25, 12);
    final store = storeOf(client,
        vault: await vaultWith('svc1'), clock: () => t);
    final c = cfg();

    await store.list(c, 'sync');
    expect(requests, 1);
    await store.list(c, 'sync');
    expect(requests, 1, reason: '60s 内缓存命中，零请求');

    await store.list(c, 'sync', force: true);
    expect(requests, 2, reason: 'force 穿透缓存');

    t = t.add(const Duration(seconds: 61));
    await store.list(c, 'sync');
    expect(requests, 3, reason: '假时钟拨过 60s，缓存过期自动重拉');
    store.close();
  });

  test('缓存键含 serviceId：同目录名不同服务互不串用', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      return bytesXml207([
        resXml('/dav/sync', dir: true),
        resXml('/dav/sync/a.txt', size: requests),
      ]);
    });
    final store = storeOf(client, vault: await vaultWith('svc1'));
    await store.list(cfg(id: 'svc1'), 'sync');
    await store.list(cfg(id: 'svc2'), 'sync');
    expect(requests, 2, reason: 'D3：缓存键 {serviceId}|{cloudDirName}');
    store.close();
  });

  test('RemoteStore.forConfig：webdav→WebDavStore、isS3→S3Store'
      '（T14 已接入，R2 合法分发位点收口）', () async {
    final s = RemoteStore.forConfig(cfg(),
        gate: HttpGate(sleeper: (d) async {}),
        vault: CredentialVault.inMemory());
    expect(s, isA<WebDavStore>());
    s.close();
    final s3 = RemoteStore.forConfig(
        ServiceConfig(id: 'x', provider: StoreProviderKind.s3, bucket: 'b'),
        gate: HttpGate(sleeper: (d) async {}),
        vault: CredentialVault.inMemory());
    expect(s3, isA<S3Store>());
    s3.close();
  });
}
