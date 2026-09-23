const fs = require('fs');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
rep('autorow', `          <button class="ml-auto bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="hbBackfillOpen()">补卡</button>
        </div>
      </div>`,
`          <button class="ml-auto bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="hbBackfillOpen()">补卡</button>
        </div>
        <div class="mt-2 flex items-center gap-1.5 text-[10.5px] flex-wrap" id="hbAutoRow"></div>
      </div>`);
rep('link', `onclick="navTo('p-habitStat')">查看周月统计</button>`, `onclick="navTo('p-habitStat');renderHabitStat()">查看周 / 月 / 年统计</button>`);
rep('hdr', `hbHdrBtn('chart','周月统计',`, `hbHdrBtn('chart','周 / 月 / 年统计',`);
if (fails) { console.log('FAILS', fails); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('OK');
