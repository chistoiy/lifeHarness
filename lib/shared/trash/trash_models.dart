import 'dart:ui';

/// V1.60 全局回收站（需求清单 §四「全局回收站」·真机轮4 批C⑦）。
///
/// 七类「删除但保留记录」的内容统一进一屏：待办 / 笔记 / 习惯 / 书籍 / 划线书摘 / 书单 / 物品。
/// 行＝模块标签＋正文＋副信息＋删于时间＋剩余天数（≤7 天标红）；
/// 恢复＝回原模块原位（不新建条目）；彻底删除走二次确认并逐条列出。
/// 语义断链批（2026-10-12）：日记为第八类（拍板「进回收站」——最私人数据不再硬删）。
enum TrashKind {
  todo('待办', Color(0xFF818CF8)),
  note('笔记', Color(0xFF38BDF8)),
  habit('习惯', Color(0xFF2DD4BF)),
  book('书籍', Color(0xFFFBBF24)),
  quote('划线书摘', Color(0xFFFB7185)),
  list('书单', Color(0xFF8B5CF6)),
  item('物品', Color(0xFFFB923C)),
  journal('日记', Color(0xFF60A5FA));

  const TrashKind(this.label, this.dot);

  /// 人话模块名（原型 GT_K.n）。
  final String label;

  /// 行首圆点色（原型 bg-*-400）。
  final Color dot;

  /// 恢复成功回执文案（原型 ttRestore 单项映射；待办/有书名的划线由调用方补全）。
  String get restoreToast => switch (this) {
        TrashKind.note => '已恢复到原文件夹',
        TrashKind.habit => '已恢复到习惯列表',
        TrashKind.book => '已回到书架 · 缓存态按源文件现状走守卫',
        TrashKind.list => '已恢复到书单列表',
        TrashKind.item => '已回到物品列表 · 每日计费按删除前状态继续',
        TrashKind.journal => '已恢复到原日期',
        _ => '已恢复',
      };
}

/// 回收站里的一行（跨各类的统一视图模型）。
class TrashItem {
  const TrashItem({
    required this.kind,
    required this.rawId,
    required this.title,
    this.deletedAt,
    this.subs = const [],
    this.amberSub = false,
    this.orphan = false,
    this.orphanHint,
    this.cascadeNotes,
    this.cascadeQuotes,
    this.src,
  });

  final TrashKind kind;

  /// 模块内主键（todos/notes/quotes/lists 为 int，habits/books 为 String）。
  final Object rawId;
  final String title;
  final DateTime? deletedAt;

  /// 行内副信息（不含「删于/剩余」）：书籍＝连带读数，划线＝所属书，书单＝成员数，待办＝截止/标签。
  final List<String> subs;

  /// 书籍连带读数用琥珀色（原型 text-amber-600）。
  final bool amberSub;

  /// 孤行＝所属书行已不在架（被彻底删除或仍在回收站），不可单独恢复（需求防幽灵口径）。
  final bool orphan;

  /// 孤行为什么孤（置灰行的说明文案）。
  final String? orphanHint;

  /// 仅书籍：彻底删除时连带清除的**在库**划线书摘条数（确认弹层读数）。
  final int? cascadeQuotes;

  /// 彻底删除确认弹层里那句玫红后果（逐类自填人话，如物品＝「连带清 成本时间轴 N 条…」）。
  /// 不给则弹层按类别走各自既有分支——**有连带清除内容的类必须给**，不许静默。
  final String? cascadeNotes;

  /// 源模型对象（Todo/Note/Habit/Book/BookQuote/BookList），按类型分派恢复与彻底删除。
  final Object? src;

  String get key => '${kind.name}:$rawId';
}

/// 垃圾箱条目剩余保留天数（与「记录管理 · 通用 · 回收站自动清理」同档）。
/// 返回 null＝设置为「不清理」；<=0＝已到期、下次启动清理（文案「待清理」）。
int? trashLeftDays(DateTime? deletedAt, int keepDays, DateTime now) {
  if (keepDays <= 0) return null;
  if (deletedAt == null) return keepDays;
  final ago = DateTime(now.year, now.month, now.day)
      .difference(DateTime(deletedAt.year, deletedAt.month, deletedAt.day))
      .inDays;
  return keepDays - ago;
}

/// 剩余天数文案（原型 ttLeftTxt：不清理 / 待清理 / 剩 N 天）。
String trashLeftTxt(DateTime? deletedAt, int keepDays, DateTime now) {
  final left = trashLeftDays(deletedAt, keepDays, now);
  if (left == null) return '不清理';
  return left <= 0 ? '待清理' : '剩 $left 天';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 「删于 09-19 14:20」（原型口径：月-日 时:分）。
String trashDelStamp(DateTime? deletedAt) => deletedAt == null
    ? '删于 --'
    : '删于 ${_two(deletedAt.month)}-${_two(deletedAt.day)} '
        '${_two(deletedAt.hour)}:${_two(deletedAt.minute)}';

/// epoch 毫秒 → DateTime（null 透传）。
DateTime? trashTimeOf(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
