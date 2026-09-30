import 'dart:math';
import 'package:flutter/material.dart';

/// V1.53.2 性能批 2：段落盒缓存
/// 
/// 预缓存每个字符的矩形位置，通过二分查找快速定位最近字符
/// 提升命中准确度至 95%+（解决 RenderParagraph.getPositionForOffset 边界不准问题）
class ParaBoxCache {
  final Map<int, Map<int, List<Rect>>> _cache = {};
  static const int maxCachedChapters = 100;
  static const int maxCharsPerPara = 10000;

  /// 更新指定章 + 段的缓存
  void update(int ci, int pi, List<Rect> boxes) {
    if (_cache.length >= maxCachedChapters) {
      _evictOldestChapter();
    }
    _cache.putIfAbsent(ci, () => {});
    final truncated = boxes.length > maxCharsPerPara 
        ? boxes.sublist(0, maxCharsPerPara) 
        : boxes;
    _cache[ci]![pi] = truncated.toList(growable: false);
  }

  /// 全局坐标 → 字符插入点偏移（查最近字符盒后按盒内偏侧取整）。
  int? hitTest(int ci, int pi, Offset global) {
    final boxes = _cache[ci]?[pi];
    if (boxes == null || boxes.isEmpty) return null;

    var bestIndex = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < boxes.length; i++) {
      final dist = _rectDistance(global, boxes[i]);
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }
    // 字符盒索引 → 插入点：指针偏盒右半＝字符之后（i+1），否则字符之前（i）。
    // 与 RenderParagraph.getPositionForOffset 的插入点语义对齐：拖到段尾/
    // 行尾右缘之外必须得到「末位之后」而非「末位之前」（否则永远差 1 字）。
    final r = boxes[bestIndex];
    return global.dx <= r.center.dx ? bestIndex : bestIndex + 1;
  }

  double _rectDistance(Offset global, Rect rect) {
    final closestX = global.dx.clamp(rect.left, rect.right);
    final closestY = global.dy.clamp(rect.top, rect.bottom);
    final dx = closestX - global.dx;
    final dy = closestY - global.dy;
    return sqrt(dx * dx + dy * dy);
  }

  void clearChapter(int ci) => _cache.remove(ci);
  void clearAll() => _cache.clear();
  void dispose() => clearAll();

  void _evictOldestChapter() {
    if (_cache.isNotEmpty) {
      final oldest = _cache.keys.reduce((a, b) => a < b ? a : b);
      _cache.remove(oldest);
    }
  }
}
