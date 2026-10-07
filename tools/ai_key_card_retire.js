/* ai_key_card_retire.js · V1.62 产品令：AI 增强页「Key 配置」整卡摘除（与服务商列表重复）
 * 用法：node tools/ai_key_card_retire.js
 * 做法＝按首尾锚点整段删除（锚点各命中 1 次才落盘），Key 录入仍在服务商表单与验证页里。
 */
const fs = require('fs'), path = require('path');
const F = path.resolve(__dirname, '..', 'lib/features/settings/presentation/ai_page.dart');
const src = fs.readFileSync(F, 'utf8');
const A = "          // —— Key 配置（原型：当前端点摘要 + 掩码 Key + 验证状态 + 重新验证钮）——";
const B = "          // —— 总开关 + 能力矩阵（原型 p-sub-ai 第三卡）——";
const nA = src.split(A).length - 1, nB = src.split(B).length - 1;
if (nA !== 1 || nB !== 1) throw new Error('锚点命中异常 A=' + nA + ' B=' + nB + '——中止');
const i = src.indexOf(A), j = src.indexOf(B);
if (j <= i) throw new Error('锚点顺序不对——中止');
const removed = j - i;
const out = src.slice(0, i) + src.slice(j);
if (removed < 2000 || removed > 6000) throw new Error('删除体积异常：' + removed + '——中止');
fs.writeFileSync(F, out, 'utf8');
console.log('REMOVED Key 配置卡 ' + removed + ' 字节 · 文件 ' + src.length + ' → ' + out.length);
