/* 批2 修② · BS_SET.brSelOps 默认名单补 X-Ray（对齐真机 kBrSelDefaultTools 顺序）
 * 根因：默认八项非空 → BR_SEL_ALL 回退不触发 → push 无效，默认打开无 X-Ray chip。
 * V1.54 批B 存量缺口（默认串来自 V1.53.4⑤ 36ad871），非批2 引入。 */
const fs = require('fs'), path = require('path');
const F = path.resolve('prototype/index-bookshelf.html');
fs.copyFileSync(F, path.resolve('tools/attic/index-bookshelf.bak-20261002-xrwords-fix2.html'));
let src = fs.readFileSync(F, 'utf8');
const anchor = "brSelOps:['复制','划线','写想法','书摘','查询','听当前','AI 解读','分享']};";
const rep2 = "brSelOps:['复制','划线','写想法','书摘','查询','X-Ray','听当前','AI 解读','分享']};";
const n = src.split(anchor).length - 1;
if (n !== 1) { console.error('锚点非唯一(' + n + ')'); process.exit(1); }
src = src.replace(anchor, rep2);
fs.writeFileSync(F, src);
console.log('OK brSelOps 默认名单补 X-Ray');
