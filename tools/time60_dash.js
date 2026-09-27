const fs = require('fs');
const P = 'lib/features/dashboard/presentation/dashboard_page.dart';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const EOL = s.includes('\r\n') ? '\r\n' : '\n';
const fix = (x) => x.replace(/\r?\n/g, EOL);

let a1 = `    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本周时间分布',`;
let b1 = `    return InkWell(
      // V1.52：点卡片直达时间账本（L4 全量统计）
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/time-stats'),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本周时间分布',`;
a1 = fix(a1); b1 = fix(b1);
if (s.split(a1).length - 1 !== 1) { console.log('a1 count', s.split(a1).length - 1); process.exit(1); }
s = s.replace(a1, b1);

let a2 = `                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}`;
let b2 = `                        ],
                      ),
              ),
            ],
          ),
          Text('合计 ${'$'}{_fmtMin(totalMin)} · 点开看时间账本',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
      ),
    );
  }

  static String _fmtMin(int m) {
    final d = m ~/ 1440, h = (m % 1440) ~/ 60, r = m % 60;
    if (m <= 0) return '0 分';
    return [
      if (d > 0) '\$d 天',
      if (h > 0) '\$h 时',
      if (r > 0 || (d == 0 && h == 0)) '\$r 分',
    ].join(' ');
  }
}`;
a2 = fix(a2); b2 = fix(b2);
if (s.split(a2).length - 1 !== 1) { console.log('a2 count', s.split(a2).length - 1); process.exit(1); }
s = s.replace(a2, b2);
fs.writeFileSync(P, s);
console.log('dashboard card wired to /time-stats |', size0, '->', s.length);
