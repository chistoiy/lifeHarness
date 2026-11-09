part of 'reader_page.dart';

// 治理G7c4：链接/图片群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。
// 内链跳章 / 外链三策略（含 UA·熔断后的回落通道）/ 图片放大与保存。
extension _ReaderLinks on _ReaderPageState {
  // ---------- 链接/图片 ----------

  /// 内链直跳：目标 href 命中 spine 章即跳章（原型 brGotoCh 链）。
  void _onLink(EpubLink l) {
    if (!l.external) {
      final doc = _doc;
      if (doc == null) return;
      final ci = doc.chapters.indexWhere((c) => c.href == l.href);
      if (ci >= 0) {
        _gotoChapter(ci);
      } else {
        _showFlash('目标章节不在正文流');
      }
      return;
    }
    _onExtLink(l.href);
  }

  Future<void> _onExtLink(String url) async {
    final repo = ref.read(readRepositoryProvider);
    final mode = await repo.kv('read.brLink') ?? '询问';
    if (!mounted) return;
    if (mode == '禁止') {
      _showFlash('外链已被禁止 · 可在阅读设置改为询问/允许');
      return;
    }
    if (mode == '允许') {
      _openUrl(url);
      return;
    }
    // 询问：sheetBrLink 半屏（原型：即将离开阅读器 + URL 卡 + 策略提示 +
    // 取消/允许一次 双钮）。
    final cs = Theme.of(context).colorScheme;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true, // F3-10 弹层骨架
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            key: const ValueKey('sheetBrLink'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '即将离开阅读器',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('brLkUrl'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(url, style: const TextStyle(fontSize: 11, height: 1.6)),
              ),
              const SizedBox(height: 6),
              Text(
                '策略可在「阅读设置 · 本地阅读器」改为 禁止 / 询问 / 允许',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sc).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('brLkOpen'),
                      onPressed: () => Navigator.of(sc).pop(true),
                      child: const Text('允许一次'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) _openUrl(url);
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _showFlash('没有可打开该链接的应用');
    }
  }

  void _openImage(EpubPara para) {
    final bytes = _doc?.imageBytes(para.imgSrc);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true, // F3-10 弹层骨架
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (sc) => SafeArea(
        child: SizedBox(
          key: const ValueKey('sheetBrImg'),
          height: MediaQuery.sizeOf(sc).height * .8,
          child: Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: bytes == null
                        ? const Text('（缺图）',
                            style: TextStyle(color: Colors.white54))
                        : Image.memory(
                            Uint8List.fromList(bytes),
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  para.alt.isEmpty ? '插图' : para.alt,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    key: const ValueKey('brImgSave'),
                    onPressed: () async {
                      if (bytes == null) return;
                      final base = await getApplicationDocumentsDirectory();
                      final dir = Directory('${base.path}${Platform.pathSeparator}share')
                        ..createSync(recursive: true);
                      final ext = p.extension(para.imgSrc).replaceFirst('.', '').toLowerCase();
                      final suffix = const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext) ? '.$ext' : '.png';
                      final out = File(
                        '${dir.path}${Platform.pathSeparator}epub_img_'
                        '${DateTime.now().millisecondsSinceEpoch}$suffix',
                      );
                      out.writeAsBytesSync(bytes);
                      if (sc.mounted) Navigator.of(sc).pop();
                    },
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('保存'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
