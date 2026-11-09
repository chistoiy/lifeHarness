/* entry_retire_proto.js · 批②③原型面：待办页回收站末卡下架＋主页「插件中心」瓦片下架
 * 用法：node tools/entry_retire_proto.js
 * 三条锚点全中才落盘；只减不增（体积校验＝净减 600~1600 字节）。
 */
const fs = require('fs'), path = require('path');
const HTML = path.resolve(__dirname, '..', 'prototype', 'index.html');
const SNAP = path.resolve(__dirname, '..', 'tmp', 'index-html.before-entryretire-20261007.html');
const src = fs.readFileSync(HTML, 'utf8');
fs.writeFileSync(SNAP, src, 'utf8');
let out = src;
const done = [];

function cut(name, from, to, expect) {
  expect = expect === undefined ? 1 : expect;
  const n = out.split(from).length - 1;
  if (n !== expect) throw new Error('锚点 ' + name + ' 命中 ' + n + ' 处（期望 ' + expect + '）——中止，不落盘');
  out = out.split(from).join(to);
  done.push(name);
}

/* 1 · 待办页末卡整块摘除（留一行下架记号，别让它日后被当成漏做） */
cut('待办回收站末卡',
  '      <!-- ===== V1.60 回收站入口（原 V1.57 待办垃圾箱升级·直达待办段·计数与全局同源） ===== -->\n'
  + '      <button class="mt-4 w-full card !py-3 flex items-center gap-3 text-left" onclick="ttOpen()">\n'
  + '        <span class="w-9 h-9 rounded-xl bg-slate-100 dark:bg-slate-800 text-slate-500 flex items-center justify-center shrink-0"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13M10 11v5m4-5v5"/></svg></span>\n'
  + '        <span class="flex-1 min-w-0"><b class="text-sm">回收站</b>\n'
  + '          <div class="text-[10px] text-slate-400" id="todoTrashMeta">待办 4 项 · 保留期内可恢复</div></span>\n'
  + '        <span class="text-slate-300">›</span></button>\n',
  '      <!-- 回收站入口已下架（2026-10-07 产品令）：待办页不挂末卡，统一走「我的」页与记录管理两处入口 -->\n');

/* 2 · ttOpen 随入口成为死函数（ttSyncKeep 的 if(m) 空守卫照旧，不需要动） */
cut('ttOpen 死函数',
  "function ttOpen(){gtOpen('todo')}   /* 待办页入口＝直达待办段（V1.57 兼容名） */\n", '');

/* 3 · 全部功能宫格摘掉插件中心一枚（p-pstore 屏与设置页占位行留着等产品定去留） */
cut('插件中心瓦片', "['🧩','插件中心','p-pstore'],", '');

const delta = out.length - src.length;
if (delta > -600 || delta < -2000) throw new Error('体积变化异常：' + delta + ' 字节（期望净减 600~2000）——中止');
fs.writeFileSync(HTML, out, 'utf8');
console.log('CUT ' + done.join(' / ') + '  bytes ' + src.length + ' → ' + out.length + ' (' + delta + ')');
