import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_words_io.dart';

/// V1.54.1 批3 · `.xrwords` 养成词库导入导出（纯数据面，无 widget）。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late XrayDao dao;
  late Directory tmp;
  late XrayWordsIoService svc;

  /// saveAs/pickFile 直通位：导出留下最终路径，导入原路选回（不触 SAF 通道）。
  var exportedPath = '';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: DbSchema.version));
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = XrayDao(db);
    tmp = await Directory.systemTemp.createTemp('xrwords_test');
    exportedPath = '';
    svc = XrayWordsIoService(
      dao,
      docsOverride: tmp,
      readAsset: (p) => File(p).readAsString(),
      // SAF 钩子直通：saveAs 原样返回临时路径并记账，pickFile 回吐它（不触平台通道）。
      saveAs: (src) async {
        exportedPath = src;
        return src;
      },
      pickFile: () async => exportedPath.isEmpty ? null : exportedPath,
    );
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('指纹：确定且 16 位 hex（非加密，仅基准比对用）', () {
    final f = XrayWordsIoService.fingerprint('assets');
    expect(f, XrayWordsIoService.fingerprint('assets'));
    expect(f, isNot(XrayWordsIoService.fingerprint('assets2')));
    expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(f), isTrue);
  });

  test('buildBundle：预置八表指纹 + 只含 GLOBAL 条目（按书行不进包）', () async {
    await dao.putUserWord(scope: 'GLOBAL', word: '波洛', action: 'add', type: 'per');
    await dao.putUserWord(scope: 'BOOK_MD5', word: '按书词', action: 'add');
    final b = await svc.buildBundle();
    expect(b['v'], 1);
    expect(b['kind'], 'xrwords');
    final files = (b['preset'] as Map)['files'] as Map;
    expect(files.keys.toSet(), {
      'func_words.txt', 'common_nouns.txt', 'titles.txt', 'surnames.txt',
      'loc_suffix.txt', 'org_suffix.txt', 'stop_en.txt', 'gazetteer.txt',
    });
    expect((files['titles.txt'] as String).length, 16);
    final entries = b['entries'] as List;
    expect(entries, hasLength(1), reason: '按书覆盖层不进包');
    expect((entries.first as Map)['word'], '波洛');
  });

  test('导入计数：新增/覆盖/跳过三桶齐', () async {
    await dao.putUserWord(scope: 'GLOBAL', word: '旧词', action: 'add');
    final r = await dao.importGlobalDict(const [
      XrayDictEntry(word: '旧词', action: 'add', type: 'term'), // 覆盖
      XrayDictEntry(word: '新词', action: 'forbid'), // 新增
      XrayDictEntry(word: '  ', action: 'add'), // 跳过：空词
      XrayDictEntry(word: '非法动作', action: 'merge_pair'), // 跳过：无 target 语义
      XrayDictEntry(word: '怪类型', action: 'add', type: 'xxx'), // 类型归 null 不跳
    ]);
    expect(r.added, 2, reason: '新词 + 怪类型');
    expect(r.updated, 1, reason: '旧词同键覆盖');
    expect(r.skipped, 2, reason: '空词 + merge_pair');
    final rows = await dao.listGlobalDict();
    expect(rows.map((e) => e.word), containsAll(['旧词', '新词', '怪类型']));
    expect(rows.firstWhere((e) => e.word == '怪类型').type, 'xxx',
        reason: 'DAO 是哑存储不校验类型——归一层在 parseEntries（下一例）');
  });

  test('parseEntries：非法类型归 null、非法动作/空词跳过', () {
    final (entries, skipped) = svc.parseEntries({
      'entries': [
        {'word': '怪类型', 'action': 'add', 'type': 'xxx', 'ts': 1},
        {'word': '波洛', 'action': 'add', 'type': 'per', 'ts': 2},
        {'word': '', 'action': 'add'},
        {'word': '非法', 'action': 'merge_pair'},
      ],
    });
    expect(skipped, 2, reason: '空词 + merge_pair');
    expect(entries, hasLength(2));
    expect(entries.firstWhere((e) => e.word == '怪类型').type, isNull,
        reason: '未收录类型随包归 null');
    expect(entries.firstWhere((e) => e.word == '波洛').type, 'per');
  });

  test('导出→读包→导入全链：条目与 ts 原样回流', () async {
    await dao.putUserWord(scope: 'GLOBAL', word: '波洛', action: 'add', type: 'per');
    await dao.putUserWord(scope: 'GLOBAL', word: '怪词', action: 'forbid');
    // 导出（saveAs 直通临时路径）。
    final saved = await svc.exportWords();
    expect(saved, isNotNull);
    expect(File(saved!).readAsStringSync(), contains('xrwords'));
    // 清库模拟换机，再从包导入。
    await dao.deleteGlobalDict('波洛');
    await dao.deleteGlobalDict('怪词');
    expect(await dao.listGlobalDict(), isEmpty);
    final bundle = await svc.readPick();
    expect(bundle, isNotNull);
    final r = await svc.importWords(bundle!);
    expect(r.total, 2);
    expect(r.added, 2);
    final rows = await dao.listGlobalDict();
    expect(rows.map((e) => e.word).toSet(), {'波洛', '怪词'});
    expect(rows.firstWhere((e) => e.word == '波洛').type, 'per');
    // ts 原样回流（非导入时刻）。
    final srcTs = ((jsonDecode(File(saved).readAsStringSync())
                as Map)['entries'] as List)
        .firstWhere((e) => (e as Map)['word'] == '波洛')['ts'] as int;
    expect(rows.firstWhere((e) => e.word == '波洛').createTime, srcTs);
  });

  test('readPick 拒收非 xrwords 包', () async {
    final bad = File('${tmp.path}/bad.xrwords');
    await bad.writeAsString(jsonEncode({'v': 1, 'kind': 'other'}));
    late Object caught;
    try {
      await XrayWordsIoService(dao, pickFile: () async => bad.path,
          docsOverride: tmp, readAsset: (p) => File(p).readAsString())
          .readPick();
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<FormatException>());
  });
}
