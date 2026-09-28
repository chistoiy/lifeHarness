const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '').split('\n');
let L = S.split('\n'), fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length); L = S.split('\n');
}
function before(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('BEFORE MISS', t); fails++; return }
  L = L.slice(0, i).concat(ins, L.slice(i)); S = L.join('\n');
}

/* 详情日历翻页 + 补记时刻 JS */
before('js', '/* 补卡 */', R('hbE_js.txt').concat(['']));
rep('bfstate', "let bfH=null,bfSel=[],bfV=[],bfMonth=0,bfVk=null;", "let bfH=null,bfSel=[],bfV=[],bfMonth=0,bfVk=null,bfAt='08:00';");
rep('bfrender', " if(on){if(bfVk!==h.id)bfValInit(h);bfValRows(h)}", " if(on){if(bfVk!==h.id)bfValInit(h);bfValRows(h)}\n bfAtRender();");
rep('bfsave', " bfSel.slice().sort((a,b)=>a-b).forEach(b=>hbDaySet(h,b,1,useVal?val:null));",
 " bfSel.slice().sort((a,b)=>a-b).forEach(b=>hbDaySet(h,b,1,useVal?val:null,{at:bfAt,bf:1}));");
rep('bftoast', "toast('已为「'+h.n+'」补记 '+bfSel.length+' 天'", "toast('已为「'+h.n+'」补记 '+bfSel.length+' 天'+(bfAt?' · 时刻 '+bfAt:'')");

/* 顶栏：去掉新建按钮（FAB 已承担），设置常驻 */
rep('hdr', `")+hbHdrBtn('cog','打卡设置','hbSetOpen()')+hbHdrBtn('plus','新建习惯','heOpen()');`,
 `")+hbHdrBtn('cog','打卡设置','hbSetOpen()');`);

/* 设置弹层：分类 / 单位管理入口 */
rep('items', " ['weekStart','周起始日','影响日历与周统计的分列方式','seg',['周一','周日']]];",
 " ['weekStart','周起始日','影响日历与周统计的分列方式','seg',['周一','周日']],\n ['catMgr','分类管理','自定义习惯分类 · 改名 / 排序 / 删除前迁移','nav',\"hbMgrOpen('cat')\"],\n ['unitMgr','单位管理','自定义记录量单位 · 同步到习惯与组内子项','nav',\"hbMgrOpen('unit')\"]];");
before('navbranch', "  if(tp==='seg')return", R('hbE_nav.txt'));

/* 操作菜单不再重复放管理入口 */
rep('ops', "const HO_OPS=[['编辑习惯','pen'],['打卡设置','cog'],['分类管理','cog'],['单位管理','cog'],", "const HO_OPS=[['编辑习惯','pen'],['打卡设置','cog'],");
rep('opsrun', " else if(k==='打卡设置')hbSetOpen();\n else if(k==='分类管理')hbMgrOpen('cat');\n else if(k==='单位管理')hbMgrOpen('unit');",
 " else if(k==='打卡设置')hbSetOpen();");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
