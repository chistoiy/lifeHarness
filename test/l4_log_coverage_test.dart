/// L4 日志批验收钉桩（docs/日志覆盖工单-20260929.md §三·L4）：
/// 习惯打卡结算、呵护记录/删档、日记读写、笔记脏数据四条路必须留痕，
/// 且**来源归类**正确（日志页按「习惯 / 呵护 / 日记 / 收集箱」筛得出来）。
/// 口径同 L1~L3：只加日志零行为改动，本文件只钉「有没有留痕」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool logged(String contains, {String? level, bool key = false}) =>
    AppLog.lines.any((l) =>
        l.text.contains(contains) &&
        (level == null || l.level.name == level) &&
        (!key || l.key));

void srcOf(String contains, String want) {
  for (final l in AppLog.lines.where((x) => x.text.contains(contains))) {
    expect(l.src, want, reason: '${l.text} 归到了 ${l.src}，应为 $want');
  }
}

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;

  setUp(() async {
    AppLog.reset();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
  });
  tearDown(() async {
    await db.close();
    AppLog.reset();
  });

  group('习惯（features/habit）· 打卡与结算', () {
    late HabitRepository repo;
    late Habit h;

    setUp(() async {
      repo = HabitRepository(db);
      h = await repo.saveHabit(
          Habit(name: '喝水', unit: 'ml', goal: 5, startDate: _dayKey(_today)));
    });

    test('落账 key 行把结算值直接写进行文（事后不必翻流水重算）', () async {
      await repo.upsertEntry(h.id, day: _dayKey(_today), value: 300);
      expect(logged('习惯落账：${h.id} · ${_dayKey(_today)} · checked=不改 value=300.0', key: true),
          isTrue, reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('结算 streak='), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('习惯落账', '习惯');
    });

    test('撤销流水留痕；未来日拒绝照旧抛错但也留 warn', () async {
      await repo.upsertEntry(h.id, day: _dayKey(_today), checked: true);
      await repo.deleteEntry(h.id, _dayKey(_today));
      expect(logged('习惯撤销流水：${h.id} · ${_dayKey(_today)} · 结算 streak=', key: true),
          isTrue, reason: AppLog.lines.map((l) => l.text).join(' | '));
      await expectLater(
          repo.upsertEntry(h.id,
              day: _dayKey(_today.add(const Duration(days: 1)))),
          throwsArgumentError);
      expect(logged('习惯未来日写入被拒', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('习惯', '习惯');
    });

    test('负向触发登记留痕（落账行随后）', () async {
      await repo.recordTrigger(h.id,
          day: _dayKey(_today), amount: 1, reasons: const ['熬夜', '咖啡']);
      expect(
          logged('习惯触发登记：${h.id} · ${_dayKey(_today)} · 量=1.0 原因=熬夜/咖啡'),
          isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('习惯落账：', key: true), isTrue);
    });
  });

  group('呵护（features/care）· 记录与高危写', () {
    late CareRepository repo;
    late int babyId;

    setUp(() async {
      repo = CareRepository(db);
      babyId = await repo.addBaby(
          name: '小满', sex: 'girl', birth: _dayKey(_today), color: '#8b5cf6');
    });

    test('速记落库留一条（宝宝/日/事件键）', () async {
      await repo.addLog(CareRecord(
          babyId: babyId, day: _dayKey(_today), k: 'feeding', s: '09:00', ml: 120));
      expect(
          logged('呵护记录落库：#1 宝宝 $babyId · ${_dayKey(_today)} · 事件 feeding',
              key: true),
          isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('呵护记录落库', '呵护');
    });

    test('过敏项重名被吞掉也要有 warn', () async {
      expect(await repo.addAllergy(babyId, '鸡蛋', '皮疹'), isTrue);
      expect(await repo.addAllergy(babyId, '鸡蛋', null), isFalse,
          reason: '同宝宝同食物唯一，第二次应被拒');
      expect(logged('呵护过敏项未写入（重名或异常）：鸡蛋', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('呵护过敏项', '呵护');
    });

    test('删档级联清理留硬证据', () async {
      await repo.deleteBaby(babyId);
      expect(logged('呵护删档级联清理：宝宝 #$babyId', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(await repo.babies(), isEmpty);
      srcOf('呵护删档', '呵护');
    });
  });

  group('日记 / 笔记（features/journal）· 读写与脏数据', () {
    late JournalRepository repo;

    setUp(() async {
      repo = JournalRepository(JournalDao(db));
    });

    test('保存与删除各留一条 key 行', () async {
      final saved = await repo.save(JournalEntry(
          day: _today,
          content: '今天走了 8000 步',
          createdAt: _now,
          updatedAt: _now));
      expect(
          logged('日记保存落库：新增一篇 · 日 ${_dayKey(_today)} · 结构化=false',
              key: true),
          isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      await repo.remove(saved.id!);
      expect(logged('日记删除单篇：#${saved.id}', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('日记', '日记');
    });

    test('rich 正文不是 Delta JSON → warn 并回退 Markdown 扫描', () {
      final bad = JournalEntry(
          day: _today,
          kind: 'rich',
          content: '{坏 JSON',
          createdAt: _now,
          updatedAt: _now);
      expect(bad.imagePaths, isEmpty);
      expect(logged('日记正文非 quill JSON', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 回退路径仍可解析 markdown 图片语法（行为未因加日志而变）。
      final md = JournalEntry(
          day: _today,
          kind: 'rich',
          content: r'![](a.png)',
          createdAt: _now,
          updatedAt: _now);
      expect(md.imagePaths, ['a.png']);
      srcOf('日记正文', '日记');
    });

    test('笔记正文非 JSON → 摘要回退原文并 warn', () {
      expect(Note.richToPlain('{坏 JSON'), '{坏 JSON');
      expect(logged('笔记正文非 quill JSON', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('笔记正文', '日记');
    });
  });

  group('收集箱（features/inbox）· 源码级留痕守门', () {
    // 分流要真落库（待办/日记/笔记/摘录四家），页面级用例另在既有 inbox 用例覆盖；
    // 这里钉「四向分支 + 直接删除都有 key 行，且原文只截 16 字」的源码事实。
    test('四向分流与直接删除都有 key 行，且不整段原文入缓冲', () {
      final src = File('lib/features/inbox/presentation/inbox_page.dart')
          .readAsStringSync();
      for (final probe in [
        "AppLog.addKey('收集箱分流→待办",
        "AppLog.addKey('收集箱分流→今晚日记",
        "AppLog.addKey('收集箱分流→笔记",
        "AppLog.addKey('收集箱分流→阅读摘录",
        "AppLog.addKey('收集箱条目直接删除",
        'level: LhLevel.warn',
        'static String _brief(String s)',
      ]) {
        expect(src, contains(probe), reason: 'inbox_page.dart 缺留痕：$probe');
      }
    });
  });
}
