# 待办 widgets 目录卡（体积预算治理）

| 文件 | 角色 | 说明 |
|---|---|---|
| `todo_edit_sheet.dart` | **宿主库** | 入口函数 `showTodoAddSheet` / `showTodoDetailSheet`、共享件 `dueLabel` / `catColorNames` / `catColorOf` / `_MiniSeg` / `_AskCard` / `_InfoRow`，以及详情弹层 `_TodoDetailSheet(State)`；`part 'todo_add_sheet.dart';` 在 import 块尾 |
| `todo_add_sheet.dart` | **part（新建/编辑表单）** | `_TodoAddSheet(State)` 整块：判象限两问、时间三态、番茄、子任务、提醒滚轮。2026-09-30 自宿主整块外提（纯移动·`g7d_puremove_check.js --toplevel` 取证 806 行全等） |
| `todo_list_view.dart` | 清单视图 | 行卡、滑动删除、筛选 chips、逾期提示卡 |
| `quadrant_board.dart` | 四象限视图 | 拖拽改象限、格内添加 |
| `pomo_screen.dart` | 番茄全屏专注页 | 路由 `/pomo`（V1.27 T7） |

## 动手前须知

- **本目录是 `todo` 模块唯一写区**（并行会话约定）；`todo_edit_sheet.dart` 已从体积预算登记表中**删除**，
  回到「>1200 行即红」的默认面——再长大就是真违规，请继续按整块 part 外提，不要塞回宿主。
- **源码级断言要扫整个库**：`test/todo_remind_1min_test.dart` 里有示范——宿主 + 同目录所有
  `part of 'todo_edit_sheet.dart';` 分片拼接后再断言。只读宿主文件会在下次外提时把文案锚点扫成假红。
- part 文件不得写 `import`（导入归宿主库统一持有），首行必须是 `part of 'todo_edit_sheet.dart';`。
- 待办的软删红线（V1.57 E 批）在数据层：所有在册查询必须带 `deleted_at IS NULL`，
  守护见 `test/todo_trash_guard_test.dart`；UI 侧垃圾箱屏是 `../todo_trash_page.dart`（独立文件）。
