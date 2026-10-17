# read/presentation — 阅读模块展示层入口

治理 G4 分五子域目录 + 根层杂件：

- `reader/` 阅读器（见其 README）
- `shelf/` 书架与书目页（见其 README）
- `biblio/` 书目检索（豆瓣先搜后加 V1.44）：`biblio_search_page` · `book_info_page` · `douban_login_page` · `isbn_scan_page`
- `import/` 导入：`read_import_page`（豆瓣清单/本地）· `local_import_page`
- `stats/` 统计与日志：`read_stat_page`（账本四档）· `read_timer_page` · `read_log_page` · `quotes_lib_page`
- 根层：`read_tab` 书架主页容器 · `read_providers` · `read_routes` · `read_settings_page` · `read_sheets` 系列

`read_sheets.dart` 为 part 库：`read_sheets_b2/b3/b4` 是同库弹层群（批 2/3/4 划分），
b2/b3 仍是 >1200 行大文件，登记在 `test/size_budget_test.dart` 预算表内（只许减不许增）。
