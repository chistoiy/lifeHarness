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
/// 三条判据：
/// ① 卡片信息层三行齐全，顺序固定＝写入卡片 → 复制到另一张卡 → 删除卡片；
/// ② 点复制弹起写卡层，且写的是**同一张卡**（副行含卡名）——复制＝同一 cardId
///    写进另一张物理卡，触发链只认 cardId，故不得换成新卡或空卡；
/// ③ 源码级钉住「复用唯一写卡层」：全文件写卡层调用点恰 2 处（写入＋复制），
///    不新开写卡通道（批3c① 「改写丢 AAR」就是绕开写卡层复发的）。
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

  final card = NfcCard(
    id: 'AbCdEfGh1234',
    name: '书桌学习卡',
    targetKind: NfcTargetKind.nav,
    targetRef: 'ledger',
    createdAt: DateTime(2026, 11, 8, 9).millisecondsSinceEpoch,
    writtenAt: DateTime(2026, 11, 8, 9).millisecondsSinceEpoch,
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

  Future<void> openCardInfo(WidgetTester tester, NfcTagIo io) async {
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

  testWidgets('T1 卡片信息层三行齐全，顺序＝写入→复制→删除', (tester) async {
    await openCardInfo(tester, _FakeIo());
    expect(find.text('卡片信息'), findsOneWidget);
    expect(find.text('写入卡片'), findsOneWidget);
    expect(find.text('复制到另一张卡'), findsOneWidget);
    expect(find.text('所有副本触发同一件事'), findsOneWidget,
        reason: '灰字要说清「副本共享同一事件」，否则用户以为复制出新事件');
    expect(find.text('删除卡片'), findsOneWidget);

    final y1 = tester.getTopLeft(find.text('写入卡片')).dy;
    final y2 = tester.getTopLeft(find.text('复制到另一张卡')).dy;
    final y3 = tester.getTopLeft(find.text('删除卡片')).dy;
    expect(y1 < y2, isTrue, reason: '复制行应在写入行下方');
    expect(y2 < y3, isTrue, reason: '复制行应在删除行上方（删除恒为末行）');
  });

  testWidgets('T2 点复制→写卡层弹起，且写的是同一张卡', (tester) async {
    final io = _FakeIo();
    await openCardInfo(tester, io);
    expect(io.reads, 0, reason: '未点复制前不该开读卡会话（§6.3 功耗口径）');

    await tester.tap(find.text('复制到另一张卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sub = tester.widget<Text>(find.byKey(const ValueKey('nfc-write-sub')));
    final text = sub.data ?? sub.textSpan!.toPlainText();
    expect(text, contains('书桌学习卡'), reason: '写卡层必须收到同一张卡，不是新卡/空卡');
    expect(io.reads, 1, reason: '写卡层打开即开读卡会话');
  });

  test('T3 源码级：复制入口复用唯一写卡层（全文件调用点恰 2 处）', () {
    final src =
        File('lib/features/nfc/presentation/nfc_sheets.dart').readAsStringSync();
    expect(RegExp(r'showNfcWriteSheet\(').allMatches(src).length, 2,
        reason: '只许「写入卡片」与「复制到另一张卡」两处调用同一写卡层；'
            '新开写卡通道会让批3c①「改写丢 AAR」复发');

    final i = src.indexOf("ValueKey('nfc-edit-copy')");
    expect(i > 0, isTrue, reason: '复制入口必须存在');
    final block = src.substring(i, i + 900);
    expect(block.contains('showNfcWriteSheet('), isTrue,
        reason: '复制入口必须走写卡层');
    expect(block.contains('card: widget.card!'), isTrue,
        reason: '复制入口必须传当前卡（同一 cardId 才共享同一事件）');
  });
}
