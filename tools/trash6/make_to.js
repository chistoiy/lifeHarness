/* 由 *_from.txt 组合出 *_to.txt（前缀/后缀拼接，避免手抄原文出错）。 */
const fs = require('fs');
const RD = (p) => fs.readFileSync('tools/trash6/' + p, 'utf8');
const WR = (p, s) => { fs.writeFileSync('tools/trash6/' + p, s); console.log('OK  ' + p + '  ' + s.length + ' 字节'); };

/* 1) D.trash 种子数据（4 条 · 含一条临近自动清理的） */
const dFrom = RD('d_from.txt');
WR('d_to.txt', `  trash:[{t:'退掉不用的视频会员',tag:'',q:3,due:'—',del:'09-16 21:05'},
         {t:'整理上季度发票',tag:'财务',q:0,due:'已逾期 3 天',del:'09-11 09:40'},
         {t:'给旧手机贴膜的约定',tag:'家人',q:2,due:'本周',del:'09-02 20:11'},
         {t:'整理车库杂物柜',tag:'生活',q:2,due:'09-30',del:'08-22 08:30'}],
` + dFrom);

/* 2) TITLES 增子页标题 */
WR('titles_to.txt', RD('titles_from.txt') + `'p-sub-todoTrash':['垃圾箱','删除的待办 · 保留期内可恢复'],`);

/* 3) 记录管理·通用·回收站自动清理：补 id + 文案纳入待办 */
const recFrom = RD('rec_from.txt');
const recTo = recFrom
  .replace(`<button class="mini-btn" onclick="cycleRecSet(this,'trash'`,
    `<button id="recTrashOpt" class="mini-btn" onclick="cycleRecSet(this,'trash'`)
  .replace('日记 / 笔记 / 阅读 / 影音游 删除的内容', '待办 / 日记 / 笔记 / 阅读 / 影音游 删除的内容');
if (recTo === recFrom) { console.log('FAIL rec_to 未产生改动'); process.exit(1); }
WR('rec_to.txt', recTo);

/* 4) cycleRecSet 改档后通知垃圾箱 */
const csFrom = RD('cs_from.txt');
const csTo = csFrom.replace(`（模拟持久化）');}`, `（模拟持久化）');if(key==='trash')recSetChanged(key);}`);
if (csTo === csFrom) { console.log('FAIL cs_to 未产生改动'); process.exit(1); }
WR('cs_to.txt', csTo);

/* 5) renderTodos 收尾刷新入口行期限读数 */
WR('rt_to.txt', RD('rt_from.txt').replace(/\n\}$/, '\n  ttSyncKeep();\n}'));

/* 6) setPage 离开垃圾箱页时收起批量条 */
WR('sp_to.txt', RD('sp_from.txt') +
  `\n  if(p!=='p-sub-todoTrash'){const _ts=$('#ttSelBar');if(_ts){_ts.classList.add('hidden');_ts.classList.remove('flex');}}`);

/* 7) delTaskFromSheet → 整块换成垃圾箱模块 JS */
WR('del_to.txt', RD('js.js'));
