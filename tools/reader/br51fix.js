const fs = require('fs');
const f = 'lib/features/read/presentation/reader_page.dart';
let s = fs.readFileSync(f, 'utf8');
const old = `          onHorizontalDragEnd: (e) {
            // 轮5①：有选区时滑动让位给首尾手柄拖动（否则手柄横向拖会被翻页吃掉）。
            if (_drawerOpen || _sel != null) return;
            final v = e.velocity.pixelsPerSecond.dx;
            final off = e.primaryVelocity ?? 0;
            if (off < -150 || (v < 0 && v < -0.4)) {
              _flip(1);
            } else if (off > 150 || (v > 0 && v > 0.4)) {
              _flip(-1);
            }
          },`;
const neu = `          // 轮5①：有选区时**不挂**滑动翻页识别器——否则手柄横向拖动会在手势竞技场
          // 里被父级 HorizontalDragGestureRecognizer 抢先认领，手柄拖不动（真机同理）。
          onHorizontalDragEnd: _sel == null && !_drawerOpen ? _onSwipe : null,`;
if (!s.includes(old)) throw new Error('未命中 onHorizontalDragEnd 段');
s = s.replace(old, neu);
const anchor = '  void _hitStep(int d) {';
if (!s.includes(anchor)) throw new Error('未找到插入锚点 _hitStep');
s = s.replace(anchor, `  /// 左右滑动翻页（无选区、无抽屉时才挂）。
  void _onSwipe(DragEndDetails e) {
    final v = e.velocity.pixelsPerSecond.dx;
    final off = e.primaryVelocity ?? 0;
    if (off < -150 || (v < 0 && v < -0.4)) {
      _flip(1);
    } else if (off > 150 || (v > 0 && v > 0.4)) {
      _flip(-1);
    }
  }

` + anchor);
const hOld = `        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => _dragSel(end: end, global: d.globalPosition),`;
const hNew = `        behavior: HitTestBehavior.opaque,
        // 起点即判定：拖动一开始就认领手势，避免与父级识别器争抢。
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: (d) => _dragSel(end: end, global: d.globalPosition),`;
if (!s.includes(hOld)) throw new Error('未命中手柄 GestureDetector 段');
s = s.replace(hOld, hNew);
fs.writeFileSync(f, s, 'utf8');
console.log('ok');
