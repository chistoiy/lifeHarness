/* 健康管理专版补丁：把 tools/ht_* 片段接入 prototype/index-health.html（index.html 零改动） */
const fs = require('fs');
const ROOT = 'D:/dev_workplace/flutter_te/lifeHarness';
const P = ROOT + '/prototype/index-health.html';
const rd = f => fs.readFileSync(ROOT + '/tools/' + f, 'utf8');
let h = fs.readFileSync(P, 'utf8');
const must = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exit(1) } };
const cnt = (s, sub) => s.split(sub).length - 1;
const splice = (a, b, content, tag) => {
  must(cnt(h, a) === 1 && cnt(h, b) === 1, tag + ' markers (' + cnt(h, a) + '/' + cnt(h, b) + ')');
  const i0 = h.indexOf(a), i1 = h.indexOf(b);
  must(i1 > i0, tag + ' order');
  h = h.slice(0, i0) + content.replace(/\s+$/, '') + '\n' + h.slice(i1);
};

/* 1) 健康屏整段替换（P9 健康 → P10 目标 OKR 之间） */
splice('    <!-- ===== P9 健康 ===== -->', '    <!-- ===== P10 目标 OKR ===== -->',
  rd('ht_frag_p1.html') + rd('ht_pages_b.html') + rd('ht_pages_c.html'), 'pages');

/* 2) 弹层组插到「插件详情弹层」之前 */
const sheetAnchor = '  <!-- ===== 插件详情弹层 ===== -->';
must(cnt(h, sheetAnchor) === 1, 'sheet anchor');
h = h.replace(sheetAnchor, rd('ht_sheets.html').replace(/\s+$/, '') + '\n\n' + sheetAnchor);

/* 3) CSS：就地内嵌滚轮 */
const cssAnchor = '  .inp{border:1px solid #e2e8f0;border-radius:12px;padding:10px 12px;background:#fff;outline:none;font-size:13px;width:100%}';
must(cnt(h, cssAnchor) === 1, 'css anchor');
h = h.replace(cssAnchor, cssAnchor + rd('ht_css.html').replace(/\s+$/, ''));

/* 4) JS：替换旧健康数据段（保留其上的 renderDays 与其下的 renderOkr） */
splice('let waterN=5;', 'function renderOkr(){', rd('ht_js_1.js') + rd('ht_js_2.js'), 'js');

/* 5) TITLES：健康各屏标题 */
const tOld = "'p-health':['健康','喝水 · 睡眠'],";
must(cnt(h, tOld) === 1, 'titles anchor');
h = h.replace(tOld, "'p-health':['健康','喝水 · 睡眠 · 运动 · 用药 · 身体数据'],'p-body':['身体数据','体重 · 体脂 · 围度 · BMI 分级'],'p-exLog':['运动记录','V1.x 排期 · 三模互算 · 计时 · 配速趋势'],'p-med':['用药管理','V1.x 排期 · 档案 · 打卡 · 按时刻提醒'],'p-sleepLog':['睡眠记录','起止 · 质量 · 分期选填'],'p-trends':['健康趋势','热力 · 曲线 · 环比同比 · 周报'],'p-goalsH':['健康目标','喝水 · 睡眠 · 运动 · 体重 · 围度'],'p-hSet':['健康设置','单位 · 提醒 · 备份与导出'],");

/* 6) 启动接线：renderHealth 之后调用 hBoot() */
const iOld = 'renderDays(); renderHealth(); renderOkr();';
must(cnt(h, iOld) === 1, 'init anchor');
h = h.replace(iOld, 'renderDays(); renderHealth(); renderOkr(); hBoot();');

/* 7) 原型标识：浏览器标签 + 桌面侧栏标题 */
const ttlOld = '<title>LifeHarness · 高保真UI原型 V1.3</title>';
must(cnt(h, ttlOld) === 1, 'doc title');
h = h.replace(ttlOld, '<title>LifeHarness · 高保真UI原型 · 健康管理专版 V1.0</title>');
const sideOld = '<div class="text-lg font-bold text-slate-200">LifeHarness 交互原型</div>';
must(cnt(h, sideOld) === 1, 'side title');
h = h.replace(sideOld, '<div class="text-lg font-bold text-slate-200">LifeHarness 交互原型 · 健康管理专版</div>');

fs.writeFileSync(P, h);
console.log('OK htpatch applied. lines =', h.split('\n').length);
