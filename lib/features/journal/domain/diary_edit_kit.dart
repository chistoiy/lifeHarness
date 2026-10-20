/// 日记编辑页（p-diaryEdit）批2 的**纯逻辑**件：心情单选组 / 保存态三态 / 头部日期。
///
/// 为什么单独成文件：这三条都是「页面里拼字符串就会写错、拼错了只有真机看得出」的判据——
/// 心情组的主轨与更多行分家、选中态比对口径、保存态三态、头部日期星期全称。
/// 放进纯逻辑件后可以脱离 widget 树直接断言（`test/journal_edit_kit_test.dart`）。
///
/// 口径来源＝`docs/handoff/交棒话术-20261019-日记模块改版批1日期轨道与图墙.md` §4d ①②⑤⑥。
library;

import 'journal_entry.dart';

/// 心情单选组：主轨 5 枚（原型 `DIARY_MOOD_MAIN`）＋「更多」6 枚（`DIARY_MOOD_MORE`）。
///
/// 主轨取 `kJournalMoods` 前 5 档（😄😌😐😪😰）——**与存储序号严格同序**：
/// 心情落库是 1..7（`JournalEntry.mood`），主轨下标 + 1 就是库里的值，不许各存一份字面量。
/// 更多行多出的两枚（😍 开心 / 🤔 思考）在先前的七档里没有对应序号，
/// **选中时落 `mood=null` 且在页内只做展示**——见 `diaryMoodIndex` 的说明。
const kMoodMainCount = 5;

/// 主轨心情（含库内序号 `$1` 为 1..5，与 `kJournalMoods` 同序）。
List<(int, String, String)> get kMoodMain => [
      for (var i = 0; i < kMoodMainCount; i++) (i + 1, kJournalMoods[i].$1, kJournalMoods[i].$2),
    ];

/// 「更多」行多出的两枚（库内无序号，见上方口径）。
const kMoodExtra = <(String, String)>[('😍', '心动'), ('🤔', '思考')];

/// 表情字符 → 库内心情序号（1..7）；不在七档内（更多行的额外两枚）= null。
int? diaryMoodIndex(String? emoji) {
  if (emoji == null) return null;
  for (var i = 0; i < kJournalMoods.length; i++) {
    if (kJournalMoods[i].$1 == emoji) return i + 1;
  }
  return null;
}

/// 库内序号 → 表情字符（越界给 null，不给「第 0 档」这种假值）。
String? diaryMoodEmoji(int? mood) => moodEmoji(mood);

/// 选中态比对：**必须按表情字符比**，不许拿序号比。
///
/// 批2 原型踩过一次（`diaryMood` 写成 0-6 索引，渲染按字符比对 ⇒ 进页整行无选中态）；
/// 实现侧同理——心情状态只存 `int? mood`，渲染前统一经本函数折算。
bool moodSelected(int? current, String emoji) {
  final idx = diaryMoodIndex(emoji);
  if (idx == null) return false; // 额外两枚没有库内序号，不参与选中
  return current == idx;
}

/// 点同一枚＝取消（返回 null）；点别的＝切过去。
int? moodToggled(int? current, String emoji) {
  final idx = diaryMoodIndex(emoji);
  if (idx == null) return current; // 额外两枚点了不改库内心情（只做视觉回显，见页面注释）
  return current == idx ? null : idx;
}

/// 保存态三态（原型 `syncSaveState` / `saveDiary`）：clean / dirty / saving。
enum DiarySaveState { clean, dirty, saving }

/// 提示文案（原型逐字）。
String diarySaveHint(DiarySaveState s) => switch (s) {
      DiarySaveState.clean => '草稿已自动保存',
      DiarySaveState.dirty => '有未保存修改',
      DiarySaveState.saving => '保存中…',
    };

/// 保存钮是否降透明（原型 clean/saving 都是 `.45`，dirty 全亮）。
bool diarySaveDimmed(DiarySaveState s) => s != DiarySaveState.dirty;

/// 头部日期：`10-19 星期一`（原型 `diaryHeadDateRender`）。
///
/// 与旧实现的差别：旧实现是「周几」（周五）；原型批2 明确改成**星期全称**——
/// 简称对不熟中文习惯的人可读性差（产品原话）。跨年补年份；跨年时也补到日（`2025-09-19`）。
/// [now] 只用于判「是否当年」，测试可注入。
String diaryHeadDate(DateTime day, {DateTime? now}) {
  const wd = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  final ref = now ?? DateTime.now();
  final md = '${_two(day.month)}-${_two(day.day)}';
  final head = day.year == ref.year ? md : '${day.year}-$md';
  return '$head ${wd[day.weekday - 1]}';
}

String _two(int v) => v.toString().padLeft(2, '0');
