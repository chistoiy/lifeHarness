import 'package:flutter/material.dart';

import 'theme_tokens.dart';

export 'theme_tokens.dart' show ThemeTokens, ThemeMeta;

/// 通过 [ThemeExtension] 把设计令牌注入 widget 树，页面可 `context.tokens` 取用。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.tokens});

  final ThemeTokens tokens;

  /// 无扩展时的兜底（内置默认主题/测试环境）。
  static const AppTokens fallback = AppTokens(tokens: ThemeTokens.defaults);

  @override
  AppTokens copyWith({ThemeTokens? tokens}) =>
      AppTokens(tokens: tokens ?? this.tokens);

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    // 令牌为离散主题，不做逐值插值，直接切换。
    return t < 0.5 ? this : other;
  }
}

/// 由设计令牌构建 [ThemeData]（Material 3）。
class AppTheme {
  const AppTheme._();

  static ThemeData build(ThemeTokens tokens, {required bool isDark}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: tokens.accent,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.page,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[AppTokens(tokens: tokens)],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.page,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          fontFamily: tokens.appFont,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          side: tokens.cardBorder == Colors.transparent
              ? BorderSide.none
              : BorderSide(color: tokens.cardBorder),
        ),
      ),
      scaffoldBackgroundColor: tokens.page,
      // V1.28⑥ 全局统一 toast 风格（原型 #toast：深 slate 半透明胶囊 · 白小字 · 浮起）。
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xE60F172A),
        contentTextStyle:
            TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28))),
        elevation: 6,
        width: 320,
      ),
      dividerColor: tokens.cardBorder,
    );
  }
}

/// 便捷访问：`context.tokens.page` 等。
extension AppTokensContext on BuildContext {
  ThemeTokens get tokens =>
      Theme.of(this).extension<AppTokens>()?.tokens ?? AppTokens.fallback.tokens;

  /// 卡片统一外观（圆角 + 描边 + 令牌阴影）。
  BoxDecoration get cardDecoration => BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: tokens.cardBorder == Colors.transparent
            ? null
            : Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      );
}
