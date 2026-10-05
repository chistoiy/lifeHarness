import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../data/epub_doc.dart';
import '../../data/epub_import.dart';
import '../../domain/book.dart';
import '../reader/epub_state_ui.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast;
import '../shelf/shelf_page.dart'
    show ShelfUI, shelfOpenTabArmedProvider, shelfUiProvider;

/// 导入本地图书（EPUB）四步向导 · V1.50 批1。
///
/// 事实源 `prototype/index-bookshelf.html#p-localImport`（BR-1 屏）：
/// 授权 → 选文件 → 解析四任务 → 元信息核对（含同书合并守卫）。
/// V1.60（§3G 拍板）：解析步**不再有「分页预计算」**——分页表随首次开书后台
/// 续算（reader_page_pag），导入第 3 步只跑到「封面与元数据抽取」即完成。
/// 步骤深链语义（原型 `_bN`）在 Flutter 侧由 [startStep] 承载（测试直达）。
/// 批3.5：[reattachBookId] ＝ 源丢失重选模式——选文件后强制挂回该原记录
/// （书摘/计时/进度共用一条），提交即重新预载（原型 brAttachHint 链路）。
class LocalImportPage extends ConsumerStatefulWidget {
  const LocalImportPage({super.key, this.startStep = 1, this.reattachBookId});

  final int startStep;
  final String? reattachBookId;

  @override
  ConsumerState<LocalImportPage> createState() => _LocalImportPageState();
}

class _LocalImportPageState extends ConsumerState<LocalImportPage> {
  static const _steps = ['授权', '选文件', '解析', '核对'];
  static const _tasks = [
    '容器校验 · mimetype',
    '版本与结构识别',
    '目录构建（NCX / nav）',
    '封面与元数据抽取',
  ];

  late int _step = widget.startStep;
  EpubPick? _pick;
  EpubDoc? _doc;
  Book? _dup;
  Book? _reattach; // 批3.5：源丢失重选模式的目标原记录
  String? _err; // 解析失败原因（DRM/坏包）
  int _taskDone = 0;
  Timer? _tick;

  final _title = TextEditingController();
  final _author = TextEditingController();
  final _publisher = TextEditingController();
  final _pubDate = TextEditingController();
  final _intro = TextEditingController();
  bool _tagLocal = true;

  @override
  void initState() {
    super.initState();
    final rid = widget.reattachBookId;
    if (rid != null) {
      unawaited(
        ref.read(readRepositoryProvider).bookById(rid).then((b) {
          if (mounted) setState(() => _reattach = b);
        }),
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    // 批3.5：向导解析走懒归档，离开页面即释放文件句柄（副本/预载另有其档）。
    _doc?.lazy?.dispose();
    for (final c in [_title, _author, _publisher, _pubDate, _intro]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _err = null);
    final picked = await ref.read(epubImportServiceProvider).pick();
    if (!mounted) return;
    if (picked == null) return; // 取消选择：停留当前步
    setState(() {
      _pick = picked;
      _step = 3;
      _taskDone = 0;
      _doc = null;
      _err = null;
    });
    _startParse();
  }

  /// 解析：真实解析跑完前用任务步进动画对齐四任务视觉；失败进错误态。
  void _startParse() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 160), (t) {
      if (_doc == null || _err != null) {
        if (mounted && _taskDone < _tasks.length) {
          setState(() => _taskDone++);
        }
      }
    });
    () async {
      final svc = ref.read(epubImportServiceProvider);
      final pick = _pick;
      if (pick == null) return;
      EpubDoc doc;
      try {
        doc = await svc.loadDoc(pick);
      } on EpubFormatException catch (e) {
        if (mounted) setState(() => _err = e.reason);
        return;
      } catch (_) {
        if (mounted) setState(() => _err = '文件无法读取');
        return;
      }
      var dup = await svc.findDup(doc);
      // 批3.5 挂回模式：目标锁定原记录（书名可能已被用户改过，不走标题匹配）。
      if (widget.reattachBookId != null) {
        dup =
            await ref.read(readRepositoryProvider).bookById(widget.reattachBookId!) ??
            dup;
      }
      if (!mounted) return;
      _tick?.cancel();
      setState(() {
        _doc = doc;
        _dup = dup;
        _taskDone = _tasks.length;
      });
      await Future.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(() {
        _step = 4;
        _title.text = doc.title;
        _author.text = doc.author;
        _publisher.text = doc.publisher ?? '';
        _pubDate.text = doc.pubDate ?? '';
        _intro.text = doc.description ?? '';
      });
    }();
  }

  Future<void> _commit() async {
    final doc = _doc;
    final pick = _pick;
    if (doc == null || pick == null) return;
    final svc = ref.read(epubImportServiceProvider);
    final b = await svc.commit(
      pick: pick,
      doc: doc,
      draft: EpubMetaDraft(
        title: _title.text.trim(),
        author: _author.text.trim(),
        publisher: _publisher.text.trim().isEmpty
            ? null
            : _publisher.text.trim(),
        pubDate: _pubDate.text.trim().isEmpty ? null : _pubDate.text.trim(),
        intro: _intro.text.trim().isEmpty ? null : _intro.text.trim(),
      ),
      tagLocal: _tagLocal,
      mergeInto: _dup,
    );
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    // 批3.5＋V1.60：落库即后台预载（解析＋快照＋封面衍生，不再建分页表）；
    // 完成前封面显进度，期间点封面可直接进入（分页随首次开书续算）。
    brStartPreload(ref, b, context);
    readToast(
      context,
      _dup != null
          ? '《${b.title}》已${_reattach != null ? '重新挂回 · 正在预载' : '附本地文件 · 正在预载'}'
          : '《${b.title}》已加入书架 · 正在后台预载整本 · 源文件保留原位',
    );
    // V1.54 批C F9：同内容指纹已有解析 → 索引整体复用（含用户整理结果）。
    if (svc.lastReuseHits.isNotEmpty && mounted) {
      readToast(context, '检测到同文件书籍 · 全书索引已直接复用');
    }
    // F5-1（轮5）：落架后直接返回书架并停在「全部」分区——旧行为＝退回
    // 「添加图书」搜索页，且书架 boot 默认「在读」分区，新书（未开始）看不见。
    // R6 守护修正：/read/shelf 非 Shell tab，go 清栈会让返回键直接退出 app，
    // 改 pushReplacement——替换导入页本身，下方栈保留。
    ref.read(shelfUiProvider.notifier).state = const ShelfUI();
    ref.read(shelfOpenTabArmedProvider.notifier).state = false;
    if (mounted) context.pushReplacement('/read/shelf');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('导入本地图书', style: TextStyle(fontSize: 15)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _stepBar(cs),
            const SizedBox(height: 12),
            switch (_step) {
              1 => _step1(cs),
              2 => _step2(cs),
              3 => _step3(cs),
              _ => _step4(cs),
            },
          ],
        ),
      ),
    );
  }

  Widget _stepBar(ColorScheme cs) {
    return Row(
      key: const ValueKey('br-steps'),
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: i == _step - 1
                  ? context.tokens.gradient
                  : null,
              color: i == _step - 1
                  ? null
                  : (i < _step ? cs.primary.withValues(alpha: .12) : cs.surfaceContainerHighest),
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: i == _step - 1
                    ? Colors.white
                    : (i < _step ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _steps[i],
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: i <= _step - 1 ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: cs.onSurfaceVariant.withValues(alpha: .25),
              ),
            ),
        ],
      ],
    );
  }

  Widget _card({required Widget child, Key? key}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      child: child,
    );
  }

  Widget _gradBtn(String label, Key key, VoidCallback onTap) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: context.tokens.gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _step1(ColorScheme cs) {
    return Column(
      key: const ValueKey('br-imp1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF10B981).withValues(alpha: .12),
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Android 13+ · 无需「所有文件访问」',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '通过系统文件选择器（SAF）读取所选 EPUB，应用只拿到该文件本身',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final line in const [
                '· 13+：一次性读取授权，不落存储权限',
                '· 12 及以下：仅申请单次读文件权限',
                '· 全程本地解析，不上传、不联网下载书籍',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              _gradBtn(
                '允许访问手机存储 · 选择文件',
                const ValueKey('br-imp1-go'),
                () => setState(() => _step = 2),
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '支持范围',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'EPUB 2 / EPUB 3\n图文混排 · 内/外链 · 目录',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFB7185).withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '不支持\nDRM 加密书 · PDF（独立模块）',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _step2(ColorScheme cs) {
    return Column(
      key: const ValueKey('br-imp2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 批3.5 挂回模式提示（原型 brAttachHint 琥珀条）。
        if (_reattach != null)
          Container(
            key: const ValueKey('brAttachHint'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: .35),
              ),
            ),
            child: Text(
              '正在为《${_reattach!.title}》重新选择文件 · 选中原文件即挂回原记录',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '手机存储 · 经系统选择器',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              EmptyDashRow(
                key: const ValueKey('br-imp2-pick'),
                text: '选择 EPUB 文件',
                onTap: _pickFile,
              ),
              if (_pick != null) ...[
                const SizedBox(height: 10),
                Text(
                  _pick!.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '加密书籍与 PDF 不出现在可选列表 · 只登记所选文件',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('br-imp2-back'),
            onPressed: () => setState(() => _step = 1),
            child: const Text('上一步'),
          ),
        ),
      ],
    );
  }

  Widget _step3(ColorScheme cs) {
    final pct = _err != null
        ? 1.0
        : (_taskDone + 1) / (_tasks.length + 1) * 0.92;
    return Column(
      key: const ValueKey('br-imp3'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: context.tokens.gradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _pick?.name ?? '—',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((_pick?.size ?? 0) > kEpubBigFileBytes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '大文件：解析与目录构建可能需要 1-2 分钟',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              for (var i = 0; i < _tasks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    key: ValueKey('br-task-$i'),
                    children: [
                      Icon(
                        i < _taskDone || _doc != null
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 14,
                        color: i < _taskDone || _doc != null
                            ? const Color(0xFF10B981)
                            : cs.onSurfaceVariant.withValues(alpha: .5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _tasks[i],
                        style: TextStyle(
                          fontSize: 11,
                          color: (i < _taskDone || _doc != null)
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        i < _taskDone || _doc != null
                            ? '完成'
                            : (_err != null ? '中止' : '…'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: (i < _taskDone || _doc != null)
                              ? const Color(0xFF10B981)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              ClipRRect(
                key: const ValueKey('br-bar'),
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
        if (_err != null)
          _card(
            key: const ValueKey('br-imp-err'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _err!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE11D48),
                  ),
                ),
                const SizedBox(height: 10),
                _gradBtn(
                  '返回重选文件',
                  const ValueKey('br-imp-retry'),
                  () => setState(() {
                    _err = null;
                    _doc = null;
                    _pick = null;
                    _step = 2;
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _step4(ColorScheme cs) {
    final doc = _doc;
    if (doc == null) return const SizedBox.shrink();
    final pages = EpubImportService.estPages(doc);
    final tocLines = doc.toc.isNotEmpty
        ? doc.toc.map((t) => (t.label, '')).toList()
        : doc.chapters.map((c) => (c.title, '')).toList();
    return Column(
      key: const ValueKey('br-imp4'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_dup != null)
          Container(
            key: const ValueKey('br-dup'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: .10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: .35),
              ),
            ),
            child: Text(
              _reattach != null
                  ? '原文件丢失的《${_dup!.title}》仍在书架保留全部记录。本次将把选中的文件挂回原记录：书摘、计时、进度共用一条。'
                  : '已存在《${_dup!.title}》（${_dup!.source ?? _dup!.state} · ${_dup!.state}${_dup!.state == Book.kStateReading ? ' ${_dup!.percent}%' : ''}）。推荐把本地文件挂到该记录：书摘、计时、进度共用一条，点封面即可阅读。',
              style: const TextStyle(
                fontSize: 11,
                height: 1.55,
                color: Color(0xFFB45309),
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(doc, cs),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: [
                  _field(_title, '书名', 'brF_t', bold: true),
                  const SizedBox(height: 8),
                  _field(_author, '作者', 'brF_a'),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '书名 / 作者 / 简介 / 目录从 EPUB 元数据自动读取 · 可修改',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _field(_publisher, '出版社', 'brF_press'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: _field(_pubDate, '出版日期', 'brF_pub'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _field(_intro, '简介', 'brF_intro', maxLines: 3),
        const SizedBox(height: 10),
        _card(
          key: const ValueKey('br-preview'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '解析内容预览',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  PillChip(
                    label: '${doc.format} · 图文混排',
                    selected: false,
                    key: const ValueKey('brFmtTag'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '共 ${doc.chapters.length} 章 · 约 $pages 页 · 内嵌字体 ${doc.fontCount} · 图片 ${doc.imageCount} 张 · 书签 ${doc.bookmarkCount} 条',
                key: const ValueKey('brMetaSum'),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: SingleChildScrollView(
                  key: const ValueKey('brTocPrev'),
                  child: Column(
                    children: [
                      for (final (label, _) in tocLines.take(40))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          key: const ValueKey('brFTag'),
          children: [
            const Expanded(
              child: Text(
                '加入「本地」标签与来源分组',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
            Switch(
              value: _tagLocal,
              onChanged: (v) => setState(() => _tagLocal = v),
            ),
          ],
        ),
        _gradBtn(
          _dup != null
              ? (_reattach != null ? '挂回原记录 · 重新预载' : '合并到已有记录 · 附本地文件')
              : '加入书架 · 开始阅读',
          const ValueKey('brSaveBtn'),
          _commit,
        ),
        const SizedBox(height: 8),
        Text(
          '源文件保留原位 · 加入书架后整本分页后台续算',
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _cover(EpubDoc doc, ColorScheme cs) {
    final bytes = doc.coverBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 96,
        height: 144,
        child: bytes != null && bytes.isNotEmpty
            ? Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover)
            : Container(
                key: const ValueKey('brMCov'),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF334155), Color(0xFF0F172A)],
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: Text(
                  doc.title,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    String key, {
    bool bold = false,
    int maxLines = 1,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      key: ValueKey(key),
      controller: c,
      maxLines: maxLines,
      style: TextStyle(
        fontSize: bold ? 13.5 : 12,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: maxLines == 1 ? 10 : 8,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: .5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: .5),
          ),
        ),
      ),
    );
  }
}
