import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 思维导图批1 测试公共底座：内存库＋全量 DDL＋tapAt 助手。
/// 各 mindmap_* 测试文件**各自独立**（全 app widget 测试不得同文件共处）。
typedef CloseableDb = Database;

void databaseFactoryInit() {
  databaseFactory = databaseFactoryFfiNoIsolate;
}

Future<Database> openMmDb() async {
  databaseFactory = databaseFactoryFfiNoIsolate;
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  for (final sql in DbSchema.createStatements) {
    await db.execute(sql);
  }
  return db;
}

MindmapDao mindmapDaoOf(Database db) => MindmapDao(db);

/// 一次「按下即起」的 tap（<4dp 单击语义；不经 GestureDetector，
/// 画布的 Listener 原始指针仲裁直接收）。
Future<void> tapAt(WidgetTester tester, Offset location) async {
  final g = await tester.startGesture(location);
  await tester.pump();
  await g.up();
  await tester.pump();
}
