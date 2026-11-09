/// 二进制电子书（AZW3 / MOBI）解析的统一拒绝异常。
///
/// 口径：**坏文件、DRM、零依赖下不可解的压缩方式一律显式抛错**，
/// UI 原样展示 [reason]；绝不静默降级成空书或乱码冒充成功。
class EbookFormatException implements Exception {
  const EbookFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'EbookFormatException: $reason';
}
