import 'dart:convert';

import '../nav/nav_collapse.dart';
import '../nav/nav_module.dart';

/// V1.65·底栏收起线索「距屏幕底部」的档位（px，闭区间）——设置滑杆与
/// [UserSettings.fromMap] 的越界收敛**同源读这一份**，防两处各写一套数字。
const int kNavLineGapMin = 8;
const int kNavLineGapMax = 48;
const int kNavLineGapDefault = 16;

/// 深色模式偏好（与主题风格正交，可叠加）。
enum ThemeModeOption {
  system('system'),
  light('light'),
  dark('dark');

  const ThemeModeOption(this.id);
  final String id;

  static ThemeModeOption fromId(String? id) => ThemeModeOption.values
      .firstWhere((e) => e.id == id, orElse: () => ThemeModeOption.system);
}

/// 提醒通知设置（原型 p-sub-notify；M0末A：待办提醒/收集箱整理/日记复盘真实排程，
/// 习惯提醒与免打扰为存储位生效在后续里程碑）。
class NotifySettings {
  const NotifySettings({
    this.todoEvent = true,
    this.leadMin = 10,
    this.overdueEscalate = true,
    this.diaryReview = false,
    this.diaryTime = '21:30',
    this.inboxClean = false,
    this.habits = false,
    this.dnd = false,
  });

  /// 📅 日程与任务提醒总开关（待办 remind_at 排程随此开关）。
  final bool todoEvent;

  /// 默认提前量（分钟；M0 存位，日程事件提醒接入后生效）。
  final int leadMin;

  /// 逾期任务升级提醒（B 批建议卡联动）。
  final bool overdueEscalate;

  /// 📔 日记复盘提醒（每日 diaryTime）。
  final bool diaryReview;
  final String diaryTime;

  /// ⚡ 收集箱清理提醒（每天 21:00）。
  final bool inboxClean;

  /// 🔁 习惯提醒（习惯模块 M1 前为存位）。
  final bool habits;

  /// ⛔ 免打扰时段（23:00–07:00 固定存位，穿透策略 M2）。
  final bool dnd;

  bool get anyDailyOn => diaryReview || inboxClean;

  /// 已开启的「真排程」提醒类数（日程与任务 / 日记复盘 / 收集箱清理）。
  /// 规格单源（2026-10-11 批A 立）：「我的」页该行读数与通知页表头同吃这一个计数，
  /// 不许两处各写一遍；习惯提醒与免打扰是存储位，不计入。
  int get scheduledOnCount =>
      (todoEvent ? 1 : 0) + (diaryReview ? 1 : 0) + (inboxClean ? 1 : 0);

  NotifySettings copyWith({
    bool? todoEvent,
    int? leadMin,
    bool? overdueEscalate,
    bool? diaryReview,
    String? diaryTime,
    bool? inboxClean,
    bool? habits,
    bool? dnd,
  }) =>
      NotifySettings(
        todoEvent: todoEvent ?? this.todoEvent,
        leadMin: leadMin ?? this.leadMin,
        overdueEscalate: overdueEscalate ?? this.overdueEscalate,
        diaryReview: diaryReview ?? this.diaryReview,
        diaryTime: diaryTime ?? this.diaryTime,
        inboxClean: inboxClean ?? this.inboxClean,
        habits: habits ?? this.habits,
        dnd: dnd ?? this.dnd,
      );

  Map<String, Object?> toMap() => {
        'todoEvent': todoEvent,
        'leadMin': leadMin,
        'overdueEscalate': overdueEscalate,
        'diaryReview': diaryReview,
        'diaryTime': diaryTime,
        'inboxClean': inboxClean,
        'habits': habits,
        'dnd': dnd,
      };

  factory NotifySettings.fromMap(Map<String, Object?> m) => NotifySettings(
        todoEvent: m['todoEvent'] as bool? ?? true,
        leadMin: m['leadMin'] as int? ?? 10,
        overdueEscalate: m['overdueEscalate'] as bool? ?? true,
        diaryReview: m['diaryReview'] as bool? ?? false,
        diaryTime: m['diaryTime'] as String? ?? '21:30',
        inboxClean: m['inboxClean'] as bool? ?? false,
        habits: m['habits'] as bool? ?? false,
        dnd: m['dnd'] as bool? ?? false,
      );
}

/// 用户可变设置快照（主题 / 深色模式 / 底部导航 / 提醒通知 / 主页卡片顺序）。
///
/// 骨架阶段持久化用 shared_preferences 模拟；正式版换 settings 表并随备份策略
/// （ADR D11：原型与两环境实现差异抽象为存储接口层）。
class UserSettings {
  const UserSettings({
    required this.themeId,
    required this.mode,
    required this.navIds,
    this.notify = const NotifySettings(),
    this.homeCardOrder = kHomeCardIds,
    this.noteRestoreMode = 'replace',
    this.noteLatex = false,
    this.notePlainLineNum = false,
    this.noteSwipe = false,
    this.noteFolder = '',
    this.noteSort = 'updated',
    this.noteSortAsc = false,
    this.noteViewCols = 0,
    this.trashKeepDays = 30,
    this.weatherCity = '',
    this.profileNick = '',
    this.profileBio = '',
    this.navGestureOn = false,
    this.navLineStyle = 'a',
    this.navLineGap = kNavLineGapDefault,
    this.myLayout = 'hero',
    this.journalDefaultTpl = '纯文本',
    this.journalFilter = 'all',
    this.journalTags = const [],
    this.journalLayout = 'list',
    this.journalIns = false,
    this.journalRange = 'all',
    this.journalFrom = '',
    this.journalTo = '',
    this.calMonthExpanded = true,
  });

  final String themeId;
  final ThemeModeOption mode;
  final List<String> navIds;
  final NotifySettings notify;

  /// 主页卡片顺序（原型 DASH_IDS；M0末C 自由编排持久化）。
  final List<String> homeCardOrder;

  /// 笔记快照恢复方式（V1.29轮1·记录管理）：
  /// replace=直接替换当前正文（替换前自动留快照）· copy=新增为副本笔记。
  final String noteRestoreMode;

  /// V1.29轮9k·记录管理：MD 预览 LaTeX 公式渲染开关（默认关=按原文显示 $..$/$$..$$）。
  final bool noteLatex;

  /// V1.29轮9p·笔记⋯弹层：纯文本行号开关（仅 kind=plain 生效，默认关）。
  final bool notePlainLineNum;

  /// V1.29轮10-2·记录管理：编辑页左右滑动切换上下篇开关（默认关=轮8②常开改为可选）。
  final bool noteSwipe;

  /// 批5③（2026-10-12）·笔记段「当前文件夹」持久化（'' = 全部；其余 = 文件夹名）。
  /// 冷启动恢复上次所在目录；夹被删/改名后由 `NoteTab` 侧校验回落「全部」。
  final String noteFolder;

  /// 批5③·笔记排序键（NoteSort.name：'updated' / 'created' / 'title'）。
  final String noteSort;

  /// 批5③·排序方向（false = 降序/A→Z，true = 升序/Z→A）。
  final bool noteSortAsc;

  /// 批5③·笔记视图档（0 = 列表；2/3 = 卡片每行列数；脏值在 provider 侧收敛到 0）。
  final int noteViewCols;

  /// V1.57 E 批 · 记录管理「通用 · 回收站自动清理」：待办垃圾箱保留天数
  /// 档位 30/7/90，0＝不清理（默认 30）。垃圾箱入口/期限文案与冷启动自动清理同源读这里。
  final int trashKeepDays;

  /// 期限展示文案（原型 ttKeepTxt 同源）：'删除 30 天后自动彻底删除' / '不自动清理'。
  String get trashKeepTxt =>
      trashKeepDays > 0 ? '删除 $trashKeepDays 天后自动彻底删除' : '不自动清理';

  /// M1批2e·设置页：日记天气城市（编码 `name|lat|lon`·''=未设置不抓取）。
  final String weatherCity;

  /// R14-12·我的页资料：昵称（''=未设置，界面回落「本地用户」）。
  /// 口径：**只进设置项 KV，不建表、不做迁移**——本地模式无账号，资料属偏好而非业务数据，
  /// 随 prefs 一起进整包备份与 WebDAV 同步，换机即带走。
  final String profileNick;

  /// R14-12·我的页资料：一句话签名（''=不显示）。
  final String profileBio;

  /// V1.65·底栏手势总开关（**默认关**，产品 2026-10-11 裁定）：开＝壳内双指张开收起底栏、
  /// 双指捏合还原。默认关＝装完不改变老用户行为，用户到「设置 › 外观 › 底栏手势」自己开。
  final bool navGestureOn;

  /// V1.65·底栏收起后的「可见线索」形态：'a'＝细握把（默认）· 'b'＝胶囊折角。
  /// 两条都保留、由设置切换（产品 2026-10-11 拍板）。
  /// 2026-10-18 加第三档 'none'＝不画线索（靠双指捏合还原，产品令），
  /// 收敛口径见 `navCueStyleOf`（'a'/'b'/'none' 之外一律回落 'a'）。
  final String navLineStyle;

  /// V1.65·线索距屏幕底部的距离（px，档位闭区间 [kNavLineGapMin,kNavLineGapMax]）。
  /// 越界值在 [fromMap] / 控制器里统一收敛，界面不出现越界读数。
  final int navLineGap;

  /// 「我的」页版式（原型 p-profile 三版式，2026-10-12 产品令 · 设置内可切换）。
  /// 'hero'＝记录仪表（默认·渐变身份卡＋连击环＋读数带＋里程碑）；'chapters'＝编辑章节
  /// （编号章节标＋连续卷轴＋居中签名页脚）；'minimal'＝极简卷轴（去编号去发丝·纯留白分组）。
  /// 未知值在 [fromMap] 收敛到 'hero'（照 trashKeepDays / navLineStyle 先例，界面不出现越界档）。
  final String myLayout;

  /// 演示残留批（2026-10-12）·记录管理「默认新建模板」：新建日记预选模板名。
  /// '纯文本'=自由书写（默认）；其余为模板名（编辑页按名查模板，查无回落自由书写）。
  /// 档位与原型 cycleRecSet 对齐：纯文本/KPT 复盘/晨间三问；脏值在 [fromMap] 收敛。
  final String journalDefaultTpl;

  /// 语义断链批 #27（2026-10-12）·记录页日记段持久化（笔记批5③ 同族）：
  /// 筛选键（'all'|'todo'|标签名）。标签被改删后由 UI 侧按当前标签集校验回落 'all'。
  ///
  /// 日记改版收尾批（2026-10-19）：**语义收窄为「标记」单选键**（all/todo/starred/liked），
  /// 标签筛选拆到 [journalTags] 多值。旧版本可能在这键里存标签名——读侧做**只读兼容**
  /// （见 `dfTagsOf`），不在 core 层迁移（core 不得依赖 feature 的标签池判据）。
  final String journalFilter;

  /// 日记改版收尾批（2026-10-19）·筛选标签**多选**（选中多个＝AND，对齐原型 `diaryTags`）。
  ///
  /// 与 [journalFilter]（标记）**正交并存**：原型 `dwHit` 是「标签 every 命中」＋「标记命中」
  /// 两条都过才算命中，选标签不会顶掉标记。
  ///
  /// 落盘用 `\u0001` 分隔（标签名由用户输入，可能含逗号/空格，逗号分隔会静默拆错）；
  /// 脏值在 [fromMap] 收敛：去空、去重、上限 32 枚（防手改 prefs 塞爆）。
  final List<String> journalTags;

  /// #27：INS 卡片流布局（false=列表·默认）。**旧值位**，新数据只写 [journalLayout]。
  /// 保留它是为了让 `v0.2.x` 的备份包 / 老 prefs 还能反序列化（见 [journalLayout] 收敛）。
  final bool journalIns;

  /// 日记页视图三档（日记改版批1a · 2026-10-19）：`track` 日期轨道 / `list` 列表 / `ins` 卡片流。
  /// 默认 `list`（产品口径「默认使用列表展示」）。旧布尔 `journalIns` 在 [fromMap] 里**单向映射**：
  /// `true → ins`（老用户开着 INS 的不能被重置回列表），读写出货一律不再碰旧位。
  final String journalLayout;

  /// 日记改版批2d（2026-10-19）：筛选的时间段键（8 档预设 或 `custom`）。
  ///
  /// 键集与展示名在 `features/journal/domain/diary_filter_kit.dart`；
  /// core 层只认「合法键」，不去 import feature（分层红线：core 不得依赖 feature）。
  final String journalRange;

  /// 自定义起止（`YYYY-MM-DD`；空串＝该端不设限＝开区间）。
  ///
  /// 与 [journalRange] 分开存、且切到预设档时**不清**这两个值：用户切回「自定义」
  /// 还能拿回上次选的区间（原型 `dfFrom/dfTo` 本来就是常驻的）。
  final String journalFrom;
  final String journalTo;

  /// 时间段合法键（8 档预设 ＋ `custom`）。脏值在 [fromMap] 收敛到 `all`。
  static const List<String> kJournalRanges = [
    'all', '7d', '30d', '90d', 'year', 'month', '1y', '2y', 'custom',
  ];

  /// 筛选标签多值的落盘分隔符。**不用逗号**：标签名由用户输入，
  /// 含逗号时逗号分隔会静默把一枚标签拆成两枚（与小组件草稿同一口径）。
  static const String _kJournalTagSep = '\u0001';

  /// 筛选标签多值的上限。超过即丢弃尾部——手改 prefs 塞几千条会让
  /// 筛选弹层每帧都算一遍宽度，属于「脏数据不该拖垮界面」的兜底。
  static const int kJournalTagMax = 32;

  /// 解析落盘的标签串：去空、去重（保序）、截断到 [kJournalTagMax]。
  static List<String> decodeJournalTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <String>[];
    for (final part in raw.split(_kJournalTagSep)) {
      final t = part.trim();
      if (t.isEmpty || out.contains(t)) continue;
      out.add(t);
      if (out.length >= kJournalTagMax) break;
    }
    return out;
  }

  /// 时间模块批1（C2/B9）：时间页月历展开态（true=展开·默认；false=收起为周行）。
  /// 首次进模块默认展开；用户手动切换后写盘（跨会话记住）；切视图档不改它。
  final bool calMonthExpanded;

  /// 昵称展示值（未设置时的回落名，界面各处统一用它，避免各页各写一套默认）。
  String get nickOrFallback => profileNick.isEmpty ? '本地用户' : profileNick;

  /// 可编排卡片 id 全集（顺序之外新增卡片按此兜底补齐）。
  static const List<String> kHomeCardIds = [
    'greeting',
    'mood',
    'events',
    'inboxBar',
    'health',
    'days',
    'chart',
    'grid',
  ];

  List<NavModule> get navModules => navIds.map(NavModule.fromId).toList();

  static const UserSettings defaults = UserSettings(
    themeId: 'minimal',
    mode: ThemeModeOption.system,
    // 今天/我的固定，中间三个可切换栏目（最多 5，需求 V1.5）。
    navIds: ['today', 'todo', 'calendar', 'journal', 'settings'],
  );

  UserSettings copyWith({
    String? themeId,
    ThemeModeOption? mode,
    List<String>? navIds,
    NotifySettings? notify,
    List<String>? homeCardOrder,
    String? noteRestoreMode,
    bool? noteLatex,
    bool? notePlainLineNum,
    bool? noteSwipe,
    String? noteFolder,
    String? noteSort,
    bool? noteSortAsc,
    int? noteViewCols,
    int? trashKeepDays,
    String? weatherCity,
    String? profileNick,
    String? profileBio,
    bool? navGestureOn,
    String? navLineStyle,
    int? navLineGap,
    String? myLayout,
    String? journalDefaultTpl,
    String? journalFilter,
    List<String>? journalTags,
    String? journalLayout,
    bool? journalIns,
    String? journalRange,
    String? journalFrom,
    String? journalTo,
    bool? calMonthExpanded,
  }) =>
      UserSettings(
        themeId: themeId ?? this.themeId,
        mode: mode ?? this.mode,
        navIds: navIds ?? this.navIds,
        notify: notify ?? this.notify,
        homeCardOrder: homeCardOrder ?? this.homeCardOrder,
        noteRestoreMode: noteRestoreMode ?? this.noteRestoreMode,
        noteLatex: noteLatex ?? this.noteLatex,
        notePlainLineNum: notePlainLineNum ?? this.notePlainLineNum,
        noteSwipe: noteSwipe ?? this.noteSwipe,
        noteFolder: noteFolder ?? this.noteFolder,
        noteSort: noteSort ?? this.noteSort,
        noteSortAsc: noteSortAsc ?? this.noteSortAsc,
        noteViewCols: noteViewCols ?? this.noteViewCols,
        trashKeepDays: trashKeepDays ?? this.trashKeepDays,
        weatherCity: weatherCity ?? this.weatherCity,
        profileNick: profileNick ?? this.profileNick,
        profileBio: profileBio ?? this.profileBio,
        navGestureOn: navGestureOn ?? this.navGestureOn,
        navLineStyle: navLineStyle ?? this.navLineStyle,
        navLineGap: navLineGap ?? this.navLineGap,
        myLayout: myLayout ?? this.myLayout,
        journalDefaultTpl: journalDefaultTpl ?? this.journalDefaultTpl,
        journalFilter: journalFilter ?? this.journalFilter,
        journalTags: journalTags ?? this.journalTags,
        journalLayout: journalLayout ?? this.journalLayout,
        journalIns: journalIns ?? this.journalIns,
        journalRange: journalRange ?? this.journalRange,
        journalFrom: journalFrom ?? this.journalFrom,
        journalTo: journalTo ?? this.journalTo,
        calMonthExpanded: calMonthExpanded ?? this.calMonthExpanded,
      );

  Map<String, Object> toMap() => {
        'themeId': themeId,
        'mode': mode.id,
        'navIds': navIds.join(','),
        'notify': jsonEncode(notify.toMap()),
        'homeOrder': homeCardOrder.join(','),
        'noteRestoreMode': noteRestoreMode,
        'noteLatex': noteLatex,
        'notePlainLineNum': notePlainLineNum,
        'noteSwipe': noteSwipe,
        'noteFolder': noteFolder,
        'noteSort': noteSort,
        'noteSortAsc': noteSortAsc,
        'noteViewCols': noteViewCols,
        'trashKeepDays': trashKeepDays,
        'weatherCity': weatherCity,
        'profileNick': profileNick,
        'profileBio': profileBio,
        'navGestureOn': navGestureOn,
        'navLineStyle': navLineStyle,
        'navLineGap': navLineGap,
        'myLayout': myLayout,
        'journalDefaultTpl': journalDefaultTpl,
        'journalFilter': journalFilter,
        'journalTags': journalTags.join(_kJournalTagSep),
        'journalLayout': journalLayout,
        'journalIns': journalIns,
        'journalRange': journalRange,
        'journalFrom': journalFrom,
        'journalTo': journalTo,
        'calMonthExpanded': calMonthExpanded,
      };

  factory UserSettings.fromMap(Map<String, Object?> m) => UserSettings(
        themeId: m['themeId'] as String? ?? defaults.themeId,
        mode: ThemeModeOption.fromId(m['mode'] as String?),
        navIds: (m['navIds'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ??
            defaults.navIds,
        notify: _decodeNotify(m['notify'] as String?),
        homeCardOrder: _sanitizeHomeOrder(m['homeOrder'] as String?),
        noteRestoreMode:
            (m['noteRestoreMode'] as String?) == 'copy' ? 'copy' : 'replace',
        noteLatex: m['noteLatex'] as bool? ?? false,
        notePlainLineNum: m['notePlainLineNum'] as bool? ?? false,
        noteSwipe: m['noteSwipe'] as bool? ?? false,
        noteFolder: m['noteFolder'] as String? ?? '',
        noteSort: const {'updated', 'created', 'title'}.contains(m['noteSort'])
            ? m['noteSort'] as String
            : 'updated',
        noteSortAsc: m['noteSortAsc'] as bool? ?? false,
        noteViewCols: const {0, 2, 3}.contains(m['noteViewCols'])
            ? m['noteViewCols'] as int
            : 0,
        trashKeepDays: const {0, 7, 30, 90}.contains(m['trashKeepDays'])
            ? m['trashKeepDays'] as int
            : 30,
        weatherCity: m['weatherCity'] as String? ?? '',
        profileNick: m['profileNick'] as String? ?? '',
        profileBio: m['profileBio'] as String? ?? '',
        navGestureOn: m['navGestureOn'] as bool? ?? false,
        navLineStyle: navCueStyleOf(m['navLineStyle'] as String? ?? 'a'),
        // 越界值一律收敛到档位闭区间（照 trashKeepDays 的先例，界面不出现越界读数）。
        navLineGap: (m['navLineGap'] as int? ?? kNavLineGapDefault).clamp(
            kNavLineGapMin, kNavLineGapMax),
        // 未知档一律收敛到默认 hero（界面不出现越界版式；与 navLineStyle 同口径）。
        myLayout: const {'hero', 'chapters', 'minimal'}.contains(m['myLayout'])
            ? m['myLayout'] as String
            : 'hero',
        // 演示残留批：脏值收敛到三档（照 myLayout 先例；查无模板时编辑页再回落自由书写）。
        journalDefaultTpl:
            const {'纯文本', 'KPT 复盘', '晨间三问'}.contains(m['journalDefaultTpl'])
                ? m['journalDefaultTpl'] as String
                : '纯文本',
        // #27：空串/脏值回落 'all'（标签名不在此校验，UI 侧按当前标签集回落）。
        // 收尾批：本键语义已收窄为「标记」，标签名不再写这里；历史值由 `dfTagsOf` 只读兼容。
        journalFilter: (m['journalFilter'] as String?) is String &&
                (m['journalFilter'] as String).isNotEmpty
            ? m['journalFilter'] as String
            : 'all',
        journalTags: decodeJournalTags(m['journalTags'] as String?),
        /* 三档收敛：合法值直取；脏值/缺键时看旧布尔位（true＝老 INS 用户，别把他拽回列表）。 */
        journalLayout: _journalLayoutOf(m),
        journalIns: m['journalIns'] as bool? ?? false,
        /* 时间段：脏键回落 'all'（不设限＝最不容易误伤）；起止只校验「是不是字符串」，
           格式合法性归应用侧（dfRangeValid）——core 层不引 feature 的判据。 */
        journalRange: (m['journalRange'] is String &&
                kJournalRanges.contains(m['journalRange']))
            ? m['journalRange']! as String
            : 'all',
        journalFrom: m['journalFrom'] is String ? m['journalFrom']! as String : '',
        journalTo: m['journalTo'] is String ? m['journalTo']! as String : '',
        calMonthExpanded: m['calMonthExpanded'] as bool? ?? true,
      );

  /// 视图三档合法值（顺序＝设置弹层里的排列顺序；`track` 排首位但不是默认）。
  static const List<String> kJournalLayouts = ['track', 'list', 'ins'];

  /// 三档收敛（单向兼容旧布尔位）：合法值 > 旧 `journalIns` > 默认 `list`。
  static String _journalLayoutOf(Map<String, Object?> m) {
    final v = m['journalLayout'];
    if (v is String && kJournalLayouts.contains(v)) return v;
    final old = m['journalIns'];
    if (old is bool && old) return 'ins';
    return 'list';
  }

  /// 校验存储顺序：剔除未知 id、补齐缺失卡片（版本升级新增卡自动排尾部）。
  static List<String> _sanitizeHomeOrder(String? raw) {
    if (raw == null || raw.isEmpty) return kHomeCardIds;
    final saved =
        raw.split(',').where(kHomeCardIds.contains).toList().toSet();
    final missing = kHomeCardIds.where((id) => !saved.contains(id));
    return [...saved, ...missing];
  }

  static NotifySettings _decodeNotify(String? raw) {
    if (raw == null || raw.isEmpty) return const NotifySettings();
    try {
      return NotifySettings.fromMap(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return const NotifySettings();
    }
  }
}
