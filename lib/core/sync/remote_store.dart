import 'package:http/http.dart' as http;

import 'credential_vault.dart';
import 'http_gate.dart';
import 'service_config.dart';
import 'webdav_store.dart';

/// 生产/测试共用假体的 client 构造工厂类型（测试注入 MockClient 后端；
/// R5 守护封死 core/sync 内 `http.Client(` 散落实例化，构造口径统一走
/// [WebDavStore] 的该参数，见 webdav_store.dart 单点聚合注释）。
typedef HttpClientFactory = http.Client Function();

/// 云端单个文件条目（协议文档 §3 FileEntry 裁剪版：digest 由 T15 差异层补）。
///
/// [relativePath] 一律以映射的 cloudDirName 为根、去前导 `/` 的归一相对路径。
class FileEntry {
  FileEntry({
    required this.relativePath,
    required this.size,
    this.etag,
    this.modified,
  });

  String relativePath;
  int size;

  /// 已去引号；弱 ETag 保留 `W/` 前缀原样（R8 判定侧再区分强弱）。
  String? etag;
  DateTime? modified;
}

/// [RemoteStore.list] 结果：目录树拉平后的文件清单（目录占位不入列）。
class CloudListing {
  CloudListing(this.files);

  final List<FileEntry> files;
}

/// 容量三态（R9）：null 即服务端未提供，UI 必须能只渲染「已用」而无进度条。
class CloudQuota {
  CloudQuota({
    this.quotaBytes,
    this.usedBytes,
    this.collectionUsed = const {},
  });

  int? quotaBytes;
  int? usedBytes;

  /// 坚果云 getUserInfo 私有扩展才有：按同步文件夹归一化目录名的用量。
  Map<String, int> collectionUsed;
}

/// 连接验证结果（verify 一次极轻请求）。
class VerifyResult {
  VerifyResult(this.ok, [this.message]);

  final bool ok;

  /// 失败时的人话文案（区分协议：WebDAV 提示应用密码，S3 侧 T14 换文案）。
  final String? message;
}

/// 协议抽象（协议文档 §8）：差异引擎与编排只依赖这六个方法，业务层零协议
/// 分支（R2——`isS3` 只允许出现在表单字段联动与 [RemoteStore.forConfig]）。
abstract class RemoteStore {
  /// 列举 [cloudDirName] 整棵子树（60s 清单缓存，D3 键 `{serviceId}|{dir}`；
  /// [force] 穿透）。
  Future<CloudListing> list(ServiceConfig c, String cloudDirName,
      {bool force = false});

  /// 上传 [localPath] 到云端相对路径 [cloudRelative]（先逐级 MKCOL 再流式 PUT）。
  Future<void> put(ServiceConfig c, String localPath, String cloudRelative);

  /// 下载 [cloudRelative] 到本地 [localPath]（流式落盘，临时文件+rename 原子放）。
  Future<void> get(ServiceConfig c, String cloudRelative, String localPath);

  /// 确保云端目录存在（相对 cloudDirName；S3 为空实现，R7）。
  Future<void> ensureDirectory(ServiceConfig c, String cloudRelativeDir);

  /// 连接验证（一次极轻请求）。
  Future<VerifyResult> verify(ServiceConfig c);

  /// 容量（5min 缓存；三态见 [CloudQuota]）。
  Future<CloudQuota> quota(ServiceConfig c, {bool force = false});

  /// 释放底层连接（幂等）。
  void close();

  /// 协议分发唯一位点（R2）。
  static RemoteStore forConfig(ServiceConfig c,
      {HttpGate? gate, CredentialVault? vault}) {
    if (c.isS3) {
      // 【云盘】R2 合法分发位点：缤纷云 S3Store（手写 SigV4）由 Task 14
      // （T14，s3_store.dart / s3_sigv4.dart）接入，此处为协议分发骨架占位。
      throw UnimplementedError(
          'S3 协议存储未实现：Task 14 接入缤纷云 S3Store（协议分发位点已预留）');
    }
    return WebDavStore(gate: gate, vault: vault);
  }
}
