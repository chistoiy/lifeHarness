// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'diary_edit_page.dart';
import 'journal_page.dart';
import 'note_edit_page.dart';
import 'tag_add_page.dart';
import 'tag_manage_page.dart';


/// C 案批1：旧「记录」四段深链的兼容落点（纯函数·路由与常驻断言共用）。
/// 无参/非法段名一律落笔记页——记录页已退役，不再有「沿用上次停留的段」这一态。
String journalLegacyTarget(String? tab) => switch (tab) {
      'diary' => '/diary',
      'note' => '/notes',
      'book' => '/readhub',
      'media' => '/mediahub',
      _ => '/notes',
    };

/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> journalShellRoutes() => [
        // C 案批1：/journal 退役为兼容跳转（旧桌面快捷方式／旧深链仍落对应独立页）。
        GoRoute(
          path: '/journal',
          redirect: (_, s) => journalLegacyTarget(s.uri.queryParameters['tab']),
        ),
        // C 案批1：四模块各自独立成页（底栏可配置池栏目直达）。
        GoRoute(
          path: '/notes',
          builder: (_, _) =>
              const JournalPage(section: 'note'),
        ),
        GoRoute(
          path: '/diary',
          builder: (_, _) =>
              const JournalPage(section: 'diary'),
        ),
        GoRoute(
          path: '/readhub',
          builder: (_, _) =>
              const JournalPage(section: 'book'),
        ),
        GoRoute(
          path: '/mediahub',
          builder: (_, _) =>
              const JournalPage(section: 'media'),
        ),
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> journalPageRoutes() => [
        // 日记编辑页：全屏无底栏（原型 p-diaryEdit 为 stack 页）。
          // V1.28 一天多篇：extra=DiaryEditArg(day 新建当天的第 N+1 篇 | entryId 编辑既有篇)。
          GoRoute(
            path: '/journal/edit',
            builder: (_, s) {
              final a = s.extra;
              return a is DiaryEditArg
                  ? DiaryEditPage(day: a.day, entryId: a.entryId)
                  : DiaryEditPage(day: a as DateTime?);
            },
          ),
        // M1 批1a 笔记编辑页：全屏纸感（原型 p-noteEdit），extra=noteId（null=新建）。
          GoRoute(
            path: '/note/edit',
            builder: (_, s) {
              final x = s.extra;
              if (x is NoteEditArg) {
                return NoteEditPage(
                  noteId: x.noteId,
                  initialKind: x.kind,
                  initialFolder: x.folder,
                );
              }
              return NoteEditPage(noteId: x as int?);
            },
          ),
        // 批2b 标签管理（原型 p-sub-tags / p-sub-tagAdd）：全屏栈页，我的页「记录」组入口。
        GoRoute(path: '/tags', builder: (_, _) => const TagManagePage()),
        GoRoute(path: '/tags/add', builder: (_, _) => const TagAddPage()),
];
