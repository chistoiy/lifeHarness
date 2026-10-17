// R15-1 立案为需求 V1.56 的交接文档登记行（命中断言 + 体积打印）
'use strict';
const fs = require('fs');
const path = require('path');
const F = path.resolve(__dirname, '..', 'docs/交接文档.md');
const s = fs.readFileSync(F, 'utf8');
const crlf = s.includes('\r\n');
const nl = (t) => (crlf ? t.replace(/\n/g, '\r\n') : t);

const ROW =
  '| 2026-09-29 | **真机复验挖出的 R15-1 立案为需求 V1.56：记账导入「整批撤销」补口（原型先行·未进开发）** ' +
  '完成页与 toast 三处承诺「支持整批撤销」（`ledger_import_page.dart:264/778/996`），但 `undoImportBatch` 在 `lib/**` **零调用方**，' +
  '原型也只有这句话没有这个钮（`index.html:3880`·`index-ledger.html:3863`）＝功能缺口 + 文案误导。' +
  '**现状查清**：数据层已完备——批次表 `ledger_import_batches`、`txns.imp_batch` 与 `idx_ltx_batch` 均在（**无需新迁移**，' +
  'V1.55 释放的 v29 预留也用不上），`commitImport` 返 `batchId`、`importBatches()` 可出列表、' +
  '`undoImportBatch(batchId,{reclaimAccounts})` 事务内含删流水→有条件回收本批新建账户→删批次行→重算余额；' + '**本单范围只剩 UI + 一条 key 行日志 + 用例**。' +
  '两步走：先补 `prototype/index-ledger.html`（专版定稿后回灌共享面走变更单）经逐屏确认，再落 Flutter ' +
  '（新 UI 走独立文件：`ledger_import_page.dart` 现 1151 行·距 1200 体积线仅剩 49 行；`ledger_repository.dart` 是棘轮登记文件只许减）。' +
  '四项待拍板已列（账户回收默认档 / 入口位置 / 可撤销范围含撤旧批回溯改写报表的口径 / 判定不做则必须摘掉三处假承诺文案）。' +
  '复验时写进真机的**批次 2**（5 笔流水 + 4 个账户）**故意不清理，留作该单的真机验收素材**——撤销它一步同时验功能与清数据。 | ' +
  'docs/交棒话术-20260929-R15-1整批撤销.md, docs/需求清单.md, docs/真机逐屏验收清单-20260929.md, docs/交接文档.md |\n';

if (s.includes(ROW.slice(0, 46))) {
  console.log('跳过：V1.56 立案行已存在');
  process.exit(0);
}
const last = s.replace(/[\r\n]+$/, '').split(/\r?\n/).pop();
if (!last.startsWith('| 2026-09-29 |')) {
  console.error('末行不是交付表行，中止：' + last.slice(0, 60));
  process.exit(1);
}
const cols = ROW.replace(/\n$/, '').split('|').length - 2;
const pipes = (ROW.match(/\|/g) || []).length;
if (cols !== 3 || pipes !== 4) {
  console.error(`本行列数不是 3（列 ${cols}·竖线 ${pipes}），中止`);
  process.exit(1);
}
const out = s.replace(/[\r\n]+$/, '') + nl('\n' + ROW, crlf) + nl('\n', crlf);
const bad = out.split(/\r?\n/).filter((l) => /^ +\|/.test(l));
if (bad.length) {
  console.error('插行产生缩进残行 ' + bad.length + ' 条，中止：' + bad[0].slice(0, 60));
  process.exit(1);
}
const before = fs.statSync(F).size;
fs.writeFileSync(F, out);
console.log(`已追加 交接文档.md V1.56 立案行 ${before} → ${Buffer.byteLength(out)}B`);
