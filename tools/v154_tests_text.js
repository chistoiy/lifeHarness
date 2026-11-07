/* 批D1/D2/D4 连带：测试断言跟随「去 emoji / 去教学文案 / 问候语随昵称」的新文案
   用法：node tools/v154_tests_text.js */
const fs = require("fs");
let hits = 0;
function apply(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  for (const [old_, neu, label] of pairs) {
    const n = s.split(old_).length - 1;
    if (n !== 1) {
      console.error("!! [" + F + "][" + label + "] 命中 " + n + " 次（要求 1）");
      process.exit(1);
    }
    s = s.replace(old_, neu);
    hits++;
  }
  fs.writeFileSync(F, s);
  console.log("  ok " + F);
}

apply("test/notify_test.dart", [
  ["expect(find.text('📅 日程与任务提醒'), findsOneWidget);", "expect(find.text('日程与任务提醒'), findsOneWidget);", "n1"],
  ["expect(find.text('📔 日记复盘'), findsOneWidget);", "expect(find.text('日记复盘'), findsOneWidget);", "n2"],
  ["expect(find.text('🔁 习惯提醒'), findsOneWidget);", "expect(find.text('习惯提醒'), findsOneWidget);", "n3"],
]);

apply("test/widget_test.dart", [
  ["expect(find.text('🎨 主题风格'), findsNothing); // 已收进二级页", "expect(find.text('主题风格'), findsNothing); // 已收进二级页", "w1"],
  ["expect(find.text('🎨 主题风格'), findsOneWidget);", "expect(find.text('主题风格'), findsOneWidget);", "w2"],
]);

apply("test/home_order_test.dart", [
  ["      // 右上「⇄ 编排」钮已删；问候卡底部有长按提示行\n      expect(find.text('⇄ 编排'), findsNothing);\n      expect(find.text('长按任意卡片可编排顺序'), findsOneWidget);",
   "      // 右上「⇄ 编排」钮已删；R14-8：长按提示行属教学文案，已摘（入口与编排模式本身不变）\n      expect(find.text('⇄ 编排'), findsNothing);\n      expect(find.text('长按任意卡片可编排顺序'), findsNothing);", "h1"],
  ["tester.getTopLeft(find.textContaining('，CHIST')).dy;", "tester.getTopLeft(find.textContaining('，本地用户')).dy;", "h2"],
]);
console.log("合计 " + hits + " 处");
