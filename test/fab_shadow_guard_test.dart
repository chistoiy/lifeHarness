import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥掉注释（块 + 行）再扫。
///
/// **必须剥**：本文件与业务文件的行注释里就写着 `FloatingActionButton.extended`、
/// `elevation:` 这些被禁词（说明「为什么禁」的文字本身包含禁词），
/// 不剥会把说明当成违规，红灯指到注释上。
String _bare(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  group('FAB 观感守护（日记批2d · 真机报障「右下角加号带正方形底纹」）', () {
    test('lib 下不得再出现原生 FloatingActionButton（一律走 GradFab 圆球）', () {
      // 报障根因：M3 的 `FloatingActionButton` 默认 `shape` 是 16px 圆角的
      // `RoundedRectangleBorder`、底色是实心的 `primaryContainer` —— 真机观感就是
      // 「一个加号压在一块浅色小方块上」。原型所有页面共用一套 `#fab`（56px 圆球 +
      // grad 渐变 + 白图标），所以实现侧必须全走 `GradFab`。
      //
      // 只匹配**调用**：`FloatingActionButtonLocation.endFloat`（Scaffold 参数）不在此列。
      final re = RegExp(
          r'FloatingActionButton\s*\(|FloatingActionButton\.extended\s*\(');
      final bad = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (re.hasMatch(_bare(f.path))) bad.add(f.path);
      }
      expect(
        bad,
        isEmpty,
        reason: '这些文件又用了原生 FloatingActionButton（M3 方块底）：$bad\n'
            '改用 `core/widgets/grad_fab.dart` 的 `GradFab`。',
      );
    });

    test('GradFab 不得用 Material.elevation 画阴影', () {
      // `Material(elevation: >0)` 走 `PhysicalShape` 的 `Canvas.drawShadow`，
      // 圆路径在部分 Android GPU（Skia fast-shadow 近似）上会退化成**方形阴影块**。
      // 源码里形状一直是圆，所以肉眼读代码找不到「方」从哪来——方的是阴影。
      // 阴影统一由 `Ink`/`BoxDecoration` 的圆形 `boxShadow` 承担（普通 canvas 圆）。
      final code = _bare('lib/core/widgets/grad_fab.dart');
      expect(
        RegExp(r'elevation\s*:').hasMatch(code),
        isFalse,
        reason: 'GradFab 里出现了 elevation：加回来真机方底就会复现。'
            '阴影请走 boxShadow（圆形）。',
      );
      expect(code.contains('boxShadow'), isTrue,
          reason: '圆球阴影由 boxShadow 承担，别整个删掉（删了球会贴在页面上）');
      expect(code.contains('BoxShape.circle'), isTrue,
          reason: '球体与阴影都必须是圆');
      expect(code.contains('MaterialType.transparency'), isTrue,
          reason: 'Material 只用来提供 ink 层，不能画 surface 底（要求透明底）');
    });

    test('日记扇形项与书架 FAB 同口径：无 elevation、容器为圆', () {
      for (final p in const [
        'lib/features/journal/presentation/widgets/diary_fan_fab.dart',
        'lib/features/read/presentation/shelf/shelf_fab.dart',
      ]) {
        final code = _bare(p);
        expect(RegExp(r'elevation\s*:').hasMatch(code), isFalse,
            reason: '$p 里出现了 elevation：小圆钮的方影在深底上尤其显眼');
        expect(code.contains('BoxShape.circle'), isTrue,
            reason: '$p 的容器必须是圆形');
      }
    });

    test('日记页 FAB 仍走 DiaryFanFab（未退回裸 GradFab 或原生 FAB）', () {
      final code = _bare('lib/features/journal/presentation/journal_page.dart');
      expect(code.contains('DiaryFanFab'), isTrue,
          reason: '日记页 FAB 是「单击新建 / 长按扇形筛选·设置」，'
              '退回裸 GradFab 会丢掉筛选与设置两个入口（顶行三枚图标早已移除）');
    });
  });
}
