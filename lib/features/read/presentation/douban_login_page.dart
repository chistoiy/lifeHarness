import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../data/isbn_enrich.dart';
import 'read_sheets.dart' show readToast;

/// 豆瓣登录 Cookie 获取页（2026-09-27 改口：替代手动粘贴——手机浏览器抠
/// Cookie 太麻烦）。应用内打开豆瓣登录页，用户自行登录（短信/扫码均可），
/// 点「完成」后经 Android 原生 CookieManager 提取 `.douban.com` 域 cookie
/// （含 HttpOnly 登录态 `dbcl2`，JS 的 document.cookie 读不到，必须走原生口）。
///
/// 口径：
/// - 校验必须含 `dbcl2`（豆瓣登录会话标记）——没有就判「未检测到登录」，
///   不存半吊子 cookie；
/// - 结果只写 SharedPreferences `read.dbCookie`（不进 settings 表＝备份导出
///   带不走；AppLog 只记事件不记值）；
/// - 页面本身不做任何自动登录/模拟点击，凭据只经用户之手进豆瓣官方页。
class DoubanLoginPage extends ConsumerStatefulWidget {
  const DoubanLoginPage({super.key});

  static const String prefsKey = 'read.dbCookie';

  @override
  ConsumerState<DoubanLoginPage> createState() => _DoubanLoginPageState();
}

/// 把提取到的 cookie 对拼成请求头；无登录标记 `dbcl2` 一律判未登录返回 null
/// （纯函数便于测试钉住「不存半吊子 cookie」口径）。
String? doubanCookieHeader(Map<String, String> cookies) {
  if (!cookies.containsKey('dbcl2')) return null;
  return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

class _DoubanLoginPageState extends ConsumerState<DoubanLoginPage> {
  late final WebViewController _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? false) {
              AppLog.add('豆瓣登录页主框架加载失败 ${e.errorCode} ${e.description}',
                  level: LhLevel.warn);
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://accounts.douban.com/passport/login/'),
      );
    // 第三方 cookie 放行：登录链路会跨 accounts/www/book 子域写会话。
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, true);
    }
  }

  /// 取 cookie → 校验登录标记 → 落 prefs → 即时生效。
  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cm = AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      );
      // www 与 book 两域各取一次（父域 .douban.com 的会话两边都可见）。
      final all = <String, String>{};
      for (final host in ['https://www.douban.com/', 'https://book.douban.com/']) {
        for (final c in await cm.getCookies(Uri.parse(host))) {
          all[c.name] = c.value;
        }
      }
      if (!mounted) return;
      final header = doubanCookieHeader(all);
      if (header == null) {
        readToast(context, '未检测到登录 · 请先完成登录');
        return;
      }
      await ref.read(sharedPreferencesProvider).setString(
            DoubanLoginPage.prefsKey,
            header,
          );
      DoubanCookie.set(header);
      if (!mounted) return;
      AppLog.add('豆瓣登录 Cookie 已获取并保存到本机（${all.length} 项）',
          level: LhLevel.info);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppLog.add('豆瓣 Cookie 提取失败：$e', level: LhLevel.error);
      readToast(context, '提取失败 · 见日志');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('豆瓣登录'),
        leading: TextButton(
          key: const ValueKey('dbl-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(fontSize: 11.5)),
        ),
        actions: [
          _busy
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  key: const ValueKey('dbl-done'),
                  onPressed: _finish,
                  child: const Text('完成', style: TextStyle(fontSize: 11.5)),
                ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
