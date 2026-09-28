// 治理G7d⑤ 一次性脚本：ai_page.dart 按类群整块外提为 part 文件（G7d② 路线，无 extension/mixin）
// 用法：node tools/g7d5_ai_split.js --groups usage,verify,prompts,widgets,form,card   （加 --dry 只看统计）
// 护栏：锚点唯一命中 + 块尾形态 + 成员「恰好出现一次」双向断言 + 体积校验 + 改前快照 .bak。
// 注：settings 群刻意留主文件（主类留主页约定）；16-17 行库级悬空注释随该群首块迁移，主文件头注释由后续 Edit 补写。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/settings/presentation';
const SRC = path.join(DIR, 'ai_page.dart');
const DRY = process.argv.includes('--dry');
const gIdx = process.argv.indexOf('--groups');
const wanted = (gIdx >= 0 ? process.argv[gIdx + 1] : '').split(',').filter(Boolean);
if (!wanted.length) {
  console.error('USAGE: --groups usage,verify,prompts,widgets,form,card');
  process.exit(1);
}

const lines = fs.readFileSync(SRC, 'utf8').replace(/\r\n/g, '\n').split('\n');
const origLen = lines.length;
const lastIdx = (() => {
  for (let i = lines.length - 1; i >= 0; i--) if (lines[i].trim() !== '') return i;
  return -1;
})();

function findOnce(pred, label) {
  const hits = [];
  for (let i = 0; i < lines.length; i++) if (pred(lines[i], i)) hits.push(i);
  if (hits.length !== 1) {
    console.error(`ANCHOR-FAIL [${label}] hits=${hits.length} -> ${hits.join(',')}`);
    process.exit(1);
  }
  return hits[0];
}
const decl = (t) => (l) => l === t;

// end 锚=下一组首个 class 声明行（0 列）；块尾向前吞掉空行与悬空注释（注释随其下类迁移）。
const ALL = {
  usage: {
    out: 'ai_page_usage.dart',
    start: decl('class _AiUsageEntryCard extends ConsumerStatefulWidget {'),
    end: decl('class AiVerifyPage extends ConsumerStatefulWidget {'),
    header: [
      "part of 'ai_page.dart';",
      '',
      '// 治理G7d⑤：AI 使用记录卡群自 ai_page 整块外提（行为零改动）。',
      '// _AiUsageEntryCard(State) 按模块分组行 + _TokenUsageCard(State) 三日/七日/三十日 token 台账。',
    ],
    members: [
      'class _AiUsageEntryCard extends ConsumerStatefulWidget {',
      'class _AiUsageEntryCardState extends ConsumerState<_AiUsageEntryCard> {',
      'class _TokenUsageCard extends ConsumerStatefulWidget {',
      'class _TokenUsageCardState extends ConsumerState<_TokenUsageCard> {',
    ],
  },
  verify: {
    out: 'ai_page_verify.dart',
    start: decl('class AiVerifyPage extends ConsumerStatefulWidget {'),
    end: decl('class AiPromptsPage extends ConsumerWidget {'),
    header: [
      "part of 'ai_page.dart';",
      '',
      '// 治理G7d⑤：连通性验证页自 ai_page 整块外提（行为零改动）。',
      '// AiVerifyPage(State)：三态＝通过/凭据错误/网络失败；tool.verify 不受能力矩阵门控（R8 豁免）。',
    ],
    members: [
      'class AiVerifyPage extends ConsumerStatefulWidget {',
      'class _AiVerifyPageState extends ConsumerState<AiVerifyPage> {',
    ],
  },
  prompts: {
    out: 'ai_page_prompts.dart',
    start: decl('class AiPromptsPage extends ConsumerWidget {'),
    end: decl('class _ProviderRow extends StatelessWidget {'),
    header: [
      "part of 'ai_page.dart';",
      '',
      '// 治理G7d⑤：提示词管理两页自 ai_page 整块外提（行为零改动）。',
      '// AiPromptsPage 按模块分组列表 + AiPromptEditPage(State) 八字段编辑与覆盖保存。',
    ],
    members: [
      'class AiPromptsPage extends ConsumerWidget {',
      'class AiPromptEditPage extends ConsumerStatefulWidget {',
      'class _AiPromptEditPageState extends ConsumerState<AiPromptEditPage> {',
    ],
  },
  widgets: {
    out: 'ai_page_widgets.dart',
    // 两段：_ProviderRow.._MiniBtn 段 + 文件尾 _Card.._fmtTime 段（start/end 给第一段的 class 行，
    // 第二段由脚本按 decl 单独定位后并入同一 part，保持逐行连续全等取证按成员块进行）。
    start: decl('class _ProviderRow extends StatelessWidget {'),
    end: decl('class _AiProviderFormSheet extends ConsumerStatefulWidget {'),
    tail: { start: decl('class _Card extends StatelessWidget {'), end: null },
    header: [
      "part of 'ai_page.dart';",
      '',
      '// 治理G7d⑤：AI 页公共小件群自 ai_page 整块外提（行为零改动）。',
      '// _ProviderRow 服务商行 + _MiniBtn 行内小按钮 + _Card 圆角壳 + _fmtTime 时间格式化。',
    ],
    members: [
      'class _ProviderRow extends StatelessWidget {',
      'class _MiniBtn extends StatelessWidget {',
      'class _Card extends StatelessWidget {',
      'String _fmtTime(int ms) {',
    ],
  },
  form: {
    out: 'ai_page_form.dart',
    start: decl('class _AiProviderFormSheet extends ConsumerStatefulWidget {'),
    end: decl('class _Card extends StatelessWidget {'),
    header: [
      "part of 'ai_page.dart';",
      '',
      '// 治理G7d⑤：服务商添加/编辑弹层自 ai_page 整块外提（行为零改动）。',
      '// _AiProviderFormSheet(State)：端点/模型/协议/Key 校验，弹层内红字反馈（页面 SnackBar 被模态遮挡＝既定坑）。',
    ],
    members: [
      'class _AiProviderFormSheet extends ConsumerStatefulWidget {',
      'class _AiProviderFormSheetState extends ConsumerState<_AiProviderFormSheet> {',
    ],
  },
  card: {
    out: 'ai_page_card.dart',
    start: decl('class _Card extends StatelessWidget {'),
    end: null, // 文件尾（含 _fmtTime）——与 widgets.tail 互斥，二者只选其一执行；默认走 widgets 收纳，本组保留兼容。
    header: [
      "part of 'ai_page.dart';",
      '',
      '// 治理G7d⑤：文件尾小件（未启用组，_Card/_fmtTime 归 ai_page_widgets）。',
    ],
    members: ['class _Card extends StatelessWidget {', 'String _fmtTime(int ms) {'],
  },
};

const groups = wanted.map((k) => ({ key: k, ...ALL[k] }));
for (const g of groups) {
  if (!g.out) {
    console.error('UNKNOWN-GROUP ' + g.key);
    process.exit(1);
  }
}

// 跨度计算：end 锚向前吞空行与悬空注释（注释随其后类迁移）；起始行再向上吸附紧邻的 /// 文档注释组。
// 主文件顶部 import 后那两行库级悬空注释刻意不吸（留给主文件改写成库文档）。
const spansOf = (g) => {
  const raw = [{ s: g.s, e: g.e0 }];
  if (g.tail) raw.push({ s: g.tailS, e: g.tailE0 });
  return raw.map((sp) => {
    let s = sp.s;
    while (s - 1 > 0 && lines[s - 1].trim().startsWith('///')) s--;
    return { s, e: sp.e };
  });
};
for (const g of groups) {
  g.s = findOnce(g.start, `${g.key}.start`);
  if (g.end === null) {
    g.e0 = lastIdx + 1;
  } else {
    const e = findOnce(g.end, `${g.key}.end`);
    let t = e;
    while (t > g.s && lines[t - 1].trim() === '') t--;
    while (t > g.s && lines[t - 1].trim().startsWith('//')) t--;
    g.e0 = t;
  }
  if (g.tail) {
    const ts = findOnce(g.tail.start, `${g.key}.tail.start`);
    const te = g.tail.end === null ? lastIdx + 1 : findOnce(g.tail.end, `${g.key}.tail.end`);
    let t = te;
    while (t > ts && lines[t - 1].trim() === '') t--;
    while (t > ts && lines[t - 1].trim().startsWith('//')) t--;
    g.tailS = ts;
    g.tailE0 = t;
  }
}

function block(start, endExclusive) {
  const b = lines.slice(start, endExclusive);
  while (b.length && b[b.length - 1].trim() === '') b.pop();
  if (!b.length || !/[};]$/.test(b[b.length - 1].trim())) {
    console.error('END-FAIL', JSON.stringify(b[b.length - 1]));
    process.exit(1);
  }
  return b;
}

// 两段式：先按原始下标收集全部跨度与块体，再对 keep 单次归并删除——
// 否则前序组的删除会让后序组（如 widgets.tail）的原始下标错位，把已删段重新放回。
const allSpans = [];
for (const g of groups) {
  const spans = spansOf(g);
  g.bodies = spans.map((sp) => block(sp.s, sp.e));
  g.total = g.bodies.reduce((n, b) => n + b.length, 0);
  allSpans.push(...spans);
}
allSpans.sort((a, b) => a.s - b.s);
for (let i = 1; i < allSpans.length; i++) {
  if (allSpans[i].s < allSpans[i - 1].e) {
    console.error('SPAN-OVERLAP', JSON.stringify(allSpans[i - 1]), JSON.stringify(allSpans[i]));
    process.exit(1);
  }
}
const keep = [];
let cur = 0;
for (const { s, e } of allSpans) {
  keep.push(...lines.slice(cur, s));
  cur = e;
}
keep.push(...lines.slice(cur));

// 成员守恒双向断言：每个成员声明在「某 part 全文」恰好 1 次 且 在「余下主文件」0 次。
const mainRemain = keep.join('\n');
for (const g of groups) {
  const partText = g.bodies.flat().join('\n');
  for (const m of g.members) {
    const inPart = partText.split('\n').filter((l) => l === m).length;
    const inMain = mainRemain.split('\n').filter((l) => l === m).length;
    if (inPart !== 1 || inMain !== 0) {
      console.error(`MEMBER-FAIL [${g.key}] ${m} part=${inPart} main=${inMain}`);
      process.exit(1);
    }
  }
}

const movedTotal = groups.reduce((n, g) => n + g.total, 0);
console.log(`groups=${groups.map((g) => `${g.key}:${g.total}`).join(' ')} moved=${movedTotal} main=${keep.length} (orig=${origLen})`);
// 体积校验：主文件余量 + 外提量 ≈ 原量（容差=每组至多 2 行的吞尾 + 空行）
if (Math.abs(keep.length + movedTotal - origLen) > groups.length * 4 + 10) {
  console.error('SIZE-FAIL');
  process.exit(1);
}

if (DRY) {
  for (const g of groups) console.log(`DRY ${g.key} -> ${g.out} (${g.total} lines)`);
  process.exit(0);
}

fs.writeFileSync(SRC + '.bak', lines.join('\n'), 'utf8');
for (const g of groups) {
  const outPath = path.join(DIR, g.out);
  if (fs.existsSync(outPath)) {
    console.error('EXISTS-FAIL ' + outPath);
    process.exit(1);
  }
  fs.writeFileSync(outPath, [...g.header, '', ...g.bodies.flat()].join('\n') + '\n', 'utf8');
}
// part 指令必须位于任何声明之前（directive_after_declaration）→ 插到最后一条 import 之后。
const withParts = keep.slice();
while (withParts.length && withParts[withParts.length - 1].trim() === '') withParts.pop();
const lastImport = (() => {
  for (let i = 0; i < withParts.length; i++) {
    if (/^import /.test(withParts[i])) {
      if (i + 1 >= withParts.length || !/^import /.test(withParts[i + 1])) return i;
    }
  }
  return -1;
})();
if (lastImport < 0) {
  console.error('NO-IMPORT-ANCHOR');
  process.exit(1);
}
withParts.splice(lastImport + 1, 0, '', ...groups.map((g) => `part '${g.out}';`));
fs.writeFileSync(SRC, withParts.join('\n') + (lines.join('\n').endsWith('\n') ? '\n' : ''), 'utf8');
// part 数断言
const pc = withParts.filter((l) => /^part '/.test(l)).length;
if (pc !== groups.length) {
  console.error(`PART-COUNT-FAIL ${pc} != ${groups.length}`);
  process.exit(1);
}
console.log(`OK wrote ${groups.length} parts + main(${withParts.length} lines)`);
