/* 轮5.2 后续：旧 checker 里断言「正文悬浮胶囊」的用例改指目录抽屉横条
   （正文胶囊按用户要求已取消）。按单行锚点替换，避免跨行匹配失配。 */
const fs = require('fs');

function patch(file, pairs) {
  let s = fs.readFileSync(file, 'utf8');
  for (const [name, a, b] of pairs) {
    const c = s.split(a).length - 1;
    if (c !== 1) { console.error('MISS[' + file + ' · ' + name + '] x' + c); process.exit(1); }
    s = s.split(a).join(b);
  }
  fs.writeFileSync(file, s);
  console.log('ok ' + file + ' · ' + pairs.length + ' 处');
}

const PILL = "document.getElementById('brBackJump')";
const BAR = "document.getElementById('brDrBack')";

patch('tools/reader/bs55check.js', [
  ['pill-line', "   pill:!" + PILL + ".classList.contains('hidden'),",
    "   pill:!" + BAR + ".classList.contains('hidden'),\n   noPill:!" + PILL + "&&!document.getElementById('brBackPos'),"],
  ['pill-assert', "  jump.pill?ok('「返回上一位置」胶囊即时可见'):bad('胶囊未显示',JSON.stringify(jump));",
    "  (jump.pill&&jump.noPill)?ok('跳章后返回入口在抽屉横条 · 正文无悬浮胶囊'):bad('返回入口',JSON.stringify(jump));"],
  ['back-line', "   hidden:" + PILL + ".classList.contains('hidden')};",
    "   hidden:" + BAR + ".classList.contains('hidden')};"],
  ['auto-line', " const auto=await ev(`brGotoCh(7);return {shown:!" + PILL + ".classList.contains('hidden')};`);",
    " const auto=await ev(`brGotoCh(7);brTocOpen('toc');return {shown:!" + BAR + ".classList.contains('hidden')};`);"],
  ['after-line', " const after=await ev(`return {hidden:" + PILL + ".classList.contains('hidden')};`);",
    " const after=await ev(`return {hidden:" + BAR + ".classList.contains('hidden')};`);"],
]);

patch('tools/reader/bs56check.js', [
  ['jp-pill', "   pill:!" + PILL + ".classList.contains('hidden'),",
    "   pill:!" + BAR + ".classList.contains('hidden'),"],
  ['jp-open', " await gotoQ('?br55=jump');",
    " await gotoQ('?br55=jump');\n await ev(`brTocOpen('toc');return 1`);"],
]);
