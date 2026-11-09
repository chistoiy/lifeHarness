# reader/ — 阅读器群入口

- `reader_page.dart`（1,108 行，治理 G7a~G7c4 后）：宿主 `_ReaderPageState` 留字段/build/装配；
  行为群以 **extension part** 外提（同库私有直访零参数化）：
  - `reader_chrome.dart` 六件 UI builder（G7c1）
  - `reader_sel_ops.dart` 选区/划线逻辑群（G7c2；`_BrAiSheet` 随唯一调用者同迁）
  - `reader_stage.dart` `_stage/_para` 渲染群（G7c3，纯渲染）
  - `reader_links.dart` 链接/图片群（G7c4）
  - `reader_sel_layer.dart` 选区浮层三件（G7b1，闭包参数化独立文件）
- 其余：`epub_state_ui`（EPUB 状态 UI）· `reader_pager`（foliate 惰性分页）· `reader_appearance_sheet`
  · `reader_bg` · `reader_bottom_sheets` · `reader_models` · `reader_search_page` · `reader_toc_drawer`
- 拆件规矩：extension 成员**静态派发**，类内/mixin 加同名成员会静默遮蔽——动刀前后跑
  「成员恰好出现一次」双向断言；纯移动取证用 `tools/g7d_puremove_check.js`（extension 默认模式）。
- 门禁池：reader_select10 + ui10 + v53*8（关键交互已钉死）。
