const fs = require('fs');
const P = 'docs/UI组件规范.md';
let s = fs.readFileSync(P, 'utf8');
const EOL = s.includes('\r\n') ? '\r\n' : '\n';
const fix = (x) => x.replace(/\r?\n/g, EOL);
const R = [];
function rep(name, a, b) {
  a = fix(a); b = fix(b);
  const n = s.split(a).length - 1;
  if (n !== 1) { console.error('MISS/DUP ' + name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b); R.push(name);
}

rep('S01',
  '| LH-S01 | 事件详情弹层 | sheetEventDetail | event_detail_sheet.dart:14 `showEventDetailSheet`（查看/开始/结束/✎编辑/删除） |',
  '| LH-S01 | 事件详情弹层 ~~sheetEventDetail~~ | **V1.52 退役**：并入 LH-S03 统一弹层（点已有事件=与新增同一个弹层） | 原 `event_detail_sheet.dart` 已删除 |');
rep('S02',
  '| LH-S02 | 标记块详情弹层 | sheetBlockDetail | event_detail_sheet.dart:201 `showBlockDetailSheet`（取消标记） |',
  '| LH-S02 | 标记块详情弹层 ~~sheetBlockDetail~~ | **V1.52 退役**：「取消标记」独立层撤销，删除动作进 LH-S03 底部「删除」+ SnackBar 撤销 | 同上 |');
rep('S03',
  '| LH-S03 | 统一添加弹层 | sheetTimePick | time_pick_sheet.dart:19 `showTimePickSheet`（日期+时分滚轮+时长 chips+分类+备注·四视图共用） |',
  '| LH-S03 | **统一添加 / 编辑弹层**（V1.52） | sheetTimePick | `showTimePickSheet(context, ref, {day, startMin, block, event})`：日/时/**分（1 分一档 · CupertinoPicker looping）**三列滚轮 ×2 组（起止 · 结束含日轮支持跨天）· 一级分类**每行 6 个**+子分组自适应 · 备注 · 底部按形态=「继续添加+添加」/「删除+保存修改」· 计时中额外「■ 结束计时」· 已结束额外「✂ 对半拆分 / ⇧ 与上一个合并 / ⇩ 与下一个合并」（间隙>30 分置灰）· 破坏性操作 SnackBar 带撤销 · 标签与「管理 ›」并入一级分组标题行 |');

rep('C12',
  '## 三、LH-S 弹层类（sheet 家族）',
  [
    '### LH-C12 时间账本卡族 time stats cards（V1.52 新增）',
    '- 原型：`index.html` `p-timeStats`（`renderTimeStats` / `tsClock` / `tsHeat` / `tsStack`）；',
    '  代码：`time_stats_page.dart`（`/time-stats` · 时间页顶栏柱状图标 + 仪表盘分布卡双入口）',
    '- 组成：四档分段（日/周/月/年）+ `‹ 期间 ›` 翻页 · 渐变 hero（总时长/日均/覆盖率/段数/计时中/未记录）·',
    '  时钟盘面（24h 极坐标扇区=每段块 · 红线=当前时刻）· 单日/单月时长对比面积图 · 满高底轨堆叠柱 ·',
    '  热力图（按日深浅 · 少→多图例）· 总时长环形（含「未记录」灰弧 · 分母=天数×1440）· 分类排行（次数/占比/进度条/环比）',
    '- 规格：每卡标题行右侧 ∧/∨ 可折叠（`_fold` 内存态）· 全部 CustomPainter 自绘零图表依赖 · 聚合一律走 `block_ops`（`minutesByCat`/`totalMinutes`/`deltaPct`）',
    '',
    '## 三、LH-S 弹层类（sheet 家族）',
  ].join('\n'));

fs.writeFileSync(P, s);
console.log('OK ' + R.join(', '));
