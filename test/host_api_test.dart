import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/host/module_registry.dart';
import 'package:lifeharness/core/host/mount_point.dart';

void main() {
  HostModule mod(String id, {int order = 0, int weight = 0}) => HostModule(
        id: id,
        title: id,
        routePath: '/$id',
        mount: {MountPoint.homeCard: order},
        weight: weight,
      );

  group('ModuleRegistry 冲突仲裁链（用户序 > 权重 > 时序）', () {
    test('缺省按 mount 声明序', () {
      final r = ModuleRegistry()
        ..register(mod('b', order: 1))
        ..register(mod('a', order: 0));
      expect(r.resolve(MountPoint.homeCard).map((m) => m.id), ['a', 'b']);
    });

    test('同序按权重降序', () {
      final r = ModuleRegistry()
        ..register(mod('x', weight: 1))
        ..register(mod('y', weight: 9));
      expect(r.resolve(MountPoint.homeCard).map((m) => m.id), ['y', 'x']);
    });

    test('同序同权重按注册时序', () {
      final r = ModuleRegistry()
        ..register(mod('first'))
        ..register(mod('second'));
      expect(r.resolve(MountPoint.homeCard).map((m) => m.id),
          ['first', 'second']);
    });

    test('用户显式序最优先', () {
      final r = ModuleRegistry()
        ..register(mod('a', weight: 10))
        ..register(mod('b', weight: 0));
      r.setUserOrder(MountPoint.homeCard, ['b', 'a']);
      expect(r.resolve(MountPoint.homeCard).map((m) => m.id), ['b', 'a']);
    });

    test('注册表：同 id 覆盖、注销、挂载点过滤', () {
      final r = ModuleRegistry()..register(mod('a'));
      r.register(HostModule(id: 'a', title: 'a2', routePath: '/a2'));
      expect(r.byId('a')!.title, 'a2');
      expect(r.resolve(MountPoint.fab), isEmpty);
      r.unregister('a');
      expect(r.all, isEmpty);
    });
  });

  group('EventBus', () {
    test('类型过滤与广播', () async {
      final bus = EventBus();
      addTearDown(bus.dispose);
      final ints = <int>[];
      final strs = <String>[];
      final subA = bus.on<int>().listen(ints.add);
      final subB = bus.on<String>().listen(strs.add);
      bus..publish(1)..publish('x')..publish(2);
      await Future.delayed(Duration.zero);
      expect(ints, [1, 2]);
      expect(strs, ['x']);
      await subA.cancel();
      await subB.cancel();
    });
  });
}
