/* 批0-1：农历引擎提升到 shared/calendar 后改四处 import（days 三处 + 回归测试一处）
 * 护栏：每处命中数必须为 1，任一处不符则整体零写入 */
const fs = require('fs');
const EDITS = [
  ['lib/features/days/data/days_repository.dart', "import '../domain/lunar.dart';", "import '../../../shared/calendar/lunar.dart';"],
  ['lib/features/days/domain/day_calc.dart', "import 'lunar.dart';", "import '../../../shared/calendar/lunar.dart';"],
  ['lib/features/days/presentation/day_edit_page.dart', "import '../domain/lunar.dart';", "import '../../../shared/calendar/lunar.dart';"],
  ['test/days_lunar_test.dart', "import 'package:lifeharness/features/days/domain/lunar.dart';", "import 'package:lifeharness/shared/calendar/lunar.dart';"],
];
const plans = [];
for (const [f, old, neu] of EDITS) {
  const raw = fs.readFileSync(f, 'utf8');
  const hits = raw.split(old).length - 1;
  if (hits !== 1) { console.error(`!! ${f} 命中 ${hits}（期望 1）：${old}`); process.exit(1); }
  plans.push([f, raw.replace(old, neu)]);
}
for (const [f, out] of plans) { fs.writeFileSync(f, out); console.log('PASS ' + f); }
