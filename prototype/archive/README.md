# prototype/archive · 归档区

2026-09-28 治理 G3 批次迁入（git mv，内容零改动）。均为被否/已降级/中间轮次稿，留档不维护：

- index-V3.html / index-V4.html：V3/V4 结构级风格试衣间，被否
- index-reader.html：阅读器专版，已并入书架专版 index-bookshelf.html（V1.50），降级参考稿
- diary-batch2-preview.html：日记批2 预览稿
- index-habitcheck-v2.html / -v3：习惯专版迭代中间稿，定稿为主区 index_habitcheck.html（用户 2026-09-28 确认）
- **index-kits.html：小工具合集专版（V1.47 模块14），2026-09-30 产品负责人拍板「模块价值太低」整模块下架**。
  批0~批3 + 验收轮2~轮5 的高保真全量留此，**留档不维护**；共享面 `index.html` 内的 p-tools 屏与入口已同步摘除。
  Flutter 侧代码删于本轮（找回：`git show 391edde:lib/features/kits/domain/kit_jpeg.dart` 等，按文件逐个 show）；
  DB 四表由 **v29→v30 迁移 DROP**（`DbSchema.migrations[29]`），偏好键 `lh.kit` 读取时一次性清除。

注意：v2.html 与 index-v2.html 按用户决定**原地勿动**（非本会话产物）。
