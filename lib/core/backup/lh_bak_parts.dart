/// `.lhbak` 的附属实现（拆出主文件以守住单文件 1200 行体量线）：
/// - 部分恢复的范围解算（余量批4 · A1 按模块整组替换）与其归属判据；
/// - `_BlobCipher` 加解密器（一次 create 共用一个 salt，逐成员独立 nonce）。
///
/// 为什么拆：批4 新增的 `LhBakRestoreScope` 是「判据 + 说明」密集型，
/// 放进主文件会把容器实现顶出体量线；而这两块与打包/解包主流程本就
/// 可以分开读——判据读的是 manifest，加密器读的是密钥材料。
part of 'lh_bak.dart';

/// **部分恢复的准入范围**（余量批4 · A1 按模块整组替换）。
///
/// 判据唯一来源＝`manifest.scope`（批3 写入），**不允许**从 `manifest.tables`
/// 反推：包内表清单还受 `excludedTables`（健康本地排除、X-Ray 可再生派生表、
/// 打包者自选排除）影响，把「没进包」误读成「不属于本包」会让恢复侧漏建表。
///
/// 分流三档（[fromManifest] 是唯一入口）：
/// - `scope == null` 或 `scope.modules` 缺失/为空 → **全量替换**（老包与全量包
///   走原路径**一字不动**，向后兼容）；
/// - `scope.modules` 非空 → **按模块整组替换**：只动 [tables] 里那些表，
///   其余模块本机数据一行不碰；
/// - `scope.modules` 有值但**一个都认不出**（注册表已退役该模块 id）→
///   抛 [LhBakException.codeBadManifest]：既不能静默按全量替换（会清空整库），
///   也不能「什么表都不动」假报成功。
class LhBakRestoreScope {
  const LhBakRestoreScope({
    required this.moduleIds,
    required this.tables,
    this.from,
    this.to,
    this.withAttachments = true,
  });

  /// 全量替换档（无范围信息）。
  static const LhBakRestoreScope full = LhBakRestoreScope(
    moduleIds: [],
    tables: {},
  );

  /// 包内声明的模块 id（顺序即导出面板 chips 序）。
  final List<String> moduleIds;

  /// 这些模块涉及的表 → 归属模块 id 清单（表→模块，用于落库前逐表判归属）。
  final Map<String, List<String>> tables;

  /// 时间维度区间（批3 写入；null＝未按时间筛）。
  final DateTime? from;
  final DateTime? to;

  /// 包内是否带附件组（批3 写入；缺省按 true 处理——老口径附件恒随包）。
  final bool withAttachments;

  /// 是否全量替换（无 scope 或 modules 为空）。
  bool get isFull => tables.isEmpty;

  /// scope 涉及的表清单（恢复侧即按此清单整组替换）。
  Set<String> get tableNames => tables.keys.toSet();

  /// 解析 manifest.scope；返回 null 表示「按全量处理」（无 scope 段）。
  /// 认不出任何模块 id → 抛 badManifest（见类注释第三档）。
  static LhBakRestoreScope? fromManifest(LhBakManifest manifest) {
    final raw = manifest.scope;
    if (raw == null) return null;
    final ids = (raw['modules'] as List?)?.cast<String>() ?? const <String>[];
    if (ids.isEmpty) return null; // 全量包（批3 对全量不写 scope，兼容手改包）
    final tables = <String, List<String>>{};
    for (final id in ids) {
      final unit = exportUnitById(id);
      if (unit == null) continue; // 退役模块 id：认不出，下面统一判空
      for (final t in unit.tables) {
        tables.putIfAbsent(t, () => <String>[]).add(id);
      }
    }
    if (tables.isEmpty) {
      throw LhBakException(
          LhBakException.codeBadManifest,
          'manifest.scope.modules 含无法识别的模块：${ids.join(",")}'
          '——既不能按全量替换（会清空整库），也不能什么都不做');
    }
    DateTime? parse(String key) {
      final v = raw[key];
      return v is String ? DateTime.tryParse(v) : null;
    }

    return LhBakRestoreScope(
      moduleIds: ids.where((id) => exportUnitById(id) != null).toList(),
      tables: tables,
      from: parse('from'),
      to: parse('to'),
      withAttachments: raw['withAttachments'] as bool? ?? true,
    );
  }
}

/// `CREATE [UNIQUE] INDEX … ON <表>` 里的目标表名（部分恢复档判索引归属）。
/// 触发器没有 ON 子句 → null（触发器不在本库 schema 里，按「非本模块」跳过）。
final RegExp _onTableRe = RegExp(
    r'\sON\s+[`"\[]?(?:main\s*\.\s*)?[`"\[]?([A-Za-z0-9_]+)',
    caseSensitive: false);

String? _indexTableOf(String ddl) {
  final m = _onTableRe.firstMatch(ddl);
  return m?.group(1);
}

/// 一次 create 的加密器：全包共用一个随机 salt（PBKDF2 派生只做一次并缓存），
/// 每个成员用独立随机 nonce；blob = salt(16)|nonce(12)|密文+tag(16)。
class _BlobCipher {
  _BlobCipher(this._passphrase) : _salt = _randomBytes(_saltLength);

  final String _passphrase;
  final Uint8List _salt;
  SecretKey? _key;

  Future<SecretKey> _deriveKey() async {
    return _key ??= await Pbkdf2.hmacSha256(
      iterations: kPbkdf2Iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: _passphrase, nonce: _salt);
  }

  Future<Uint8List> encrypt(List<int> plain) async {
    final key = await _deriveKey();
    final nonce = _randomBytes(_nonceLength);
    final box = await AesGcm.with256bits()
        .encrypt(plain, secretKey: key, nonce: nonce);
    final mac = box.mac.bytes;
    final out = Uint8List(
        _saltLength + _nonceLength + box.cipherText.length + mac.length);
    var o = 0;
    out.setRange(o, o + _saltLength, _salt);
    o += _saltLength;
    out.setRange(o, o + _nonceLength, nonce);
    o += _nonceLength;
    out.setRange(o, o + box.cipherText.length, box.cipherText);
    o += box.cipherText.length;
    out.setRange(o, o + mac.length, mac);
    return out;
  }
}
