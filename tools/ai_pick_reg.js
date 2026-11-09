/* ai_pick_reg.js · 把新弹层 sheetAiPick 登记进 prototype/_modules.json（protogate 闸1）
 * 用法：node tools/ai_pick_reg.js
 */
const fs = require('fs'), path = require('path');
const REG = path.resolve(__dirname, '..', 'prototype', '_modules.json');
const txt = fs.readFileSync(REG, 'utf8');
if (txt.includes('"sheetAiPick"')) { console.log('ALREADY REGISTERED'); process.exit(0) }
const anchor = '  {\n   "id": "sheetAiProv",\n';
if (txt.split(anchor).length - 1 !== 1) throw new Error('锚点命中异常——中止');
const entry = '  {\n'
  + '   "id": "sheetAiPick",\n'
  + '   "kind": "sheet",\n'
  + '   "title": "选择服务商",\n'
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
fs.writeFileSync(REG, out, 'utf8');
console.log('REGISTERED sheetAiPick +' + (out.length - txt.length));
