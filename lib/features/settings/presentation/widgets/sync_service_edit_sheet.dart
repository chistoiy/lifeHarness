part of 'sync_sheets.dart';

// 治理G7d②：S1 服务配置编辑弹层自 sync_sheets 整块外提（行为零改动）。
// 缺省端点常量 + showServiceEditSheet + _ServiceEditSheet(State)；凭据只经 CredentialVault 写入（R11）。
// ============================ S1 · 服务配置编辑 ============================

/// WebDAV 缺省端点 / S3 缺省 endpoint（原型表单预填口径）。
const String _kWebDavDefaultUrl = 'https://dav.jianguoyun.com/dav/';
const String _kS3DefaultUrl = 'https://s3.bitiful.net';

Future<Object?> showServiceEditSheet(BuildContext context, {ServiceConfig? config}) {
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ServiceEditSheet(config: config),
  );
}

class _ServiceEditSheet extends ConsumerStatefulWidget {
  const _ServiceEditSheet({this.config});

  final ServiceConfig? config;

  @override
  ConsumerState<_ServiceEditSheet> createState() => _ServiceEditSheetState();
}

class _ServiceEditSheetState extends ConsumerState<_ServiceEditSheet> {
  late StoreProviderKind _prov;
  late final TextEditingController _url;
  late final TextEditingController _account;
  late final TextEditingController _region;
  late final TextEditingController _bucket;
  late final TextEditingController _dir;
  final TextEditingController _secret = TextEditingController();
  bool _hasSecret = false;
  bool _secretVisible = false;
  String? _error;
  bool _busy = false;

  bool get _isNew => widget.config == null;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _prov = c?.provider ?? StoreProviderKind.webdav;
    _url = TextEditingController(text: c?.apiUrl ?? _kWebDavDefaultUrl);
    _account = TextEditingController(text: c?.account ?? '');
    _region = TextEditingController(text: c?.region ?? '');
    _bucket = TextEditingController(text: c?.bucket ?? '');
    _dir = TextEditingController(text: c?.cloudDirName ?? 'sync');
    _loadSecretState();
  }

  /// 编辑已有服务时从 vault 读回密钥填入 _secret（R2 项⑤a——过去只显状态点、
  /// 不回填，用户看不到已存值、易误清空重填）；新增服务无回填。默认掩码显示，
  /// 行尾眼睛钮切显隐；保存逻辑不变（非空即写 vault）。
  Future<void> _loadSecretState() async {
    final id = widget.config?.id;
    if (id == null) return;
    final secret = await ref.read(credentialVaultProvider).read(id);
    if (!mounted) return;
    setState(() {
      _hasSecret = (secret ?? '').isNotEmpty;
      _secret.text = secret ?? '';
    });
  }

  void _setProvider(StoreProviderKind kind) {
    setState(() {
      // 评审修复轮1 Minor-3：**新增态**切协议清空账户字段——WebDAV「账户」
      // （邮箱）与 S3「Access Key」语义不同，留着会串显并误导保存；编辑态
      // 协议 pill 已锁（R2⑤b）走不进这里，无需保护已存值。
      if (_isNew && kind != _prov) _account.clear();
      _prov = kind;
      // 端点未手改时在两协议缺省值间联动切换（原型 Endpoint「写死」口径）。
      final cur = _url.text.trim();
      if (cur.isEmpty || cur == _kWebDavDefaultUrl || cur == _kS3DefaultUrl) {
        _url.text = kind == StoreProviderKind.s3 ? _kS3DefaultUrl : _kWebDavDefaultUrl;
      }
      _error = null;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _account.dispose();
    _region.dispose();
    _bucket.dispose();
    _dir.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  ServiceConfig _compose() => ServiceConfig(
        id: widget.config?.id ??
            'svc_${DateTime.now().millisecondsSinceEpoch}',
        provider: _prov,
        apiUrl: _url.text.trim(),
        account: _account.text.trim(),
        region: _prov == StoreProviderKind.s3 ? _region.text.trim() : '',
        bucket: _prov == StoreProviderKind.s3 ? _bucket.text.trim() : '',
        cloudDirName: _dir.text.trim(),
        requestIntervalMs:
            widget.config?.requestIntervalMs ?? ServiceConfig.defaultRequestIntervalMs,
        verifyContent: widget.config?.verifyContent ?? false,
      );

  /// 地址校验（与 S3Store._root 携带修复同一口径：缺 scheme/host 即配置错误）。
  String? _validateUrl() {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return '地址无效：需含 https:// 方案与主机名';
    }
    return null;
  }

  Future<void> _save({bool thenVerify = false}) async {
    if (_busy) return;
    final bad = _validateUrl();
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final cfg = _compose();
    final secret = _secret.text;
    bool ok;
    try {
      ok = await ref
          .read(syncConfigStoreProvider)
          .saveService(cfg, secret: secret.isEmpty ? null : secret);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败：${e.message}';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // R11：vault 写失败 → 配置原样保留，绝不把服务变成「没有凭据」。
      _toast('保险箱写入失败 · 原凭据与原配置已保留');
      return;
    }
    if (secret.isNotEmpty) {
      setState(() => _hasSecret = true);
      _toast('已保存 · 凭据已存入本机加密区');
    } else {
      _toast('已保存');
    }
    if (thenVerify) {
      // R6 真机反馈：验证不再关闭编辑弹层——S2 盖在 S1 之上，
      // 失败关掉结果层即可原地改配置重验。
      await showVerifySheet(context, config: cfg);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    if (_busy || _isNew) return;
    setState(() => _busy = true);
    final store = ref.read(syncConfigStoreProvider);
    final id = widget.config!.id;
    // 台账键按「存储侧目录」清（编辑未保存的目录不算数）；vault 键由
    // SyncConfigStore.removeService 内部清除（D1 无孤儿凭据）。
    final stored = store.load().services.where((c) => c.id == id).firstOrNull;
    final ledger = SyncLedger(
      ref.read(sharedPreferencesProvider),
      serviceId: id,
      cloudDirName: stored?.cloudDirName ?? widget.config!.cloudDirName,
    );
    await ledger.clear();
    await store.removeService(id);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('已删除服务 · 密钥与台账已清除');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isS3 = _prov == StoreProviderKind.s3;
    // R2 项⑤d 输入法遮挡：showModalBottomSheet 在本工程 Flutter(3.38.9) 无
    // resizeToAvoidBottomInset 形参，改在内容外层用 viewInsets.bottom 兜底抬升
    // （与滚动视图配合即等效于「键盘弹起内容不被遮」）。
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SingleChildScrollView(
          key: const ValueKey('svc-edit-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('服务配置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              const Text('字段随协议联动 · 凭据读写仅走本机加密区',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  PillChip(
                    key: const ValueKey('edit-pill-webdav'),
                    label: '坚果云 · WebDAV',
                    selected: !isS3,
                    // R2 项⑤b 协议锁定：编辑已建服务时禁改协议（改协议会覆盖同
                    // 一条服务致「列表只剩一个」），仅新增可选。
                    enabled: _isNew,
                    onTap: () => _setProvider(StoreProviderKind.webdav),
                  ),
                  const SizedBox(width: 8),
                  PillChip(
                    key: const ValueKey('edit-pill-s3'),
                    label: '缤纷云 · S3',
                    selected: isS3,
                    enabled: _isNew,
                    onTap: () => _setProvider(StoreProviderKind.s3),
                  ),
                ],
              ),
              _field('地址', 'Endpoint', _url, 'edit-apiurl'),
              _field('账户', 'Access Key', _account, 'edit-account',
                  hintWebDav: '邮箱 / 手机号'),
              if (isS3) ...[
                _field('Region', 'Region', _region, 'edit-region',
                    hintWebDav: 'cn-east-1'),
                _field('Bucket', 'Bucket', _bucket, 'edit-bucket',
                    hintWebDav: '私有桶名'),
              ],
              _field(
                  '应用密码', 'Secret Key', _secret, 'edit-secret',
                  obscure: !_secretVisible,
                  secret: true,
                  // R2 项⑤a：默认掩码，行尾线性眼睛钮切显隐。
                  trailing: IconButton(
                    key: const ValueKey('edit-secret-eye'),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    tooltip: _secretVisible ? '隐藏密钥' : '显示密钥',
                    onPressed: () =>
                        setState(() => _secretVisible = !_secretVisible),
                    icon: Icon(_secretVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                  )),
              _field('远程目录', '远程目录', _dir, 'edit-dir'),
              if (isS3)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('缤纷云密钥来自控制台子账户 · 主账户密钥不可直连',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('坚果云「安全信任 → 应用密码」，非登录密码',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ),
              if (_hasSecret)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: const [
                      _LockDot(),
                      SizedBox(width: 6),
                      Text('已存入本机加密区',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF047857))),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!,
                      key: const ValueKey('edit-error'),
                      style:
                          const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('edit-save'),
                      onPressed: _busy ? null : () => _save(),
                      child: const Text('保存'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('edit-verify'),
                      onPressed: _busy ? null : () => _save(thenVerify: true),
                      child: const Text('验证连接'),
                    ),
                  ),
                ],
              ),
              if (!_isNew) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const ValueKey('edit-delete'),
                    onPressed: _busy ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                    ),
                    child: const Text('删除服务 · 连带清除保险箱密钥'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 单字段：标签随协议切换（webDavLabel ↔ s3Label），凭据类字段带保险箱点。
  /// [trailing] 行尾动作位（密钥眼睛钮）；聚焦经 [Scrollable.ensureVisible]
  /// 把输入框抬进可视区（R2 项⑤d 输入法遮挡）。
  Widget _field(String webDavLabel, String s3Label, TextEditingController ctl, String key,
      {bool obscure = false, bool secret = false, String? hintWebDav, Widget? trailing}) {
    final label = _prov == StoreProviderKind.s3 ? s3Label : webDavLabel;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              if (secret && _hasSecret) ...[
                const SizedBox(width: 6),
                const _LockDot(),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 4),
          Builder(builder: (fieldContext) => TextField(
            key: ValueKey(key),
            controller: ctl,
            obscureText: obscure,
            style: const TextStyle(fontSize: 12.5),
            onTap: () => Scrollable.ensureVisible(
              fieldContext,
              alignment: 0.1,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintWebDav,
              border: const OutlineInputBorder(),
            ),
          )),
        ],
      ),
    );
  }
}
