import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/settings/user_settings.dart';

/// 「我的」页结构守护（2026-10-11 批A 立 · 2026-10-12 三版式落实现后扩写）。
///
/// 批A（缺陷修正·零门禁）判据：
/// ③ 提醒读数＝`NotifySettings.scheduledOnCount`，且与通知页同源；
/// ④ 母婴联动行缩进对齐主行文字左缘（60）；
/// ⑤ 关于卡＝logo + 版本行（不再是纯文字一段）。
///
/// 2026-10-12 三版式（原型 p-profile）落实现后：
/// ① 四组分组结构（记录 / 数据与提醒 / 外观与交互 / 系统与维护）且组标题有序；
/// ② 组内行序＝原型原序的连续子序列（记录管理已收回「记录」组卡）；
/// ⑥ myLayout 三档字段与越界收敛 / 往返；
/// ⑦ 三版式组件齐备（旧三宫格 _StatCell 已摘）。
///
/// 交互级判据（切版式真换 UI、持久化落盘）见 `test/profile_layout_switch_test.dart`。
///
/// 走源码/纯函数级而非拉整页：`SettingsPage` 依赖主题注册表 + DB + 天气等重桩，
/// 能静态定性的结论就不必靠重桩整页实跑去逼近（照文件头历史注）。
void main() {
  final src = File('lib/features/settings/presentation/settings_page.dart')
      .readAsStringSync();

  /// 断言 [titles] 在源码中按序出现（indexOf 单调递增）。
  void ordered(List<String> titles, {String where = ''}) {
    var last = -1;
    for (final t in titles) {
      final k = src.indexOf("title: '$t'");
      expect(k, greaterThanOrEqualTo(0), reason: '缺行「$t」$where');
      expect(k, greaterThan(last), reason: '「$t」相对上一行倒序$where');
      last = k;
    }
  }

  group('「我的」页 四组结构（2026-10-12）', () {
    test('① 四组标题齐备且有序', () {
      const groups = ['记录', '数据与提醒', '外观与交互', '系统与维护'];
      var last = -1;
      for (final g in groups) {
        final k = src.indexOf("title: '$g'");
        expect(k, greaterThanOrEqualTo(0), reason: '缺组标题「$g」');
        expect(k, greaterThan(last),
            reason: '组标题「$g」相对上一组倒序（批前＝无分组、一张大卡）');
        last = k;
      }
    });

    test('② 组内行序＝原型原序（连续子序列）', () {
      ordered(['分类管理', '记录管理'], where: '（记录组）');
      ordered(['数据与同步', '提醒通知', 'AI 增强'], where: '（数据与提醒组）');
      ordered(['运行日志', '回收站', '图片存储清理'], where: '（系统与维护组）');
    });

    test('③ 记录管理落在「记录」组卡（_EntryCard）内，非独立单行卡', () {
      final gStart = src.indexOf("title: '记录'");
      final gEnd = src.indexOf("title: '数据与提醒'");
      expect(gStart, greaterThan(0), reason: '找不到「记录」组标题');
      expect(gEnd, greaterThan(gStart), reason: '找不到「数据与提醒」组标题');
      final seg = src.substring(gStart, gEnd);
      expect(seg.contains("ValueKey('entry-recmg')"), isTrue,
          reason: '记录管理不在「记录」组内（批前＝组卡外一张独立 _EntryCard）');
      expect(seg.contains('_EntryCard('), isTrue,
          reason: '「记录」组不是组卡（_EntryCard）');
    });
  });

  group('「我的」页 批A 结构守护', () {
    test('④ 提醒读数＝scheduledOnCount，与通知页同源', () {
      const off = NotifySettings();
      expect(off.scheduledOnCount, 1, reason: '默认只有「日程与任务提醒」开');
      expect(off.copyWith(todoEvent: false).scheduledOnCount, 0);
      expect(
        off
            .copyWith(
                todoEvent: true, diaryReview: true, inboxClean: true)
            .scheduledOnCount,
        3,
      );
      // 习惯提醒 / 免打扰是存储位，不计入（否则「N 项开启」会虚高）。
      expect(off.copyWith(habits: true, dnd: true).scheduledOnCount, 1);
      // 一级页读数吃这一处，不许自己写 OR 布尔。
      expect(src.contains('notify.scheduledOnCount'), isTrue);
      expect(src.contains('s.notify.todoEvent || s.notify.inboxClean'), isFalse,
          reason: '一级页回退成三选一布尔（开 1 项与开 3 项显示相同）');
      final notify = File(
              'lib/features/settings/presentation/notify_settings_page.dart')
          .readAsStringSync();
      expect(notify.contains('n.scheduledOnCount'), isTrue,
          reason: '通知页表头应与一级页同源');
    });

    test('⑤ 母婴联动行缩进对齐主行文字（60 ≠ 旧 52）', () {
      expect(src.contains('EdgeInsets.fromLTRB(60, 0, 16, 12)'), isTrue,
          reason: '联动行左缘未对齐主行文字起点（14+34+12=60）');
      expect(src.contains('EdgeInsets.fromLTRB(52, 0, 16, 12)'), isFalse,
          reason: '批前 52 仍在＝比上下行左移 8px');
    });

    test('⑥ 关于卡＝logo + 版本行', () {
      expect(src.contains("assets/brand/app_icon.png"), isTrue,
          reason: '关于卡缺 logo（批前＝纯文字一段）');
      expect(src.contains("ValueKey('settings-version')"), isTrue,
          reason: '关于卡缺版本行');
      expect(src.contains('appVersionProvider'), isTrue);
      // 版本串必须是安装包真值，不许硬编码。
      expect(RegExp(r"return '[0-9]+\.[0-9]+").hasMatch(src), isFalse,
          reason: '版本号被硬编码（应由 PackageInfo 读安装包）');
    });
  });

  group('「我的」页版式字段（2026-10-12）', () {
    test('⑦ myLayout 默认 hero，未知值收敛到 hero', () {
      const s = UserSettings(
          themeId: 'minimal', mode: ThemeModeOption.system, navIds: []);
      expect(s.myLayout, 'hero', reason: '默认版式应为记录仪表 hero');
      expect(UserSettings.fromMap(const {}).myLayout, 'hero');
      expect(UserSettings.fromMap(const {'myLayout': 'chapters'}).myLayout,
          'chapters');
      expect(UserSettings.fromMap(const {'myLayout': 'minimal'}).myLayout,
          'minimal');
      expect(UserSettings.fromMap(const {'myLayout': 'zzz'}).myLayout, 'hero',
          reason: '越界档未收敛（界面会出现非法版式）');
    });

    test('⑦ myLayout 往返 toMap / copyWith', () {
      final s = UserSettings.fromMap(const {'myLayout': 'minimal'});
      expect(s.toMap()['myLayout'], 'minimal');
      expect(s.copyWith(myLayout: 'chapters').myLayout, 'chapters');
      // 持久化逐字段读写必须带上（否则切档不落盘）。
      final repo = File('lib/core/settings/settings_repository.dart')
          .readAsStringSync();
      expect(repo.contains("_kMyLayout = 'lh.my_layout'"), isTrue);
      expect(repo.contains("setString(_kMyLayout, m['myLayout']!"), isTrue,
          reason: 'save 未写 myLayout（切档刷新即丢）');
      expect(repo.contains("'myLayout': ?_prefs.getString(_kMyLayout)"), isTrue,
          reason: 'load 未读 myLayout');
    });

    test('⑧ 三版式组件齐备（旧三宫格 _StatCell 已摘）', () {
      for (final c in [
        '_ProfileHero',
        '_ProfileIdentityRow',
        '_ReadoutBand',
        '_GroupLabel',
        '_AboutFooter',
      ]) {
        expect(src.contains('class $c'), isTrue, reason: '缺组件 $c');
      }
      expect(src.contains('_StatCell'), isFalse,
          reason: '旧三宫格 _StatCell 未摘（已被身份卡/读数带取代）');
      // 外观页须有版式切换入口（三分段 + setMyLayout）。
      expect(src.contains("ValueKey('my-layout-seg')"), isTrue);
      expect(src.contains('setMyLayout'), isTrue);
    });
  });
}
