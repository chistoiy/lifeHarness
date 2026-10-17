import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_widget.dart';
import 'package:lifeharness/features/widget/domain/widget_binding.dart';

/// 小组件批A · **渲染层**守护（打卡-单习惯 2×2）。
///
/// 这一层是「Dart 算好 → 原生只画」的接缝，两侧任何一处口径漂移都表现为
/// **桌面静默错**（不崩、不报错，只是显示不对或永远停在占位），所以逐条钉死：
///
/// ① 编码（Dart 唯一出口）字段序/分隔符/空名/长名不截断；
/// ② 跨语言同源（键名、类名、绑定键前缀、种类常量、分隔符）；
/// ③ 失效三态文案逐字 ＋ **判定优先级**（无快照 > 无绑定 > 源失效）；
/// ④ 渲染语句（状态点切换、已打卡真不可点、连击 0 不显示）；
/// ⑤ 布局（四件套 id 齐备、占位默认隐藏、状态点用白名单控件）；
/// ⑥ 绑定解析与预选认领（三条安全线）＋ 配置页无感回写。
void main() {
  const kt = 'android/app/src/main/kotlin/com/lifeharness/lifeharness';
  const res = 'android/app/src/main/res';

  final support = File('$kt/LhWidgetSupport.kt').readAsStringSync();
  final habit = File('$kt/HabitCheckWidget.kt').readAsStringSync();
  final cfg = File('$kt/WidgetConfigActivity.kt').readAsStringSync();
  final layout = File('$res/layout/lh_widget_habit.xml').readAsStringSync();
  final strings = File('$res/values/strings.xml').readAsStringSync();

  group('① 编码（Dart 唯一出口）', () {
    test('字段序 name/streak/done，done 位 1|0', () {
      final out = encodeWidgetHabitItems(const <WidgetHabitItem>[
        WidgetHabitItem(name: '早起', streak: 12, done: false),
        WidgetHabitItem(name: '喝水', streak: 0, done: true),
      ]);
      final rows = out.split(kTodoItemSep);
      expect(rows.length, 2);
      expect(rows[0].split(kTodoFieldSep), <String>['早起', '12', '0']);
      expect(rows[1].split(kTodoFieldSep), <String>['喝水', '0', '1']);
    });

    test('控制字符被剔除、两端空白被 trim、空名整行丢弃', () {
      final out = encodeWidgetHabitItems(const <WidgetHabitItem>[
        WidgetHabitItem(name: '  读\u001e书  ', streak: 3, done: true),
        WidgetHabitItem(name: '   ', streak: 9, done: true),
        WidgetHabitItem(name: '早\u001f起', streak: 1, done: false),
      ]);
      final rows = out.split(kTodoItemSep);
      // 空白名整行丢弃 ⇒ 只剩两条（否则桌面会出现一条没有名字的空行）。
      expect(rows.length, 2);
      expect(rows[0].split(kTodoFieldSep).first, '读 书');
      expect(rows[1].split(kTodoFieldSep).first, '早 起');
    });

    test('空表 ⇒ 空串（不是 null、不是占位符）', () {
      expect(encodeWidgetHabitItems(const <WidgetHabitItem>[]), '');
    });

    test('名字**不截断**（它是绑定键，裁了就对不上绑定值）', () {
      // ⚠ 样例必须**长于**任何可能的裁剪阈值（本条曾被 24 字的样例骗过：
      //   恰好卡在 `length > 24` 边界外，变异刀「加截断」竟然还是绿的）。
      final long = '这是一个非常非常长的习惯名字用来验证不截断的行为而且还要再长一些才行';
      expect(long.length, greaterThan(24), reason: '样例须越过 24 字边界，否则测不出截断');
      final out = encodeWidgetHabitItems(<WidgetHabitItem>[
        WidgetHabitItem(name: long, streak: 1, done: false),
      ]);
      expect(out.split(kTodoFieldSep).first, long,
          reason: '一旦截断，实例绑定里存的完整名字就永远匹配不上 ⇒ 桌面恒「内容已失效」');
    });
  });

  group('② 跨语言同源（禁两套）', () {
    test('键名与类名', () {
      expect(LhWidgetKeys.habitItems, 'habit_items');
      expect(support, contains('"habit_items"'));
      expect(LhWidgetNames.habitCheck, 'HabitCheckWidget');
      expect(support, contains('const val PROVIDER_HABIT = "HabitCheckWidget"'));
    });

    test('绑定键前缀 / 种类 / 分隔符 两侧逐字一致', () {
      // 存储位置＝Flutter legacy 偏好文件的 `flutter.` 前缀 + `desktop.widget_bind.`。
      expect(kWidgetBindKeyPrefix, 'desktop.widget_bind.');
      expect(support, contains(r'FLUTTER_KEY_PREFIX + "desktop.widget_bind."'));
      expect(kWidgetBindPendingKey, 'desktop.widget_bind.pending');
      expect(support,
          contains(r'const val PREF_WIDGET_BIND_PENDING = PREF_WIDGET_BIND_PREFIX + "pending"'));
      expect(kWidgetKindHabit, 'habit');
      expect(support, contains('const val WIDGET_KIND_HABIT = "habit"'));
      expect(kWidgetBindFieldSep, '\u001f');
      expect(support, contains(r"const val WIDGET_BIND_FIELD_SEP = '\u001f'"));
      // 打卡状态表复用待办那对分隔符：两套各写一遍必漂移。
      expect(support, contains(r"const val TODO_ITEM_SEP = '\u001e'"));
      expect(support, contains(r"const val TODO_FIELD_SEP = '\u001f'"));
    });

    test('预选有效期两侧同值（不同值 ⇒ 一边认领一边已作废）', () {
      expect(kWidgetBindPendingTtlMs, 2 * 60 * 1000);
      expect(kWidgetBindPendingSkewMs, 60 * 1000);
      expect(support, contains('WIDGET_BIND_PENDING_TTL_MS = 2 * 60 * 1000L'));
      expect(support, contains('WIDGET_BIND_PENDING_SKEW_MS = 60 * 1000L'));
    });
  });

  group('③ 失效三态（文案逐字 ＋ 优先级）', () {
    test('三条文案与产品 2026-10-17 勾定逐字一致', () {
      expect(strings, contains('<string name="lh_widget_wait_data">等待数据</string>'));
      expect(strings,
          contains('<string name="lh_widget_no_binding">未选择内容，点此设置</string>'));
      expect(strings, contains('<string name="lh_widget_source_invalid">内容已失效，点此重新选择</string>'));
    });

    test('判定顺序：无快照 → 无绑定 → 源失效（源码次序即优先级）', () {
      // 首装/清数据后先显示「等待数据」，等快照到了才暴露绑定态——否则用户会
      // 误以为「是我没选」。这个次序写反，症状是「明明选了却显示未选择」。
      final iSnap = habit.indexOf('LhWidget.hasSnapshot(data)');
      final iBind = habit.indexOf('LhWidget.boundHabitName(context, appWidgetId)');
      final iRow = habit.indexOf('readHabitRows(data).firstOrNull');
      expect(iSnap, greaterThan(0), reason: '缺无快照判定');
      expect(iBind, greaterThan(iSnap), reason: '无绑定判定必须排在无快照之后');
      expect(iRow, greaterThan(iBind), reason: '源失效判定必须排在无绑定之后');
    });

    test('三态共用同一个占位控件（不另画三套布局）', () {
      expect(habit, contains('private fun renderPlaceholder('));
      // 三处调用只换文案资源，不换布局。
      for (final s in <String>[
        'R.string.lh_widget_wait_data',
        'R.string.lh_widget_no_binding',
        'R.string.lh_widget_source_invalid',
      ]) {
        expect(habit, contains('renderPlaceholder(context, views, $s)'));
      }
      expect(layout, contains('@+id/lh_wg_ph'));
    });
  });

  group('④ 渲染语句（原生）', () {
    test('状态点用 setBackgroundResource 在两枚 drawable 间切（不用 ImageView src）', () {
      expect(habit, contains('"setBackgroundResource"'));
      expect(habit, contains('R.drawable.lh_wg_dot_on'));
      expect(habit, contains('R.drawable.lh_wg_dot_off'));
      // 状态点必须是 ImageView（RemoteViews 白名单内），且带背景而非 src——
      // setInt("setBackgroundResource") 对任何 View 生效，改 src 则要另一套 API。
      expect(layout, contains('@drawable/lh_wg_dot_off'));
      for (final f in <String>['res/drawable/lh_wg_dot_on.xml', 'res/drawable/lh_wg_dot_off.xml']) {
        expect(File('android/app/src/main/$f').existsSync(), isTrue, reason: '缺 $f');
      }
    });

    test('已打卡：按钮换淡底 + 字色转次文本 + **真不可点**', () {
      expect(habit, contains('R.drawable.lh_wg_habit_btn_off'));
      expect(habit, contains('R.color.lh_wg_sub'));
      // 「灰着但点得动、点了没反应」是最糟的一种；必须显式撤掉点击意图。
      expect(habit, contains('views.setOnClickPendingIntent(R.id.lh_wg_btn, null)'),
          reason: '已打卡态必须撤掉按钮点击意图，否则有点按反馈却毫无反应');
    });

    test('连击 0 不显示「连击 0 天」（0 天不是成绩）', () {
      expect(habit, contains('row.streak > 0'));
      expect(habit, contains('R.string.lh_widget_habit_streak0_done'));
      expect(habit, contains('R.string.lh_widget_habit_streak0'));
      // 四档文案都在 strings 里（streak>0 的两档 + 0 的两档）。
      for (final k in <String>[
        'lh_widget_habit_streak',
        'lh_widget_habit_streak_done',
        'lh_widget_habit_streak0',
        'lh_widget_habit_streak0_done',
      ]) {
        expect(strings, contains('name="$k"'), reason: '缺文案 $k');
      }
      expect(strings, contains('连击 %1\$d 天'), reason: '带连击的两档须带天数占位');
    });

    test('点击一律走 C15 唯一出口 clickIntent（禁自拼 Intent）', () {
      final clicks = RegExp(r'setOnClickPendingIntent\(').allMatches(habit).length;
      final viaHelper =
          RegExp(r'LhWidget\.clickIntent\(').allMatches(habit).length;
      expect(clicks, greaterThanOrEqualTo(2));
      expect(viaHelper, greaterThanOrEqualTo(2),
          reason: '有 $clicks 处点击、只有 $viaHelper 处走 clickIntent ⇒ 有人自拼了 Intent');
      expect(habit, contains('LhWidget.SEG_HABIT_CHECK'));
      expect(support, contains('const val SEG_HABIT_CHECK = "habit/check"'));
    });
  });

  group('⑤ 布局（RemoteViews 口径）', () {
    test('四件套 id 齐备（漏一个 ⇒ 该件永远不显示）', () {
      for (final id in <String>[
        'lh_wg_title',
        'lh_wg_habit',
        'lh_wg_status_row',
        'lh_wg_dot',
        'lh_wg_status',
        'lh_wg_gap',
        'lh_wg_ph',
        'lh_wg_btn',
      ]) {
        expect(layout, contains('@+id/$id'), reason: '布局缺件：$id');
      }
    });

    test('占位控件默认 gone（正常态不许露出占位文案）', () {
      final ph = RegExp(r'<TextView[^>]*@\+id/lh_wg_ph[\s\S]*?/>')
          .firstMatch(layout)
          ?.group(0) ??
          '';
      expect(ph, contains('android:visibility="gone"'), reason: '占位默认必须 gone：$ph');
    });

    test('状态点与撑开器都不许用裸 <View>（8150 装机实锤）', () {
      final src = layout.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      expect(src, isNot(contains('<View')),
          reason: 'android.view.View 不在 RemoteViews 白名单 ⇒ Launcher 抛 InflateException');
      final dot = RegExp(r'<ImageView[^>]*@\+id/lh_wg_dot').hasMatch(src);
      expect(dot, isTrue, reason: '状态点须用 ImageView（白名单内）');
    });
  });

  group('⑥ 绑定解析与预选认领', () {
    test('绑定值三段落逐段校验（宁写「未选择」也不猜一个习惯）', () {
      expect(support, contains('fun boundHabitName('));
      expect(support, contains('fun habitNameOf('));
      expect(support, contains('if (f.size != 3) return null'));
      expect(support, contains('if (f[0].trim() != WIDGET_TARGET_KIND_NAV) return null'));
      expect(support, contains('if (f[1].trim() != WIDGET_REF_HABIT) return null'));
    });

    test('实例键优先、回落全局默认（R2 老实例兜底）', () {
      final body = RegExp(r'fun boundHabitName[\s\S]*?\n    \}')
          .firstMatch(support)
          ?.group(0) ??
          '';
      final iInst = body.indexOf(r'PREF_WIDGET_BIND_PREFIX$appWidgetId');
      final iDef = body.indexOf('PREF_WIDGET_BIND_DEFAULT');
      expect(iInst, greaterThan(0), reason: '缺实例键读取');
      expect(iDef, greaterThan(iInst), reason: '实例键必须优先于全局默认：$body');
    });

    test('预选认领三条安全线：种类不符不动 / 过期作废 / 脏值清掉', () {
      final body = RegExp(r'fun consumePendingBind[\s\S]*?\n    \}')
          .firstMatch(support)
          ?.group(0) ??
          '';
      expect(body, isNotEmpty, reason: '缺 consumePendingBind');
      // ① 种类不符 ⇒ **不动**它（不是给这类的预选，留给真正那枚认领）。
      expect(body, contains('if (f[0].trim() != WIDGET_KIND_HABIT) return false'));
      // ② 过期/回拨超容忍 ⇒ 清掉（否则取消后的下一次会被误吃）。
      expect(body, contains('now - at <= WIDGET_BIND_PENDING_TTL_MS'));
      expect(body, contains('now - at >= -WIDGET_BIND_PENDING_SKEW_MS'));
      // ③ 段数不对 ⇒ 清掉（脏残留会一直挡住后面的正常配置）。
      expect(body, contains('if (f.size != 5)'));
      // 命中后：写本实例键 **并** remove 交接位（一次性）。
      expect(body, contains(r'PREF_WIDGET_BIND_PREFIX$appWidgetId'));
      expect(body, contains('.remove(PREF_WIDGET_BIND_PENDING)'));
      // 顺序：种类校验必须排在「写本实例键」之前——否则别人的预选会被我们认领走。
      expect(body.indexOf('WIDGET_KIND_HABIT'),
          lessThan(body.indexOf(r'PREF_WIDGET_BIND_PREFIX$appWidgetId')),
          reason: '种类校验必须排在实际认领（写实例键）之前');
    });

    test('配置页无感回写：认领 + 直接 RESULT_OK 收摊（用户看不到配置页）', () {
      expect(cfg, contains('private fun providerClassName()'));
      expect(cfg, contains('LhWidget.PROVIDER_HABIT'));
      expect(cfg, contains('LhWidget.consumePendingBind(this, widgetId)'));
      // 必须在 setContentView **之前**返回（否则配置页会闪一下再关）。
      final iClaim = cfg.indexOf('LhWidget.consumePendingBind(this, widgetId)');
      final iSetContent = cfg.indexOf('setContentView(');
      expect(iClaim, greaterThan(0));
      expect(iClaim, lessThan(iSetContent),
          reason: '无感回写必须早于 setContentView，否则用户会看到配置页闪一下');
      expect(cfg, contains('RESULT_OK'));
      // 兜底：类名取不到也按绑定型处理（配置阶段系统可能还没建好记录）。
      expect(cfg, contains('pcls == null || pcls == LhWidget.PROVIDER_HABIT'));
    });

    test('预选键不进实例清单（键尾不是数字，loadAll 必须跳过）', () {
      // 否则「预选」会被当成一枚实例去 prune，绑好的实例反被清掉。
      final store = File('lib/features/widget/data/widget_binding_store.dart')
          .readAsStringSync();
      expect(store, contains("tail == 'pending'"),
          reason: 'loadAll 未跳过 pending ⇒ 预选被当实例参与清理');
      expect(store, contains("tail == 'default'"));
    });
  });
}
