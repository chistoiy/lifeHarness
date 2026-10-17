import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/weather_city_sheet.dart';
import 'package:lifeharness/shared/weather/weather_dao.dart';
import 'package:lifeharness/shared/weather/weather_service.dart';
import 'package:lifeharness/shared/weather/weather_visual.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 真机反馈轮4①：天气城市搜索的三态弹层回归（独立文件防 isolate 污染）。
/// 口径＝「网络不可达」与「无匹配城市」必须分开，失败不许静默（落日志行）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SharedPreferences prefs;

  setUp(() async {
    AppLog.reset();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    AppLog.reset();
  });

  /// 打开弹层并搜一个词；返回后停在搜索结果态（busy 已落定）。
  Future<void> openAndSearch(
      WidgetTester tester, WeatherJsonFetcher fetch, String query) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherServiceProvider
            .overrideWithValue(WeatherService(WeatherDao(db), fetch: fetch)),
      ],
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) => Scaffold(
              body: Builder(
                builder: (inner) => Center(
                  child: ElevatedButton(
                    onPressed: () => showWeatherCitySheet(inner, ref),
                    child: const Text('open-sheet'),
                  ),
                ),
              ),
            )),
      ),
    ));
    await tester.tap(find.text('open-sheet'));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('city-search')), query);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle5(tester);
  }

  /// 失败日志按出现次数计（去重断言口径：禁 textContaining+findsOne 假绿）。
  int failLogCount(String needle) => AppLog.lines
      .where((l) => l.src == '天气' && l.text.contains(needle))
      .length;

  testWidgets('取数失败=「网络不可达」＋重试，绝不显示成「无匹配城市」，且落日志行',
      (tester) async {
    await openAndSearch(
        tester, (u) async => (json: null, err: 'socket'), '杭州');

    expect(find.text('网络不可达'), findsOneWidget);
    expect(find.byKey(const ValueKey('city-retry')), findsOneWidget);
    expect(find.text('无匹配城市'), findsNothing);
    expect(failLogCount('城市搜索失败'), 1); // 一次搜索＝一条留痕

    // 点「重试」＝再走一次搜索：仍不可达，日志累计两条（一条记录＝落盘一行）
    await tester.tap(find.byKey(const ValueKey('city-retry')));
    await settle5(tester);
    expect(find.text('网络不可达'), findsOneWidget);
    expect(failLogCount('城市搜索失败'), 2);
  });

  testWidgets('查无此城=「无匹配城市」，不冒充网络不可达；空结果落 info 留痕', (tester) async {
    await openAndSearch(
        tester, (u) async => (json: const {'results': <Object>[]}, err: null),
            '不存在的城市名');

    expect(find.text('无匹配城市'), findsOneWidget);
    expect(find.text('网络不可达'), findsNothing);
    expect(failLogCount('城市搜索失败'), 0);
    expect(failLogCount('城市搜索无结果'), 1); // 正当空结果也有一行可辨
  });

  testWidgets('200 但结构不合（限流 error JSON）=归「网络不可达」并留痕，不伪装无匹配',
      (tester) async {
    await openAndSearch(tester,
        (u) async => (json: const {'error': true, 'reason': 'abuse'}, err: null),
        '常州');

    expect(find.text('网络不可达'), findsOneWidget);
    expect(find.text('无匹配城市'), findsNothing);
    // 裸名「常州」会自动并查「常州市」＝两趟各留一行（一次搜索一条留痕）。
    expect(failLogCount('响应结构异常'), 2);
  });

  testWidgets('中文裸名自动并查「市」形态：市形命中排前（阜阳/常州真机案）',
      (tester) async {
    await openAndSearch(tester, (u) async {
      final name = u.queryParameters['name'];
      if (name == '常州市') {
        return (
          json: const {
            'results': [
              {'name': '常州市', 'latitude': 31.81, 'longitude': 119.97, 'admin1': '江苏'},
            ]
          },
          err: null
        );
      }
      // 裸名只回一个江苏的村（真机「阜阳」同款脏数据）
      return (
        json: const {
          'results': [
            {
              'name': '阜阳',
              'latitude': 33.79,
              'longitude': 119.70,
              'admin1': '江苏',
              'admin2': '盐城市'
            },
          ]
        },
        err: null
      );
    }, '常州');

    // 市形在前：列表首行是「常州市」；裸名条目带二级区划可区分（产品口径=全展示自选）
    expect(find.textContaining('常州市'), findsOneWidget);
    expect(find.text('阜阳 · 江苏 · 盐城市'), findsOneWidget);
    expect(find.text('网络不可达'), findsNothing);
  });

  testWidgets('正常命中=列表可选，无失败态', (tester) async {
    await openAndSearch(tester, (u) async {
      return (
        json: const {
          'results': [
            {
              'name': '杭州',
              'latitude': 30.29,
              'longitude': 120.16,
              'admin1': '浙江'
            },
          ]
        },
        err: null
      );
    }, '杭州');

    expect(find.byKey(const ValueKey('city-hit-杭州')), findsOneWidget);
    expect(find.text('网络不可达'), findsNothing);
    expect(find.text('无匹配城市'), findsNothing);
    expect(failLogCount('城市搜索失败'), 0);
  });
}
