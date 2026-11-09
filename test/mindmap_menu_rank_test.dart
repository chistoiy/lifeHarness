import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/features/mindmap/domain/mindmap_menu_rank.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_sheets.dart'
    show MmMenuItem, mmRankMenuGroups;

/// 批P7 · 节点菜单按频次重排（域层 ＋ prefs 存取）。
///
/// 这一层全是**纯函数**，所以每条都做**两档对照**（正档真前移／负档不动），
/// 单断正档等于「零次点击」也过——那正是这条功能最怕的假绿。
bool _hasAdjacent(List<String> g, String a, String b) =>
    g.contains(a) && g.indexOf(b) == g.indexOf(a) + 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('基线表自洽', () {
    test('基线七个键集合里，可排集只剔掉置顶键且不重复', () {
      final all = [for (final g in mmMenuBaselineGroups) ...g];
      expect(all.toSet().length, all.length, reason: '基线里不许出现同名键');
      final sortable = mmSortableKeys;
      expect(sortable.toSet().length, sortable.length, reason: '可排集不重复');
      expect(sortable.toSet(),
          all.where((k) => !mmSortPinned.contains(k)).toSet(),
          reason: '可排集＝基线减置顶，不多不少');
      // 当前画布菜单真正参与的只有这几枚（其余都置顶）
      expect(sortable, ['child', 'sibling', 'connect', 'edit', 'bind', 'fold']);
    });

    test('危险项与导航项都在置顶表里（删/断/收/展/归位/剪贴板/上下移）', () {
      for (final k in [
        'del',
        'detach',
        'collapse',
        'expand',
        'reset',
        'copy',
        'cut',
        'pasteSib',
        'pasteChild',
        'up',
        'down',
      ]) {
        expect(mmSortPinned.contains(k), isTrue, reason: '「$k」必须置顶');
      }
      // 正档反证：普通项不在置顶表里（否则这条只证明「表非空」）
      expect(mmSortPinned.contains('edit'), isFalse);
    });
  });

  group('mmRankKeys 判闸', () {
    const keys = ['edit', 'bind', 'fold'];

    test('样本不足＝回基线序（同一入参在不同样本下输出不同）', () {
      // 负档：总样本 < 3 时，哪怕「fold」是唯一被点过的，也不许动
      expect(mmRankKeys(keys, {'fold': 1}), keys);
      expect(mmRankKeys(keys, {'fold': 2}), keys);
      // 正档：刚好 3 次 ⇒ 真前移
      expect(mmRankKeys(keys, {'fold': 3}), ['fold', 'edit', 'bind']);
      expect(mmRankMinSamples, 3);
    });

    test('空计数表逐项等于基线（零变化守护点）', () {
      expect(mmRankKeys(keys, const {}), keys);
      // 全为 0 的显式表也一样（不能把「0 次」当成「未知」）
      expect(mmRankKeys(keys, {'edit': 0, 'bind': 0, 'fold': 0}), keys);
    });

    test('次数相同＝保持基线相对序（稳定），不是整体倒置', () {
      final out = mmRankKeys(keys, {'edit': 5, 'bind': 5, 'fold': 5});
      expect(out, keys, reason: '同票不退序');
      // 反证：把 fold 多加一次的同一张表必须挪动，证明上一条不是恒等
      expect(mmRankKeys(keys, {'edit': 5, 'bind': 5, 'fold': 6}).first, 'fold');
    });

    test('置顶键的计数被忽略：点一百次「删除」也进不了可排位', () {
      final out = mmRankKeys(['edit', 'bind', 'fold', 'del'],
          {'del': 100, 'edit': 3, 'bind': 1, 'fold': 1});
      expect(out, ['edit', 'bind', 'fold', 'del'], reason: '删永远在末位');
      // 反证：把同样的注意力给「bind」，它就真能超过 edit
      final out2 = mmRankKeys(['edit', 'bind', 'fold', 'del'],
          {'del': 100, 'edit': 3, 'bind': 4, 'fold': 1});
      expect(out2, ['bind', 'edit', 'fold', 'del']);
    });

    test('排序步长压得住「次数差 1」：大数稳定压小数', () {
      // edit 用 9999 次、bind 用 9998 次 ⇒ 名次差再大也翻不过来
      final out = mmRankKeys(['fold', 'bind', 'edit'], {'edit': 9999, 'bind': 9998, 'fold': 1});
      expect(out, ['edit', 'bind', 'fold']);
    });

    test('mmRankMenuGroups：组序与并排结构不动，只排组内非并排项', () {
      MmMenuItem it(String k, {bool inline = false}) =>
          (key: k, icon: Icons.add, label: k, enabled: true, inline: inline);
      // 第三组的收/展必须**真的标成 inline**——它们是并排对（真实菜单里
      // `collapse/expand` 都写 `inline: true`）。早期版本漏了这个标记，于是
      // 「并排保护」这条分支压根没被这条用例走到：拆掉保护照样全绿（假绿）。
      List<List<MmMenuItem>> base() => [
            [it('child'), it('sibling')],
            [
              it('edit'),
              it('bind'),
              it('fold'),
              it('collapse', inline: true),
              it('expand', inline: true),
            ],
            [it('up', inline: true), it('down', inline: true)],
            [it('pasteSib', inline: true), it('pasteChild', inline: true)],
            [it('del')],
          ];
      List<String> keysOf(List<List<MmMenuItem>> g) =>
          [for (final r in g) for (final x in r) x.key];

      // 负档：不给 ranks（null）⇒ 同一个 List 原样返回（零分配、零变动）
      final g0 = base();
      expect(identical(mmRankMenuGroups(g0, null), g0), isTrue);
      // 空表**不走短路**（要过判闸），但结果必须逐项等于基线
      expect(keysOf(mmRankMenuGroups(g0, const {})), keysOf(g0));

      // 正档一：同组可排位只有 `edit`、`bind` 两个（`fold` 后面紧跟并排组，
      // 按「并排原子」口径它连同并排头一起留在原位）。给 bind 9 票 ⇒ 与 edit 换位，
      // `fold` 与收/展三格**一格不动**。
      final g1 = mmRankMenuGroups(base(), {'bind': 9});
      expect(g1.length, 5, reason: '组数不动');
      expect(keysOf(g1).take(2), ['child', 'sibling'], reason: '首组不动');
      expect(keysOf(g1).sublist(2, 5), ['bind', 'edit', 'fold'],
          reason: '组内可排的两枚换位');
      expect(g1[1].length, 5);
      expect(g1[1][3].key, 'collapse', reason: '并排头钉死，不被排序卷走');
      expect(g1[1][4].key, 'expand');

      // 正档二（**并排保护的判定点**）：把 fold 顶到最高票，它**仍然不动**——
      // 因为它是「并排组的前驱」，属于原子。若拆掉 `mmRankMenuGroups` 里那条
      // `if (i + 1 < g.length && g[i + 1].inline) continue;`，fold 会被卷进可排位
      // 并凭高票窜到组头，这条立刻红。（变异刀 k5 的靶心就是它。）
      final g2 = mmRankMenuGroups(base(), {'fold': 9});
      expect(keysOf(g2).sublist(2, 5), ['edit', 'bind', 'fold'],
          reason: 'fold 是并排组前驱，票数再高也不越过它前面的项');

      // 末组一枚、并排组本身没有可排项 ⇒ 一律不动
      expect(g1[2].map((x) => x.key), ['up', 'down']);
      expect(g1[4].single.key, 'del');

      // 编辑前的对象不被就地改动（返回的是副本，浮层每次开都要干净基线）
      final g3 = base();
      mmRankMenuGroups(g3, {'bind': 9});
      expect(keysOf(g3).sublist(2, 5), ['edit', 'bind', 'fold']);
    });

    test('置顶项原位不动：零次的可排项挤不下去，真点出来的才挤得动', () {
      const k = ['edit', 'fold', 'reset', 'child'];
      // 负档：reset 零次、edit 点够 3 次 ⇒ reset 仍在其基线位（第 3）
      expect(mmRankKeys(k, {'edit': 3}).indexOf('reset'), 2);
      // 正档：把 reset 前面的项都点上去，它才顺势后移一位——证明上一条不是「钉在表头」
      expect(mmRankKeys(k, {'edit': 3, 'fold': 3}).indexOf('reset'), 2,
          reason: '前两名互换算过之后 reset 仍是第三');
      // 次数是主键：child 点得最多就排前面；置顶的 reset 一格都不动（还在第 3）
      expect(mmRankKeys(k, {'child': 5, 'edit': 3, 'fold': 3}),
          ['child', 'edit', 'reset', 'fold'],
          reason: 'reset 原位（第 3 格），可排项只在自己那几格里换位');
      // 同票者（edit/fold 各 3 次）之间仍守基线相对序 —— 这一条才是「不退序」的实证
      expect(mmRankKeys(k, {'child': 5, 'edit': 3, 'fold': 3}).indexOf('edit'),
          lessThan(mmRankKeys(k, {'child': 5, 'edit': 3, 'fold': 3}).indexOf('fold')));
      expect(mmRankKeys(k, {'edit': 1, 'child': 9}).first, 'child',
          reason: '票数差到手就真前移（上一条不是恒等）');
      // 置顶项原位不动：child 被点到 9 次也只占「可排槽位」的首格，reset 仍在第 3 格
      expect(mmRankKeys(k, {'child': 9}), ['child', 'edit', 'reset', 'fold'],
          reason: '零次的可排项挤不动置顶项（reset 位置一格不动）');
      expect(mmRankKeys(k, {'child': 2}).indexOf('reset'), 2,
          reason: '样本不够时 reset 一个位置都不动（同上，反面对照）');
    });
  });

  group('MmMenuUsageStore', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('bump 只认可排键：陌生键与置顶键一个字都不写', () async {
      final st = MmMenuUsageStore(prefs);
      // 负档：这些键必须拒绝，且盘上不留痕
      expect(await st.bump('del'), isFalse);
      expect(await st.bump('up'), isFalse);
      expect(await st.bump('pasteChild'), isFalse);
      expect(await st.bump('never-registered'), isFalse);
      expect(prefs.getString(MmMenuUsageStore.key), isNull,
          reason: '被拒的点击不许写出半个 key');
      // 正档：可排键真写、真累加
      expect(await st.bump('child'), isTrue);
      expect(await st.bump('child'), isTrue);
      expect(st.load(), {'child': 2});
    });

    test('坏数据按空表回落，不炸菜单', () async {
      final st = MmMenuUsageStore(prefs);
      prefs.setString(MmMenuUsageStore.key, '{not json');
      expect(st.load(), isEmpty);
      prefs.setString(MmMenuUsageStore.key, '[1,2,3]');
      expect(st.load(), isEmpty);
      // 脏值逐项过滤：非数字/零/负数丢掉，超上限钳到 cap
      prefs.setString(MmMenuUsageStore.key,
          '{"edit":"x","bind":0,"fold":-2,"child":3.0,"sibling":99999}');
      expect(st.load(), {'child': 3, 'sibling': MmMenuUsageStore.cap});
      // 正档：坏数据之后还能正常记账（下一笔覆盖成合法 JSON）
      expect(await st.bump('edit'), isTrue);
      expect(st.load()['edit'], 1);
    });

    test('计数封顶：连点超过上限不再增长（也保护权重算式不溢出）', () async {
      final st = MmMenuUsageStore(prefs);
      prefs.setString(MmMenuUsageStore.key, '{"edit":${MmMenuUsageStore.cap}}');
      await st.bump('edit');
      expect(st.load()['edit'], MmMenuUsageStore.cap);
    });

    test('clear 之后回基线序（存取的复位口）', () async {
      final st = MmMenuUsageStore(prefs);
      await st.bump('fold');
      await st.bump('fold');
      await st.bump('fold');
      expect(mmRankKeys(['edit', 'bind', 'fold'], st.load()).first, 'fold');
      await st.clear();
      expect(mmRankKeys(['edit', 'bind', 'fold'], st.load()), ['edit', 'bind', 'fold']);
    });
  });

  group('基线表与画布真实菜单一致单测', () {
    test('并排对在基线表里仍相邻同序（并排原子判据的前提）', () {
      final base = mmMenuBaselineGroups;
      expect(base.any((b) => _hasAdjacent(b, 'up', 'down')), isTrue);
      expect(base.any((b) => _hasAdjacent(b, 'collapse', 'expand')), isTrue);
      expect(base.any((b) => _hasAdjacent(b, 'pasteSib', 'pasteChild')), isTrue);
    });

    test('画布菜单每一枚都在基线表里，且组序/组界与基线逐项相等', () {
      final menu = mmMenuBaselineFromCanvas;
      final keys = [for (final g in menu) ...g];
      expect(keys.toSet().length, keys.length, reason: '菜单里不许出现同名项');
      // 正档：菜单项与基线表**同一集合**（不是「差集为空」就行——少了也漏）
      expect(keys.toSet(), mmMenuBaselineKeys,
          reason: '菜单与 mmMenuBaselineGroups 不同步：新增菜单项必须同步基线表，'
              '否则那一枚永远学不到频次');
      // 组界也要相等：跨组挪项会让「并排原子」与「组内排序」两套判据错位
      expect([for (final g in menu) g.length.toString()].join(','),
          [for (final g in mmMenuBaselineGroups) g.length.toString()].join(','));
      // 反证：随便挪一枚到别的组，上面那条就必须红
      final moved = [
        for (var i = 0; i < menu.length; i++) List.of(menu[i]),
      ];
      moved[0].add(moved[1].removeAt(0));
      expect([for (final g in moved) g.length.toString()].join(','),
          isNot([for (final g in mmMenuBaselineGroups) g.length.toString()].join(',')));
    });
  });
}
