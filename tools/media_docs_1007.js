/* media_docs_1007.js · 影音游解禁批1 的文档收口（STATUS·INDEX·变更日志·健康工单 §3 改口）
 * 用法：node tools/media_docs_1007.js
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const P = f => path.join(ROOT, f);
const done = [];
function rep(file, from, to, expect) {
  const f = P(file);
  const s = fs.readFileSync(f, 'utf8');
  const n = s.split(from).length - 1;
  if (n !== (expect === undefined ? 1 : expect)) throw new Error(file + ' 锚点命中 ' + n + '——中止');
  fs.writeFileSync(f, s.replace(from, to), 'utf8');
  done.push(path.basename(file));
}

rep('docs/STATUS.md',
  '# STATUS（唯一状态源 · 最后更新 2026-10-07 **本批＝插件中心整簇下架（产品拍板「删屏」）＋健康模块批0/1 数据层',
  '# STATUS（唯一状态源 · 最后更新 2026-10-07 **本批＝影音游解禁＋批1 数据层（DB v37→v38 media_* 七表·'
  + '八源外部 id 部分唯一索引·6 例常驻绿·工单 `docs/handoff/交棒话术-20261007-影音游解禁与批1数据层.md`）；'
  + '**下一站＝影音游批2＝先清 `index-media.html` 的 22 枚越权副本再从 frozen 出表，然后才上影音架 UI**；'
  + '同场并行余量＝健康批2（喝水＋睡眠＋工作台骨架）；前批＝插件中心整簇下架（产品拍板「删屏」）＋健康模块批0/1 数据层');

rep('docs/STATUS.md',
  '· DB `DbSchema.version=37`（**健康模块批0/1**',
  '· DB `DbSchema.version=38`（**影音游解禁批1**：`migrations[37]` 建 `media_*` 七表，新模块零搬数据；'
  + 'v37＝**健康模块批0/1**');

rep('docs/INDEX.md',
  '| docs/handoff/交棒话术-20261007-健康批2起与影音游解禁.md |',
  '| docs/handoff/交棒话术-20261007-影音游解禁与批1数据层.md | **影音游解禁落地账＋批2 规格**（活）：'
  + '解禁三件已改口（AGENTS·需求清单模块 10·注册表 media=current/rep=m-shelf/dev 仍 notStarted）；'
  + '批1 数据层已交付＝`media_*` 七表·DB 37→38·八源外部 id 部分唯一索引·常驻 6 例；'
  + '**批2 第一刀＝清 `index-media.html` 22 枚越权副本再从 frozen 出表**（解冻实测暴露的治理债，本批未做）；'
  + '专版里的插件中心副本已一并摘净 ｜\n'
  + '| docs/handoff/交棒话术-20261007-健康批2起与影音游解禁.md |');

rep('docs/handoff/交棒话术-20261007-健康批2起与影音游解禁.md',
  '- 影音游：**本轮未开工**（上下文预算）。解禁口径见 §3，开工前必须先过 §3 的三件文档落档。',
  '- 影音游：**2026-10-07 同日已解禁并开工批1**（数据层），账目与批2 规格另立新单 '
  + '`docs/handoff/交棒话术-20261007-影音游解禁与批1数据层.md`；本工单只管健康线，§3 三件已落。');

const L = P('docs/交接文档.md');
let ls = fs.readFileSync(L, 'utf8').split('\n');
const i = ls.findIndex(l => l.startsWith('- 2026-10-07 13:4x'));
if (i < 0) throw new Error('变更日志锚点找不到——中止');
if (!ls.some(l => l.startsWith('- 2026-10-07 14:0x'))) {
  ls.splice(i + 1, 0,
    '- 2026-10-07 14:0x 影音游解禁＋批1 数据层（产品令「影音游解禁可以开发」）＝解禁三件落档'
    + '（AGENTS 移出「已下架勿复活」·需求清单模块 10 标回现行·注册表 media=deferred→current 且 rep=m-shelf，'
    + 'dev 仍 notStarted 等批2 翻）；`lib/core/database/schema/media.dart` 七表（条目 TEXT 主键/会话与 book_sessions 同构带 txn_id/'
    + '笔记/子项/字典/影音单/成员），**三级去重第一级上成八个外部源的部分唯一索引**（空值不参与·同 IMDb 号第二条直接撞库），'
    + '字典 source 预置 14 家幂等；DB v37→v38（`migrations[37]`，无跳号）。'
    + '专版 `index-media.html` 里插件中心两份副本一并摘净（净减 14,185 字符·注册表两条作废）。'
    + '**一笔债登记给批2**：该原型解冻后被 protogate 判出 22 枚越权副本（冻结期间从未清理），'
    + '本批选择重新放回 frozen 并立刀，不混进功能批——批2 第一刀＝清副本→出表→strict 全绿。'
    + '门禁＝`test/media_schema_test.dart` 6 例常驻＋database/health_schema/守护三件套同轮 32 绿·analyze 零新增·'
    + 'protogate strict 全绿·registry CLEAN·doclint strict 全绿。未推送。');
  fs.writeFileSync(L, ls.join('\n'), 'utf8');
  done.push('变更日志');
}
console.log('DONE ' + done.join(' / '));
