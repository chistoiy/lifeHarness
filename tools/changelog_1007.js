/* changelog_1007.js · 交接文档 §5 变更日志追加两条（2026-10-07 健康批0/1＋真机反馈五条）
 * 用法：node tools/changelog_1007.js
 */
const fs = require('fs'), path = require('path');
const F = path.resolve(__dirname, '..', 'docs', '交接文档.md');
const lines = fs.readFileSync(F, 'utf8').split('\n');
const i = lines.findIndex(l => l.startsWith('- 2026-10-07 12:0x'));
if (i < 0) throw new Error('找不到 12:0x 那条日志锚点——中止');
if (lines.some(l => l.startsWith('- 2026-10-07 12:3') || l.startsWith('- 2026-10-07 13:'))) {
  console.log('ALREADY APPENDED'); process.exit(0);
}
const add = [
  '- 2026-10-07 12:3x 健康模块批0/1 数据层已交付（产品令「健康模块可以开发上线了」）＝提交 `840f3f5`：'
  + 'DB v36→v37 建 `health_*` 十四表＋「本人」档案种子、§五 十一条口径纯函数、档案隔离仓储、§六 15 设置键、providers；'
  + '**UI 一行未动**（`/health` 路由还没接，主页宫格「健康」仍灰位）。门禁＝常驻三文件 40 绿＋守护三件套绿＋变异三刀各红其位（`tools/health_mut.js`）。'
  + '下一批＝批2（喝水＋睡眠＋工作台骨架），规格与执行面板＝`docs/handoff/交棒话术-20261007-健康批2起与影音游解禁.md`；'
  + '同档 §3 记影音游解禁前置三件（本轮未开工）。深色工单随批2 降级「路过清」归档。',
  '- 2026-10-07 13:0x 真机反馈五条已交付（看图三条＋口头两条·提交 `dda745c`）＝AI 增强页服务商**收成一行**（点开出「选择服务商」半屏，'
  + '不引 DropdownButton＝撞 U5 禁词闸与「勿循环切」条）＋**Key 配置整卡摘除**（与列表重复；验证状态与「重新验证/测试新 Key」钮留在服务商卡）；'
  + '日记天气从「我的」挪进「记录管理·日记」段；图片存储清理补**全选↔取消全选**；'
  + '「外观/记录管理与上方条目缩进不一致」判定＝**实现漂移**（原型本就同基准），新增 `_EntryCard` 归位、同 U11 判例不过门。'
  + '闸＝新 `tools/ux162check.js` 8/8＋`tools/ux162_mut.js` 三刀各红其位；回归 aiprovcheck 12/12（两条按新形态翻面）·'
  + 'aiverifycheck 15/15·protogate strict·registry 312 条全复现；U5 棘轮 dashboard V1x 2→1 收紧。批内 7 文件全绿·DB 零迁移·未推送。',
];
lines.splice(i + 1, 0, ...add);
fs.writeFileSync(F, lines.join('\n'), 'utf8');
console.log('APPENDED 2 条 @ line ' + (i + 2));
