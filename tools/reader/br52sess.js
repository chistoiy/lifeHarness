const fs = require('fs');
const f = 'lib/features/read/domain/book_session.dart';
let s = fs.readFileSync(f, 'utf8');
const subs = [
  [`    fromLoc: (r['from_loc'] as num?)?.toDouble(),
    toLoc: (r['to_loc'] as num?)?.toDouble(),`,
   `    fromLoc: (r['from_loc'] as num?)?.toDouble(),
    toLoc: (r['to_loc'] as num?)?.toDouble(),
    fromChapter: r['from_chapter'] as String?,
    toChapter: r['to_chapter'] as String?,
    fromPct: (r['from_pct'] as num?)?.toDouble(),
    toPct: (r['to_pct'] as num?)?.toDouble(),`],
  [`    'from_loc': fromLoc,
    'to_loc': toLoc,`,
   `    'from_loc': fromLoc,
    'to_loc': toLoc,
    'from_chapter': fromChapter,
    'to_chapter': toChapter,
    'from_pct': fromPct,
    'to_pct': toPct,`],
  [`    double? fromLoc,
    double? toLoc,
    String? source,`,
   `    double? fromLoc,
    double? toLoc,
    String? fromChapter,
    String? toChapter,
    double? fromPct,
    double? toPct,
    String? source,`],
  [`    fromLoc: fromLoc ?? this.fromLoc,
    toLoc: toLoc ?? this.toLoc,`,
   `    fromLoc: fromLoc ?? this.fromLoc,
    toLoc: toLoc ?? this.toLoc,
    fromChapter: fromChapter ?? this.fromChapter,
    toChapter: toChapter ?? this.toChapter,
    fromPct: fromPct ?? this.fromPct,
    toPct: toPct ?? this.toPct,`],
];
for (const [a, b] of subs) {
  if (!s.includes(a)) throw new Error('未命中：' + a.split('\n')[0]);
  s = s.replace(a, b);
}
if (!s.includes('toPct: toPct ?? this.toPct')) throw new Error('copyWith 未更新');
fs.writeFileSync(f, s, 'utf8');
console.log('ok ' + s.length);
