import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/epub_doc.dart';
import '../domain/book.dart';
import 'read_providers.dart';

/// 阅读主屏（本地 EPUB）· 批1 最小形态。
///
/// 与原型 `#p-readerPage`（BR-2）对齐的批1子集：全屏沉浸舞台、纸面主题
/// （批4 外观面板接管）、chrome 点按显隐、顶栏返回 + 会话计时 chip、
/// **进页自动开始阅读计时 / 退出结算**（V1.50 口径④，复用全局计时基建）。
/// 批2 在此页接入分页重排引擎（翻页⇄滚动）、CFI 位置恢复、目录侧边抽屉、
/// 进度条与图片/链接；批3 划词菜单；批4 外观/TTS/自动翻页。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  /// 原型 BR_THEMES.day 纸面色（日间主题基线）。
  static const _paper = Color(0xFFFAF6EE);
  static const _ink = Color(0xFF3B3630);

  Book? _book;
  EpubDoc? _doc;
  String? _err;
  bool _chrome = false;
  bool _ownTimer = false;
  int _sessSecs = 0;
  Timer? _clock;
  DateTime? _t0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final repo = ref.read(readRepositoryProvider);
    final b = await repo.bookById(widget.bookId);
    if (!mounted) return;
    if (b == null || !b.local || b.epub == null) {
      setState(() => _err = '这本书没有可用的本地 EPUB 文件');
      return;
    }
    setState(() => _book = b);
    // 进阅读器自动开始计时：已有进行中的会话则沿用（原型 brV.ownT 同语义）。
    final running = await repo.runningSession();
    if (running == null) {
      await repo.startSession(b.id);
      _ownTimer = true;
    }
    _t0 = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _t0 != null) {
        setState(
          () => _sessSecs = DateTime.now().difference(_t0!).inSeconds,
        );
      }
    });
    try {
      final doc = await ref.read(epubDocLoaderProvider)(b.epub!.path);
      if (!mounted) return;
      setState(() => _doc = doc);
    } on EpubFormatException catch (e) {
      if (mounted) setState(() => _err = e.reason);
    } catch (_) {
      if (mounted) setState(() => _err = '文件无法读取');
    }
  }

  /// 结算交给全局计时模型（同一会话表）；仅当本页自行开启时才结束，
  /// 避免抢停其它入口起的计时。同步发起不等 UI 悬挂（fire-and-forget 落库）。
  void _leave() {
    _clock?.cancel();
    if (_ownTimer) {
      unawaited(ref.read(readRepositoryProvider).endSession(widget.bookId));
      ref.read(readTickProvider.notifier).state++;
    }
  }

  String get _clockText {
    final m = _sessSecs ~/ 60;
    final s = _sessSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 任何 pop（系统返回/按钮）都在 didPop 后统一结算一次。
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: _paper,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 原型 brTapCenter：中央区域点按切换 chrome；有错误态时不响应。
          onTap: _err == null && _doc != null
              ? () => setState(() => _chrome = !_chrome)
              : null,
          child: SafeArea(
            child: Column(
              children: [
                if (_chrome) _topBar(),
                Expanded(child: _stage()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      key: const ValueKey('br-top'),
      color: const Color(0xDB0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('br-back'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _book?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _doc?.format ?? '',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: .6),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              _clockText,
              key: const ValueKey('br-sess-chip'),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage() {
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _err!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE11D48),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                key: const ValueKey('br-err-back'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    final doc = _doc;
    if (doc == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _ink),
        ),
      );
    }
    // 批1：滚动式全文平铺（批2 换分页引擎实算 + CFI 恢复）。
    final items = <Object>[
      for (final c in doc.chapters) ...[
        'chapter:${c.title}',
        for (final p in c.paras) p,
      ],
    ];
    return ListView.builder(
      key: const ValueKey('br-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
      itemBuilder: (_, i) {
        final it = items[i];
        if (it is String && it.startsWith('chapter:')) {
          return Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text(
              it.substring('chapter:'.length),
              style: const TextStyle(
                fontSize: 20,
                height: 1.5,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          );
        }
        return _para(it as EpubPara);
      },
      itemCount: items.length,
    );
  }

  Widget _para(EpubPara p) {
    switch (p.kind) {
      case EpubParaKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Text(
            p.text,
            style: TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        );
      case EpubParaKind.quote:
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.only(left: 11),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _ink, width: 3)),
          ),
          child: Text(
            p.text,
            style: TextStyle(
              fontSize: 17,
              height: 1.62,
              letterSpacing: .4,
              color: _ink.withValues(alpha: .85),
            ),
          ),
        );
      case EpubParaKind.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            p.alt.isEmpty ? '' : p.alt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: _ink.withValues(alpha: .55),
            ),
          ),
        );
      case EpubParaKind.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Text(
            p.text,
            textAlign: TextAlign.justify,
            style: const TextStyle(
              fontSize: 17,
              height: 1.62,
              letterSpacing: .4,
              color: _ink,
            ),
          ),
        );
    }
  }
}
