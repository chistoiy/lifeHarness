import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/database/schema/nfc.dart' show NfcTagKind;
import '../../../shared/linkage/nfc_mounts.dart' show nfcTargetStateOf;
import '../data/nfc_repo.dart';
import '../data/nfc_tag_io.dart';
import '../domain/nfc_card.dart';
import '../domain/nfc_write_state.dart';

/// 写卡层（原型 `sheetNfcWrite` · 冻结档 §4.3 状态机 / §4.5 动画 / §4.6 反馈）。
///
/// 返回值：`true`＝**写成功过**（调用方据此刷新列表与写入态），`false`＝没写成（取消/超时/未写）。
///
/// 三条口径写在最前，改前先读：
/// · **层内文案只出当前状态，不堆历史**（§4.3）；文案表在域层 `kNfcWriteCopy`（逐字照原型）。
/// · **读卡会话只在本层存活期间存在**（§6.3 功耗）：开层即开、关层必停；重试不重开会话
///   （同一会话能继续发现换上的新卡），但切后台要停（B34：回前台须重新贴）。
/// · **30 秒自首次进入起算，切后台不重置**（B34）；超时只在 `waiting` 生效（B7），
///   已读到卡后的读/写过程不掐。
Future<bool> showNfcWriteSheet(
  BuildContext context, {
  required NfcCard card,
  required NfcRepo repo,
  NfcTagIo? io,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (_) => _NfcWriteSheet(card: card, repo: repo, io: io),
  );
  return r ?? false;
}

class _NfcWriteSheet extends StatefulWidget {
  const _NfcWriteSheet({required this.card, required this.repo, this.io});

  final NfcCard card;
  final NfcRepo repo;

  /// 测试注入缝（widget 用例注入假 IO，全程不碰真硬件）。
  final NfcTagIo? io;

  @override
  State<_NfcWriteSheet> createState() => _NfcWriteSheetState();
}

class _NfcWriteSheetState extends State<_NfcWriteSheet>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final NfcTagIo _io = widget.io ?? NfcManagerTagIo();
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// 首次进入时刻（B34：30s 窗口**不因切后台重置**）。
  final DateTime _enteredAt = DateTime.now();

  Timer? _ticker;
  Timer? _closeTimer;
  NfcWriteState _state = NfcWriteState.waiting;
  NfcTagProbe? _probe;

  /// 本卡的目标名（副行「目标摘要」用；异步查库）。
  String? _targetName;

  /// 占用态里「本机另一张卡」的名字（C12：要说清是「哪一张」）。
  String? _ownCardName;

  bool _wrote = false;

  /// 处理中闸（天线贴住不动会反复回调 ⇒ 同一次处理只走一遍）。
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _checkTimeout());
    _startSession();
    _loadSubtitle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _closeTimer?.cancel();
    _breath.dispose();
    unawaited(_io.stop()); // 离开层即停会话（§6.3：App 不持有 NFC 监听）
    super.dispose();
  }

  /// B34：写卡层切后台 → 读卡回调丢弃（不缓存 tag），回前台须重新贴；
  /// 30s 计时照算，回前台若已超时 ⇒ 直接关层（不 toast）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isOverdue) {
        _close(false);
        return;
      }
      if (_state == NfcWriteState.waiting) _startSession();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_io.stop());
    }
  }

  bool get _isOverdue =>
      DateTime.now().difference(_enteredAt).inMilliseconds >=
      kNfcWriteTimeoutMs;

  /// 层标题下的副行：「卡名」· 目标标签（原型 `nfcOpenWrite` 同款）。
  Future<void> _loadSubtitle() async {
    final st = await nfcTargetStateOf(widget.card);
    if (!mounted) return;
    setState(() => _targetName = st.name);
  }

  void _checkTimeout() {
    if (!nfcWriteShouldTimeout(_state)) return;
    if (_isOverdue) _close(false);
  }

  void _close(bool wrote) {
    if (!mounted) return;
    Navigator.pop(context, wrote);
  }

  Future<void> _startSession() async {
    await _io.startRead(
      onProbe: (probe) {
        if (!mounted) return;
        if (_handling || _state != NfcWriteState.waiting) return;
        unawaited(_onProbe(probe));
      },
      onError: (code) {
        if (!mounted) return;
        setState(() => _state = nfcWriteFailureOf(code));
      },
    );
  }

  /// 读到标签 → 分派（§4.3 的 reading 分支）→ 该写就写。
  Future<void> _onProbe(NfcTagProbe probe) async {
    _handling = true;
    try {
      setState(() {
        _probe = probe;
        _state = NfcWriteState.reading;
      });

      final tagCardId = nfcCardIdOfTagUri(probe.existingUri);
      final isSelf = tagCardId != null && tagCardId == widget.card.id;
      var ownOther = false;
      String? ownName;
      if (tagCardId != null && !isSelf) {
        final other = await widget.repo.byId(tagCardId);
        if (other != null) {
          ownOther = true;
          ownName = other.name;
        }
      }
      if (!mounted) return;
      setState(() => _ownCardName = ownName ?? _ownCardName);

      final next = nfcWriteStateAfterRead(
        isNdef: probe.isNdef,
        isWritable: probe.isWritable,
        hasContent: probe.hasContent,
        isSelfCard: isSelf,
        isOwnOtherCard: ownOther,
      );
      if (next == NfcWriteState.writing) {
        await _write();
      } else {
        setState(() => _state = next);
      }
    } finally {
      _handling = false;
    }
  }

  /// 真正写卡（唯一一次 NDEF 写入）。容量先预判（B5：N 取系统报数）。
  Future<void> _write() async {
    final probe = _probe;
    final uri = nfcTagUriOf(widget.card.id);
    final cap = nfcWriteCapacityPrecheck(
      messageBytes: nfcTagUriBytes(uri),
      maxSize: probe?.maxSize ?? 0,
    );
    if (cap != null) {
      setState(() => _state = cap);
      return;
    }
    setState(() => _state = NfcWriteState.writing);
    try {
      await _io.writeUri(uri);
      // C31：写入态的唯一判据＝`written_at` 列（写 now）＋ tag_key/tag_kind。
      await widget.repo.markWritten(
        widget.card.id,
        tagKey: ndefTagKeyOf(widget.card.id),
        tagKind: NfcTagKind.ndef,
      );
      if (!mounted) return;
      _wrote = true;
      setState(() => _state = NfcWriteState.done);
      // §4.3/§4.5：对勾停 1.2s 后自动关层；关的是**本层**，下层的编辑/绑定层
      // 保留不退出（B39：用户可能还没填完名称）。
      _closeTimer = Timer(kNfcWriteDoneHold, () => _close(true));
    } catch (e) {
      if (!mounted) return;
      // F2-2：以系统报错类别为准（`PlatformException.code`＝原生异常类名）。
      setState(() => _state = nfcWriteFailureOf(codeOf(e)));
    }
  }

  /// 占用确认块「覆盖写入」（C12：仅 `occupied` 给此钮，本机另一张卡只可取消）。
  Future<void> _overwrite() async {
    if (_probe == null) {
      setState(() => _state = NfcWriteState.waiting);
      return;
    }
    await _write();
  }

  /// 错误态主钮：只读＝换卡（回等待）／系统 NFC 关＝去设置／其余＝重试。
  Future<void> _retry() async {
    if (_state == NfcWriteState.errNfcOff) {
      await _io.openSettings();
      return;
    }
    setState(() => _state = NfcWriteState.waiting);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final copy = nfcWriteCopyOf(_state);
    final occupy = nfcWriteIsOccupy(_state);
    final err = nfcWriteIsError(_state);
    final hint = _state == NfcWriteState.occupiedOwn && _ownCardName != null
        ? '这已经是「$_ownCardName」卡片，只能取消'
        : copy.hint;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('写入卡片',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '「${widget.card.name}」· ${nfcTargetLabelOf(widget.card, targetName: _targetName)}',
                key: const ValueKey('nfc-write-sub'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 104,
              child: Center(child: _indicator(scheme, err)),
            ),
            const SizedBox(height: 18),
            // §4.8：状态文案进 liveRegion（TalkBack 可播报状态变化）。
            Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  Text(
                    copy.main,
                    key: const ValueKey('nfc-write-main'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: err ? scheme.error : scheme.onSurface,
                    ),
                  ),
                  if (hint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        hint,
                        key: const ValueKey('nfc-write-hint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),

            // ===== 占用确认块（C12：普通占用给覆盖；本机另一张只给取消）=====
            if (occupy) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _ghostBtn('取消', () => _close(_wrote))),
                  if (nfcWriteCanOverwrite(_state)) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _dangerBtn(
                          '覆盖写入', () => unawaited(_overwrite())),
                    ),
                  ],
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _ghostBtn('取消', () => _close(_wrote))),
                  if (err) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _primaryBtn(
                          nfcWriteRetryLabel(_state), () => unawaited(_retry())),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 三态指示器：呼吸圆环（等待/读/写）／成功对勾（done）／错误红圈（err_*）。
  Widget _indicator(ColorScheme scheme, bool err) {
    if (_state == NfcWriteState.done) {
      return Icon(Icons.check_circle_outline, size: 56, color: scheme.primary);
    }
    if (err) {
      return Icon(Icons.error_outline, size: 56, color: scheme.error);
    }
    return AnimatedBuilder(
      animation: _breath,
      builder: (_, child) => Opacity(
        opacity: 0.5 + 0.5 * _breath.value,
        child: Transform.scale(scale: 1 + 0.04 * _breath.value, child: child),
      ),
      child: CustomPaint(
        size: const Size(104, 104),
        painter: _DashedRingPainter(color: scheme.outlineVariant),
      ),
    );
  }

  Widget _ghostBtn(String label, VoidCallback onTap) => SizedBox(
        height: 46,
        child: OutlinedButton(
          key: ValueKey<String>('nfc-write-$label'),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  Widget _primaryBtn(String label, VoidCallback onTap) => SizedBox(
        height: 46,
        child: FilledButton(
          key: ValueKey<String>('nfc-write-$label'),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  Widget _dangerBtn(String label, VoidCallback onTap) => SizedBox(
        height: 46,
        child: FilledButton(
          key: ValueKey<String>('nfc-write-$label'),
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}

/// 虚线圆环（原型 `.nfc-ring`：`2px dashed` · 1.6s 呼吸）——本模块唯一循环动画的载体。
class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - 2) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const segments = 36;
    const sweep = 2 * math.pi / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}
