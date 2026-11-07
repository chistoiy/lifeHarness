/* 批1a-3：KitSheetScaffold 的 child 形参改名 body（弹层外壳是 title/body/actions 三段结构，
 * 非「容器唯一子项」语义，同时消掉 sort_child_properties_last 提示）
 * 另：_FavSheet._draft 改 late final。
 * 护栏：每处命中数必须为 1，任一处不符即整体零写入 */
const fs = require('fs');
const F = 'lib/features/kits/presentation/kit_sheets.dart';
let raw = fs.readFileSync(F, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
const e = (a, b) => [a.replace(/\n/g, NL), b.replace(/\n/g, NL)];
const EDITS = [
  e('    required this.child,', '    required this.body,'),
  e('  final String title;\n  final Widget child;', '  final String title;\n  final Widget body;'),
  e('Flexible(child: SingleChildScrollView(child: child)),', 'Flexible(child: SingleChildScrollView(child: body)),'),
  e("      title: '⇄ 主卡数据位',\n      child: Column(", "      title: '⇄ 主卡数据位',\n      body: Column("),
  e("      title: '小工具设置',\n      child: Column(", "      title: '小工具设置',\n      body: Column("),
  e("      title: '收藏管理',\n      child: Column(", "      title: '收藏管理',\n      body: Column("),
  e("      title: '最近使用',\n      trailing: KitTwoStageButton(", "      title: '最近使用',\n      trailing: KitTwoStageButton("),
  e('      child: Column(\n        children: [\n          if (recent.isEmpty)', '      body: Column(\n        children: [\n          if (recent.isEmpty)'),
  e('  late List<String> _draft = List.of(widget.initial);', '  late final List<String> _draft = List.of(widget.initial);'),
];
for (const [a, b] of EDITS) {
  const hits = raw.split(a).length - 1;
  if (hits !== 1) {
    console.error(`!! 命中 ${hits}（期望 1）：${JSON.stringify(a).slice(0, 70)}`);
    process.exit(1);
  }
  raw = raw.replace(a, b);
}
fs.writeFileSync(F, raw);
console.log('PASS child→body 改名（4 处调用 + 声明 3 处）· _FavSheet._draft 改 final');
