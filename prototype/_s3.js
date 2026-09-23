
/* =========================================================================
 * index-ledger.html · 记账模块高保真全家桶（L1~L17 + S1~S5）
 * 内存态数据引擎：txns / accounts / categories / budgets / recurring /
 * wishes / debts / tags；写路径统一走 ledgerWrite/ledgerEdit/ledgerDelete，
 * 完成后重算余额、月合计、预算、分类占比、报表与主页五处联动。
 * ========================================================================= */
/* ======================= 记账全家桶 · 引擎核心 ======================= */
const TODAY='2026-09-23';
const LEDGER_PAGES=new Set(['p-finance','p-txAdd','p-txDetail','p-report','p-yearly','p-budget','p-assets','p-assetAcct','p-cats','p-recur','p-wish','p-debt','p-txSearch','p-lset','p-export','p-billImport','p-billImport2']);
/* ---- 线性 SVG 图标库（stroke 1.8 · currentColor，UI 禁用 emoji 约定） ---- */
const LIC={
 food:'<path d="M4 10.5h16c0 4.7-3.6 8.5-8 8.5s-8-3.8-8-8.5z"/><path d="M8.5 7.5c0-1.4 1-1.9 1-3.3M12.5 7.5c0-1.4 1-1.9 1-3.3"/>',
 car:'<path d="M5.5 12 7 7.5h10L18.5 12"/><rect x="4.5" y="12" width="15" height="5" rx="1.8"/><path d="M7.5 17v2M16.5 17v2"/>',
 bag:'<path d="M6 8.5h12l1 11.5H5z"/><path d="M9 10.5V6.8a3 3 0 0 1 6 0v3.7"/>',
 home:'<path d="M4 11 12 4l8 7"/><path d="M6.2 9.3V20h11.6V9.3"/><path d="M10 20v-5.5h4V20"/>',
 film:'<rect x="4" y="5.5" width="16" height="13" rx="2.5"/><path d="M4 10h16M9.5 5.5v13M14.5 5.5v13"/>',
 run:'<circle cx="14" cy="5.2" r="1.7"/><path d="M13.5 9.5 9.5 11l-1 3.5M13.5 9.5l1.5 4 2.5 2.5M13.5 9.5 9 11l-3.5 5M15 13.5l1 4.5 2 3"/>',
 book:'<path d="M5 5.2A2.2 2.2 0 0 1 7.2 3h11.8v14.5H7.2A2.2 2.2 0 0 0 5 19.7z"/><path d="M9 7.5h6M9 11h4.5"/>',
 heart:'<path d="M12 20S4.8 15.6 3.7 10.6C3 7.4 5.5 5.2 8 5.9c1.5.4 2.7 1.7 4 3.2 1.3-1.5 2.5-2.8 4-3.2 2.5-.7 5 1.5 4.3 4.7C19.2 15.6 12 20 12 20z"/>',
 plane:'<path d="M3.5 11 20.5 3.5 13 20.5l-2.6-6.9z"/><path d="m10.4 13.6 10-10"/>',
 gift:'<rect x="5" y="9" width="14" height="11" rx="1.6"/><path d="M3.8 9h16.4M12 9v11.8"/><path d="M12 9C7.5 9 6.6 4.6 9.2 4.2 11.1 4 12 6.6 12 9zM12 9c4.5 0 5.4-4.4 2.8-4.8C12.9 4 12 6.6 12 9z"/>',
 phone:'<rect x="7" y="3" width="10" height="18" rx="2.6"/><path d="M10.5 18.2h3"/>',
 paw:'<circle cx="7" cy="8.2" r="1.5"/><circle cx="12" cy="6.6" r="1.5"/><circle cx="17" cy="8.2" r="1.5"/><path d="M12 11.4c2.9 0 5.3 2.2 5.3 4.4 0 1.8-1.5 2.8-3.1 2.3-1.4-.4-3-.4-4.4 0-1.6.5-3.1-.5-3.1-2.3 0-2.2 2.4-4.4 5.3-4.4z"/>',
 repeat:'<path d="M20 12a8 8 0 1 1-2.34-5.66"/><path d="M20 4v4.5h-4.5"/>',
 dots:'<circle cx="6" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="18" cy="12" r="1.5"/>',
 wallet:'<rect x="3.5" y="6" width="17" height="13" rx="2.8"/><path d="M3.5 10.2h17M16 14.6h2.2"/>',
 star:'<path d="m12 3.6 2.5 5.2 5.7.7-4.2 4 1.1 5.7L12 16.4l-5.1 2.8 1.1-5.7-4.2-4 5.7-.7z"/>',
 laptop:'<rect x="5.5" y="5" width="13" height="9.5" rx="1.6"/><path d="M3 18h18"/>',
 chart:'<path d="M5 19.5V10M11 19.5v-13M17 19.5v-7M3.5 19.5h17"/>',
 receipt:'<path d="M6.5 3h11v17.2l-2.4-1.7-2.3 1.7-2.3-1.7-2.3 1.7L6.5 19.5z"/><path d="M9.6 8h5M9.6 11.8h5"/>',
 redpack:'<rect x="5" y="3.6" width="14" height="16.8" rx="2"/><path d="M5 8.8h14"/><circle cx="12" cy="12.6" r="1.7"/>',
 cup:'<path d="M6.5 4h11l-1 16.2h-9z"/><path d="M17.5 8h2.2a2 2 0 0 1 0 4h-2.6"/>',
 switch:'<path d="M4 8.5h13l-3-3M20 15.5H7l3 3"/>',
 eye:'<path d="M2.5 12S6 5.8 12 5.8 21.5 12 21.5 12 18 18.2 12 18.2 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.7"/>',
 eyeoff:'<path d="M4 4l16 16"/><path d="M9.6 6.3A9.6 9.6 0 0 1 12 6c6 0 9.5 6 9.5 6a17 17 0 0 1-2.7 3.4M6.6 8.2A17 17 0 0 0 2.5 12S6 18 12 18c1 0 1.9-.1 2.7-.4"/>',
 target:'<circle cx="12" cy="12" r="8.2"/><circle cx="12" cy="12" r="3.4"/>',
 pie:'<path d="M12 3.8v8.2l6.2 5.5A8.4 8.4 0 1 0 20.3 8z"/><path d="M12 3.8a8.4 8.4 0 0 1 8.3 4.2"/>',
 bars:'<rect x="4.5" y="12" width="3.6" height="7.5" rx="1.2"/><rect x="10.2" y="6.5" width="3.6" height="13" rx="1.2"/><rect x="15.9" y="9.5" width="3.6" height="10" rx="1.2"/>',
 cal:'<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>',
 grid2:'<rect x="4" y="4" width="7" height="7" rx="1.8"/><rect x="13" y="4" width="7" height="7" rx="1.8"/><rect x="4" y="13" width="7" height="7" rx="1.8"/><rect x="13" y="13" width="7" height="7" rx="1.8"/>',
 card:'<rect x="3" y="5.5" width="18" height="13" rx="2.6"/><path d="M3 10h18"/>',
 cardplus:'<rect x="3" y="5.5" width="18" height="13" rx="2.6"/><path d="M3 10h18M15.5 14.8h4M17.5 12.8v4"/>',
 chat:'<path d="M12 3.8c4.6 0 8.2 3.2 8.2 7.3 0 4-3.6 7.2-8.2 7.2-1 0-2-.15-2.9-.42L5.5 20l1.2-3.3C5.1 15.4 3.8 13 3.8 11.1c0-4.1 3.6-7.3 8.2-7.3z"/>',
 arrows:'<path d="M4 9h13l-3.2-3.2M20 15H7l3.2 3.2"/>',
 scale:'<path d="M12 4v16M6 8h12M8.5 8 5.5 14.5h6zM15.5 8l-3 6.5h6z"/>',
 down:'<path d="m6 9 6 6 6-6"/>',plus:'<path d="M12 5v14M5 12h14"/>',
 trash:'<path d="M4.5 7h15M9.5 7V4.5h5V7M7 7l1 13.5h8L17 7"/><path d="M10.5 10.5v7M13.5 10.5v7"/>',
 edit:'<path d="M12 20.5h8.5"/><path d="M16.6 3.6a2.1 2.1 0 0 1 3 3L7.2 19l-4.1 1.1 1.1-4.1z"/>',
 copy:'<rect x="8.5" y="8.5" width="11" height="11" rx="2.2"/><path d="M5 15.5A2.2 2.2 0 0 1 4.2 14V5.5a2.2 2.2 0 0 1 2.2-2.2H14a2.2 2.2 0 0 1 1.5.7"/>',
 tag:'<path d="M3.5 11V4.5a1 1 0 0 1 1-1H11l9.5 9.5a1.6 1.6 0 0 1 0 2.2l-6.8 6.8a1.6 1.6 0 0 1-2.2 0z"/><circle cx="7.8" cy="7.8" r="1.3"/>',
 back:'<path d="m14.5 5.5-7 6.5 7 6.5"/>',
 search:'<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
 gear:'<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3M5.4 5.4l2.1 2.1M16.5 16.5l2.1 2.1M18.6 5.4l-2.1 2.1M7.5 16.5l-2.1 2.1"/>',
 dl:'<path d="M12 4v11M7.5 10.5 12 15l4.5-4.5"/><path d="M4.5 19.5h15"/>',
 link:'<path d="M9.5 14.5 14.5 9.5"/><path d="M11 6.5l1.8-1.8a3.6 3.6 0 0 1 5.1 5.1L16 11.7M13 17.5l-1.8 1.8a3.6 3.6 0 0 1-5.1-5.1L8 12.3"/>',
 undo:'<path d="M4 9.5h9.5a5.5 5.5 0 1 1 0 11H8"/><path d="M7.5 5.5 3.7 9.5l3.8 4"/>',
};
const svgIco=(k,cls='w-4.5 h-4.5')=>`<svg class="${cls}" fill="none" stroke="currentColor" stroke-width="1.8" viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round">${LIC[k]||LIC.dots}</svg>`;

/* ---- 分类树（记账模块内两级；时间账本 CATS/SUBS 全局同源另表） ---- */
const LCATS={
 expense:[
  {id:'food',n:'餐饮',i:'food',c:'#f97316',s:['早餐','午餐','晚餐','饮品','外卖','零食']},
  {id:'trans',n:'交通',i:'car',c:'#0ea5e9',s:['地铁','打车','加油','单车','停车']},
  {id:'shop',n:'购物',i:'bag',c:'#fb7185',s:['日用','数码','服饰','美妆']},
  {id:'live',n:'居住',i:'home',c:'#6366f1',s:['房租','水电','物业','宽带']},
  {id:'fun',n:'娱乐',i:'film',c:'#a855f7',s:['电影','游戏','聚会','演出']},
  {id:'sport',n:'运动',i:'run',c:'#22c55e',s:['健身','装备']},
  {id:'study',n:'学习',i:'book',c:'#8b5cf6',s:['书籍','课程']},
  {id:'med',n:'医疗健康',i:'heart',c:'#ef4444',s:['门诊','药品','体检']},
  {id:'travel',n:'旅行',i:'plane',c:'#06b6d4',s:['交通','住宿','门票']},
  {id:'social',n:'人情',i:'gift',c:'#f59e0b',s:['红包','礼物','AA']},
  {id:'comm',n:'通讯',i:'phone',c:'#64748b',s:['话费','流量']},
  {id:'pet',n:'宠物',i:'paw',c:'#d946ef',s:['主粮','医疗','用品']},
  {id:'sub',n:'订阅',i:'repeat',c:'#14b8a6',s:['会员','软件',' automat']},
  {id:'oe',n:'其他',i:'dots',c:'#94a3b8',s:[]},
 ],
 income:[
  {id:'salary',n:'工资',i:'wallet',c:'#22c55e',s:['月薪','津补贴']},
  {id:'bonus',n:'奖金',i:'star',c:'#f59e0b',s:['绩效','年终奖']},
  {id:'part',n:'兼职',i:'laptop',c:'#0ea5e9',s:['外包','私活']},
  {id:'invest',n:'理财',i:'chart',c:'#14b8a6',s:['利息','分红','赎回']},
  {id:'reim',n:'报销',i:'receipt',c:'#8b5cf6',s:[]},
  {id:'rpkt',n:'红包',i:'redpack',c:'#fb7185',s:[]},
  {id:'oi',n:'其他',i:'dots',c:'#94a3b8',s:[]},
 ]};
LCATS.sub.fix=undefined; LCATS.expense.find(x=>x.id==='sub').s=['会员','软件','自动续费'];
function lcat(id){for(const k of['expense','income']){const c=LCATS[k].find(x=>x.id===id);if(c)return{...c,kind:k}}return null}
function lcatN(id){return lcat(id)?.n||'其他'}

/* ---- 账户 ---- */
let L={
 accounts:[
  {id:'cash',type:'cash',n:'现金',i:'wallet',c:'#f59e0b',base:2000},
  {id:'wx',type:'ewallet',n:'微信零钱',i:'chat',c:'#22c55e',base:3500},
  {id:'ali',type:'ewallet',n:'支付宝',i:'card',c:'#6366f1',base:1500},
  {id:'debit',type:'debit',n:'储蓄卡 · 招商',i:'card',c:'#0ea5e9',base:30000},
  {id:'credit',type:'credit',n:'信用卡 · 交行',i:'cardplus',c:'#fb7185',base:-4200,limit:20000,billDay:8,repayDay:28},
  {id:'fund',type:'invest',n:'余额宝 · 理财',i:'chart',c:'#14b8a6',base:15000},
 ],
 txns:[], recur:[
  {id:'r1',n:'房租',amt:2300,cat:'live',sub:'房租',acct:'debit',freq:'month',next:'2026-10-01',on:true},
  {id:'r2',n:'视频会员',amt:25,cat:'sub',sub:'会员',acct:'ali',freq:'month',next:'2026-09-23',on:true},
  {id:'r3',n:'家庭宽带',amt:99,cat:'live',sub:'宽带',acct:'debit',freq:'month',next:'2026-09-23',on:true},
  {id:'r4',n:'基金定投',amt:1000,cat:'invest',sub:'',acct:'fund',freq:'month',next:'2026-09-25',on:true},
  {id:'r5',n:'网盘年度会员',amt:199,cat:'sub',sub:'自动续费',acct:'wx',freq:'year',next:'2027-01-05',on:false},
 ],
 wishes:[
  {id:'w1',n:'富士 X100VI',target:6999,saved:2100},
  {id:'w2',n:'人体工学键盘',target:1299,saved:1299},
  {id:'w3',n:'露营套装',target:2400,saved:360},
 ],
 debts:[
  {id:'d1',side:'lend',p:'老王',total:3000,paid:1200,note:'装修周转'},
  {id:'d2',side:'lend',p:'小李',total:500,paid:0,note:'聚餐垫付'},
  {id:'d3',side:'borrow',p:'阿珍',total:2000,paid:800,note:'周转 8 月'},
 ],
 tags:['必要','冲动','报销','出差','AA','爱好'],
 budget:{'2026-09':{total:12000,perCat:{food:2200,shop:1600,trans:500,fun:800},carry:false},
        '2026-08':{total:12000,perCat:{food:2200,shop:1600,trans:500,fun:800},carry:false},
        '2026-07':{total:11000,perCat:{food:2000,shop:1500,trans:500,fun:700},carry:false}},
 set:{hide:false,defAcct:'wx',monthStart:1,confirmDel:true,afterSave:'back'}
};
/* ---- 确定性种子流水（7/8 月趋势 + 9 月明细） ---- */
let _seed=20260923; const rnd=()=>{_seed=(_seed*1103515245+12345)&0x7fffffff;return _seed/0x7fffffff};
const ri=(a,b)=>a+Math.floor(rnd()*(b-a+1)), rf=(a,b)=>+(a+rnd()*(b-a)).toFixed(2);
const POOL=[
 ['food','午餐',['公司食堂','兰州拉面','快餐·写字楼','麻辣烫'],16,45,['ali','wx','debit'],.9],
 ['food','晚餐',['家常菜外卖','烧烤局','火锅AA'],35,160,['wx','ali','credit'],.5],
 ['food','早餐',['包子豆浆','三明治·咖啡'],6,22,['cash','wx'],.75],
 ['food','饮品',['咖啡','奶茶','气泡水'],9,34,['wx','ali'],.45],
 ['trans','地铁',['地铁通勤'],3,8,['cash','wx'],.85],
 ['trans','打车',['打车回家','打车去公司'],18,88,['ali','wx'],.28],
 ['trans','单车',['共享单车骑行'],1.5,4.5,['wx'],.3],
 ['shop','日用',['超市采购','日用品补货'],28,180,['ali','wx','debit'],.35],
 ['shop','数码',['耳机','机械键盘','手机配件'],199,899,['credit','debit'],.06],
 ['shop','服饰',['T恤','卫衣','冲锋衣试穿'],79,499,['credit','ali'],.1],
 ['fun','电影',['电影票'],35,80,['ali','wx'],.12],
 ['fun','游戏',['游戏内购','Steam 新游戏'],30,198,['ali','wx'],.1],
 ['fun','聚会',['剧本杀','密室逃脱'],60,150,['wx'],.1],
 ['live','水电',['水电燃气缴费'],80,260,['ali'],.05],
 ['med','药品',['感冒药','维生素'],25,95,['ali','wx'],.07],
 ['study','书籍',['买书 · 电子书'],28,120,['ali','wx'],.08],
 ['comm','话费',['话费充值'],50,100,['ali'],.04],
 ['social','红包',['给爸妈红包','同事随礼'],200,600,['wx','debit'],.05],
 ['pet','主粮',['猫粮','猫砂'],89,260,['ali','wx'],.08],
 ['sport','健身',['健身次卡','泳池'],40,120,['wx'],.08],
 ['travel','住宿',['民宿','酒店'],280,650,['credit','debit'],.03],
];
let txSeq=100;
function rawTx(t){t.id=t.id||++txSeq;L.txns.push(t);return t}
function seedMonth(y,md,last,partial){
 for(let d=1;d<=last;d++){
  if(partial&&d>=last)continue;
  const n=2+Math.floor(rnd()*3);
  for(let i=0;i<n;i++){
   const p=POOL.find(x=>rnd()<x[7]&&rnd()<x[7]*2.2)||POOL[Math.floor(rnd()*POOL.length)];
   const dt=`${y}-${String(md).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
   rawTx({kind:'expense',cat:p[0],sub:p[1],n:p[2][Math.floor(rnd()*p[2].length)],amt:+rf(p[3],p[4]).toFixed(2),
    a:p[5][Math.floor(rnd()*p[5].length)],d:dt,tags:[],src:'manual'});
  }
  if(rnd()<.08){const dt=`${y}-${String(md).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
   rawTx({kind:'income',cat:'reim',sub:'',n:'差旅报销',amt:rf(150,820),a:'ali',d:dt,tags:['报销'],src:'manual'})}
 }
 rawTx({kind:'income',cat:'salary',sub:'月薪',n:`${md}月工资`,amt:12000,a:'debit',d:`${y}-${String(md).padStart(2,'0')}-15`,tags:[],src:'manual'});
 rawTx({kind:'expense',cat:'live',sub:'房租',n:'房租 · 月付',amt:2300,a:'debit',d:`${y}-${String(md).padStart(2,'0')}-01`,tags:['必要'],src:'recurring',note:'周期账单'});
}
seedMonth('2026',7,31); seedMonth('2026',8,31); seedMonth('2026',9,23,true);
/* 手工特色流水：跑鞋（联动物品）、退款冲抵、转账还款、今日明细 */
rawTx({id:900,kind:'expense',cat:'shop',sub:'服饰',n:'跑鞋（已转物品档案）',amt:899,a:'credit',d:'2026-09-18',tags:['爱好'],src:'item',link:'Nike 跑鞋'});
rawTx({id:901,kind:'expense',cat:'shop',sub:'服饰',n:'卫衣 · 已退款',amt:329,a:'ali',d:'2026-09-05',tags:['冲动'],src:'manual'});
rawTx({id:902,kind:'refund',cat:'shop',sub:'服饰',n:'退款 · 卫衣',amt:329,a:'ali',d:'2026-09-17',tags:[],src:'manual',refundOf:901});
rawTx({id:903,kind:'transfer',amt:3860.5,a:'debit',to:'credit',d:'2026-09-01',n:'信用卡全额还款',cat:'oe',sub:'',tags:[],src:'manual'});
rawTx({id:904,kind:'expense',cat:'sub',sub:'会员',n:'视频会员 · 周期账单',amt:25,a:'ali',d:'2026-09-08',tags:[],src:'recurring',note:'周期账单'});
rawTx({id:905,kind:'expense',cat:'food',sub:'早餐',n:'包子豆浆',amt:14,a:'cash',d:'2026-09-23',tags:[],src:'manual'});
rawTx({id:906,kind:'expense',cat:'food',sub:'午餐',n:'公司食堂',amt:32,a:'ali',d:'2026-09-23',tags:[],src:'manual'});
rawTx({id:907,kind:'expense',cat:'trans',sub:'地铁',n:'地铁通勤',amt:6,a:'cash',d:'2026-09-23',tags:[],src:'manual'});
L.txns.sort((a,b)=>a.d<b.d?-1:(a.d>b.d?1:a.id-b.id));

/* ---- 工具函数 ---- */
const LA=id=>L.accounts.find(a=>a.id===id);
const money=v=>'¥'+Math.abs(v).toLocaleString('zh-CN',{minimumFractionDigits:2,maximumFractionDigits:2});
const AMT=v=>L.set.hide?'¥•••••':money(v);
const lq=s=>String(s).replace(/'/g,"\\'");
function eff(t,aid){switch(t.kind){
 case 'expense':return t.a===aid?-t.amt:0;
 case 'income':return t.a===aid?t.amt:0;
 case 'refund':return t.a===aid?t.amt:0;
 case 'transfer':return t.a===aid?-t.amt:(t.to===aid?t.amt:0);
 case 'adjust':return t.a===aid?t.amt:0;
 default:return 0}}
function accBal(id){return LA(id).base+L.txns.reduce((s,t)=>s+eff(t,id),0)}
const mTx=m=>L.txns.filter(t=>t.d.slice(0,7)===m);
function mStat(m){let e=0,i=0,n=0;for(const t of mTx(m)){
 if(t.kind==='expense')e+=t.amt;else if(t.kind==='refund')e-=t.amt;else if(t.kind==='income')i+=t.amt;else n++}
 return{exp:e,inc:i,net:i-e}}
function catStat(m){const o={};for(const t of mTx(m)){
 if(t.kind==='expense')o[t.cat]=(o[t.cat]||0)+t.amt;
 else if(t.kind==='refund')o[t.cat]=(o[t.cat]||0)-t.amt}
 return Object.entries(o).filter(([,v])=>v>0).sort((a,b)=>b[1]-a[1])}
function dayMap(m){const o={};for(const t of mTx(m)){const k=t.d.slice(8);
 o[k]=o[k]||{exp:0,inc:0,cats:new Set()};
 if(t.kind==='expense'){o[k].exp+=t.amt;o[k].cats.add(t.cat)}
 else if(t.kind==='refund'){o[k].exp-=t.amt;o[k].cats.add(t.cat)}
 else if(t.kind==='income')o[k].inc+=t.amt}
 return o}
const WD=['日','一','二','三','四','五','六'];
function wdOf(ds){const[d,m,y]=ds.split('-').map(Number);return WD[new Date(y,m-1,d).getDay()]}
function monthOf(m){const[y,mm]=m.split('-').map(Number);const last=new Date(y,mm,0).getDate();
 return{last,firstWd:new Date(y,mm-1,1).getDay()}}
/* ---- 统一写路径（五处联动 = 各视图渲染时全量重算） ---- */
function finTouch(){renderL1();if(typeof LED_RENDER!=='undefined'&&LED_RENDER[curPage])LED_RENDER[curPage]()}
function ledgerAdd(t){t.id=t.id||++txSeq;L.txns.push(t);L.txns.sort((a,b)=>a.d<b.d?-1:(a.d>b.d?1:a.id-b.id));finTouch();return t}
function ledgerDel(id){L.txns=L.txns.filter(t=>t.id!==id&&(t.refundOf!==id));finTouch()}
function ledgerEdit(id,patch){const t=L.txns.find(x=>x.id===id);if(t)Object.assign(t,patch);L.txns.sort((a,b)=>a.d<b.d?-1:(a.d>b.d?1:a.id-b.id));finTouch()}
/* ======================= 路由补丁与注册表 ======================= */
const LED_RENDER={};
const _finSetPage=setPage;
setPage=function(p){_finSetPage(p);if(LED_RENDER[p])LED_RENDER[p]()};
const _finScope=scopeForPage;
scopeForPage=p=>LEDGER_PAGES.has(p)?'记账':_finScope(p);
Object.assign(TITLES,{
 'p-finance':['记账','本地账本 · 全离线'],'p-txAdd':['记一笔','支出 · 收入 · 转账'],
 'p-txDetail':['流水详情',''],'p-report':['统计报表','趋势 · 分类 · Top'],'p-yearly':['年度总结',''],
 'p-budget':['预算中心','总额与分类预算'],'p-assets':['资产','净资产 · 账户总览'],
 'p-assetAcct':['账户详情',''],'p-cats':['分类管理','两级分类 · 图标与颜色'],
 'p-recur':['周期账单','订阅 · 房租 · 定投'],'p-wish':['心愿单','为想要的攒一攒'],
 'p-debt':['借出 · 借入','往来清晰'],'p-txSearch':['搜索流水','多条件组合过滤'],
 'p-lset':['记账设置',''],'p-export':['数据导出','CSV · JSON']});
let finMonth='2026-09',finView='list',finCalSel=null;
function finMonthStep(d){const[y,m]=finMonth.split('-').map(Number);const n=m-1+d;
 finMonth=`${y+Math.floor(n/12)}-${String(n%12+1).padStart(2,'0')}`;finCalSel=null;renderL1()}
function setFinView(v){finView=v;
 $('#finSegList').className='px-3 py-1 rounded-full'+(v==='list'?' seg-on':'');
 $('#finSegCal').className='px-3 py-1 rounded-full'+(v==='cal'?' seg-on':'');
 renderL1()}
function toggleHideAmounts(){L.set.hide=!L.set.hide;renderL1();toast(L.set.hide?'金额已隐藏':'金额已显示')}
function finLbl(m){const[y,mm]=m.split('-');return `${y}年${+mm}月`}

/* ======================= L1 记账主页 ======================= */
function renderL1(){
 if(!document.getElementById('finList'))return;
 $('#finMonthLbl').textContent=finLbl(finMonth);
 const st=mStat(finMonth);
 $('#finNetLbl').textContent='本月净结余';
 $('#finNet').textContent=(st.net<0?'-':'')+AMT(st.net);
 $('#finInOut').textContent=`支出 ${AMT(st.exp)} · 收入 ${AMT(st.inc)}`;
 const b=L.budget[finMonth]||{total:0,perCat:{}};
 const pct=b.total?Math.min(100,st.exp/b.total*100):0,over=b.total&&st.exp>b.total;
 $('#finBudgetBar').style.width=pct+'%';
 $('#finBudgetBar').className='rounded-full '+(over?'bg-rose-300':'bg-white/90');
 $('#finBudgetL').textContent=`月度预算 ${b.total?money(b.total):'未设置'}`;
 const daysInM=finMonth===TODAY.slice(0,7)?+TODAY.slice(8,10):monthOf(finMonth).last;
 $('#finBudgetR').textContent=over?`已超支 ${money(st.exp-b.total)}`:b.total?`已用 ${pct.toFixed(0)}% · 日均可用 ${AMT(Math.max(0,(b.total-st.exp)/Math.max(1,daysInM-(+TODAY.slice(8,10)+1)+1))}`:'点击查看';
 /* 功能区 */
 $('#finFuncRow').innerHTML=[['assets','pie','资产','p-assets'],['budget','target','预算','p-budget'],['report','bars','报表','p-report'],['recur','repeat','周期','p-recur'],['more','grid2','更多',null]].map(([id,ic,n,pg])=>
  `<button class="func-b" onclick="${pg?`navTo('${pg}')`:`openSheet('sheetLedgerMore')`}">${svgIco(ic,'w-5 h-5')}<span>${n}</span></button>`).join('');
 $('#ledgerMoreGrid')&&($('#ledgerMoreGrid').innerHTML=[['p-cats','tag','分类管理'],['p-wish','star','心愿单'],['p-debt','arrows','借出·借入'],['p-txSearch','search','搜索筛选'],['p-billImport','dl','账单导入'],['p-export','copy','数据导出'],['p-yearly','cal','年度总结'],['p-lset','gear','记账设置']].map(([pg,ic,n])=>
  `<button class="func-b !min-h-[64px]" onclick="closeSheet('sheetLedgerMore');navTo('${pg}')">${svgIco(ic,'w-5 h-5')}<span>${n}</span></button>`).join(''));
 /* 快捷记一笔 5 格 */
 $('#finQuickCats').innerHTML=LCATS.expense.slice(0,4).map(c=>
  `<button class="catcell" onclick="openL2({catId:'${c.id}'})"><span class="ci" style="background:${c.c}1f;color:${c.c}">${svgIco(c.i,'w-5 h-5')}</span><span>${c.n}</span></button>`).join('')+
  `<button class="catcell" onclick="openSheet('sheetLedgerMore')"><span class="ci" style="background:#e2e8f0;color:#64748b">${svgIco('plus','w-5 h-5')}</span><span>更多</span></button>`;
 /* 分类环图 */
 const cs=catStat(finMonth),tot=cs.reduce((s,[,v])=>s+v,0);
 const r=30,C=2*Math.PI*r;let off=0;
 $('#finRing').innerHTML=tot?cs.map(([id,v])=>{const c=lcat(id),len=v/tot*C;const seg=
  `<circle cx="42" cy="42" r="${r}" fill="none" stroke="${c.c}" stroke-width="11" stroke-dasharray="${len-1.5} ${C-len+1.5}" stroke-dashoffset="${-off}" transform="rotate(-90 42 42)" stroke-linecap="butt"/>`;off+=len;return seg}).join('')
  :`<circle cx="42" cy="42" r="${r}" fill="none" stroke="#e2e8f0" stroke-width="11"/>`;
 $('#finRingLegend').innerHTML=cs.length?cs.slice(0,4).map(([id,v])=>{const c=lcat(id);
  return `<button class="flex items-center gap-2 w-full text-left" onclick="navTo('p-report');setTimeout(()=>repDrill('${id}'),60)"><span class="w-2.5 h-2.5 rounded-full shrink-0" style="background:${c.c}"></span><span class="text-[11px] font-bold flex-1 truncate">${c.n}</span><b class="text-[11px]">${AMT(v)}</b><span class="text-[10px] text-slate-400 w-9 text-right">${(v/tot*100).toFixed(0)}%</span></button>`}).join('')
  :'<span class="text-[11px] text-slate-400">本月暂无支出流水</span>';
 /* 流水视图 */
 $('#finList').classList.toggle('hidden',finView!=='list');
 $('#finCal').classList.toggle('hidden',finView!=='cal');
 if(finView==='list')renderFinList();else renderFinCal();
}
function srcBadge(t){if(t.src==='recurring')return '<span class="text-[8px] px-1 py-px rounded bg-teal-500/10 text-teal-500 font-bold">周期</span>';
 if(t.src==='bill')return '<span class="text-[8px] px-1 py-px rounded bg-sky-500/10 text-sky-500 font-bold">账单导入</span>';
 if(t.src==='item')return '<span class="text-[8px] px-1 py-px rounded bg-indigo-500/10 text-indigo-400 font-bold">物品 L12</span>';
 if(t.src==='read')return '<span class="text-[8px] px-1 py-px rounded bg-amber-500/10 text-amber-500 font-bold">阅读 L4</span>';
 if(t.src==='debt')return '<span class="text-[8px] px-1 py-px rounded bg-rose-500/10 text-rose-400 font-bold">借贷</span>';return ''}
function txRow(t){
 const c=t.kind==='transfer'?{n:'转账',c:'#64748b',i:'switch'}:t.kind==='refund'?{n:'退款',c:'#10b981',i:'undo'}:lcat(t.cat)||{n:'其他',c:'#94a3b8',i:'dots'};
 const pre=t.kind==='expense'?'−':(t.kind==='income'||t.kind==='refund')?'+':t.kind==='adjust'?(t.amt<0?'−':'+'):'';
 const acct=t.kind==='transfer'?`${LA(t.a).n} → ${LA(t.to).n}`:LA(t.a)?.n||'';
 const tags=t.tags?.length?`<span class="text-[8px] text-slate-400">${t.tags.map(x=>'#'+x).join(' ')}</span>`:'';
 return `<button class="fin-row w-full text-left" onclick="openTxDetail(${t.id})">
  <span class="fin-ico" style="background:${c.c}1a;color:${c.c}">${svgIco(c.i,'w-[18px] h-[18px]')}</span>
  <span class="flex-1 min-w-0"><span class="text-[13px] font-bold block truncate">${t.n||c.n}</span>
   <span class="text-[9px] text-slate-400 flex items-center gap-1">${t.cat&&t.kind!=='transfer'&&t.kind!=='adjust'?lcatN(t.cat)+(t.sub?' · '+t.sub:''):''}${acct?`<i class="not-italic opacity-70">${acct}</i>`:''}${srcBadge(t)}${tags}</span></span>
  <b class="text-[13px] ${t.kind==='income'||t.kind==='refund'?'text-emerald-500':t.kind==='transfer'?'text-slate-400':''}">${pre}${AMT(t.amt)}</b></button>`}
function renderFinList(){
 const groups={};for(const t of mTx(finMonth))(groups[t.d]=groups[t.d]||[]).push(t);
 const ds=Object.keys(groups).sort().reverse();
 $('#finList').innerHTML=ds.length?ds.map(d=>{
  const dayExp=groups[d].reduce((s,t)=>s+(t.kind==='expense'?t.amt:t.kind==='refund'||t.kind==='adjust'?-t.amt:0),0);
  const dayInc=groups[d].reduce((s,t)=>s+(t.kind==='income'?t.amt:0),0);
  return `<div class="card !p-0 overflow-hidden"><div class="flex items-center justify-between px-3.5 pt-2.5 pb-1">
   <b class="text-[11px]">${d.slice(5)} 周${wdOf(d)}</b>
   <span class="text-[10px] text-slate-400">${dayInc?'收 '+money(dayInc)+(dayExp?' · ':''):''}${dayExp?'支 '+money(dayExp):''}</span></div>
   ${groups[d].sort((a,b)=>b.id-a.id).map(txRow).join('')}</div>`}).join('')
  :'<div class="text-center text-xs text-slate-400 py-12">本月暂无流水，点下方按钮记一笔</div>';
}
function renderFinCal(){
 const{last,firstWd}=monthOf(finMonth),dm=dayMap(finMonth);
 let h=`<div class="grid grid-cols-7 text-center text-[9px] text-slate-400 font-bold mb-1">${WD.map(w=>`<span>${w}</span>`).join('')}</div><div class="grid grid-cols-7 gap-1">`;
 for(let i=0;i<firstWd;i++)h+='<span></span>';
 for(let d=1;d<=last;d++){const k=String(d).padStart(2,'0'),v=dm[k],isToday=finMonth+'-'+k===TODAY;
  h+=`<button class="cal-d ${finCalSel===k?'ring-1 ring-brand-500 bg-brand-50 dark:bg-brand-500/10':''}" onclick="finCalSel='${k}';renderL1()">
   <span class="text-[10px] font-bold ${isToday?'text-brand-500':''}">${d}</span>
   ${v?`<div class="text-[8px] leading-3 ${v.exp>0?'text-rose-400':'text-emerald-500'}">${v.exp?AMT(v.exp).replace('¥',''):v.inc?'+'+AMT(v.inc).replace('¥',''):''}</div>
   <div class="flex justify-center gap-0.5">${[...v.cats].slice(0,3).map(cid=>`<i class="w-1 h-1 rounded-full not-italic" style="background:${lcat(cid)?.c||'#94a3b8'}"></i>`).join('')}</div>`:'<div class="h-4"></div>'}</button>`}
 h+='</div>';
 if(finCalSel){const d=finMonth+'-'+finCalSel;const ts=L.txns.filter(t=>t.d===d);
  h+=`<div class="mt-3"><div class="flex items-center justify-between px-1"><b class="text-[11px]">${d.slice(5)} 周${wdOf(d)} 流水</b><button class="text-[10px] text-brand-500 font-bold" onclick="openL2({date:'${d}'})">＋ 记一笔</button></div>
  <div class="mt-1.5 space-y-1.5">${ts.length?ts.map(txRow).join(''):'<div class="text-center text-[11px] text-slate-400 py-4">当天暂无流水</div>'}</div></div>`}
 $('#finCal').innerHTML=h;
}
/* ======================= L2 记一笔（全屏） ======================= */
const txState={kind:'expense',cat:'food',sub:'',expr:'',note:'',tags:[],acct:'wx',to:'debit',date:TODAY,editId:null};
function exprVal(e){if(!e)return 0;
 const toks=e.match(/\d+\.?\d*|[+−×÷]/g)||[];if(!toks.length)return 0;
 let pass1=[],i=0;
 while(i<toks.length){const tk=toks[i];
  if(tk==='×'||tk==='÷'){const a=parseFloat(pass1.pop()),b=parseFloat(toks[++i]);
   pass1.push(String(b!==0&&isFinite(a/b)?a/b:a))}
  else pass1.push(tk);i++}
 let res=parseFloat(pass1[0])||0;
 for(i=1;i<pass1.length;i+=2){const op=pass1[i],v=parseFloat(pass1[i+1]);if(isNaN(v))break;
  if(op==='+')res+=v;else if(op==='−')res-=v}
 return Math.max(0,+res.toFixed(2))}
function txKey(k){
 const s=txState;
 if(k==='del'){s.expr=s.expr.slice(0,-1)}
 else if(k==='save'){return saveTx()}
 else if(/[0-9.]/.test(k)){const tail=s.expr.split(/[+−×÷]/).pop();
  if(k==='.'&&tail.includes('.'))return;
  if(tail.length>=9)return;s.expr+=k}
 else{if(!s.expr||/[+−×÷]$/.test(s.expr))s.expr+='0';s.expr+=k}
 renderTxShow()}
function renderTxShow(){const v=exprVal(txState.expr);
 $('#txAmtShow').textContent=L.set.hide?'••••':v.toLocaleString('zh-CN',{minimumFractionDigits:2,maximumFractionDigits:2});
 $('#txExpr').textContent=/[+−×÷]/.test(txState.expr)?txState.expr+' =':''}
function txSetKind(k){txState.kind=k;renderTxAdd()}
function txPickCat(id){txState.cat=id;txState.sub='';renderTxAdd()}
function txPickSub(sn){txState.sub=txState.sub===sn?'':sn;renderTxAdd()}
function openL2(opt={}){Object.assign(txState,{kind:opt.kind||'expense',cat:opt.catId||(opt.kind==='income'?'salary':'food'),sub:'',expr:'',note:opt.note||'',tags:[],acct:opt.acct||L.set.defAcct,to:'debit',date:opt.date||TODAY,editId:opt.editId||null});
 if(opt.editId){const t=L.txns.find(x=>x.id===opt.editId);if(t){txState.kind=t.kind;txState.cat=t.cat||txState.cat;txState.sub=t.sub||'';txState.expr=String(t.amt);txState.note=t.n||'';txState.tags=[...(t.tags||[])];txState.acct=t.a;txState.to=t.to||'debit'}}
 navTo('p-txAdd')}
function renderTxAdd(){
 const s=txState;
 $('#txKindSeg').innerHTML=['expense','income','transfer'].map(k=>
  `<button class="flex-1 py-1.5 rounded-xl ${s.kind===k?'seg-on':''}" onclick="txSetKind('${k}')">${k==='expense'?'支出':k==='income'?'收入':'转账'}</button>`).join('');
 const isTr=s.kind==='transfer';
 $('#txCatWrap').classList.toggle('hidden',isTr);$('#txTransferWrap').classList.toggle('hidden',!isTr);
 if(!isTr){const list=LCATS[s.kind];
  $('#txCatRail').innerHTML=list.map(c=>
   `<button class="catcell ${s.cat===c.id?'on':''}" onclick="txPickCat('${c.id}')"><span class="ci" style="background:${c.c}1f;color:${c.c}">${svgIco(c.i,'w-5 h-5')}</span><span>${c.n}</span></button>`).join('');
  const subs=lcat(s.cat)?.s||[];
  $('#txSubRail').innerHTML=(subs.length?subs.map(sn=>`<button class="tag-chip ${s.sub===sn?'on':''}" onclick="txPickSub('${lq(sn)}')">${sn}</button>`).join(''):'')+
   `<button class="tag-chip !bg-transparent !border !border-dashed !border-slate-300 dark:!border-slate-600 text-slate-400" onclick="openCatAddSheet('${s.cat}')">＋子分类</button>`;
 }else{
  $('#txTransferWrap').innerHTML=['a','to'].map((f,idx)=>
   `<button class="card w-full flex items-center gap-3 text-left" onclick="openLedgerAcctPick(a=>{txState.${f}=a;renderTxAdd()},${idx?'选入':'选出'})">
    <span class="fin-ico" style="background:${LA(s[f]).c}1a;color:${LA(s[f]).c}">${svgIco(LA(s[f]).i,'w-[18px] h-[18px]')}</span>
    <span class="flex-1 text-left"><span class="text-[13px] font-bold block">${LA(s[f]).n}</span><span class="text-[9px] text-slate-400">${idx?'转入账户':'转出账户'} · 余额 ${AMT(accBal(s[f]))}</span></span>
    <b class="text-[13px]">${AMT(exprVal(s.expr))}</b></button>`).join('')+
   `<div class="text-center text-[9px] text-slate-400">转账不计入收支，仅移动账户余额</div>`}
 $('#txMetaRow').innerHTML=`
  <button class="chip flex items-center gap-1" ${isTr?'disabled style="opacity:.5"':`onclick="openLedgerAcctPick(a=>{txState.acct=a;renderTxAdd()})"`}>${svgIco(LA(s.acct).i,'w-3.5 h-3.5')}${isTr?'支出账户见上方':LA(s.acct).n}</button>
  <button class="chip flex items-center gap-1" onclick="openLedgerDate(d=>{txState.date=d;renderTxAdd()},'day')">${svgIco('cal','w-3.5 h-3.5')}${s.date===TODAY?'今天':s.date.slice(5)}</button>
  <button class="chip flex items-center gap-1 ${s.tags.length?'chip-on':''}" onclick="txTagToggle()">${svgIco('tag','w-3.5 h-3.5')}标签${s.tags.length?' '+s.tags.length:''}</button>
  ${s.editId?'<span class="ml-auto text-[9px] text-slate-400 self-center">编辑中</span>':''}`;
 const KEYS=['7','8','9','÷','4','5','6','×','1','2','3','−','.','0','del','+'];
 $('#txPad').innerHTML=KEYS.map(k=>{const l={del:'⌫'}[k]||k;
  return `<button class="kp ${k==='del'?'op del':/[+−×÷]/.test(k)?'op':''}" onclick="txKey('${k==='del'?'del':k}')">${l}</button>`}).join('')+
  `<button class="kp save col-span-4" onclick="txKey('save')">${s.editId?'保存修改':'保存'}</button>`;
 $('#txTagWrap').classList.toggle('hidden',!s._tagsOpen);
 $('#txTagWrap').innerHTML=L.tags.map(t=>`<button class="tag-chip ${s.tags.includes(t)?'on':''}" onclick="txTagPick('${lq(t)}')">#${t}</button>`).join('');
 $('#txNote').value=s.note;renderTxShow()}
function txTagToggle(){txState._tagsOpen=!txState._tagsOpen;renderTxAdd()}
function txTagPick(t){const s=txState;s.tags=s.tags.includes(t)?s.tags.filter(x=>x!==t):[...s.tags,t];renderTxAdd()}
function saveTx(){const s=txState,amt=exprVal(s.expr);
 if(s.kind==='transfer'){if(!amt)return toast('请输入转账金额');
  if(s.acct===s.to)return toast('转出与转入账户不能相同')}
 else if(!amt)return toast('请输入金额');
 const t={kind:s.kind,cat:s.cat,sub:s.sub,n:s.note.trim(),amt,a:s.acct,d:s.date,tags:[...s.tags],src:'manual'};
 if(s.kind==='transfer'){t.cat='oe';t.sub='';t.a=s.acct;t.to=s.to;t.n=s.note.trim()||`${LA(s.acct).n} → ${LA(s.to).n}`}
 if(s.editId){ledgerEdit(s.editId,Object.assign(t,{id:s.editId}));toast('已更新流水 · 各视图同步回算')}
 else{ledgerAdd(t);toast(`已记一笔 · ${s.kind==='expense'?'支出':s.kind==='income'?'收入':'转账'} ${money(amt)}`)}
 if(L.set.afterSave==='back'){stack.length=0;setPage('p-finance')}
 else{txState.expr='';txState.note='';txState.tags=[];txState.editId=null;renderTxAdd()}}

/* ======================= S1 速记半屏 ======================= */
const qkState={kind:'expense',cat:'food',expr:'',note:''};let qkAcct='';
function qkKind(k){qkState.kind=k;qkState.cat=k==='expense'?'food':'salary';renderQuick()}
function qkKey(k){const s=qkState;
 if(k==='del')s.expr=s.expr.slice(0,-1);
 else if(k==='save')return qkSave();
 else if(/[0-9.]/.test(k)){const tail=s.expr.split(/[+−×÷]/).pop();if(k==='.'&&tail.includes('.'))return;if(tail.length>=9)return;s.expr+=k}
 else{if(!s.expr||/[+−×÷]$/.test(s.expr))s.expr+='0';s.expr+=k}
 renderQuick(true)}
function qkSave(){const amt=exprVal(qkState.expr);if(!amt)return toast('请输入金额');
 ledgerAdd({kind:qkState.kind,cat:qkState.cat,sub:'',n:qkState.note.trim(),amt,a:qkAcct||L.set.defAcct,d:TODAY,tags:[],src:'manual'});
 closeSheet('sheetLedgerQuick');qkState.expr='';qkState.note='';qkState.cat='food';
 toast(`已记一笔 · ${money(amt)}`)}
function ledgerQuickOpen(){if(curPage!=='p-finance'){stack.length=0;setPage('p-finance')}
 qkAcct=L.set.defAcct;openSheet('sheetLedgerQuick');renderQuick()}
function renderQuick(showOnly){
 const s=qkState,list=LCATS[s.kind];
 $('#qkAcctBtn').innerHTML=`${svgIco('wallet','w-3.5 h-3.5')}${LA(qkAcct||L.set.defAcct).n}<span class="text-slate-400">${AMT(accBal(qkAcct||L.set.defAcct))}</span>`;
 if(showOnly){$('#qkAmtShow').textContent=L.set.hide?'••••':exprVal(s.expr).toFixed(2);return}
 $('#qkCatRail').innerHTML=list.map(c=>
  `<button class="catcell ${s.cat===c.id?'on':''}" onclick="qkState.cat='${c.id}';renderQuick()"><span class="ci" style="background:${c.c}1f;color:${c.c}">${svgIco(c.i,'w-5 h-5')}</span><span>${c.n}</span></button>`).join('');
 const KEYS=['7','8','9','÷','4','5','6','×','1','2','3','−','.','0','del','+'];
 $('#qkPad').innerHTML=KEYS.map(k=>{const l={del:'⌫'}[k]||k;
  return `<button class="kp !h-11 !text-base ${k==='del'?'op del':/[+−×÷]/.test(k)?'op':''}" onclick="qkKey('${k==='del'?'del':k}')">${l}</button>`}).join('')+
  `<button class="kp save col-span-4 !h-11" onclick="qkKey('save')">保存</button>`;
 $('#qkAmtShow').textContent=L.set.hide?'••••':exprVal(s.expr).toFixed(2);
 $('#qkNote').value=s.note}

/* ======================= S2 日期滚轮 ======================= */
let ldMode='day',ldSel=[2026,9,23],ldCb=null;
function openLedgerDate(cb,mode){ldCb=cb;ldMode=mode||'day';
 const base=(mode==='month'?finMonth:txState.date).split('-').map(Number);ldSel=[base[0],base[1],base[2]||1];
 $('#ldDateTitle').textContent=mode==='month'?'选择年月':'选择日期';
 openSheet('sheetLedgerDate');buildLd()}
function openFinMonthPick(){openLedgerDate(m=>{finMonth=m;renderL1()},'month')}
function buildLd(){const yrs=[2024,2025,2026,2027],
 mons=Array.from({length:12},(_,i)=>i+1),
 dmax=ldMode==='month'?1:new Date(ldSel[0],ldSel[1],0).getDate(),
 days=Array.from({length:dmax},(_,i)=>i+1);
 $('#ldWD').classList.toggle('hidden',ldMode==='month');
 $('#sheetLedgerDate .wbox').className='wbox grid '+(ldMode==='month'?'grid-cols-2':'grid-cols-3')+' gap-1';
 wheel('#ldWY',yrs.map(y=>y+' 年'),yrs.indexOf(ldSel[0]),i=>ldSel[0]=yrs[i]);
 wheel('#ldWM',mons.map(m=>m+' 月'),mons.indexOf(ldSel[1]),i=>{ldSel[1]=mons[i];if(ldMode==='day')buildLd()});
 if(ldMode==='day')wheel('#ldWD',days.map(d=>d+' 日'),Math.min(dmax-1,dmax?ldSel[2]-1:0),i=>ldSel[2]=days[i]);}
function wheel(sel,items,selIdx,onSel){const el=document.querySelector(sel);
 el.innerHTML=items.map((t,i)=>`<div class="witem ${i===selIdx?'on':''}">${t}</div>`).join('');
 el.scrollTop=selIdx*36;
 el.onscroll=()=>{clearTimeout(el._t);el._t=setTimeout(()=>{const i=Math.max(0,Math.min(items.length-1,Math.round(el.scrollTop/36)));
  el.querySelectorAll('.witem').forEach((x,k)=>x.classList.toggle('on',k===i));onSel(i)},110)}}
function ledgerDateOk(){closeSheet('sheetLedgerDate');
 const v=ldMode==='month'?`${ldSel[0]}-${String(ldSel[1]).padStart(2,'0')}`:`${ldSel[0]}-${String(ldSel[1]).padStart(2,'0')}-${String(ldSel[2]).padStart(2,'0')}`;
 ldCb&&ldCb(v);ldCb=null}

/* ======================= S4-lite 账户选择弹层 ======================= */
let _acctCb=null;
function openLedgerAcctPick(cb,title){_acctCb=cb;
 $('#ldAcctTitle').textContent=title||'选择账户';
 $('#ldAcctList').innerHTML=L.accounts.filter(a=>!a.archived).map(a=>
  `<button class="fin-row w-full text-left" onclick="closeSheet('sheetLedgerAcct');_acctCb&&_acctCb('${a.id}')">
   <span class="fin-ico" style="background:${a.c}1a;color:${a.c}">${svgIco(a.i,'w-[18px] h-[18px]')}</span>
   <span class="flex-1 text-left"><span class="text-[13px] font-bold block">${a.n}</span><span class="text-[9px] text-slate-400">${a.type==='credit'?'可用额度 '+money(a.limit+accBal(a.id)):'余额'}</span></span>
   <b class="text-[13px]">${AMT(accBal(a.id))}</b></button>`).join('');
 openSheet('sheetLedgerAcct')}

/* ======================= L3 流水详情 ======================= */
let txdId=null;
function openTxDetail(id){txdId=id;navTo('p-txDetail')}
function renderTxDetail(){const t=L.txns.find(x=>x.id===txdId);if(!t)return;
 const c=t.kind==='transfer'?{n:'转账',c:'#64748b',i:'switch'}:t.kind==='refund'?{n:'退款',c:'#10b981',i:'undo'}:t.kind==='adjust'?{n:'余额调整',c:'#94a3b8',i:'scale'}:lcat(t.cat);
 const sign=t.kind==='expense'?'−':(t.kind==='income'||t.kind==='refund')?'+':t.amt<0?'−':'+';
 const rel=t.refundOf?L.txns.find(x=>x.id===t.refundOf):null;
 const refunds=t.kind==='expense'?L.txns.filter(x=>x.refundOf===t.id):[];
 $('#txdBody').innerHTML=`
  <div class="card text-center !py-6">
   <span class="inline-flex w-12 h-12 rounded-2xl items-center justify-center" style="background:${c.c}1a;color:${c.c}">${svgIco(c.i,'w-6 h-6')}</span>
   <div class="mt-2 text-[11px] text-slate-400">${c.n}${t.sub?' · '+t.sub:''}</div>
   <div class="text-3xl font-extrabold tracking-tight ${t.kind==='income'||t.kind==='refund'?'text-emerald-500':''}">${sign}${AMT(t.amt)}</div>
   ${t.n?`<div class="mt-1.5 text-[12px] text-slate-500 dark:text-slate-400">${t.n}</div>`:''}
  </div>
  <div class="card mt-3 text-[12px] space-y-2.5">
   ${t.kind==='transfer'?`<div class="flex justify-between"><span class="text-slate-400">转出</span><b>${LA(t.a).n}</b></div><div class="flex justify-between"><span class="text-slate-400">转入</span><b>${LA(t.to).n}</b></div>`
    :`<div class="flex justify-between"><span class="text-slate-400">账户</span><b>${LA(t.a).n} · ${AMT(accBal(t.a))}</b></div>`}
   <div class="flex justify-between"><span class="text-slate-400">日期</span><b>${t.d} 周${wdOf(t.d)}</b></div>
   ${t.tags?.length?`<div class="flex justify-between"><span class="text-slate-400">标签</span><b>${t.tags.map(x=>'#'+x).join(' ')}</b></div>`:''}
   ${rel?`<div class="flex justify-between"><span class="text-slate-400">退回至</span><b class="text-brand-500" onclick="openTxDetail(${rel.id})">${rel.n} ${money(rel.amt)} ›</b></div>`:''}
   ${refunds.length?`<div class="flex justify-between"><span class="text-slate-400">已退款</span><b class="text-emerald-500" onclick="openTxDetail(${refunds[0].id})">${money(refunds.reduce((s,x)=>s+x.amt,0))} ›</b></div>`:''}
   ${t.link?`<div class="flex justify-between"><span class="text-slate-400">关联</span><b class="text-brand-500">${t.src==='item'?'物品档案 · '+t.link+'（L12）':t.link} ›</b></div>`:''}
   ${t.src==='recurring'?`<div class="flex justify-between"><span class="text-slate-400">来源</span><b>周期账单自动生成 · 已同步续费提醒日程（L8）</b></div>`:''}
   ${t.src==='bill'?`<div class="flex justify-between"><span class="text-slate-400">来源</span><b>账单导入 · ${t.note||'支付宝'}</b></div>`:''}
  </div>
  <div class="mt-4 grid grid-cols-4 gap-2 text-center">
   <button class="func-b" onclick="openL2({editId:${t.id}})">${svgIco('edit','w-5 h-5')}<span>编辑</span></button>
   <button class="func-b" onclick="txdCopy()">${svgIco('copy','w-5 h-5')}<span>复制</span></button>
   <button class="func-b" ${t.kind!=='expense'||refunds.length?'disabled style="opacity:.35"':''} onclick="txdRefund()">${svgIco('undo','w-5 h-5')}<span>退款</span></button>
   <button class="func-b !text-rose-400" onclick="txdDel()">${svgIco('trash','w-5 h-5')}<span>删除</span></button>
  </div>`}
function txdCopy(){const t=L.txns.find(x=>x.id===txdId);openL2({kind:t.kind,catId:t.cat,note:t.n,acct:t.a});
 txState.expr=String(t.amt);if(t.kind==='transfer'){txState.acct=t.a;txState.to=t.to}renderTxAdd()}
function txdRefund(){const t=L.txns.find(x=>x.id===txdId);
 if(t.kind!=='expense')return;
 ledgerAdd({kind:'refund',cat:t.cat,sub:t.sub,n:'退款 · '+(t.n||lcatN(t.cat)),amt:t.amt,a:t.a,d:TODAY,tags:[],src:'manual',refundOf:t.id});
 toast('已生成退款冲抵 · 支出与预算同步扣减');renderTxDetail()}
let _delArm=0;
function txdDel(){if(L.set.confirmDel&&Date.now()-_delArm>2600){_delArm=Date.now();return toast('再次点击删除以确认')}
 ledgerDel(txdId);toast('已删除该笔流水及其退款');goBack()}
LED_RENDER['p-finance']=renderL1;LED_RENDER['p-txAdd']=renderTxAdd;LED_RENDER['p-txDetail']=renderTxDetail;
function openCatAddSheet(cat){toast('子分类添加见「分类管理」')}
//LEDGER_JS_END
