// 一次性补丁：真机走查四条修正（已执行过勿重跑，命中数会报错）。
// ① 展开段不再预留 12 行高度 ② 统计文案压短（被三个动作钮挤到截断）
// ③ 入口卡去掉多余的 p 后缀 ④ 底部与空态不写教学文案
// 说明：Dart 的 ${} 一律用字符串拼接出来，避免被 JS 模板串当插值求值。
const fs = require('fs');
const D = '$' + '{'; // Dart 插值开头

function patch(p, pairs) {
  let s = fs.readFileSync(p, 'utf8');
  for (const [a, b, n] of pairs) {
    const c = s.split(a).length - 1;
    if (c !== n) throw new Error(p + ' 命中 ' + c + ' != ' + n + ' :: ' + a.slice(0, 56));
    s = s.split(a).join(b);
  }
  fs.writeFileSync(p, s, 'utf8');
  console.log('OK', p);
}

const sumOld =
  "                          '筛选 " + D + "_sum.n} 条 · 入 " + D + "_sum.inTok}/出 " + D + "_sum.outTok} tokens'\n" +
  "                          ' · 未成功 " + D + "_sum.bad} · 今日 " + D + "_today.n} 次',";
const sumNew =
  "                          '" + D + "_sum.n} 条 · 入" + D + "_sum.inTok}/出" + D + "_sum.outTok}'\n" +
  "                          ' · 未成 " + D + "_sum.bad} · 今日 " + D + "_today.n} 次',";

const hintOld =
  "                        ? '还没有 AI 调用记录 · 各模块用一次 AI 就会在这里留一行'\n" +
  "                        : '共 $_total 条 · 近 7 天 $_week 次 · 点一行展开输入与输出全文',";
const hintNew =
  "                        ? '还没有 AI 调用记录'\n" +
  "                        : '共 $_total 条 · 近 7 天 $_week 次',";

patch('lib/features/settings/presentation/ai_usage_page.dart', [
  ['                color: danger ? const Color(0xFFF43F5E) : null),\n                maxLines: 12),',
   '                color: danger ? const Color(0xFFF43F5E) : null),', 1],
  [sumOld, sumNew, 1],
  [hintOld, hintNew, 1],
  ["        child: Text('该范围暂无 AI 调用记录\\n换时间范围或清掉关键词再看',",
   "        child: Text('该范围暂无 AI 调用记录',", 1],
]);

patch('lib/features/settings/presentation/ai_page.dart', [
  ["_cell('今日 tokens', '" + D + "_todayTok}p', 'ai-usage-k2')",
   "_cell('今日 tokens', '" + D + "_todayTok}', 'ai-usage-k2')", 1],
]);
