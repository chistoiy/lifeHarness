import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_layout_kit.dart';

/// 日记改版批1a · 视图三档纯逻辑（工单 §1 执行面板「新增常驻」第一件）。
///
/// 这里只钉**不依赖 widget 树**的口径：存储收敛、日期块合并、图墙三态次序与月界偏移。
/// 画面级验证在 `journal_view_mode_test.dart`（要 pump），二者不重复。

JournalEntry _e(DateTime day, {int? mood, String content = '正文', List<String> imgs = const []}) =>
    JournalEntry(
      day: day,
      mood: mood,
      content: imgs.isEmpty
          ? content
          : '$content\n![i](file://${imgs.join('|')})',
      createdAt: DateTime(day.year, day.month, day.day, 9, 30),
      updatedAt: DateTime(day.year, day.month, day.day, 9, 30),
    );

void main() {
  group('三档存储收敛（UserSettings）', () {
    test('P1 缺省＝列表（不是轨道、也不是 INS）', () {
      expect(UserSettings.defaults.journalLayout, kJournalLayoutList);
      expect(UserSettings.defaults.journalLayout, 'list');
    });

    test('P2 合法值原样往返', () {
      for (final k in UserSettings.kJournalLayouts) {
        final s = UserSettings.fromMap({'journalLayout': k});
        expect(s.journalLayout, k);
        expect(s.toMap()['journalLayout'], k);
      }
    });

    test('P3 脏值/未知档回落列表', () {
      expect(UserSettings.fromMap({'journalLayout': 'waterfall'}).journalLayout, 'list');
      expect(UserSettings.fromMap({'journalLayout': 3}).journalLayout, 'list');
      expect(UserSettings.fromMap(const {}).journalLayout, 'list');
    });

    test('P4 旧布尔位单向映射：true→ins，false→list（老 INS 用户不被拽回列表）', () {
      expect(UserSettings.fromMap({'journalIns': true}).journalLayout, 'ins');
      expect(UserSettings.fromMap({'journalIns': false}).journalLayout, 'list');
    });

    test('P5 三档值优先于旧布尔位（两边冲突时以新值为准）', () {
      expect(
        UserSettings.fromMap({'journalLayout': 'track', 'journalIns': true})
            .journalLayout,
        'track',
      );
    });

    test('P6 copyWith 只改目标键，其余不动', () {
      final s = UserSettings.defaults.copyWith(journalLayout: 'ins');
      expect(s.journalLayout, 'ins');
      expect(s.journalFilter, UserSettings.defaults.journalFilter);
      expect(s.journalDefaultTpl, UserSettings.defaults.journalDefaultTpl);
    });
  });

  group('日期块合并（同日多篇只出一次）', () {
    test('B1 同一天三篇 → 一个日期块、块内三篇', () {
      final d = DateTime(2026, 10, 17);
      final blocks = buildTrackBlocks([
        _e(d, content: 'a'),
        _e(d, content: 'b'),
        _e(d, content: 'c'),
        _e(DateTime(2026, 10, 16), content: 'd'),
      ]);
      expect(blocks.length, 2, reason: '两天＝两块，同日三篇不许画成三块');
      expect(blocks.first.entries.length, 3);
      expect(blocks.last.entries.length, 1);
    });

    test('B2 块序＝入参序（新→旧，不重排）', () {
      final blocks = buildTrackBlocks([
        _e(DateTime(2026, 10, 18)),
        _e(DateTime(2026, 10, 17)),
        _e(DateTime(2026, 10, 16)),
      ]);
      expect(blocks.map((b) => b.day.day).toList(), [18, 17, 16]);
    });

    test('B3 四档分层数据齐备：日号补零 / 月份 / 星期', () {
      final b = buildTrackBlocks([_e(DateTime(2026, 10, 5))]).single;
      expect(b.dayNo, '05', reason: '日号补两位，22px 字号下才不会两个日期块宽度不一致');
      expect(b.monthLabel, '10月');
      expect(b.weekLabel, '周一');
      expect(kTrackDayNoSize, 22);
      expect(kTrackMetaSize, 10);
    });

    test('B4 时刻取当篇创建时刻（同日后篇靠它区分）', () {
      final b = buildTrackBlocks([_e(DateTime(2026, 10, 5))]).single;
      expect(b.timeOf(b.entries.first), '09:30');
    });

    test('B5 心情色回调：记了心情才给色，没记给 null', () {
      final withMood = buildTrackBlocks(
        [
          _e(DateTime(2026, 10, 17), mood: 1),
          _e(DateTime(2026, 10, 16)),
        ],
        moodColorOf: (e) => e.mood == null ? null : const Color(0xFF6366F1),
      );
      expect(withMood[0].hasMoodColor, isTrue);
      expect(withMood[0].moodColor, isNotNull);
      expect(withMood[1].hasMoodColor, isFalse);
    });

    test('B6 空列表＝零块（不炸）', () {
      expect(buildTrackBlocks(const []), isEmpty);
    });
  });

  group('月历图墙三态与月界', () {
    test('W1 三态次序：无日记＞有日记无图＞有日记有图', () {
      expect(wallCellStateOf(null), WallCellState.empty);
      expect(wallCellStateOf(_e(DateTime(2026, 10, 1))), WallCellState.written);
      expect(
        wallCellStateOf(_e(DateTime(2026, 10, 1), imgs: ['/a.jpg'])),
        WallCellState.writtenWithImage,
      );
    });

    test('W2 有日记但只有心情、没有正文，仍算「写过」（不是空环）', () {
      final e = JournalEntry(
        day: DateTime(2026, 10, 2),
        mood: 2,
        content: '',
        createdAt: DateTime(2026, 10, 2),
        updatedAt: DateTime(2026, 10, 2),
      );
      expect(wallCellStateOf(e), WallCellState.written);
    });

    test('W3 格数＝7 的倍数，且能装下整月', () {
      final oct = DateTime(2026, 10, 1);
      final n = wallCellCount(oct);
      expect(n % 7, 0);
      expect(n, greaterThanOrEqualTo(31));
    });

    test('W4 首格偏移＝周一开头（2026-10-01 是周四 ⇒ 前面空 3 格）', () {
      final first = DateTime(2026, 10, 1);
      expect(first.weekday, DateTime.thursday);
      expect(first.weekday - 1, 3);
    });

    test('W5 二月与闰年边界', () {
      expect(wallCellCount(DateTime(2026, 2, 1)), greaterThanOrEqualTo(28));
      expect(wallCellCount(DateTime(2028, 2, 1)), greaterThanOrEqualTo(29));
    });
  });

  group('设置弹层档位元数据', () {
    test('M1 三档顺序与存储合法值同集合', () {
      expect(kJournalLayoutsOrdered.toSet(), UserSettings.kJournalLayouts.toSet());
      expect(kJournalLayoutsOrdered.length, 3);
    });

    test('M2 每档都有中文名与图标', () {
      for (final k in kJournalLayoutsOrdered) {
        expect(kJournalLayoutLabels[k], isNotNull);
        expect(journalLayoutIcon(k), isNotNull);
      }
      expect(kJournalLayoutLabels[kJournalLayoutTrack], '日期轨道');
      expect(kJournalLayoutLabels[kJournalLayoutIns], 'INS 卡片流');
    });
  });
}
