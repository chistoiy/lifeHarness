/// LH-F01 · 三档字体角色链（唯一事实源＝《docs/UI组件规范.md》〇A 节）。
///
/// 口径：**正文衬线 / 标题与一切 UI 标签无衬线 / 数字·代码等宽**，三档全部走
/// **系统回落链，不随包字体文件**（思源宋体一字重全量 8~20MB，与《APK包体压缩可行性》
/// 「无无损压缩空间」冲突，已否决）。串内容与原型 `:root{--f-body/--f-ui/--f-code}`
/// **逐字符一致**——两边各写一份迟早分叉，所以 Flutter 侧也只允许这一处定义。
///
/// 平台事实：链里的 `Microsoft YaHei` 只在 Windows（开发期预览兜底），安卓真机取不到；
/// 安卓/鸿蒙的衬线回落到 Noto Serif CJK、无衬线回落到 Noto Sans CJK。链尾的
/// `serif / sans-serif / monospace` 正是 Android 的系统泛族别名，minikin 认得；
/// `system-ui` 是 CSS 关键字，Flutter 里取不到会被跳过（保留只为与原型同串可审计）。
library;

import 'package:flutter/painting.dart';

/// 一档角色＝链首 + 回落链。[first] 给 `TextStyle.fontFamily`，[fallback] 给
/// `TextStyle.fontFamilyFallback`（两者必须成对使用，只取其一＝换机器就变字）。
class LhFontRole {
  const LhFontRole(this.role, this.first, this.fallback);

  /// 角色名（`body` / `ui` / `code`，进守护断言与调试标签）。
  final String role;
  final String first;
  final List<String> fallback;

  /// 只带字族的空样式（调用方再叠字号/行高/颜色）。
  TextStyle get style =>
      TextStyle(fontFamily: first, fontFamilyFallback: fallback);

  /// 把本角色套到既有样式上（`copyWith` 会带上 fallback，两处同源不会走偏）。
  TextStyle apply(TextStyle base) =>
      base.copyWith(fontFamily: first, fontFamilyFallback: fallback);
}

/// 正文（长文）＝衬线链。
const LhFontRole kFontBody = LhFontRole('body', 'Noto Serif SC', [
  'Source Han Serif SC',
  'Songti SC',
  'STSong',
  'SimSun',
  'Georgia',
  'serif',
]);

/// UI（标题·底栏·按钮·标签·表单·书名）＝无衬线链。
const LhFontRole kFontUi = LhFontRole('ui', 'Inter', [
  'Noto Sans SC',
  'Source Han Sans SC',
  'PingFang SC',
  'Microsoft YaHei',
  'system-ui',
  'sans-serif',
]);

/// 数字·代码·计时·日志＝等宽链。
const LhFontRole kFontCode = LhFontRole('code', 'ui-monospace', [
  'JetBrains Mono',
  'Consolas',
  'Menlo',
  'monospace',
]);

/// 阅读器字体目录的三值族 → 角色链（`ReaderCfg.font` / `ReaderLayout.font`）。
///
/// `'system'`＝**不指定**：这是老用户落库里的旧默认值，白名单必须留着、读得回来，
/// 新默认已改 `'serif'`（产品 2026-10-02 拍板：已手动选过字体的老用户保持其选择）。
LhFontRole? lhFontRoleOfReaderFont(String font) => switch (font) {
      'serif' => kFontBody,
      'hei' => kFontUi,
      'mono' => kFontCode,
      _ => null,
    };
