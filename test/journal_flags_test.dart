import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_layout_kit.dart';

/// 日记改版批1a · 收藏/点亮两个**视图出口**（工单 §1 执行面板末件）。
///
/// 为什么单开一套：这两个键不是标签，它们走的是「固定键」白名单（`starred` / `liked`），
/// 与 `todo` 同族。这里钉三件事：① 固定键不被标签白名单判成脏值回落 `all`；
/// ② 过滤只放行该位为真的篇；③ 三档视图下「篇数」口径一致（同一天多篇不重复算）。
///
/// 复刻 build 里的筛选算式（不放宽也不收紧）——build 本体要整页 pump，
/// 为一条筛选口径拖起整套 provider 成本过高，且真正会回归的就是这三行。

/// 与 `_DiaryTabState.build` 同源的筛选：固定键 + 标签键 + 脏值回落。
List<JournalEntry> applyFilter(
  List<JournalEntry> entries,
  String filter,
) {
  final rawTags = <String>{for (final e in entries) ...e.tags};
  const fixedKeys = {'all', 'todo', 'starred', 'liked'};
  final eff = (fixedKeys.contains(filter) || rawTags.contains(filter))
      ? filter
      : 'all';
  return switch (eff) {
    'all' => entries,
    'todo' => entries.where((e) => e.todoLines().isNotEmpty).toList(),
    'starred' => entries.where((e) => e.starred).toList(),
    'liked' => entries.where((e) => e.liked).toList(),
    _ => entries
        .where((e) => e.tags.any((t) => t == eff || '#$t' == eff))
        .toList(),
  };
}

JournalEntry _e(
  int day, {
  bool starred = false,
  bool liked = false,
  String content = '正文',
  List<String> tags = const [],
}) =>
    JournalEntry(
      day: DateTime(2026, 10, day),
      starred: starred,
      liked: liked,
      // tags 必须真传进去：正文里写 `#阅读` 只影响 hashTags()，不改 `e.tags`
      //（F7 首版就栽在这——筛选读的是 `e.tags`，正文写了等于没写）。
      tags: tags,
      content: '$content${tags.isEmpty ? '' : '\n\n${tags.join(' ')}'}',
      createdAt: DateTime(2026, 10, day, 9, 30),
      updatedAt: DateTime(2026, 10, day, 9, 30),
    );

void main() {
  group('收藏/点亮筛选', () {
    final all = [
      _e(19, starred: true),
      _e(18, liked: true),
      _e(17, content: '☐ 买牛奶'),
      _e(16, content: '带标签', tags: const ['阅读']),
      _e(15),
    ];

    test('F1 starred 只放行收藏篇', () {
      final r = applyFilter(all, 'starred');
      expect(r.length, 1);
      expect(r.single.day.day, 19);
    });

    test('F2 liked 只放行点亮篇', () {
      final r = applyFilter(all, 'liked');
      expect(r.length, 1);
      expect(r.single.day.day, 18);
    });

    test('F3 两位都为真时两个键各自命中（不是二选一的互斥位）', () {
      final both = [_e(1, starred: true, liked: true)];
      expect(applyFilter(both, 'starred').length, 1);
      expect(applyFilter(both, 'liked').length, 1);
    });

    test('F4 固定键不被标签白名单判脏回落 all（回归：加了键却只在弹层出现）', () {
      // 全部篇都没有 starred 字样的标签，若白名单没收这两个键，就会静默回落 all
      expect(applyFilter(all, 'starred').length, isNot(all.length));
      expect(applyFilter(all, 'liked').length, isNot(all.length));
    });

    test('F5 全都没收藏时给空列表，不能回落成全量（否则筛选看不出效果）', () {
      final none = [_e(1), _e(2)];
      expect(applyFilter(none, 'starred'), isEmpty);
      expect(applyFilter(none, 'liked'), isEmpty);
    });

    test('F6 真脏值仍回落 all（收口不能把原语义放宽）', () {
      expect(applyFilter(all, '不存在的标签').length, all.length);
      expect(applyFilter(all, '').length, all.length);
    });

    test('F7 标签键照旧命中（新增固定键没打坏标签分支）', () {
      // 落库的 tags 是裸词（无 #），settings 里存的也是裸词 ⇒ 裸词命中。
      expect(applyFilter(all, '阅读').length, 1);
      expect(applyFilter(all, '阅读').single.day.day, 16);
      // 带 # 的写法在 build 的白名单里被判脏 ⇒ 回落 all。这是**原有**语义，
      // 本批不该顺手改（改了等于悄悄放宽筛选），此处只钉住它没变。
      expect(applyFilter(all, '#阅读').length, all.length);
    });

    test('F8 待办键照旧命中（新增固定键没打坏 todo 分支）', () {
      final r = applyFilter(all, 'todo');
      expect(r.length, 1);
      expect(r.single.day.day, 17);
    });

    test('F9 收藏键与轨道折块复合：同日两篇只收藏一篇 ⇒ 只出那一篇那块', () {
      final two = [
        _e(19, starred: true, content: '收藏的'),
        _e(19, content: '没收藏的'),
      ];
      final shown = applyFilter(two, 'starred');
      final blocks = buildTrackBlocks(shown);
      expect(blocks.length, 1);
      expect(blocks.single.entries.length, 1);
      expect(blocks.single.entries.single.content, contains('收藏的'));
    });
  });
}
