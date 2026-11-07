# shelf/ — 书架页群入口

- `shelf_page.dart`（547 行，治理 G7d① 后）：留 `ShelfUI` + provider + 字段 + build；文件零 setState
  （状态走 provider），拆件全部 **extension part**（免定点 ignore）：
  - 尾随整块 part：`shelf_batch_tag` / `shelf_fab` / `shelf_long_press`（含 kLp* 与 showLongPressSheet）/ `shelf_goal_ring`
  - 行为群 extension part：`shelf_goal` · `shelf_panel` · `shelf_views` · `shelf_spine_time` · `shelf_batch_ops`
- 书目页：`book_detail`（1,570 行）· `book_form_page`（1,362 行）· `book_mgr_page` · `read_lists_page`
  ——前两者登记在 `test/size_budget_test.dart` 预算表（只许减不许增）。
- 纯移动取证：`tools/g7d_puremove_check.js --base <治理提交> --main shelf_page.dart --dir 本目录 --parts …`。
