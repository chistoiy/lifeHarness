// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'diary_edit_page.dart';
import 'journal_page.dart';
import 'note_edit_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> journalShellRoutes() => [
        GoRoute(path: '/journal', builder: (_, _) => const JournalPage())
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
          )
];
