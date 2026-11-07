/* 修编号：本单已有 §五/§六（2026-09-27 两批），本会话新增的两节改为 §七/§八，并同步引用
 * 用法：node tools/kits/doc_fixnum.js */
const fs = require('fs'), path = require('path');
for (const F of ['docs/变更单-小工具专版共享面-20260927.md', 'docs/需求清单.md']) {
  const raw = fs.readFileSync(path.resolve(F), 'utf8');
  const nl = raw.includes('\r\n') ? '\r\n' : '\n';
  let n = 0;
  const L = raw.split(/\r\n|\n/).map(l => {
    let m = l;
    m = m.replace(/^## 五、V1\.47 逐屏走查与修复/, '## 七、V1.47 逐屏走查与修复');
    m = m.replace(/^## 六、验收轮2 改刀/, '## 八、验收轮2 改刀');
    m = m.split('变更单 §五').join('变更单 §七').split('变更单》§五').join('变更单》§七');
    m = m.split('见 §六）').join('见 §八）');
    if (m !== l) n++;
    return m;
  });
  fs.writeFileSync(path.resolve(F), L.join(nl));
  console.log(F + ' 改 ' + n + ' 行');
}
const chk = fs.readFileSync(path.resolve('docs/变更单-小工具专版共享面-20260927.md'), 'utf8').split(/\r\n|\n/).filter(l => /^## /.test(l));
console.log(chk.join('\n'));
