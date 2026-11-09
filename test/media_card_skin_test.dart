/// 2A · 实物卡材质皮肤常驻守护（2026-11-08 产品「过门·落实现（保留扁平基线）」）。
///
/// 钉死四件事：① 默认关＝扁平卡逐像素零变化；② 开＝四类材质＋双层阴影；
/// ③ 设置 KV → provider → 两个卡调用点整条同源、当场生效；④ 不碰桌面底／配色令牌。
/// 每条都给正档/负档对照，避免「被测分支没进也能绿」的假绿。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_set_page.dart';
import 'package:lifeharness/features/media/presentation/media_shelf_page.dart';
import 'package:lifeharness/features/media/presentation/widgets/media_card.dart';
import 'package:lifeharness/features/media/presentation/widgets/media_card_skin.dart';

import 'helpers.dart';

const _card = 'lib/features/media/presentation/widgets/media_card.dart';
const _set = 'lib/features/media/presentation/media_set_page.dart';
const _prov = 'lib/features/media/presentation/media_providers.dart';
const _shelf = 'lib/features/media/presentation/media_shelf_page.dart';
const _work = 'lib/features/media/presentation/media_workbench.dart';
const _proto = 'prototype/index-media.html';

String _read(String rel) => File(rel).readAsStringSync();

MediaItem _item(String kind) => MediaItem(
      id: 'sk1',
      kind: kind,
      title: '样片',
      state: MediaItem.initialState(kind),
      progressWay: MediaItem.defaultWay(kind),
      creator: '主创',
      createdAt: 1,
      updatedAt: 1,
    );

Finder get _skinPainter => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is MdsSkinPainter,
    );

Finder get _twoShadows => find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).boxShadow?.length == 2,
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required bool? skin,
  String kind = MediaItem.kMovie,
  VoidCallback? onTap,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 180,
          height: 230,
          child: skin == null
              ? MediaItemCard(item: _item(kind), onTap: onTap)
              : MediaItemCard(
                  item: _item(kind), cardSkin: skin, onTap: onTap),
        ),
      ),
    ),
  ));
  await settle5(tester);
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('① 双层阴影两档各两层；深档整档加厚，不许混搭', () {
    final light = mdsSkinShadows(false);
    final dark = mdsSkinShadows(true);
    expect(light.length, 2, reason: '接触影＋环境影，缺一层即退化');
    expect(dark.length, 2);
    expect(light[0].color, const Color(0x330F172A));
    expect(light[1].color, const Color(0x240F172A));
    expect(dark[0].color, const Color(0x8C000000));
    expect(dark[1].color, const Color(0x7A000000));
    expect(light[1].offset.dy, 10);
    expect(light[1].blurRadius, 24);
    expect(dark[1].offset.dy, 12);
    expect(dark[1].blurRadius, 28);
    expect(identical(light, kMdsSkinShadowLight), isTrue);
    expect(identical(dark, kMdsSkinShadowDark), isTrue);
    expect(light, isNot(dark), reason: '两档必须真不同，否则 dark 分支没进也会绿');
  });

  testWidgets('② 默认关（含不传参）＝零材质层零双层阴影；开启＝两样都进树',
      (tester) async {
    await useSurface(tester, const Size(420, 900));
    final cardBox = find
        .descendant(
          of: find.byType(MediaItemCard),
          matching: find.byType(Container),
        )
        .first;

    await _pumpCard(tester, skin: null);
    expect(_skinPainter, findsNothing);
    expect(_twoShadows, findsNothing);
    expect(tester.widget<Container>(cardBox).child, isA<Column>(),
        reason: '默认关＝整卡仍是原来的 Column 子节点，不许额外套 Stack');
    expect(
        find.descendant(
          of: find.byType(MediaItemCard),
          matching: find.byType(IgnorePointer),
        ),
        findsNothing,
        reason: '默认关＝不进任何材质挂件');

    await _pumpCard(tester, skin: false);
    expect(_skinPainter, findsNothing);
    expect(_twoShadows, findsNothing);
    expect(tester.widget<Container>(cardBox).child, isA<Column>());

    await _pumpCard(tester, skin: true);
    expect(_skinPainter, findsOneWidget);
    expect(_twoShadows, findsOneWidget);
    expect(tester.widget<Container>(cardBox).child, isA<Stack>(),
        reason: '开启后才有 Stack 叠材质层');
    expect(
        find.descendant(
          of: find.byType(MediaItemCard),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
        reason: '材质层必须由 IgnorePointer 兜住，不许抢卡片手势');
  });

  testWidgets('③ 四类各挂各的 painter；kind 换档要重绘', (tester) async {
    await useSurface(tester, const Size(420, 900));
    final seen = <String>[];
    for (final kind in MediaItem.kinds) {
      await _pumpCard(tester, skin: true, kind: kind);
      final w = tester.widget<CustomPaint>(_skinPainter);
      final p = w.painter! as MdsSkinPainter;
      seen.add(p.kind);
    }
    expect(seen, MediaItem.kinds, reason: '四类材质不许串档/缺档');
    // 卷角面与深档标记都吃主题：明暗两档给到不同值（写死白／写死浅档都会红）。
    await _pumpCard(tester, skin: true, brightness: Brightness.light);
    final lightPainter =
        tester.widget<CustomPaint>(_skinPainter).painter! as MdsSkinPainter;
    await _pumpCard(tester, skin: true, brightness: Brightness.dark);
    final darkPainter =
        tester.widget<CustomPaint>(_skinPainter).painter! as MdsSkinPainter;
    expect(darkPainter.dark, isTrue);
    expect(lightPainter.dark, isFalse);
    expect(darkPainter.surface, isNot(lightPainter.surface),
        reason: '卷角面必须跟 scheme.surface 走，不许写死白');
    const a = MdsSkinPainter(
        kind: MediaItem.kMovie, dark: false, surface: Color(0xFFFAFAFA));
    const b = MdsSkinPainter(
        kind: MediaItem.kGame, dark: false, surface: Color(0xFFFAFAFA));
    expect(a.shouldRepaint(b), isTrue);
    expect(a.shouldRepaint(a), isFalse);
  });

  testWidgets('④ 材质层不抢手势：开/关两档点击都可达', (tester) async {
    await useSurface(tester, const Size(420, 900));
    for (final skin in <bool>[false, true]) {
      var taps = 0;
      await _pumpCard(tester, skin: skin, onTap: () => taps++);
      await tester.tap(find.byType(MediaItemCard));
      await settle5(tester);
      expect(taps, 1, reason: 'skin=$skin 时卡面点击被材质层吃掉');
    }
  });

  test('⑤ 原型／设置／provider／调用点同源（源码级；防桌面底越界）', () {
    final proto = _read(_proto);
    expect(proto.contains('cardSkin:false'), isTrue,
        reason: '原型开关默认必须关');
    expect(proto.contains("['cardSkin','实物卡材质','bool']"), isTrue);
    expect(proto.contains('<style id="mclab-skin">'), isTrue);
    expect(proto.contains('body:has(#m-shelf.active) #phone'), isFalse,
        reason: '亚麻/胡桃桌面底不许挂到正式架面（扁平基线不推翻）');

    final setSrc = _read(_set);
    expect(setSrc.contains("_bool('media.cardSkin', '实物卡材质')"), isTrue);
    expect(setSrc.contains("'media.cardSkin': 'false'"), isTrue);
    expect(kMdsPreset['media.cardSkin'], 'false', reason: '读侧回落同源');
    expect(kMdsSetGroups.firstWhere((g) => g.id == 'shelf').rows.length, 3,
        reason: '架面组＝默认视图／列数／实物卡材质三行');
    expect(
        kMdsSetGroups.firstWhere((g) => g.id == 'shelf').rows.last.key,
        'media.cardSkin');

    expect(_read(_prov).contains("'media.cardSkin', 'false'"), isTrue);
    expect(_read(_card).contains('this.cardSkin = false'), isTrue);
    expect(_read(_card).contains('boxShadow: cardSkin ? mdsSkinShadows(dark) : null'),
        isTrue);
    for (final f in <String>[_shelf, _work]) {
      expect(
          _read(f).contains(
              'cardSkin: ref.watch(mediaCardSkinProvider).valueOrNull ?? false'),
          isTrue,
          reason: '$f 漏了皮肤参数贯通');
    }
  });

  testWidgets('⑥ 设置写 KV → provider 当场生效 → 架面卡真挂材质层', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    final repo = MediaRepository(db);
    await repo.addItem(_item(MediaItem.kMovie));
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MediaShelfPage())),
    ));
    await settle5(tester);
    expect(await container.read(mediaCardSkinProvider.future), isFalse);
    expect(_skinPainter, findsNothing, reason: '默认关＝架面一张扁平卡');

    await repo.setKv('media.cardSkin', 'true');
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(await container.read(mediaCardSkinProvider.future), isTrue);
    expect(_skinPainter, findsOneWidget, reason: '写库后架面卡当场叠材质层');
    expect(_twoShadows, findsOneWidget);

    await repo.setKv('media.cardSkin', 'false');
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(await container.read(mediaCardSkinProvider.future), isFalse);
    expect(_skinPainter, findsNothing, reason: '关回去必须完整退回扁平卡');
    expect(_twoShadows, findsNothing);
  });
}
