import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/ai/ai_providers.dart' show aiConfigProvider;
import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../../../core/nav/nav_collapse.dart'
    show NavLineCapsule, NavLineGrip;
import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/settings/user_settings.dart';
import '../../../core/sync/sync_providers.dart' show activeSyncServiceProvider;
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/trash/trash_providers.dart';
import '../../../shared/widgets/scroll_pad.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'profile_edit_sheet.dart';

/// 我的/设置（M0 · 对齐原型 p-profile）。
/// 真数据：完成任务数/连续记录天/在册书籍/同步与提醒读数/安装包版本号。
/// 2026-10-11 批A：行序与卡片分组回到原型（记录管理收回组卡、维护类三行移末段）；
/// 仍为死键待批C 落地＝主题市场（原型 `sheetThemeMarket` 未实现）、字号调节。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsControllerProvider);
    final streak = ref.watch(streakDaysProvider).valueOrNull ?? 0;
    final doneTasks = ref.watch(doneTaskCountProvider).valueOrNull ?? 0;
    // R14-12/13：资料与读数带同源实算——昵称/签名走设置项，书籍数走聚合层。
    final nick = settings.nickOrFallback;
    final books = ref.watch(shelfBookCountProvider).valueOrNull ?? 0;
    // 关于卡版本行（2026-10-11 批A）：读安装包真值，装机复验期在机内可自查。
    final ver = ref.watch(appVersionProvider).valueOrNull ?? '';

    // 「我的」页版式（原型 p-profile 三版式，2026-10-12 产品令）：
    // hero＝渐变身份卡＋常驻圆角卡；chapters＝身份行＋去卡读数带、组标题编号化＋行间发丝；
    // minimal＝同 chapters 但去掉编号与发丝、纯留白分组。三档同读 settings.myLayout。
    final lay = settings.myLayout;
    final isHero = lay == 'hero';
    final flat = !isHero; // 去卡（chapters/minimal）
    final hairline = lay != 'minimal'; // 行间发丝（仅 minimal 去）
    final showIndex = lay == 'chapters'; // 组标题编号
    final dimLabel = lay == 'minimal'; // 组标题更淡
    final sub = '本地模式 · 无账号 · 已记录 $streak 天'
        '${settings.profileBio.isEmpty ? '' : ' · ${settings.profileBio}'}';

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ScrollPad(
        // T2-B：「我的」主屏滚动垫（切栏回来原位）。
        id: 'profile',
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== 顶部身份区（原型 p-profile：hero＝渐变身份卡 / 其余＝身份行＋读数带）=====
          if (isHero)
            _ProfileHero(
              nick: nick,
              sub: sub,
              done: '$doneTasks',
              streak: '$streak',
              books: '$books',
              onEdit: () => showProfileEditSheet(context, ref),
              onTodo: () => context.go(NavModule.todo.path),
              onJournal: () => context.go(NavModule.journal.path),
              onShelf: () => context.push('/read/shelf'),
            )
          else ...[
            _ProfileIdentityRow(
              nick: nick,
              sub: sub,
              onEdit: () => showProfileEditSheet(context, ref),
              onSub: () => context.go(NavModule.journal.path),
            ),
            const SizedBox(height: 12),
            _ReadoutBand(
              done: '$doneTasks',
              streak: '$streak',
              books: '$books',
              numSize: lay == 'minimal' ? 23 : 21,
              onTodo: () => context.go(NavModule.todo.path),
              onJournal: () => context.go(NavModule.journal.path),
              onShelf: () => context.push('/read/shelf'),
            ),
          ],
          // ===== 四组入口（原型批B 分组结构：记录 / 数据与提醒 / 外观与交互 / 系统与维护）=====
          // 组标题在 chapters 版式带编号 01–04；每组行序＝原型 p-profile 原序的连续子序列。
          _GroupLabel(title: '记录', index: showIndex ? '01' : null, dim: dimLabel),
          _EntryCard(
            flat: flat,
            child: Column(
              children: [
                _EntryRow(
                    key: const ValueKey('entry-cats'),
                    iconWidget: const Icon(Icons.label_outline,
                        size: 18, color: Color(0xFFF97316)),
                    bg: const Color(0xFFF97316).withValues(alpha: .12),
                    title: '分类管理',
                    sub: '时间块/日程两级分类 · 颜色 · 标签 · 拖拽换组',
                    trailing: '',
                    divider: hairline,
                    onTap: () => context.push('/categories')),
                // 记录管理（原型 p-profile 在组卡内）：2026-10-11 批A 由独立单行卡收回组卡。
                _EntryRow(
                    key: const ValueKey('entry-recmg'),
                    iconWidget: const Icon(Icons.menu_book_outlined,
                        size: 18, color: Color(0xFF8B5CF6)),
                    bg: const Color(0xFF8B5CF6).withValues(alpha: .12),
                    title: '记录管理',
                    sub: '版本恢复 · 快照 · 文件夹',
                    trailing: '',
                    last: true,
                    onTap: () => context.push('/settings/recmg')),
              ],
            ),
          ),
          _GroupLabel(
              title: '数据与提醒',
              index: showIndex ? '02' : null,
              dim: dimLabel),
          _EntryCard(
            flat: flat,
            child: Column(
              children: [
                _EntryRow(
                    key: const ValueKey('entry-sync'),
                    iconWidget: const Icon(Icons.cloud_outlined,
                        size: 18, color: Color(0xFF10B981)),
                    bg: const Color(0xFF10B981).withValues(alpha: .12),
                    title: '数据与同步',
                    sub: 'WebDAV · 备份 · 加密 · 同步历史',
                    // 真机反馈轮①：读激活服务真值；措辞用「已配置」不用「已连接」
                    //（本机只知道自己存了端点，连通性＝同步页「测试连接」的口径）。
                    trailing: ref.watch(activeSyncServiceProvider) == null
                        ? '● 未配置'
                        : '● 已配置',
                    trailingColor: ref.watch(activeSyncServiceProvider) == null
                        ? Colors.grey
                        : const Color(0xFF10B981),
                    divider: hairline,
                    // R2 项④：go→push，从设置页进后返回回设置页而非退出 app。
                    onTap: () => context.push('/sync')),
                // 批8收口：母婴敏感数据同步排除联动行（开关实体在呵护提醒页）。
                const _CareSyncLink(),
                // 提醒通知：读数照原型出「N 项开启」——
                // 此前把三项压成一个布尔，开 1 项与开 3 项显示完全相同。
                _EntryRow(
                    iconWidget: const Icon(Icons.notifications_none,
                        size: 18, color: Color(0xFF6366F1)),
                    bg: const Color(0xFF6366F1).withValues(alpha: .12),
                    title: '提醒通知',
                    sub: '日程 · 日记复盘 · 收集箱清理 · 习惯',
                    trailing:
                        '${ref.watch(settingsControllerProvider).notify.scheduledOnCount} 项开启',
                    trailingColor: Colors.grey,
                    divider: hairline,
                    onTap: () => context.push('/settings/notify')),
                _EntryRow(
                    key: const ValueKey('entry-ai'),
                    iconWidget: const Icon(Icons.memory,
                        size: 18, color: Color(0xFF8B5CF6)),
                    bg: const Color(0xFF8B5CF6).withValues(alpha: .12),
                    title: 'AI 增强',
                    sub: '服务商 · Key · 能力矩阵 · API 验证',
                    trailing:
                        ref.watch(aiConfigProvider.select((c) => c.master))
                            ? '已开启'
                            : '默认关闭',
                    trailingColor:
                        ref.watch(aiConfigProvider.select((c) => c.master))
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                    last: true,
                    // AI批：占位 toast → 真实二级页（原型 p-sub-ai）。
                    onTap: () => context.push('/settings/ai')),
              ],
            ),
          ),
          _GroupLabel(
              title: '外观与交互',
              index: showIndex ? '03' : null,
              dim: dimLabel),
          // V1.27 P2：主题风格/深色/主题色/字号 收进「外观」二级页，主页只留一行入口
          _EntryCard(
            flat: flat,
            child: _EntryRow(
                    key: const ValueKey('entry-appearance'),
                    iconWidget: const Icon(Icons.palette_outlined,
                        size: 18, color: Color(0xFF0EA5E9)),
                    bg: const Color(0xFF0EA5E9).withValues(alpha: .12),
                    title: '外观',
                    sub: '主题风格 · 深色模式 · 主题色 · 字体大小',
                    trailing: '',
                    last: true,
                    onTap: () => context.push('/settings/appearance')),
          ),
          const SizedBox(height: 12),
          // 底部导航自定义卡（原型「外观与交互」组内独立卡）
          _Card(
            flat: flat,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('底部导航栏自定义',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    Text(
                      '已启用 ${settings.navIds.length}/5',
                      style: TextStyle(
                          fontSize: 11,
                          color: tokens.accent,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Text('开启的栏目实时出现在底部导航；「今天」「我的」固定',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                NavToggleGrid(settings: settings),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    // V1.27 P3：编排直达 = 回今天页并进入长按编排模式（与 H1 同一实现）
                    onPressed: () {
                      context.go(NavModule.today.path);
                      Future.delayed(const Duration(milliseconds: 350),
                          () => ref
                              .read(eventBusProvider)
                              .publish(const EnterDashEditEvent()));
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: tokens.accent.withValues(alpha: .06),
                      foregroundColor: tokens.accent,
                      side: BorderSide(color: tokens.accent.withValues(alpha: .3)),
                    ),
                    child: const Text('主页编排直达（或长按卡片）›',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          _GroupLabel(
              title: '系统与维护',
              index: showIndex ? '04' : null,
              dim: dimLabel),
          _EntryCard(
            flat: flat,
            child: Column(
              children: [
                // V1.41批1 Task 6：日志查看页入口（原型 index-sync p-log）。
                _EntryRow(
                    key: const ValueKey('entry-log'),
                    iconWidget: const Icon(Icons.receipt_long_outlined,
                        size: 18, color: Color(0xFF0891B2)),
                    bg: const Color(0xFF06B6D4).withValues(alpha: .12),
                    title: '运行日志',
                    sub: '环形缓冲 300 · 级别过滤 · 复制全量 · 保留天数',
                    trailing: '',
                    divider: hairline,
                    // R2 项④：go→push，从设置页进日志后返回回设置页而非退出 app。
                    onTap: () => context.push('/log')),
                // V1.60 全局回收站：计数与屏内、待办页卡同源。
                _EntryRow(
                    key: const ValueKey('entry-trash'),
                    iconWidget: const Icon(Icons.delete_outline,
                        size: 18, color: Color(0xFF64748B)),
                    bg: const Color(0xFF94A3B8).withValues(alpha: .14),
                    title: '回收站',
                    sub: '八类删除内容 · 保留期内可恢复',
                    trailing: '${ref.watch(trashCountsProvider).total} 项',
                    divider: hairline,
                    onTap: () => context.push('/settings/trash')),
                // R5c：图片存储清理入口（本地孤儿图片勾选清理）。
                _EntryRow(
                    key: const ValueKey('entry-media-clean'),
                    iconWidget: const Icon(Icons.image_outlined,
                        size: 18, color: Color(0xFF059669)),
                    bg: const Color(0xFF10B981).withValues(alpha: .12),
                    title: '图片存储清理',
                    sub: '未引用图片扫描 · 勾选清理',
                    trailing: '',
                    last: true,
                    onTap: () => context.push('/settings/media-clean')),
              ],
            ),
          ),
          // ===== 关于卡页脚（原型 #pfAbout）：hero＝卡；chapters/minimal＝居中签名页脚 =====
          _AboutFooter(flat: flat, center: !isHero, ver: ver),
        ],
      ),
      ),
    );
  }

  static bool _isDarkNow(BuildContext context, UserSettings s) {
    if (s.mode == ThemeModeOption.dark) return true;
    if (s.mode == ThemeModeOption.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)));
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.flat = false});

  final Widget child;

  /// 去卡（chapters/minimal 版式）：透明、无描边、无阴影，仅留内容与内边距。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: const EdgeInsets.all(16),
      child: child,
    );
    if (flat) return SizedBox(width: double.infinity, child: inner);
    return Container(
      width: double.infinity,
      decoration: context.cardDecoration,
      child: inner,
    );
  }
}

/// 单行入口卡：与上方多行组卡**同一缩进基准**。
/// 组卡本身不加 16 内边距（行自带 14），所以单行卡也必须零内边距——
/// 否则同页两类卡左缘差 16px（2026-10-07 产品指出「外观/记录管理与上方条目缩进不一致」）。
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.child, this.flat = false});

  final Widget child;

  /// 去卡（chapters/minimal 版式）：透明、无描边、无圆角、无裁剪，仅留行内容。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    if (flat) return SizedBox(width: double.infinity, child: child);
    return Container(
      width: double.infinity,
      decoration: context.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 设置行图标块（原型 .set-ic：36px 圆角浅底）。
/// 2026-10-11 批A：emoji 位已整体摘除（R14-7），此件只收线性图标；无对应线性图标时
/// 用字母标（当前仅字号位「Aa」），原 emoji/text 双参数与 16px 普通字重分支从未被走到。
class _SetIc extends StatelessWidget {
  const _SetIc({this.icon, this.glyph});

  /// R14-7：外观页小方格图标位（禁 emoji，传线性图标）。
  final IconData? icon;

  /// 无线性图标可用时的字母标（如字号位「Aa」）。
  final String? glyph;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: icon != null
          ? Icon(icon, size: 18, color: scheme.onSurfaceVariant)
          : Text(glyph ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
    );
  }
}

/// 组标题（原型 .pf-gt）：hero/minimal＝素小字；chapters＝前置编号 01–04 ＋右侧发丝线。
/// [index] 非空时启用编号与发丝（chapters 专属）；[dim]＝minimal 更淡档且间距更大。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.title, this.index, this.dim = false});

  final String title;
  final String? index;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final numbered = index != null;
    return Padding(
      padding: EdgeInsets.only(top: dim ? 30 : (numbered ? 26 : 22), bottom: 6),
      child: Row(
        children: [
          if (numbered) ...[
            Text(index!,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                    color: tokens.accent.withValues(alpha: .55),
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
          ],
          Text(title,
              style: TextStyle(
                  fontSize: dim ? 11 : 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                  color: scheme.onSurfaceVariant
                      .withValues(alpha: dim ? .6 : .85))),
          if (numbered) ...[
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                height: 1,
                color: scheme.onSurfaceVariant.withValues(alpha: .13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「我的」页·方向一「记录仪表」身份卡（原型 .pf-hero）：
/// 渐变底 ＋ 装饰圆 ＋ 头像嵌连击环（连击天数 / 100 里程碑）＋ 姓名/副行 ＋ 读数带 ＋ 里程碑行。
/// 节点 key 与 legacy 身份行同源（profile-sub / profile-edit / stat-done / stat-streak /
/// stat-books），默认版式（hero）下的既有导航微测因此仍可点。
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.nick,
    required this.sub,
    required this.done,
    required this.streak,
    required this.books,
    required this.onEdit,
    required this.onTodo,
    required this.onJournal,
    required this.onShelf,
  });

  final String nick;
  final String sub;
  final String done;
  final String streak;
  final String books;
  final VoidCallback onEdit;
  final VoidCallback onTodo;
  final VoidCallback onJournal;
  final VoidCallback onShelf;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final st = int.tryParse(streak) ?? 0;
    final ringValue = st.clamp(0, 100) / 100;
    final leftDays = (100 - st).clamp(0, 100);
    final initial = nick.isEmpty ? 'U' : nick.substring(0, 1).toUpperCase();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: tokens.gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: tokens.accent.withValues(alpha: .22),
              blurRadius: 22,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          // 装饰圆（原型 .pf-hero 内两个白色 10% 圆，出框裁切）
          Positioned(
              right: -40,
              top: -56,
              child: Container(
                  width: 144,
                  height: 144,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .10)))),
          Positioned(
              right: -8,
              top: 48,
              child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .10)))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 62,
                            height: 62,
                            child: CircularProgressIndicator(
                              value: ringValue,
                              strokeWidth: 2.6,
                              backgroundColor:
                                  Colors.white.withValues(alpha: .28),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: .20)),
                            child: Text(initial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nick,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.2)),
                          const SizedBox(height: 3),
                          // 真机反馈轮4③：副标题「已记录 N 天」点按直达日记（记录页）。
                          GestureDetector(
                            key: const ValueKey('profile-sub'),
                            behavior: HitTestBehavior.opaque,
                            onTap: onJournal,
                            child: Text(sub,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: .85))),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('profile-edit'),
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .20),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('编辑',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _heroStat('stat-done', done, '完成任务', onTodo),
                    _heroDivider(),
                    _heroStat('stat-streak', streak, '连续记录天', onJournal),
                    _heroDivider(),
                    _heroStat('stat-books', books, '在册书籍', onShelf),
                  ],
                ),
                const SizedBox(height: 12),
                // 里程碑行：给连击环补语义（移动端无 hover，裸环看不懂），
                // 也补足头像区缺失的「人格」（原型 .pf-ro 底部胶囊）。
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: .8))),
                      const SizedBox(width: 6),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: '再记 '),
                          TextSpan(
                              text: '$leftDays',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const TextSpan(text: ' 天达成百日里程碑'),
                        ]),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: .92)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String key, String value, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        key: ValueKey(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: Colors.white.withValues(alpha: .80))),
          ],
        ),
      ),
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        height: 30,
        color: Colors.white.withValues(alpha: .20),
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );
}

/// 「我的」页 chapters/minimal 顶部身份行（原型 .pf-legacy 身份行·去卡）。
class _ProfileIdentityRow extends StatelessWidget {
  const _ProfileIdentityRow({
    required this.nick,
    required this.sub,
    required this.onEdit,
    required this.onSub,
  });

  final String nick;
  final String sub;
  final VoidCallback onEdit;
  final VoidCallback onSub;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final initial = nick.isEmpty ? 'U' : nick.substring(0, 1).toUpperCase();
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(shape: BoxShape.circle, gradient: tokens.gradient),
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nick,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              GestureDetector(
                key: const ValueKey('profile-sub'),
                behavior: HitTestBehavior.opaque,
                onTap: onSub,
                child: Text(sub,
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
              ),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey('profile-edit'),
          onPressed: onEdit,
          child: Text('编辑',
              style:
                  TextStyle(color: tokens.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// chapters/minimal 顶部读数带（原型 .pf-legacy 统计行·去卡）：
/// 等宽数字 ＋ 单位小字 ＋ 发丝竖线；[numSize] 随版式（chapters 21 / minimal 23）。
class _ReadoutBand extends StatelessWidget {
  const _ReadoutBand({
    required this.done,
    required this.streak,
    required this.books,
    required this.numSize,
    required this.onTodo,
    required this.onJournal,
    required this.onShelf,
  });

  final String done;
  final String streak;
  final String books;
  final double numSize;
  final VoidCallback onTodo;
  final VoidCallback onJournal;
  final VoidCallback onShelf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String key, String value, String label, Color color,
        VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          key: ValueKey(key),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: numSize,
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    Widget hair() => Container(
        width: 1,
        height: 30,
        color: scheme.onSurfaceVariant.withValues(alpha: .14));

    return Row(
      children: [
        cell('stat-done', done, '完成任务', context.tokens.accent, onTodo),
        hair(),
        cell('stat-streak', streak, '连续记录天', const Color(0xFF2DD4BF),
            onJournal),
        hair(),
        cell('stat-books', books, '在册书籍', const Color(0xFFF59E0B), onShelf),
      ],
    );
  }
}

/// 关于卡页脚（原型 #pfAbout）：hero＝带卡；chapters/minimal＝居中签名式页脚（去卡）。
class _AboutFooter extends StatelessWidget {
  const _AboutFooter({
    required this.flat,
    required this.center,
    required this.ver,
  });

  final bool flat;
  final bool center;
  final String ver;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final head = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child:
              Image.asset('assets/brand/app_icon.png', width: 40, height: 40),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LifeHarness',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            Text('本地优先 · 自我记录 Harness',
                style: TextStyle(fontSize: 10.5, color: Colors.grey)),
          ],
        ),
      ],
    );
    final body = Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        center ? Center(child: head) : head,
        const SizedBox(height: 10),
        Text(
          '仅中文 ｜ 纯本地无账号 ｜ Android 8.0+ ｜ 离线优先 ｜ AI 能力可选增强\n'
          '7 套内置主题 · 设计令牌热加载 · 未开放模块入口灰显 + 版本角标',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
              fontSize: center ? 10.5 : 11.5,
              height: 1.7,
              letterSpacing: center ? .5 : 0,
              color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Text('版本 ${ver.isEmpty ? '—' : ver}',
            key: const ValueKey('settings-version'),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tokens.accent)),
      ],
    );
    final inner = flat
        ? Padding(
            padding: const EdgeInsets.only(top: 42),
            child: body,
          )
        : Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration,
            child: body,
          );
    return KeyedSubtree(key: const ValueKey('settings-about'), child: inner);
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.iconWidget,
    required this.bg,
    required this.title,
    required this.sub,
    required this.trailing,
    this.last = false,
    this.divider = true,
    this.trailingColor,
    required this.onTap,
  });

  /// R14-7：入口位只接受线性图标（UI 禁 emoji 硬规矩；emoji 文本位已整体摘除）。
  final Widget iconWidget;
  final Color bg;
  final String title;
  final String sub;
  final String trailing;
  final bool last;

  /// 是否画行间发丝（极小「我的」页版式去卡后一并去发丝→纯留白分组）。
  final bool divider;
  final Color? trailingColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: (last || !divider)
              ? null
              : const Border(bottom: BorderSide(color: Color(0x14000000))),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: iconWidget,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Text(trailing,
                style: TextStyle(
                    fontSize: 10.5, color: trailingColor ?? Colors.grey)),
            const Text(' ›', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// 主题预览缩略卡 3 列（原型 themeStyleRow）。
class _ThemeGrid extends ConsumerWidget {
  const _ThemeGrid({required this.registry, required this.selectedId});

  final ThemeRegistry registry;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        const cols = 3;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in registry.all)
              SizedBox(
                width: w,
                child: _ThemeTile(
                  bundle: b,
                  selected: b.id == selectedId,
                  onTap: () {
                    ref.read(settingsControllerProvider.notifier).setTheme(b.id);
                    ref.read(eventBusProvider).publish(ThemeChangedEvent(b.id));
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.bundle, required this.selected, required this.onTap});

  final ThemeBundle bundle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = bundle.pick(Theme.of(context).brightness == Brightness.dark);
    final darkBg =
        ThemeData.estimateBrightnessForColor(t.card) == Brightness.dark;
    final labelColor = darkBg ? Colors.white70 : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? t.accent : t.cardBorder, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                  gradient: t.gradient, borderRadius: BorderRadius.circular(5)),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                    child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(3)))),
                const SizedBox(width: 3),
                Expanded(
                    child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: t.page,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: t.cardBorder)))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(bundle.meta.name,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? t.accent : labelColor),
                      overflow: TextOverflow.ellipsis),
                ),
                if (selected) Icon(Icons.check_circle, size: 13, color: t.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏栏目两列开关网格（U10 批转公开：固定项锁定态要能在不设整页依赖的情况下直达取证）。
class NavToggleGrid extends ConsumerWidget {
  const NavToggleGrid({super.key, required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = {NavModule.today.id, NavModule.settings.id};
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final m in NavModule.values)
              SizedBox(
                width: w,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pinned.contains(m.id) ? '${m.label}（固定）' : m.label,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch(
                      key: ValueKey('nav-sw-${m.id}'),
                      // U10：固定栏目出「常开＋不可点」的锁定态——原读 navIds 在
                      // pinned 时取到 false，画成「关」＝误导（原型同款已改）。
                      value:
                          pinned.contains(m.id) ||
                          settings.navIds.contains(m.id),
                      onChanged: pinned.contains(m.id)
                          ? null
                          : (_) async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleNav(m);
                              if (!ok) {
                                messenger.showSnackBar(
                                    const SnackBar(content: Text('底部导航最多 5 个栏目')));
                              }
                            },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// V1.27 P2 外观二级页（原型 p-sub-appearance）：主题风格/深色模式/主题色/字体大小 收拢。
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsControllerProvider);
    final registry = ref.watch(themeRegistryProvider);
    // 强制深色主题（赛博朋克）要让深色三档置灰——按当前主题包判，不写死主题名。
    final bundle = ref.watch(currentThemeBundleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('主题风格',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    TextButton(
                      onPressed: () => _toast(context, '主题市场（GitHub 热加载）V1.x 上线'),
                      child: Text('更多主题 ›',
                          style: TextStyle(
                              fontSize: 11,
                              color: tokens.accent,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                Text('${registry.ids.length} 套内置 · 配置文件热加载 · 与深色模式正交 · 赛博朋克强制深色',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 10),
                _ThemeGrid(registry: registry, selectedId: settings.themeId),
                // 深色模式三档（2026-10-07 产品令 · 原型 p-sub-appearance 同步改）：
                // 旧形态＝一枚 Switch＋把「跟随系统」藏在副标小字的点击里——枚举三档必须
                // 一次看全、点哪个是哪个（LH-K38 SegRow 首个落点）；强制深色主题下整条置灰，
                // 副注说清为什么不可选，绝不静默改值。
                Row(
                  children: [
                    _SetIc(icon: Icons.dark_mode_outlined),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('深色模式',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 8),
                SegRow<ThemeModeOption>(
                  key: const ValueKey('dark-mode-seg'),
                  keyPrefix: 'dark-mode',
                  enabled: !bundle.forceDark,
                  value: settings.mode,
                  items: const [
                    (id: ThemeModeOption.system, label: '跟随系统'),
                    (id: ThemeModeOption.light, label: '浅色'),
                    (id: ThemeModeOption.dark, label: '深色'),
                  ],
                  onChanged: (m) =>
                      ref.read(settingsControllerProvider.notifier).setMode(m),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    bundle.forceDark
                        ? '当前主题强制深色 · 三档暂不可选'
                        : settings.mode == ThemeModeOption.system
                            ? '跟随系统 · 现在是${SettingsPage._isDarkNow(context, settings) ? '深色' : '浅色'} · 与任意主题风格叠加生效'
                            : '${settings.mode == ThemeModeOption.dark ? '已锁定深色' : '已锁定浅色'} · 与任意主题风格叠加生效',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 6),
                // 主题色（原型 themeDots：一排色点，点击=切对应主题）
                Row(
                  children: [
                    _SetIc(icon: Icons.palette_outlined),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('主题色',
                            style:
                                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final b in registry.all)
                          Builder(builder: (context) {
                            final t = b.pick(
                                Theme.of(context).brightness == Brightness.dark);
                            final on = b.id == settings.themeId;
                            return GestureDetector(
                              key: ValueKey('theme-dot-${b.id}'),
                              onTap: () {
                                ref
                                    .read(settingsControllerProvider.notifier)
                                    .setTheme(b.id);
                                ref
                                    .read(eventBusProvider)
                                    .publish(ThemeChangedEvent(b.id));
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: t.gradient,
                                  border: Border.all(
                                      color: on
                                          ? t.accent
                                          : Colors.black.withValues(alpha: .12),
                                      width: on ? 2.5 : 1),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ],
                ),
                // 字体大小（原型默认第 2 档）
                Row(
                  children: [
                    _SetIc(glyph: 'Aa'),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('字体大小',
                            style:
                                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: 2,
                        max: 3,
                        onChanged: (_) =>
                            _toast(context, '字号调节 · 敬请期待（无障碍）'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // V1.65 底栏手势（原型 p-sub-appearance #tbSetCard）：
          // 总开关（默认关）+ 收起线索形态（A/B）+ 线索距屏幕底部；卡内预览框与壳内
          // 全屏线索共用同一对件，所见即所得，不用真去收起底栏。
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _SetIc(icon: Icons.pinch_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('底栏手势',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                          Text('双指张开收起底栏 · 捏合还原',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(
                      key: const ValueKey('nav-gesture-sw'),
                      value: settings.navGestureOn,
                      onChanged: (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setNavGesture(v),
                    ),
                  ],
                ),
                // 开关关＝下半区置灰且不可点（原型 tglTb 同口径：看得见有什么、但明确不生效）。
                Opacity(
                  opacity: settings.navGestureOn ? 1 : .4,
                  child: IgnorePointer(
                    ignoring: !settings.navGestureOn,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Text('收起后的可见线索',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey)),
                        const SizedBox(height: 8),
                        SegRow<String>(
                          key: const ValueKey('nav-line-seg'),
                          keyPrefix: 'nav-line',
                          value: settings.navLineStyle,
                          items: const [
                            (id: 'a', label: '细握把'),
                            (id: 'b', label: '胶囊折角'),
                          ],
                          onChanged: (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .setNavLineStyle(v),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text('线索距屏幕底部',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ),
                            Text('${settings.navLineGap} px',
                                key: const ValueKey('nav-gap-val'),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ],
                        ),
                        Slider(
                          key: const ValueKey('nav-gap-range'),
                          value: settings.navLineGap.toDouble(),
                          min: kNavLineGapMin.toDouble(),
                          max: kNavLineGapMax.toDouble(),
                          divisions: kNavLineGapMax - kNavLineGapMin,
                          onChanged: (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .setNavLineGap(v.round()),
                        ),
                        _NavLinePreview(
                          style: settings.navLineStyle,
                          gap: settings.navLineGap,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '悬浮球保持原位（不随底栏落底）· 预览仅示意线索相对屏幕底部的位置',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ===== 我的页版式（原型 p-profile 三版式，2026-10-12 产品令）=====
          // 记录仪表（默认·渐变身份卡＋连击环）｜编辑章节（编号章节标＋卷轴＋签名页脚）｜
          // 极简卷轴（去卡去发丝·纯留白分组）。与「我的」页 build 同读 settings.myLayout，
          // 切换即时生效并持久化（越界收敛在 UserSettings.fromMap）。
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _SetIc(icon: Icons.dashboard_customize_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('我的页版式',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                          Text('身份区与列表的呈现方式 · 三选一',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegRow<String>(
                  key: const ValueKey('my-layout-seg'),
                  keyPrefix: 'my-layout',
                  value: settings.myLayout,
                  items: const [
                    (id: 'hero', label: '记录仪表'),
                    (id: 'chapters', label: '编辑章节'),
                    (id: 'minimal', label: '极简卷轴'),
                  ],
                  onChanged: (v) => ref
                      .read(settingsControllerProvider.notifier)
                      .setMyLayout(v),
                ),
                const SizedBox(height: 8),
                Text(
                  settings.myLayout == 'chapters'
                      ? '顶部为身份行＋读数带；分组标题编号化，卡片去边框连成卷轴，结尾签名页脚。'
                      : settings.myLayout == 'minimal'
                          ? '顶部为身份行＋读数带；卡片完全去卡，仅靠留白与间距分组，最安静。'
                          : '顶部为渐变身份卡：连击环＋读数带＋里程碑；下半页分组圆角卡。',
                  key: const ValueKey('my-layout-hint'),
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// V1.65 设置卡里的「线索预览框」（原型 #tbSetPrev）：底部虚线＝屏幕下沿，
/// 线索按当前距底值定位。与壳内全屏线索**共用 [NavLineGrip]/[NavLineCapsule]**。
class _NavLinePreview extends StatelessWidget {
  const _NavLinePreview({required this.style, required this.gap});

  final String style;
  final int gap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('nav-line-prev'),
      height: 112,
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Stack(
        children: [
          // 屏幕下沿：一排小短横（原型 repeating-linear-gradient）。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              children: List.generate(
                14,
                (i) => Expanded(
                  child: Container(
                    height: 2,
                    margin: EdgeInsets.only(right: i == 13 ? 0 : 6),
                    color: scheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: gap.toDouble()),
              child: Center(
                child: style == 'b' ? const NavLineCapsule() : const NavLineGrip(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 安装包真实版本串（versionName+versionCode，例 `0.2.15+4106`）。
/// 装机复验与反馈问题要在机内读到「我现在装的是哪一版、哪一号」——发版台账与真机门
/// 文档全靠这串对账。测试环境（flutter_tester）无平台通道，回落空串，由关于卡显示
/// 「—」而不是编一个值（2026-10-11 批A）。
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return '';
  }
});

/// 呵护敏感数据同步排除·联动行（红线 7）。
/// 开关实体在「呵护提醒」页；此行只读展示状态并作为跳转入口，
/// 与原型 p-sub-data 的灰字提示行对应（同步引擎落地前先可见可查）。
final careSyncExcludedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final rows = await AppDatabase.instance.db.query(DbSchema.tSettings,
      where: 'key = ?', whereArgs: ['care.syncExcluded'], limit: 1);
  final v = rows.isEmpty ? null : rows.first['value'] as String?;
  return v == null || v == 'true'; // 默认开
});

class _CareSyncLink extends ConsumerWidget {
  const _CareSyncLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(careSyncExcludedProvider).valueOrNull ?? true;
    return GestureDetector(
      key: const ValueKey('settings-care-sync'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/care/remind'),
      // 左缘对齐主行文字（14 行内边距 + 34 图标块 + 12 间距 = 60）：
      // 2026-10-11 批A 前为 52，比上下行左移 8px，缩进基准破格。
      child: Container(
        padding: const EdgeInsets.fromLTRB(60, 0, 16, 12),
        child: Row(
          children: [
            const Expanded(
              child: Text('母婴等敏感数据排除同步（模块级）',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Text(on ? '已开启 · 呵护内管理 ›' : '已关闭 · 呵护内管理 ›',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: on ? const Color(0xFF10B981) : Colors.grey)),
          ],
        ),
      ),
    );
  }
}
