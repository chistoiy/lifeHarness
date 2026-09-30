// 小工具下架 · 归档/计划文档补丁（修正版：README 去重 + 计划文档终止横幅）
const fs = require('fs');
function load(f) { const raw = fs.readFileSync(f, 'utf8'); const crlf = raw.includes('\r\n'); return { f, crlf, s: crlf ? raw.replace(/\r\n/g, '\n') : raw }; }
function save(b) { fs.writeFileSync(b.f, b.crlf ? b.s.replace(/\n/g, '\r\n') : b.s); console.log('written ' + b.f); }

/* ① README：上一轮重复写入，删掉第二份条目 */
{
  const b = load('prototype/archive/README.md');
  const entry = '- **index-kits.html：小工具合集专版（V1.47 模块14），2026-09-30 产品负责人拍板「模块价值太低」整模块下架**。';
  const n = b.s.split(entry).length - 1;
  if (n !== 2) throw new Error('README 条目命中 ' + n + '（预期 2：重复了一次）');
  const i1 = b.s.indexOf(entry);
  const i2 = b.s.indexOf(entry, i1 + 1);
  b.s = b.s.slice(0, i1) + b.s.slice(i2);
  if (b.s.split(entry).length - 1 !== 1) throw new Error('去重后仍非 1 份');
  save(b);
}

/* ② 计划文档顶部终止横幅 */
{
  const b = load('docs/小工具模块开发计划-20260929.md');
  if (b.s.includes('整模块下架**（产品负责人')) { console.log('计划文档横幅已在，跳过'); }
  else {
    const title = '# 小工具合集（模块 14 · V1.47）Flutter 开发计划';
    if (b.s.split(title).length - 1 !== 1) throw new Error('标题锚点未命中');
    b.s = b.s.replace(title, title + '\n\n' +
      '> ⛔ **本模块已于 2026-09-30 整模块下架**（产品负责人拍板：「小工具功能全部移除掉，模块价值太低」）。\n' +
      '> 批0~批3 与验收轮2~轮5 都曾有效交付，本文自此**停止维护**，仅作过程留档。\n' +
      '> 下架口径：`lib/features/kits/**` 与只被它使用的 `core/ai/ai_verify_channel.dart` 删除；`/kits` 路由、\n' +
      '> `NavModule.kits` 栏目、宫格「小工具」枚、`KitSettings`(`lh.kit`) 偏好、原型 p-tools 屏全部摘除；\n' +
      '> **DB v29→v30 迁移 DROP kit_\\* 四表**，`lh.kit` 读取时一次性清除（照 care.rm.lock 先例）；\n' +
      '> 专版原型 `index-kits.html` 移入 `prototype/archive/` 留档不删。共享面改动见《需求清单》V1.58 修订记录。');
    save(b);
  }
}
console.log('OK');
