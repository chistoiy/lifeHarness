import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/todo/presentation/todo_providers.dart'
    show PomoSession;
import 'package:lifeharness/features/todo/presentation/todo_routes.dart'
    show pomoRedirect;

/// T10 路由收口 · 常驻守护（交互整改批五）。
///
/// 三档：① 迁移面回归——收口过的模块文件不许再出现匿名页面级 push；
/// ② 路由表——这些屏必须能在 `*_routes.dart` 里查到登记（深链可达＝兜底盖得到），
///    且代码里 `context.push('…')` 用到的每个路径都在表内（写错路径＝运行期落
///    unknownRoute 兜底，静态先拦）；③ 残留匿名 push 逐条挂理由，
///    理由失效（文件里已无 MaterialPageRoute，或"退回型"丢了 maybeOf 前置支）即红。
void main() {
  String read(String rel) => File('lib/$rel').readAsStringSync();

  /// Directory('lib') 在测试里给的是 `lib\features\...` 相对路径，
  /// 绝对路径场景也要能剥掉前缀——统一成「相对 lib 的路径」。
  String relToLib(String path) {
    final s = path.replaceAll(r'\', '/');
    final i = s.lastIndexOf('/lib/');
    if (i >= 0) return s.substring(i + 5);
    return s.startsWith('lib/') ? s.substring(4) : s;
  }

  /// 全模块路由表里登记过的路径集合。
  Set<String> registeredPaths() {
    final out = <String>{};
    final re = RegExp(r"path:\s*'([^']+)'");
    for (final f in Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!f.path.endsWith('_routes.dart')) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        out.add(m.group(1)!);
      }
    }
    return out;
  }

  group('1 · 收口面不许回潮匿名 push', () {
    const migrated = [
      'features/days/presentation/days_page.dart',
      'features/days/presentation/day_detail_page.dart',
      'features/goals/presentation/goals_page.dart',
      'features/goals/presentation/goal_detail_page.dart',
      'features/goals/presentation/goal_edit_page.dart',
      'features/items/presentation/items_page.dart',
      'features/items/presentation/item_detail_page.dart',
      'features/items/presentation/item_stats_page.dart',
      'features/todo/presentation/widgets/todo_list_view.dart',
    ];
    for (final rel in migrated) {
      test('$rel 无匿名页面级 push', () {
        final src = read(rel);
        expect(src, isNot(contains('Navigator.push(')),
            reason: '$rel 又直接用 Navigator.push 了');
        expect(src, isNot(contains('MaterialPageRoute')),
            reason: '$rel 又自建匿名路由了');
        expect(src, isNot(matches(RegExp(r'Navigator\.of\([^)]*\)\s*\.push'))),
            reason: '$rel 用 Navigator.of(...).push 绕开路由表');
      });
    }
  });

  group('2 · 路由表登记与调用面对齐', () {
    const required = [
      '/days/detail', '/days/edit', '/days/remind',
      '/goals/detail', '/goals/edit', '/goals/review',
      '/items/detail', '/items/edit', '/items/stats', '/items/settle',
      '/pomo',
    ];
    const pushers = [
      'features/days/presentation/days_page.dart',
      'features/days/presentation/day_detail_page.dart',
      'features/goals/presentation/goals_page.dart',
      'features/goals/presentation/goal_detail_page.dart',
      'features/items/presentation/items_page.dart',
      'features/items/presentation/item_detail_page.dart',
      'features/items/presentation/item_stats_page.dart',
      'features/todo/presentation/widgets/todo_list_view.dart',
    ];
    test('T10 用到的 11 条路径全部登记在 *_routes.dart', () {
      final reg = registeredPaths();
      expect(reg.containsAll(required), isTrue,
          reason: '缺：${required.where((r) => !reg.contains(r)).toList()}');
    });

    test('收口文件里 context.push 的字面路径都在路由表内（含查询串的取基址）', () {
      final reg = registeredPaths();
      final re = RegExp(r"context\.push(?:<[^>]*>)?\(\s*'([^']+)");
      final bad = <String>[];
      for (final rel in pushers) {
        for (final m in re.allMatches(read(rel))) {
          final path = m.group(1)!.split('?').first;
          // 模板串尾部带 ${...} 的路径不可能命中登记值，先摘掉插值再比。
          final base = path.replaceAll(RegExp(r'\$\{[^}]*\}'), '');
          if (!reg.contains(base)) bad.add('$rel → ${m.group(1)}');
        }
      }
      expect(bad, isEmpty, reason: '这些 push 目标没登记：$bad');
    });
  });

  group('3 · 残留匿名 push 白名单（逐条理由，失效即红）', () {
    const whitelist = <String, String>{
      'features/read/presentation/shelf/book_form_page.dart':
          '退回型：`GoRouter.maybeOf` 拿到路由时一律走命名路由，只有 widget 测试直挂 MaterialApp 才匿名 push',
      // 高保真批6b·刀2（2026-10-16）：书籍表单 UI 积木群拆 part 迁入同库件，其中一条
      // 退回型匿名 push 随组搬迁（maybeOf 前置支口径不变），在此挂同款理由。
      'features/read/presentation/shelf/book_form_page_form.dart':
          '退回型：自 book_form_page 拆 part 迁入，`GoRouter.maybeOf` 拿到路由时一律走命名路由，只有 widget 测试直挂 MaterialApp 才匿名 push',
      'features/read/presentation/biblio/biblio_search_page.dart':
          '退回型：同上（建档/ISBN 扫描两条）',
      'features/read/presentation/reader/epub_state_ui.dart':
          '全书检索整页携带**活 EpubDoc 句柄**，用完即 dispose，生命周期挂在这条 await 上，无深链语义',
      'features/read/presentation/reader/reader_page.dart':
          '同上，且要等 `BrSearchResult` 返回值挂命中链',
      // 高保真批6c·刀1（2026-10-16）：书摘表单群拆 part 迁入同库件，匿名 push 随组搬迁
      //（maybeOf 前置支口径不变），登记随迁、白名单力度不减。
      'features/read/presentation/read_sheets_b3_quote.dart':
          '自 read_sheets_b3 拆 part 迁入：书摘表单 `_QuoteForm` 是本库私有全屏表单（带编辑对象与六项运行时参数），不是可登记屏',
    };
    test('lib 内出现 MaterialPageRoute 的文件必须都在白名单里', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => relToLib(f.path))
          .where((rel) => read(rel).contains('MaterialPageRoute'))
          .toList()
        ..sort();
      final miss = hits.where((h) => !whitelist.containsKey(h)).toList();
      final stale = whitelist.keys.where((k) => !hits.contains(k)).toList();
      expect(miss, isEmpty, reason: '新增匿名页面级 push 未挂理由：$miss');
      expect(stale, isEmpty,
          reason: '白名单条目已不再含匿名 push，请删掉：$stale');
    });

    test('退回型两处必须仍是「命名路由优先」，摘掉 maybeOf 前置支即红', () {
      for (final rel in [
        'features/read/presentation/shelf/book_form_page.dart',
        'features/read/presentation/biblio/biblio_search_page.dart',
      ]) {
        expect(read(rel), contains('GoRouter.maybeOf'),
            reason: '$rel 的匿名 push 只该是路由缺失时的退回路径');
      }
    });
  });

  group('4 · /pomo 入参闸（T10 顺带补的兜底）', () {
    test('带 PomoSession 放行；缺失或形状不对回落待办主页', () {
      expect(pomoRedirect(null), '/todo');
      expect(pomoRedirect('/pomo'), '/todo');
      expect(
          pomoRedirect(PomoSession(
              todoId: 7, title: '写周报', mode: 'down', minutes: 25)),
          isNull);
    });
  });

  group('5 · 删除连退改走路由返回值（不再往子页塞闭包）', () {
    test("目标编辑页带 'purged' 出栈，详情页接住后连退", () {
      final edit = read('features/goals/presentation/goal_edit_page.dart');
      final detail = read('features/goals/presentation/goal_detail_page.dart');
      expect(edit, contains("Navigator.pop(context, 'purged')"),
          reason: '删除结果靠路由返回值传回发起页');
      expect(edit, isNot(contains('onDeleted')),
          reason: '闭包参数已摘：路由表里塞闭包＝深链不可用又查不到');
      expect(detail, contains(r"'/goals/edit?id=${g.id}'"),
          reason: '详情页改走命名路由');
      expect(detail, contains("r == 'purged'"), reason: '必须接住返回值连退');
      // 日子那条同式（本批前已是 await 返回值口径，钉住别回退成闭包）
      final dayDetail = read('features/days/presentation/day_detail_page.dart');
      expect(dayDetail, contains(r"'/days/edit?id=${day.id}'"));
      expect(dayDetail, contains("r == 'purged'"));
    });
  });
}
