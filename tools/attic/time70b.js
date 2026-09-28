const fs = require('fs');
const B = String.fromCharCode(96);
const bad = 'stroke-linecap="round"/>' + B + ";";
const good = 'stroke-linecap="round"/>' + B + ":'';";
for (const f of ['prototype/index.html', 'tools/time70a.js']) {
  let s = fs.readFileSync(f, 'utf8');
  const esc = f.endsWith('.js') ? bad.replace(/"/g, '\\"') : bad;
  const escGood = f.endsWith('.js') ? good.replace(/"/g, '\\"') : good;
  const n = s.split(esc).length - 1;
  if (n !== 1) { console.log(f, 'count', n); continue; }
  fs.writeFileSync(f, s.split(esc).join(escGood));
  console.log(f, 'fixed');
}
