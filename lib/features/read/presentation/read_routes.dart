// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'biblio/biblio_search_page.dart';
import 'shelf/book_detail.dart';
import 'shelf/book_form_page.dart';
import 'biblio/book_info_page.dart';
import 'shelf/book_mgr_page.dart';
import 'biblio/douban_login_page.dart';
import 'biblio/isbn_scan_page.dart';
import 'import/local_import_page.dart';
import 'stats/quotes_lib_page.dart';
import 'import/read_import_page.dart';
import 'stats/read_log_page.dart';
import 'read_settings_page.dart';
import 'stats/read_stat_page.dart';
import 'stats/read_timer_page.dart';
import 'reader/reader_page.dart';
import 'shelf/shelf_page.dart';
import 'shelf/read_lists_page.dart';
import 'xray_words_page.dart';

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> readPageRoutes() => [
        // M1批3 阅读：书架与书籍详情（原型 p-bookshelf / p-bookDetail）。
          GoRoute(path: '/read/shelf', builder: (_, _) => const ShelfPage()),
        GoRoute(
            path: '/read/book/:id',
            builder: (_, s) => BookDetailPage(
              bookId: s.pathParameters['id']!,
              initialTab: (s.extra as BookDetailArg?)?.tab ?? 'c',
            ),
          ),
        // M1批3·批2：书籍资料页（p-bookInfo）与沉浸计时页（p-readtimer·全屏形态）。
          GoRoute(
            path: '/read/info/:id',
            builder: (_, s) => BookInfoPage(bookId: s.pathParameters['id']!),
          ),
        GoRoute(
            path: '/read/timer/:id',
            builder: (_, s) => ReadTimerPage(bookId: s.pathParameters['id']!),
          ),
        // 真机验收轮1e：阅读记录页（原型 p-readlog · 计时明细改全屏页）。
          GoRoute(
            path: '/read/log/:id',
            builder: (_, s) => ReadLogPage(bookId: s.pathParameters['id']!),
          ),
        // M1批3·批3 笔记库（原型 p-quotes · 跨书摘录四视图，extra=入口书 id）。
          GoRoute(
            path: '/read/quotes',
            builder: (_, s) => QuotesLibPage(bookId: s.extra as String?),
          ),
        // M1批3·批4 统计与书单（原型 p-readstat / p-booklists / p-booklist）。
          GoRoute(
            path: '/read/stat',
            builder: (_, _) => const ReadStatPage(),
          ),
        GoRoute(
            path: '/read/lists',
            builder: (_, _) => const BookListsPage(),
          ),
        GoRoute(
            path: '/read/list/:id',
            builder: (_, s) =>
                BookListDetailPage(listId: int.parse(s.pathParameters['id']!)),
          ),
        // M1批3·批5 导入向导与阅读设置（原型 p-readimport / p-readset）。
          GoRoute(
            path: '/read/import',
            builder: (_, _) => const ReadImportPage(),
          ),
        GoRoute(
            path: '/read/settings',
            builder: (_, s) => ReadSettingsPage(
              // ?sec= 定位组（书架长按菜单「调整长按菜单」→ 1＝内容显示与排序）。
              initialSec: int.tryParse(s.uri.queryParameters['sec'] ?? '') ?? 0,
            ),
          ),
        // 扫书脊 ISBN 全屏页（保真批F2 · 书籍表单「扫 ISBN」钮 push，命中 pop 回码值）。
          GoRoute(
            path: '/read/scan',
            builder: (_, _) => const IsbnScanPage(),
          ),
        // V1.44 先搜后加：添加图书＝豆瓣书目搜索页（原型 p-biblioSearch），
          // 点结果行带 DoubanSearchRow 进整页表单；?id= 为编辑态（原型 p-bookForm）。
          GoRoute(
            path: '/read/biblio-search',
            builder: (_, _) => const BiblioSearchPage(),
          ),
        GoRoute(
            path: '/read/book-form',
            builder: (_, s) => BookFormPage(
              bookId: s.uri.queryParameters['id'],
              seed: s.extra,
            ),
          ),
        // V1.45 豆瓣登录 Cookie 获取页（替代手动粘贴：设置页「登录豆瓣」push，
          // 用户自行登录点「完成」→ 原生 CookieManager 提取 → pop 回 true）。
          GoRoute(
            path: '/read/douban-login',
            builder: (_, _) => const DoubanLoginPage(),
          ),
        // V1.50 阅读器（本地 EPUB）：导入四步向导（原型 p-localImport）与
          // 阅读主屏（p-readerPage · 栈内全屏页，TimerBarOverlay 壳外不显胶囊）。
          GoRoute(
            path: '/read/import-epub',
            // 批3.5：?reattach=<bookId> ＝ 源丢失重选模式（选中原文件挂回原记录）。
            builder: (_, s) =>
                LocalImportPage(reattachBookId: s.uri.queryParameters['reattach']),
          ),
        GoRoute(
            path: '/read/reader/:id',
            builder: (_, s) => ReaderPage(bookId: s.pathParameters['id']!),
          ),
        // 书架资料单类管理页：?kind= 决定类（书架维度行「管理X」入口；默认来源）。
          GoRoute(
            path: '/read/mgr',
            builder: (_, s) {
              const kinds = ['source', 'group', 'tag', 'author', 'publisher'];
              final k = s.uri.queryParameters['kind'];
              return BookMgrPage(kind: kinds.contains(k) ? k! : 'source');
            },
          ),
        // V1.54.1 批2：X-Ray 词库管理（GLOBAL 养成词库 CRUD＋启用开关）。
          GoRoute(
            path: '/read/xray-words',
            builder: (_, _) => const XrayWordsPage(),
          )
];
