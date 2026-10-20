part of 'shelf_page.dart';

// V1.53.4⑥：系统「打开方式」命中已导入 / 导入成功后，在书架滚动定位并一次性
// 描边闪烁（原型 shLocate + .br-flash-loc：3px accent 环、radius 14、约 1.6s）。
// 分区对齐该书状态（原型 shSt=b.st），当前视图找不到时 toast 兜底。
extension _ShelfLocate on _ShelfPageState {
  Future<void> _locateBook(String bookId) async {
    final seq = ++_locateSeq;
    List<Book> books;
    try {
      books = await ref.read(booksProvider.future);
    } catch (_) {
      // catch-ok: 拉列表失败走「未在当前视图找到」兜底提示，用户可见、不静默。
      books = const [];
    }
    if (!mounted || seq != _locateSeq) return;
    final hits = books.where((b) => b.id == bookId && !b.isDeleted).toList();
    if (hits.isEmpty) {
      _locateMiss();
      return;
    }
    final book = hits.first;
    final ui = ref.read(shelfUiProvider);
    if (ui.st != book.state) {
      ref.read(shelfUiProvider.notifier).state = ui.copyWith(
        st: () => book.state,
      );
    }
    // 帧驱动轮询找书卡（入库重取/筛选重建/转场各占几帧），约 2s 未命中即失败。
    for (var i = 0; i < 120; i++) {
      if (!mounted || seq != _locateSeq) return;
      final el = _findLocateTile(bookId);
      if (el != null) {
        ref.read(locateBookProvider.notifier).state = null;
        await Scrollable.ensureVisible(
          el,
          alignment: .35,
          duration: const Duration(milliseconds: 240),
        );
        if (!mounted || seq != _locateSeq) return;
        _showLocateFlash(el);
        readToast(context, '已在书架定位《${book.title}》');
        return;
      }
      final c = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!c.isCompleted) c.complete();
      });
      await c.future;
    }
    if (mounted && seq == _locateSeq) _locateMiss();
  }

  void _locateMiss() {
    ref.read(locateBookProvider.notifier).state = null;
    if (mounted) readToast(context, '未在当前视图找到该书');
  }

  /// 书卡热区 key 为 `sh-item-<pfx><id>`（五视图共用 _tapWrap；时间线
  /// 视图无书卡 key，走未找到兜底）。
  Element? _findLocateTile(String bookId) {
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      final k = e.widget.key;
      if (k is ValueKey<String> &&
          k.value.startsWith('sh-item-') &&
          k.value.endsWith(bookId)) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  void _showLocateFlash(Element el) {
    _locateFlashEntry?.remove();
    _locateFlashEntry = null;
    final ro = el.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return;
    final rect = ro.localToGlobal(Offset.zero) & ro.size;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: _LocateFlashRing(
            color: context.tokens.accent.withValues(alpha: .6),
            onDone: () {
              if (identical(_locateFlashEntry, entry)) {
                _locateFlashEntry = null;
              }
              entry.remove();
            },
          ),
        ),
      ),
    );
    _locateFlashEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

/// 一次性描边环：帧驱动 1.6s 后自移除（不用 Timer，测试 settle 友好）。
class _LocateFlashRing extends StatefulWidget {
  const _LocateFlashRing({required this.color, required this.onDone});

  final Color color;
  final VoidCallback onDone;

  @override
  State<_LocateFlashRing> createState() => _LocateFlashRingState();
}

class _LocateFlashRingState extends State<_LocateFlashRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: .6 * (1 - _c.value)),
              spreadRadius: 3,
              blurRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}
