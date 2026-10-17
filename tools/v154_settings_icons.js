/* 批D1（R14-7 落 Flutter）：设置族入口行 emoji → 线性图标
   口径：与已确认原型 tools/proto_r147_svg.js 的图标语义一一对应；
   _EntryRow/_SetIc 的 emoji 形参改为可选（默认 ''），行内只留 iconWidget。
   每处替换断言命中 1 次，改完打印体积差。用法：node tools/v154_settings_icons.js */
const fs = require("fs");
let hits = 0;
function apply(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  const before = s.length;
  for (const [old_, neu, label] of pairs) {
    const n = s.split(old_).length - 1;
    if (n !== 1) {
      console.error("!! [" + F + "][" + (label || "") + "] 命中 " + n + " 次（要求 1）：" + old_.slice(0, 64));
      process.exit(1);
    }
    s = s.replace(old_, neu);
    hits++;
  }
  fs.writeFileSync(F, s);
  console.log("  " + F + "：" + pairs.length + " 处 · " + before + " → " + s.length + "（" + (s.length - before) + "）");
}

/* 图标工厂：与既有两行（运行日志/图片清理）同款写法保持一致 */
const ic = (name, color, indent) => "iconWidget: Icon(Icons." + name + ",\n" + indent + "size: 18, color: const Color(" + color + ")),\n" + indent;

const SP = "lib/features/settings/presentation/settings_page.dart";
apply(SP, [
  /* ① 形参改可选：行内不再传 emoji */
  ["    required this.emoji,\n    this.iconWidget,", "    this.emoji = '',\n    this.iconWidget,", "EntryRow-emoji-optional"],
  ["  final String emoji;\n\n  /// 批2e：新条目按「UI 禁 emoji」规范传线性图标，替换 emoji 文本位。",
   "  /// R14-7：入口位一律线性图标（UI 禁 emoji 硬规矩）；本字段仅为历史行保留，新行不传。\n  final String emoji;\n\n  /// 批2e：新条目按「UI 禁 emoji」规范传线性图标，替换 emoji 文本位。",
   "EntryRow-doc"],
  ["  const _SetIc({required this.emoji, this.text = false});", "  const _SetIc({this.emoji = '', this.icon, this.text = false});", "SetIc-signature"],
  ["  final String emoji;\n  final bool text;", "  final String emoji;\n\n  /// R14-7：外观页小方格图标位（禁 emoji，传线性图标）。\n  final IconData? icon;\n  final bool text;", "SetIc-fields"],
  ["      child: Text(emoji,\n          style: TextStyle(\n              fontSize: text ? 13 : 16,\n              fontWeight: text ? FontWeight.w800 : FontWeight.normal)),",
   "      child: icon != null\n          ? Icon(icon, size: 18, color: scheme.onSurfaceVariant)\n          : Text(emoji,\n              style: TextStyle(\n                  fontSize: text ? 13 : 16,\n                  fontWeight: text ? FontWeight.w800 : FontWeight.normal)),",
   "SetIc-build"],

  /* ② 11 个入口行换图标（颜色沿用该行底色同源色） */
  ["                    emoji: '☁️',\n", "                    " + ic("cloud_outlined", "0xFF10B981", "                    "), "row-sync"],
  ["                    emoji: '🔔',\n", "                    " + ic("notifications_none", "0xFF6366F1", "                    "), "row-notify"],
  ["                    emoji: '🤖',\n", "                    " + ic("memory", "0xFF8B5CF6", "                    "), "row-ai"],
  ["                    emoji: '🏷',\n", "                    " + ic("label_outline", "0xFFF97316", "                    "), "row-cats"],
  ["                    emoji: '🧰',\n", "                    " + ic("handyman_outlined", "0xFF6B7280", "                    "), "row-tools"],
  ["                    emoji: '🧩',\n", "                    " + ic("extension_outlined", "0xFF6B7280", "                    "), "row-plugin"],
  ["                    emoji: '🎨',\n", "                    " + ic("palette_outlined", "0xFF0EA5E9", "                    "), "row-appearance"],
  ["                    emoji: '📔',\n", "                    " + ic("menu_book_outlined", "0xFF8B5CF6", "                    "), "row-recmg"],

  /* ③ 标题/按钮装饰 emoji 前缀 → 纯文字 */
  ["child: Text('🧭 底部导航栏自定义',", "child: Text('底部导航栏自定义',", "title-nav"],
  ["child: const Text('🧩 主页编排直达（或长按卡片）›',", "child: const Text('主页编排直达（或长按卡片）›',", "title-dashorder"],
  ["child: Text('🎨 主题风格',", "child: Text('主题风格',", "title-themestyle"],
  ["child: Text('🛍 更多主题 ›',", "child: Text('更多主题 ›',", "title-moretheme"],
  ["Text('本地模式 · 无账号 🔒 · 已记录 $streak 天',", "Text('本地模式 · 无账号 · 已记录 $streak 天',", "sub-lock"],

  /* ④ _SetIc 两处图标位 */
  ["_SetIc(emoji: '🌙')", "_SetIc(icon: Icons.dark_mode_outlined)", "setic-moon"],
  ["_SetIc(emoji: '🎨')", "_SetIc(icon: Icons.palette_outlined)", "setic-palette"],
]);
