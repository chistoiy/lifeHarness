import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeharness/features/widget/data/widget_binding_store.dart';
import 'package:lifeharness/features/widget/domain/widget_binding.dart';

/// 小组件模块 批A · 按实例绑定层守护（工单 §1 面板·新增常驻三件之第一件）。
///
/// 覆盖工单点名的四组判据（纯函数口径）：
/// ① 绑定读写（一实例一键·紧凑编码·无效目标不落盘）；
/// ② 实例删除回收（只留在役·默认键不误伤）；
/// ③ **老实例回落全局默认**（R2 升级迁移口径：实例无记录读默认，实例记录优先）；
/// ④ 失效三态判据（无快照/无绑定/源失效＋优先级）。
/// 另钉：编码容错（不猜）、键名与分隔符同族口径（与原生将读的键一致）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WidgetTarget habit(String name) =>
      WidgetTarget(kind: 'nav', ref: 'habit', sub: name);

  group('WidgetTarget 编解码（纯函数）', () {
    test('三字段往返（sub 可空；空 sub 编码后解回 null）', () {
      expect(habit('早起').encode(), 'nav\u001fhabit\u001f早起');
      expect(WidgetTarget.decode('nav\u001fhabit\u001f早起'), habit('早起'));
      final noSub = WidgetTarget(kind: 'timer_cat', ref: '12');
      expect(noSub.encode(), 'timer_cat\u001f12\u001f');
      expect(WidgetTarget.decode('timer_cat\u001f12\u001f'), noSub);
    });

    test('脏数据一律 null（不猜）：字段数不符/空 kind/空 ref/未知 kind', () {
      expect(WidgetTarget.decode(null), isNull);
      expect(WidgetTarget.decode(''), isNull);
      expect(WidgetTarget.decode('   '), isNull);
      expect(WidgetTarget.decode('nav\u001fhabit'), isNull); // 少一段
      expect(WidgetTarget.decode('nav\u001fhabit\u001f早起\u001f多'), isNull); // 多一段
      expect(WidgetTarget.decode('\u001fhabit\u001f早起'), isNull); // 空 kind
      expect(WidgetTarget.decode('nav\u001f\u001f早起'), isNull); // 空 ref
      expect(WidgetTarget.decode('bogus\u001fhabit\u001f早起'), isNull); // 未知 kind
    });

    test('isValid：kind/ref 缺一不可绑（与 NFC hasTarget 同判据）', () {
      expect(habit('早起').isValid, isTrue);
      expect(const WidgetTarget(kind: '', ref: 'habit').isValid, isFalse);
      expect(const WidgetTarget(kind: 'nav', ref: '').isValid, isFalse);
    });
  });

  group('实例删除回收（pruneBindings·纯函数）', () {
    test('只留在役实例；死实例进 deadInstanceIds', () {
      final map = <int, WidgetBinding>{
        11: WidgetBinding(appWidgetId: 11, target: habit('早起')),
        12: WidgetBinding(appWidgetId: 12, target: habit('喝水')),
        13: WidgetBinding(appWidgetId: 13, target: habit('阅读')),
      };
      final live = <int>{11, 13};
      final kept = pruneBindings(map, live);
      expect(kept.keys.toSet(), <int>{11, 13});
      expect(deadInstanceIds(map, live), <int>{12});
    });

    test('空 map / 全死 / 全活 三态不炸', () {
      expect(pruneBindings(<int, WidgetBinding>{}, <int>{1}).isEmpty, isTrue);
      final one = <int, WidgetBinding>{
        7: WidgetBinding(appWidgetId: 7, target: habit('早睡')),
      };
      expect(pruneBindings(one, <int>{}).isEmpty, isTrue);
      expect(pruneBindings(one, <int>{7}).length, 1);
    });
  });

  group('老实例回落全局默认（R2·纯函数）', () {
    test('实例无记录＋有默认 ⇒ fallbackDefault（升级迁移口径）', () {
      final r = resolveWidgetBinding(
        <int, WidgetBinding>{},
        99,
        globalDefault: habit('早起'),
      );
      expect(r.state, WidgetBindingState.fallbackDefault);
      expect(r.target, habit('早起'));
      expect(r.isActionable, isTrue);
    });

    test('实例记录优先于默认；两者皆无 ⇒ unbound', () {
      final map = <int, WidgetBinding>{
        99: WidgetBinding(appWidgetId: 99, target: habit('喝水')),
      };
      final r1 = resolveWidgetBinding(map, 99, globalDefault: habit('早起'));
      expect(r1.state, WidgetBindingState.bound);
      expect(r1.target, habit('喝水'));
      final r2 = resolveWidgetBinding(<int, WidgetBinding>{}, 99);
      expect(r2.state, WidgetBindingState.unbound);
      expect(r2.target, isNull);
      expect(r2.isActionable, isFalse);
    });
  });

  group('失效三态判据（widgetInstanceState·纯函数）', () {
    final bound = resolveWidgetBinding(
      <int, WidgetBinding>{
        5: WidgetBinding(appWidgetId: 5, target: habit('早起')),
      },
      5,
    );
    final unbound =
        resolveWidgetBinding(<int, WidgetBinding>{}, 5);

    test('四态各归其位', () {
      expect(
        widgetInstanceState(
            hasSnapshot: true, resolution: bound, sourceExists: true),
        WidgetInstanceState.ok,
      );
      expect(
        widgetInstanceState(
            hasSnapshot: false, resolution: bound, sourceExists: true),
        WidgetInstanceState.noSnapshot,
      );
      expect(
        widgetInstanceState(
            hasSnapshot: true, resolution: unbound, sourceExists: true),
        WidgetInstanceState.noBinding,
      );
      expect(
        widgetInstanceState(
            hasSnapshot: true, resolution: bound, sourceExists: false),
        WidgetInstanceState.sourceInvalid,
      );
    });

    test('优先级：无快照压过无绑定；绑定态里源失效压过正常', () {
      expect(
        widgetInstanceState(
            hasSnapshot: false, resolution: unbound, sourceExists: false),
        WidgetInstanceState.noSnapshot,
      );
      expect(
        widgetInstanceState(
            hasSnapshot: true,
            resolution: bound,
            sourceExists: false),
        WidgetInstanceState.sourceInvalid,
      );
    });
  });

  group('WidgetBindingStore（SharedPreferences 读写）', () {
    test('绑定读写／解绑／默认键', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = WidgetBindingStore(prefs);

      await store.bind(42, habit('早起'));
      expect(store.targetOf(42), habit('早起'));
      expect(store.loadAll().keys.toSet(), <int>{42});
      expect(prefs.getString('desktop.widget_bind.42'),
          'nav\u001fhabit\u001f早起');

      await store.bind(42, habit('喝水')); // 覆盖
      expect(store.targetOf(42), habit('喝水'));

      await store.unbind(42);
      expect(store.targetOf(42), isNull);
      expect(store.loadAll(), isEmpty);
    });

    test('无效目标不落盘（半成品状态禁写）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = WidgetBindingStore(prefs);
      await store.bind(7, const WidgetTarget(kind: 'nav', ref: ''));
      expect(prefs.getKeys().where((k) => k.startsWith('desktop.widget_bind.')),
          isEmpty);
    });

    test('prune：死实例键被清、在役与默认键保留', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = WidgetBindingStore(prefs);
      await store.bind(11, habit('早起'));
      await store.bind(12, habit('喝水'));
      await store.setGlobalDefault(habit('阅读'));

      final dead = await store.prune(<int>{11});
      expect(dead, <int>{12});
      expect(store.targetOf(11), habit('早起'));
      expect(store.targetOf(12), isNull);
      expect(store.globalDefault, habit('阅读')); // 默认键不被回收误伤
      expect(store.loadAll().keys.toSet(), <int>{11});
    });

    test('resolve：实例优先→回落默认→unbound 三态落地', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = WidgetBindingStore(prefs);

      await store.setGlobalDefault(habit('早起'));
      // 老实例（无绑定记录）：回落默认
      var r = store.resolve(99);
      expect(r.state, WidgetBindingState.fallbackDefault);
      expect(r.target, habit('早起'));
      // 新实例绑定后：实例优先
      await store.bind(99, habit('喝水'));
      r = store.resolve(99);
      expect(r.state, WidgetBindingState.bound);
      expect(r.target, habit('喝水'));
      // 清默认＋解绑：unbound
      await store.setGlobalDefault(null);
      await store.unbind(99);
      expect(store.resolve(99).state, WidgetBindingState.unbound);
    });

    test('loadAll 跳过脏值与默认键（宁少不错）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'desktop.widget_bind.5': 'nav\u001fhabit\u001f早起',
        'desktop.widget_bind.6': '坏数据',
        'desktop.widget_bind.notanumber': 'nav\u001fhabit\u001f喝水',
        'desktop.widget_bind.default': 'nav\u001fhabit\u001f阅读',
        'other.prefix': 'x',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = WidgetBindingStore(prefs);
      final all = store.loadAll();
      expect(all.keys.toSet(), <int>{5});
      expect(store.globalDefault, habit('阅读'));
    });
  });

  group('键与分隔符口径（与原生/待办编码同族）', () {
    test('键带实例 id；默认键在实例命名空间外不被误当实例', () {
      expect(widgetBindingKeyOf(42), 'desktop.widget_bind.42');
      expect(WidgetBindingStore.defaultKey, 'desktop.widget_bind.default');
      expect(int.tryParse('default'), isNull); // loadAll 据此跳过默认键
    });

    test('字段分隔符与待办行编码同值（控制字符·禁两处各写一个）', () {
      expect(WidgetBindingStore.fieldSep, '\u001f');
    });
  });
}
