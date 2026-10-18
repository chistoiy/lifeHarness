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
/// ④ 渲染语句（状态点切换、已打卡＝回 App 改、连击 0 不显示）；
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
    test('字段序 name/streak/done/value/goal/unit/step，done 位 1|0', () {
      final out = encodeWidgetHabitItems(const <WidgetHabitItem>[
        WidgetHabitItem(name: '早起', streak: 12, done: false),
        WidgetHabitItem(name: '喝水', streak: 0, done: true),
      ]);
      final rows = out.split(kTodoItemSep);
      expect(rows.length, 2);
      // 布尔型：数值四段给字面量 0/0/空/0（**不省段**——原生只判 goal > 0，
      // 省段会让解码器要兼容三种长度）。
      expect(rows[0].split(kTodoFieldSep), <String>['早起', '12', '0', '0', '0', '', '0']);
      expect(rows[1].split(kTodoFieldSep), <String>['喝水', '0', '1', '0', '0', '', '0']);
    });

    test('数值型：value/goal/unit/step 四段带真值（整数值不带 .0）', () {
      // 2026-10-18 真机报障：「带数值的打卡也只显示一个打卡，不显示数值修改能力」。
      final out = encodeWidgetHabitItems(const <WidgetHabitItem>[
        WidgetHabitItem(
          name: '喝水',
          streak: 3,
          done: false,
          value: 3,
          goal: 8,
          unit: '杯',
          step: 2,
        ),
      ]);
      expect(out.split(kTodoFieldSep), <String>['喝水', '3', '0', '3', '8', '杯', '2']);
      // 小数量不能被格式化成 0（0.5 杯是最常见的一档）。
      expect(
        encodeWidgetHabitItems(const <WidgetHabitItem>[
          WidgetHabitItem(name: 'x', streak: 0, done: false, value: 0.5, goal: 1),
        ]).split(kTodoFieldSep)[3],
        '0.5',
      );
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
      // 2026-10-18：绑定解析收进 resolveBinding（内含「实例键 → 交接位自认领 →
      // 全局默认」三级兜底），故这里认**调用点**，不再认单个 boundHabitName。
      final iBind = habit.indexOf('resolveBinding(context, appWidgetId)');
      // 2026-10-18 二次报障轮：源失效那行要报「表内 N 条」给排障轨迹用，
      // 故拆成 `val rows = readHabitRows(data)` ＋ `rows.firstOrNull` 两句，
      // 这里认**取行那一步**（`rows.firstOrNull { it.name == name }`）。
      final iRow = habit.indexOf('rows.firstOrNull { it.name == name }');
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

    test('已打卡：按钮换淡底 + 字色转次文本 + **点了回 App 改**（批E）', () {
      expect(habit, contains('R.drawable.lh_wg_habit_btn_off'));
      expect(habit, contains('R.color.lh_wg_sub'));
      // 「灰着但点得动、点了没反应」是最糟的一种。批E 起选**导航**而不是死区：
      // App 内已能改数值／改打卡时间／删记录，桌面这枚灰按钮就是去那里的入口
      //（产品原话「缺少修改打卡记录，删除或修改（打卡时间，数值这一类的）」）。
      expect(
          habit,
          contains(
              'LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_BTN)'),
          reason: '已打卡态按钮必须是「回 App 改」的导航意图，不能是死区');
      expect(habit, contains('const val REQ_BTN'), reason: '与 root 分开取码，互不覆写');
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

    test('点击一律走 LhWidget 出口（clickIntent/habitCheckIntent·禁自拼 Intent）', () {
      final clicks = RegExp(r'setOnClickPendingIntent\(').allMatches(habit).length;
      // 批D：计数型 ± 走 habitAdjustIntent（同样收在 LhWidget 里，禁 provider 自拼）。
      final viaHelper =
          RegExp(r'LhWidget\.(clickIntent|habitCheckIntent|habitAdjustIntent)\(')
              .allMatches(habit)
              .length;
      final viaNull = RegExp(r'setOnClickPendingIntent\(R\.id\.lh_wg_\w+, null\)')
          .allMatches(habit)
          .length;
      expect(clicks, greaterThanOrEqualTo(3));
      // 每处点击都必须是「LhWidget 出口」或「显式撤意图」之一，禁裸拼 Intent。
      expect(viaHelper + viaNull, clicks,
          reason: '有 $clicks 处点击、只有 ${viaHelper + viaNull} 处走 LhWidget 出口'
              '（含显式 null）⇒ 有人自拼了 Intent');
      expect(habit, contains('LhWidget.SEG_HABIT_CHECK'));
      // 批A 交互闭环层：未打卡按钮走**广播直达**（不开 App），root 仍走 C15 起 App。
      expect(habit, contains('LhWidget.habitCheckIntent('));
      expect(habit, contains('LhWidget.habitCheckIntent(context, appWidgetId, row.name)'));
      expect(habit, contains('LhWidget.habitAdjustIntent('));
      expect(support, contains('fun habitCheckIntent('));
      expect(support, contains('fun habitAdjustIntent('));
      expect(support, contains('const val SEG_HABIT_CHECK = "habit/check"'));
      // requestCode 必须每实例一个（PendingIntent 相等性不比 extras：
      // 同码＋FLAG_UPDATE_CURRENT 会让第二枚覆写第一枚里的习惯名）。
      expect(support, contains('REQ_HABIT_CHECK_BASE + appWidgetId'));
      // ± 同理，且**每钮**一个（同码会让「＋」覆写「−」）。
      expect(support, contains('REQ_HABIT_ADJUST_BASE + appWidgetId * 2'));
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
      // 2026-10-18 真机实锤改口：**禁**用 Kotlin/Java 的 `trim()` 洗绑定段——
      // `Character.isWhitespace` 把 0x1C~0x1F 也算空白，而 0x1F 正是字段分隔符，
      // 整串 trim 会把「sub 为空」那条值的尾分隔符吃掉（3 段变 2 段 ⇒ 判非打卡形态）。
      // 故洗段一律走 `clean()`（只剥 ASCII 空格/制表/换行/回车）。
      expect(support, contains('if (clean(f[0]) != WIDGET_TARGET_KIND_NAV) return null'));
      expect(support, contains('if (clean(f[1]) != WIDGET_REF_HABIT) return null'));
      expect(support, contains('private fun clean(s: String): String ='));
      expect(support.contains('(raw ?: "").trim()'), isFalse,
          reason: '绑定值禁整串 trim()（会吃掉尾部分隔符）');
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
      expect(body, contains('if (clean(f[0]) != WIDGET_KIND_HABIT) return false'));
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

  // ===== 2026-10-18 真机三缺陷修复（6175 装机报障）=====
  group('⑦ 真机报障修（点此设置／选了不生效）', () {
    /// 抽一段原生源码（起点 → 下一个声明起点），用于「只在本函数里断言」。
    String bodyOf(String src, String from, String to) {
      final i = src.indexOf(from);
      final j = src.indexOf(to, i + 1);
      expect(i, greaterThan(-1), reason: '缺 $from');
      expect(j, greaterThan(i), reason: '缺边界 $to');
      return src.substring(i, j);
    }

    test('失效三态点击去设置页（写着「点此设置」就必须到设置页）', () {
      // 真机原话：「小组件上写着点击设置，点击后直接打开习惯页面，没有设置的内容」。
      // 三态文案里两态含「点此设置／点此重新选择」，去向却曾是 habit/check（习惯页）。
      final ph = bodyOf(habit, 'private fun renderPlaceholder(', 'private fun renderHabit(');
      expect(ph, contains('LhWidget.SEG_SETTINGS_DESKTOP'),
          reason: '占位态必须指向设置页（重选入口在设置 › 桌面与快捷方式）');
      expect(ph, isNot(contains('SEG_HABIT_CHECK')),
          reason: '占位态禁再指向习惯页——那正是本缺陷本体');
      expect(support, contains('const val SEG_SETTINGS_DESKTOP = "settings/desktop"'));
    });

    test('系统寻址段两侧同源（原生白名单 ↔ Dart kSystemLaunchPaths）', () {
      // 段即 id：不进动作表（那张表喂三张用户可勾选清单），故两侧各有一份登记。
      expect(support, contains('const val SEG_SETTINGS_DESKTOP = "settings/desktop"'));
      final main = File('$kt/MainActivity.kt').readAsStringSync();
      expect(main, contains('"settings/desktop" to "settings/desktop"'),
          reason: '原生 LH_WHITELIST 缺该段 ⇒ enqueueLaunch 静默丢弃');
      expect(main, contains('"settings"'),
          reason: '原生 LH_NS 缺 settings ⇒ 段首 ns 校验不过');
      final actions =
          File('lib/core/platform/desktop_actions.dart').readAsStringSync();
      expect(actions, contains("'settings/desktop': '/settings/desktop'"));
      expect(actions, contains("'settings',"));
    });

    test('实例自认领预选绑定（MIUI 不跑配置页也能绑上）', () {
      // 真机原话：「app内添加点击习惯打卡没有让先选习惯，到桌面后打卡里面没有打卡内容」。
      // 根因：先选后落第④步靠系统拉起 android:configure，MIUI 桌面实测不拉。
      final rb = bodyOf(habit, 'private fun resolveBinding(', 'private fun renderPlaceholder(');
      expect(rb, contains('LhWidget.consumePendingBind(context, appWidgetId)'),
          reason: '实例必须自己认领交接位——不能只指望配置页');
      // 认领后要重新读一次本实例键（认领写的就是它），否则拿到的还是 null。
      expect(RegExp(r'instanceHabitName\(context, appWidgetId\)').allMatches(rb).length,
          greaterThanOrEqualTo(2),
          reason: '认领后必须重读绑定，否则白认领');
      // 2026-10-18 真机二次实锤：认领必须排在**默认键之前**——
      // 原顺序「实例键 → 默认键 → 认领」使默认键一旦有值，交接位就永远没人认领，
      // 加第二枚打卡枚时两枚都显示最后选的那个习惯（用户原话「添加多个不同打卡
      // 后，会全部变成最后添加的打卡内容」）。
      expect(
          rb.indexOf('LhWidget.consumePendingBind(context, appWidgetId)'),
          lessThan(rb.indexOf('LhWidget.defaultHabitName(context)')),
          reason: '认领必须先于默认键回落，否则新实例全吃同一个默认');
    });

    test('Dart 侧落点补默认绑定回落 + 当场重绘（选了立刻看得见）', () {
      final mounts =
          File('lib/shared/linkage/widget_bind_mounts.dart').readAsStringSync();
      final iPick = mounts.indexOf('final picked = await showWidgetTargetPicker(');
      final iPending = mounts.indexOf('setPendingTarget(kWidgetKindHabit, picked)');
      final iDefault = mounts.indexOf('setGlobalDefault(picked)');
      final iPin = mounts.indexOf('await pinDesktopWidget(kWidgetKindHabit)');
      expect(iPending, greaterThan(iPick), reason: '缺预选交接位');
      expect(iDefault, greaterThan(iPending), reason: '缺默认绑定回落（MIUI 不跑配置页的兜底）');
      expect(iPin, greaterThan(iDefault), reason: '默认绑定必须在 pin 之前写好');
      expect(mounts, contains('HomeWidget.updateWidget(androidName: LhWidgetNames.habitCheck)'),
          reason: '选完必须推一把重绘——已在桌面的未绑定枚不会自己醒');
    });
  });

  group('⑧ 数值型（记量）习惯（2026-10-18 真机报障补）', () {
    /// 抽一段函数体（`from` 起点 → `to` 起点前一位）；找不到就红。
    String bodyOf(String src, String from, String to) {
      final i = src.indexOf(from);
      final j = src.indexOf(to, i);
      expect(i, greaterThanOrEqualTo(0), reason: '源码里找不到「$from」——函数被改名/删了？');
      expect(j, greaterThan(i), reason: '源码里找不到「$to」——抽取区间不成立');
      return src.substring(i, j);
    }

    test('原生按 goal > 0 分流到数值分支（与 Dart isNumeric 同一判据）', () {
      // 报障原话：「带数值的打卡也只显示一个打卡，不显示数值修改能力」。
      final rh = bodyOf(habit, 'private fun renderHabit(', 'private fun renderNumeric(');
      expect(rh, contains('if (row.isNumeric)'), reason: '正常态必须分流，否则数值型只画一枚「打卡」');
      expect(rh, contains('renderNumeric(context, views, row, appWidgetId)'));
      expect(support, contains('val isNumeric: Boolean get() = goal > 0'),
          reason: '判据只能是 goal > 0（Dart 侧 isNumeric 同式，两处一分叉就「写着 +2 却是布尔打卡」）');
    });

    test('未提交态：状态行给进度、步进行三格、主按钮「打卡」（批D）', () {
      final rn = bodyOf(habit, 'private fun renderNumeric(', 'private fun bindRoot(');
      expect(rn, contains('R.string.lh_widget_habit_val'), reason: '缺进度文案 ⇒ 看不到今天记了多少');
      // 报障核心：原型是 [−5] [30] [+5] 三格，不是一枚 +N。
      expect(rn, contains('R.string.lh_widget_habit_minus'), reason: '缺减号格（报障原话「没有减数值」）');
      expect(rn, contains('R.string.lh_widget_habit_add'), reason: '缺加号格');
      expect(rn, contains('R.string.lh_widget_habit_btn'), reason: '主按钮必须是「打卡」（一次提交），不是 +N');
      expect(rn, contains('LhWidget.draftValue('), reason: '中间值必须读实例草稿（± 改的就是它）');
      expect(rn, contains('LhWidget.initialDraftValue(row)'), reason: '无草稿时取初值（今日目标量）');
      expect(rn, contains('LhWidget.numText(mid)'), reason: '中间格文案走唯一格式化出口');
      expect(strings, contains(r'name="lh_widget_habit_minus">−%1$s<'));
      expect(strings, contains(r'name="lh_widget_habit_add">+%1$s<'));
      expect(strings, contains(r'name="lh_widget_habit_done_val">已打卡 · %1$s<'));
    });

    test('已提交态（今日 value > 0）：± 收起、按钮灰＋回 App 改、文案 已打卡 · N', () {
      final rn = bodyOf(habit, 'private fun renderNumeric(', 'private fun bindRoot(');
      expect(rn, contains('if (row.value > 0)'), reason: '已提交判定＝今日已有记录（不是「达标」）');
      expect(rn, contains('R.string.lh_widget_habit_done_val'), reason: '缺「已打卡 · N」收敛态');
      expect(rn, contains('REQ_BTN'),
          reason: '已提交态按钮＝「回 App 改」的导航意图（批E：改数/改时间/删除都在 App 内）');
      expect(rn, contains('R.id.lh_wg_cnt, View.GONE'), reason: '已提交态步进行必须收起');
    });

    test('提交带量：habitCheckIntent(amount = mid)（绝对量写，不是再加一档）', () {
      final rn = bodyOf(habit, 'private fun renderNumeric(', 'private fun bindRoot(');
      expect(rn, contains('amount = mid'), reason: '提交的必须是中间格那一刻的值');
      expect(rn, contains('LhWidget.habitCheckIntent(context, appWidgetId, row.name, amount = mid)'));
      // 中间格是「数」不是「钮」：点它不提交（提交只走主按钮，避免误记）。
      expect(rn, contains('setOnClickPendingIntent(R.id.lh_wg_cnt_val, null)'));
      // 中间值被减到 0：撤意图（记 0 是空记录，会污染「今日已记」）。
      expect(rn, contains('if (mid > 0)'));
      // 支持：意图里带不带 amount 决定 Dart 走绝对量还是加一档。
      expect(support, contains('if (amount != null) putExtra(HabitCheckReceiver.EXTRA_VALUE, amount)'));
    });

    test('± 两条意图：每实例每钮一个 requestCode，且不起引擎不写库', () {
      final adj = bodyOf(support, 'fun habitAdjustIntent(', 'fun quickAddIntent(');
      expect(adj, contains('REQ_HABIT_ADJUST_BASE + appWidgetId * 2'),
          reason: '同码会让「＋」覆写「−」（PendingIntent 相等性不比 extras）');
      expect(adj, contains('if (delta < 0) 0 else 1'), reason: '正负各占一个码');
      final recv = File('$kt/HabitAdjustReceiver.kt').readAsStringSync();
      final code = recv
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//.*'), '');
      expect(recv, contains('LhWidget.putDraft('), reason: '± 只改显示态草稿');
      expect(recv, contains('LhWidget.draftValue('), reason: '基准值必须读草稿（连点累积）');
      expect(recv, contains('coerceAtLeast(0.0)'), reason: '下限 0：减到底停在 0，不出现负数');
      expect(recv, contains('HabitCheckWidget().redraw(app, widgetId)'),
          reason: '只重画自己这一枚（广播整类会让同类实例集体闪）');
      for (final banned in <String>['FlutterEngine', 'upsertEntry', 'sqlite', 'HabitCheckReceiver']) {
        expect(code, isNot(contains(banned)),
            reason: '± 出现 $banned ⇒ 又在起引擎/复刻写库（± 只是显示态）');
      }
    });

    test('草稿三条作废：跨日 / 换绑 / 负值', () {
      final dv = bodyOf(support, 'fun draftValue(', 'fun putDraft(');
      expect(dv, contains('d.day != day'), reason: '昨天的量不能带到今天');
      expect(dv, contains('d.name != name'), reason: '换绑后旧草稿属于别的习惯');
      expect(dv, contains('d.value < 0'), reason: '脏值一律不认');
      expect(support, contains('const val PREF_WIDGET_HABIT_DRAFT = FLUTTER_KEY_PREFIX + "desktop.widget_habit_draft"'));
    });

    test('步进行三件套常驻布局且默认 gone（RemoteViews 禁动态 addView）', () {
      for (final id in <String>[
        'lh_wg_cnt',
        'lh_wg_cnt_minus',
        'lh_wg_cnt_val',
        'lh_wg_cnt_plus',
      ]) {
        expect(layout, contains('@+id/$id'), reason: '布局缺 $id');
      }
      final at = layout.indexOf('@+id/lh_wg_cnt"');
      expect(at, greaterThan(0));
      final block = layout.substring(at, layout.indexOf('</LinearLayout>', at));
      expect(block, contains('android:visibility="gone"'), reason: '默认收起（布尔型整行不出现）');
    });

    test('回显：数值型当场画成「已打卡 · 本次量」、布尔型置已打卡', () {
      final ec = bodyOf(habit, 'fun echoChecked(', 'private companion object');
      expect(ec, contains('if (row.isNumeric)'), reason: '两种形态回显内容不同');
      expect(ec, contains('val next = amount'), reason: '数值型回显用**本次提交量**（不是 value + step）');
      expect(ec, contains('row.copy(value = next'), reason: '数值型把值置成提交量');
      expect(ec, contains('row.copy(done = true)'), reason: '布尔型回显已打卡');
    });

    test('Dart 写库按 goal > 0 分流：带量走绝对量写、不带量加一档', () {
      final cm =
          File('lib/shared/linkage/widget_checkin_mounts.dart').readAsStringSync();
      expect(cm, contains('habitIncrementWrite(repo, h, now: now)'));
      expect(cm, contains('habitValueWrite(repo, h, value: amount, now: now)'),
          reason: '带量提交必须走绝对量写（否则桌面写 30、库里记成加一档）');
      expect(cm, contains('if (amount != null)'));
      expect(cm, contains('if (!h.isGroup && (h.goal ?? 0) > 0)'),
          reason: '分流判据必须与快照 isNumeric 逐字同式');
      final hm = File('lib/shared/linkage/habit_mounts.dart').readAsStringSync();
      expect(hm, contains('Future<HabitCheckOutcome> habitIncrementWrite('));
      expect(hm, contains('Future<HabitCheckOutcome> habitValueWrite('));
      expect(hm, contains('habitStepOf(h.goal ?? 0)'),
          reason: '步进必须走 domain 那一处阶梯（与记量弹层同源）');
      // 步进阶梯只许有一份实现：弹层里的 hStepOf 只能是转发。
      final hs =
          File('lib/features/habit/presentation/habit_sheets.dart').readAsStringSync();
      expect(hs, contains('double hStepOf(double goal) => habitStepOf(goal);'));
      expect(RegExp(r'\b1000\.0,?\s*$', multiLine: true).allMatches(hs), isEmpty,
          reason: '弹层里不许再留一份阶梯字面量（两套步进必然漂移）');
    });

    test('解码兼容老快照：只判前 3 段，缺段按 0 兜', () {
      final rd = bodyOf(support, 'fun readHabitRows(', 'fun numText(');
      expect(rd, contains('if (f.size < 3) return@mapNotNull null'),
          reason: '老快照三段仍要能显示名字与打卡态');
      expect(rd, contains('f.getOrNull(4)?.trim()?.toDoubleOrNull() ?: 0.0'),
          reason: '缺 goal ⇒ 走布尔分支（不猜一个目标出来）');
    });
  });
}
