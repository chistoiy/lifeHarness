/// 真机反馈轮① ·「我的」页数据与同步状态行的数据源验收。
///
/// 根因＝那一行曾是写死的 `'● 未配置'` 常量（配好 WebDAV 也永远不亮）。
/// 修法＝读 [activeSyncServiceProvider]（激活服务，未配置给 null 且**绝不抛错**）。
/// 本文件钉三件事：未配置＝null、配好＝出条目、activeId 悬空时按既有口径回落第一条。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/sync/credential_vault.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/sync_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late SyncConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = SyncConfigStore(prefs, vault: CredentialVault());
  });

  ProviderContainer boot() {
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      syncConfigStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('一条服务都没有＝null（UI 据此画「未配置」，不弹错不打断）', () {
    expect(boot().read(activeSyncServiceProvider), isNull);
  });

  test('存好并激活一条 WebDAV＝读出该条目（UI 据此画「已配置」）', () async {
    await store.saveService(ServiceConfig(id: 's1', cloudDirName: 'lh'));
    expect(boot().read(activeSyncServiceProvider)?.id, 's1');
  });

  test('activeId 悬空（服务被删）＝按既有口径回落第一条，主页不许变灰', () async {
    await store.saveService(ServiceConfig(id: 's1', cloudDirName: 'lh'));
    await store.saveService(ServiceConfig(id: 's2', cloudDirName: 'lh2'));
    // 覆写整表把 activeId 指向不存在的服务，模拟悬空态。
    await store.save(SyncConfigSnapshot(
        services: [
          ServiceConfig(id: 's1', cloudDirName: 'lh'),
          ServiceConfig(id: 's2', cloudDirName: 'lh2'),
        ],
        activeId: 'gone'));
    expect(boot().read(activeSyncServiceProvider)?.id, 's1',
        reason: '悬空 activeId 由 load() 归位第一条，状态行不许谎报未配置');
  });
}
