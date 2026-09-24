import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/sync/credential_vault.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 便捷构造：一条记录 = 一个「服务 + 云端目录」映射（brief 唯一口径）。
ServiceConfig _cfg(
  String id, {
  StoreProviderKind provider = StoreProviderKind.webdav,
  String apiUrl = 'https://dav.jianguoyun.com/dav/',
  String account = 'me@example.com',
  String region = '',
  String bucket = '',
  String cloudDirName = 'photos',
}) =>
    ServiceConfig(
      id: id,
      provider: provider,
      apiUrl: apiUrl,
      account: account,
      region: region,
      bucket: bucket,
      cloudDirName: cloudDirName,
    );

/// 全程内存版保险箱 + mock prefs，零平台通道。
Future<SyncConfigStore> _store(CredentialVault vault,
    {Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  return SyncConfigStore(await SharedPreferences.getInstance(), vault: vault);
}

void main() {
  group('R4 旧格式兼容', () {
    test('缺 provider/region/bucket/节奏字段一律落 WebDAV 默认；authCode 残留容忍', () async {
      final store = await _store(CredentialVault.inMemory(), seed: {
        SyncConfigStore.servicesKey: jsonEncode({
          'services': [
            {
              'id': 'old1',
              'apiUrl': 'https://dav.jianguoyun.com/dav/',
              'account': 'a@b.c',
              'cloudDirName': 'shots',
              'authCode': 'legacy-secret', // 旧明文残留：读取容忍、忽略
            },
          ],
          'activeId': 'old1',
        }),
      });
      final snap = store.load();
      expect(snap.services, hasLength(1));
      final s = snap.services.single;
      expect(s.provider, StoreProviderKind.webdav);
      expect(s.isS3, isFalse);
      expect(s.requestIntervalMs, ServiceConfig.defaultRequestIntervalMs);
      expect(s.requestIntervalMs, 300);
      expect(s.region, isEmpty);
      expect(s.bucket, isEmpty);
      expect(s.verifyContent, isFalse);
      expect(s.cloudDirName, 'shots');
      expect(snap.activeId, 'old1');
    });

    test('D1 取舍：保存时明文 JSON 剔除 authCode 键', () async {
      final store = await _store(CredentialVault.inMemory(), seed: {
        SyncConfigStore.servicesKey: jsonEncode({
          'services': [
            {'id': 'old1', 'apiUrl': 'https://x/', 'authCode': 'legacy-secret'},
          ],
          'activeId': 'old1',
        }),
      });
      await store.save(store.load());
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SyncConfigStore.servicesKey)!;
      expect(raw, isNot(contains('authCode')));
      expect(raw, isNot(contains('legacy-secret')));
      // 回读照常落 WebDAV 默认（R4 单测固定「1.1.x 配置升级后照常工作」）
      expect(store.load().services.single.provider, StoreProviderKind.webdav);
      expect(store.load().services.single.requestIntervalMs, 300);
    });

    test('坏 JSON 返回空快照不炸', () async {
      final store = await _store(CredentialVault.inMemory(),
          seed: {SyncConfigStore.servicesKey: '{坏包'});
      expect(store.load().services, isEmpty);
      expect(store.load().activeId, isNull);
    });

    test('activeId 悬空指向不存在服务时回落第一条', () async {
      final store = await _store(CredentialVault.inMemory(), seed: {
        SyncConfigStore.servicesKey: jsonEncode({
          'services': [
            {'id': 'keep', 'apiUrl': 'https://x/'},
          ],
          'activeId': 'ghost',
        }),
      });
      expect(store.load().activeId, 'keep');
    });
  });

  group('CredentialVault（内存版）', () {
    test('键约定 sync_secret_{serviceId}（设计稿 §4.3）', () {
      expect(CredentialVault.keyFor('s1'), 'sync_secret_s1');
    });

    test('write→read 一致；delete 清干净', () async {
      final v = CredentialVault.inMemory();
      expect(await v.read('s1'), isNull);
      expect(await v.write('s1', 'sk-abc'), isTrue);
      expect(await v.read('s1'), 'sk-abc');
      await v.delete('s1');
      expect(await v.read('s1'), isNull);
    });

    test('failNextWrite：写返回 false 且旧值保留（R11）', () async {
      final v = CredentialVault.inMemory();
      await v.write('s1', 'old');
      v.failNextWrite = true;
      expect(await v.write('s1', 'new'), isFalse);
      expect(await v.read('s1'), 'old');
      v.failNextWrite = false;
      expect(await v.write('s1', 'new'), isTrue);
      expect(await v.read('s1'), 'new');
    });
  });

  group('R11 配置与凭据写入路径', () {
    test('vault 写失败时 saveService 返回 false，vault 与明文侧均保留原值', () async {
      final v = CredentialVault.inMemory();
      final store = await _store(v);
      expect(
          await store.saveService(_cfg('a', apiUrl: 'https://old/dav/'),
              secret: 'old-secret'),
          isTrue);
      v.failNextWrite = true;
      expect(
          await store.saveService(_cfg('a', apiUrl: 'https://new/dav/'),
              secret: 'new-secret'),
          isFalse);
      expect(await v.read('a'), 'old-secret');
      expect(store.load().services.single.apiUrl, 'https://old/dav/');
    });

    test('不带 secret 的编辑不动 vault', () async {
      final v = CredentialVault.inMemory();
      final store = await _store(v);
      await store.saveService(_cfg('a'), secret: 'keep-me');
      await store.saveService(_cfg('a', cloudDirName: 'renamed'));
      expect(await v.read('a'), 'keep-me');
      expect(store.load().services.single.cloudDirName, 'renamed');
    });
  });

  group('cloudDirName 判重（钉死口径：id 唯一 + 同 provider 端点下目录唯一，跨 provider 可同名）', () {
    test('同 WebDAV 端点重名目录被拒，且列表不被写入', () async {
      final store = await _store(CredentialVault.inMemory());
      await store.saveService(_cfg('a', cloudDirName: 'photos'));
      await expectLater(store.saveService(_cfg('c', cloudDirName: 'photos')),
          throwsStateError);
      expect(store.load().services.map((c) => c.id), ['a']);
    });

    test('跨 provider / 跨端点同名目录放行', () async {
      final store = await _store(CredentialVault.inMemory());
      await store.saveService(_cfg('a', cloudDirName: 'photos'));
      await store.saveService(_cfg('b',
          provider: StoreProviderKind.s3,
          apiUrl: 'https://s3.bitiful.net',
          account: 'AK',
          bucket: 'bk',
          cloudDirName: 'photos'));
      expect(store.load().services.map((c) => c.id), ['a', 'b']);
      await store.saveService(
          _cfg('d', apiUrl: 'https://other-dav.example.com/', cloudDirName: 'photos'));
      expect(store.load().services, hasLength(3));
    });

    test('同 id 换目录是原地替换，不误报判重', () async {
      final store = await _store(CredentialVault.inMemory());
      await store.saveService(_cfg('a', cloudDirName: 'one'));
      await store.saveService(_cfg('a', cloudDirName: 'two'));
      final s = store.load().services;
      expect(s, hasLength(1));
      expect(s.single.cloudDirName, 'two');
    });

    test('save 直接提交重复 id 列表被拒（id 唯一不变式）', () async {
      final store = await _store(CredentialVault.inMemory());
      await expectLater(
          store.save(SyncConfigSnapshot(services: [
            _cfg('a', cloudDirName: 'x'),
            _cfg('a', cloudDirName: 'y'),
          ])),
          throwsStateError);
    });

    test('端点大小写/尾斜杠差异归一后仍同端点，目录重名被拒', () async {
      final store = await _store(CredentialVault.inMemory());
      await store.saveService(
          _cfg('a', apiUrl: 'https://A.com/dav/', cloudDirName: 'photos'));
      await expectLater(
          store.saveService(
              _cfg('c', apiUrl: 'https://a.com/dav', cloudDirName: 'photos')),
          throwsStateError);
      expect(store.load().services.map((c) => c.id), ['a']);
    });

    test('目录名尾斜杠判重互认（photos/ 与 photos 冲突）', () async {
      final store = await _store(CredentialVault.inMemory());
      await store.saveService(_cfg('a', cloudDirName: 'photos'));
      await expectLater(store.saveService(_cfg('c', cloudDirName: 'photos/')),
          throwsStateError);
      expect(store.load().services.map((c) => c.id), ['a']);
    });
  });

  group('删服务与 activeId 回落', () {
    test('removeService 清 vault 孤儿键，activeId 指向被删服务时回落第一条', () async {
      final v = CredentialVault.inMemory();
      final store = await _store(v);
      await store.saveService(_cfg('a', cloudDirName: 'one'), secret: 'pa');
      await store.saveService(
          _cfg('b', apiUrl: 'https://b-dav/', cloudDirName: 'two'),
          secret: 'pb');
      expect(store.load().activeId, 'a'); // 首条服务自动激活
      await store.setActive('a');
      await store.removeService('a');
      expect(await v.read('a'), isNull); // 孤儿密钥清理
      expect(await v.read('b'), 'pb'); // 其他服务凭据不动
      final snap = store.load();
      expect(snap.services.map((c) => c.id), ['b']);
      expect(snap.activeId, 'b');
    });

    test('删除唯一服务后 activeId 回落 null', () async {
      final store = await _store(CredentialVault.inMemory());
      await store.saveService(_cfg('a'));
      await store.removeService('a');
      expect(store.load().services, isEmpty);
      expect(store.load().activeId, isNull);
    });
  });
}
