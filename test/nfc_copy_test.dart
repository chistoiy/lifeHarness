import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/database/schema/nfc.dart' show NfcTargetKind;
import 'package:lifeharness/features/nfc/data/nfc_repo.dart';
import 'package:lifeharness/features/nfc/data/nfc_tag_io.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:lifeharness/features/nfc/domain/nfc_tag_content.dart'
    show NfcRawRecord;
import 'package:lifeharness/features/nfc/presentation/nfc_sheets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批3d · NFC 卡复制入口（规格＝冻结档 §批3d 修订记录）。
///
/// 产品 2026-11-08 裁定「合并」：不再并存「写入卡片」与「复制到另一张卡」两行，
/// 而是**一行随写入态切语义**——未写入＝写入卡片／已写入＝复制到另一张卡。
/// 三条判据：
/// ① 一行两态文案互斥（正负两档都断，防「只测一档」假绿）；
/// ② 点该行弹起写卡层，且写的是**同一张卡**（复制＝同一 cardId 写进另一张物理卡）；
/// ③ 源码级钉住「复用唯一写卡层」：全文件写卡层调用点恰 1 处。
class _FakeIo implements NfcTagIo {
  int reads = 0;

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> startRead({
    required void Function(NfcTagProbe probe) onProbe,
    required void Function(String code) onError,
  }) async {
    reads++;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> writeUri(String uri) async {}

  @override
  Future<void> writeRecords(List<NfcRawRecord> records) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmp;
  late Database db;
  late NfcRepo repo;

  NfcCard cardOf({required bool written}) => NfcCard(
        id: 'AbCdEfGh1234',
        name: '书桌学习卡',
        targetKind: NfcTargetKind.nav,
        targetRef: 'ledger',
        createdAt: DateTime(2026, 11, 8, 9).millisecondsSinceEpoch,
        writtenAt: written
            ? DateTime(2026, 11, 8, 9).millisecondsSinceEpoch
            : null,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nfc3d_');
    db = await AppDatabase.instance.open(pathOverride: tmp.path);
    repo = NfcRepo(db);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> openCardInfo(
      WidgetTester tester, NfcCard card, NfcTagIo io) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showNfcEditSheet(
                ctx,
                card: card,
                mode: NfcEditMode.card,
                repo: repo,
                io: io,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('T1 未写入档：一行＝写入卡片／未写入，不出现复制文案', (tester) async {
    await openCardInfo(tester, cardOf(written: false), _FakeIo());
    expect(find.text('卡片信息'), findsOneWidget);
    expect(find.text('写入卡片'), findsOneWidget);
    expect(find.text('未写入'), findsOneWidget);
    expect(find.text('复制到另一张卡'), findsNothing,
        reason: '没写过卡时不该出现复制语义');
    expect(find.text('删除卡片'), findsOneWidget);
  });

  testWidgets('T2 已写入档：同一行切成复制文案，且删除恒为末行', (tester) async {
    await openCardInfo(tester, cardOf(written: true), _FakeIo());
    expect(find.text('复制到另一张卡'), findsOneWidget);
    expect(find.text('所有副本触发同一件事'), findsOneWidget,
        reason: '灰字要说清副本共享同一事件，否则用户以为复制出新事件');
    expect(find.text('写入卡片'), findsNothing,
        reason: '已写入后不该再显示「写入卡片」（两行并存即产品裁定要合并的冗余）');
    expect(find.text('删除卡片'), findsOneWidget);

    final y1 = tester.getTopLeft(find.text('复制到另一张卡')).dy;
    final y2 = tester.getTopLeft(find.text('删除卡片')).dy;
    expect(y1 < y2, isTrue, reason: '删除恒为末行');
  });

  testWidgets('T3 点该行→写卡层弹起，且写的是同一张卡', (tester) async {
    final io = _FakeIo();
    await openCardInfo(tester, cardOf(written: true), io);
    expect(io.reads, 0, reason: '未点之前不该开读卡会话（§6.3 功耗口径）');

    await tester.tap(find.text('复制到另一张卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sub = tester.widget<Text>(find.byKey(const ValueKey('nfc-write-sub')));
    final text = sub.data ?? sub.textSpan!.toPlainText();
    expect(text, contains('书桌学习卡'), reason: '写卡层必须收到同一张卡，不是新卡/空卡');
    expect(io.reads, 1, reason: '写卡层打开即开读卡会话');
  });

  test('T4 源码级：合并后全文件写卡层调用点恰 1 处', () {
    final src =
        File('lib/features/nfc/presentation/nfc_sheets.dart').readAsStringSync();
    expect(RegExp(r'showNfcWriteSheet\(').allMatches(src).length, 1,
        reason: '写入与复制合并成同一行同一调用；多出第二处即两行并存的旧形态复发');
    expect(src.contains("ValueKey('nfc-edit-copy')"), isFalse,
        reason: '独立复制行已被产品裁定合并删除');
    expect(src.contains("ValueKey('nfc-edit-write')"), isTrue);
    expect(src.contains("written ? '复制到另一张卡' : '写入卡片'"), isTrue,
        reason: '文案必须随写入态切换');
  });
}
