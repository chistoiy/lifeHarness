/* aiverify_reg.js · 批①：把新屏 p-sub-aiVerify 登记进 prototype/_modules.json（protogate 闸1 要求）
 * 用法：node tools/aiverify_reg.js        # 插入条目（size/hash 留空占位，随后由 proto_registry.js --write 按实测回写）
 */
const fs = require('fs'), path = require('path');
const REG = path.resolve(__dirname, '..', 'prototype', '_modules.json');
const txt = fs.readFileSync(REG, 'utf8');
if (txt.includes('"p-sub-aiVerify"')) { console.log('ALREADY REGISTERED'); process.exit(0); }
const anchor = '  {\n   "id": "p-sub-appearance",\n';
const n = txt.split(anchor).length - 1;
if (n !== 1) throw new Error('锚点命中 ' + n + ' 处（期望 1）——中止');
const entry = '  {\n'
  + '   "id": "p-sub-aiVerify",\n'
  + '   "kind": "screen",\n'
  + '   "title": "AI API 验证",\n'
  + '   "home": "index.html",\n'
  + '   "reps": [],\n'
  + '   "status": "exclusive",\n'
  + '   "files": {\n'
  + '    "index.html": {\n'
  + '     "size": 0,\n'
  + '     "hash": ""\n'
  + '    }\n'
  + '   }\n'
  + '  },\n';
const out = txt.replace(anchor, entry + anchor);
JSON.parse(out);
if (out.length - txt.length < 100 || out.length - txt.length > 600) throw new Error('体积变化异常：' + (out.length - txt.length));
fs.writeFileSync(REG, out, 'utf8');
console.log('REGISTERED +' + (out.length - txt.length) + ' bytes');
