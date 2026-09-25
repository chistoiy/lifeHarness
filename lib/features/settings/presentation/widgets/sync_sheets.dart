import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/providers.dart';
import '../../../../core/sync/cloud_clean_service.dart';
import '../../../../core/sync/diff_service.dart';
import '../../../../core/sync/remote_store.dart';
import '../../../../core/sync/service_config.dart';
import '../../../../core/sync/snapshot_service.dart';
import '../../../../core/sync/sync_ledger.dart';
import '../../../../core/sync/sync_orchestrator.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';

/// V1.41 Task 18 · /sync 弹层家族（原型 index-sync.html s-svc-edit /
/// s-svc-verify / s-diff / s-syncprog / s-throttle；s-backup 归 Task 10）。
///
/// 口径：
/// - S1 凭据只经 [CredentialVault] 写入，成功才落配置（R11）；删服务连带清
///   保险箱键 + 台账键（D1/D3 无孤儿）。
/// - S2 三态 = 连接通过 / 凭据错误 / 网络失败，文案随协议（WebDAV 提示应用
///   密码 · S3 提示子账户 AK/SK + 桶权限）；凭据缺失时本地预检直出，不发请求。
/// - S3 四态分组 + 一致组折叠计数 + 逐条勾选 + 合计行；仅云端行带「下载」
///   （下载到导出目录，**绝不自动导入**）。
/// - S4 订阅 [SyncOrchestrator.state]（current/done/total + 取消钮）。
/// - S6 档位写回当前 ServiceConfig、快照份数滚轮（T6 同源单列滚轮实现）、
///   仅Wi-Fi 开关存 prefs `sync_wifiOnly`（T19 消费）。
/// - 文案一律功能标签式，无教学句、无 emoji（UI 规范）。

/// 仅 Wi-Fi 自动同步开关的 prefs 键（本期只存值）。
const String kSyncWifiOnlyKey = 'sync_wifiOnly';

// ============================ 公共小件 ============================

/// 字节数人类口径：`272.2 MB` / `1.2 GB` / `3 GB`（整数值去 `.0`）。
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final s = u == 0
      ? '$bytes'
      : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return '$s ${units[u]}';
}

/// epoch 毫秒 → `今天 08:31` / `昨天 21:02` / `09-22 20:15`。
String formatHistoryTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}';
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  final yesterday = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  final isYesterday =
      d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
  if (sameDay) return '今天 $hm';
  if (isYesterday) return '昨天 $hm';
  return '${two(d.month)}-${two(d.day)} $hm';
}

/// 服务展示名（ServiceConfig 无独立显示名字段，按端点派生——与原型
/// 「坚果云 · WebDAV / 缤纷云 · S3 / 自定义 · …」口径一致）。
String serviceDisplayName(ServiceConfig c) {
  final host = Uri.tryParse(c.apiUrl)?.host ?? '';
  if (c.isS3) {
    if (host.contains('bitiful')) return '缤纷云 · S3';
    return host.isEmpty ? '自定义 · S3' : '$host · S3';
  }
  if (host.contains('jianguoyun')) return '坚果云 · WebDAV';
  return host.isEmpty ? '未配置 · WebDAV' : '$host · WebDAV';
}

/// 差异徽标（原型 .badge-webdav / .badge-s3：协议徽标一律文字，无图标）。
class _ProtoBadge extends StatelessWidget {
  const _ProtoBadge({required this.isS3});

  final bool isS3;

  @override
  Widget build(BuildContext context) {
    final color = isS3 ? const Color(0xFF059669) : const Color(0xFF0284C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isS3 ? 'S3' : 'WebDAV',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color,
            letterSpacing: .4),
      ),
    );
  }
}

/// 保险箱状态点（原型 .lock-dot）。
class _LockDot extends StatelessWidget {
  const _LockDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration:
            const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      );
}

/// 方向徽标（S3/S4 行首上/下载箭头，原型 .dir-tag）。
class _DirTag extends StatelessWidget {
  const _DirTag({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    final color = up ? Theme.of(context).colorScheme.primary : const Color(0xFF047857);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 12, color: color),
    );
  }
}

/// 分段单选钮（原型 .seg-btn，S5 同源形态）。
class _SegBtn extends StatelessWidget {
  const _SegBtn({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? tokens.accent.withValues(alpha: .10) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: on ? tokens.accent : tokens.cardBorder, width: on ? 1.5 : 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: on ? tokens.accent : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 弹层小标题（原型 .sectitle）。
class _SecTitle extends StatelessWidget {
  const _SecTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
      );
}

/// 单列滚轮（T6 日志页 `_RetentionWheel` 同源实现：StatefulWidget 自持
/// FixedExtentScrollController + didUpdateWidget 等值守卫，防自激重建回环）。
class NumberWheel extends StatefulWidget {
  const NumberWheel({
    super.key,
    required this.labels,
    required this.index,
    required this.onSel,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSel;

  @override
  State<NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<NumberWheel> {
  static const double _itemExtent = 34;

  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
      initialItem: widget.index.clamp(0, widget.labels.length - 1));

  @override
  void didUpdateWidget(NumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        _ctl.hasClients &&
        _ctl.selectedItem != widget.index) {
      _ctl.jumpTo(widget.index.clamp(0, widget.labels.length - 1) * _itemExtent);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: _itemExtent * 3,
      child: CupertinoPicker(
        scrollController: _ctl,
        itemExtent: _itemExtent,
        diameterRatio: 1.5,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: widget.onSel,
        children: [
          for (var i = 0; i < widget.labels.length; i++)
            Center(
              child: Text(
                widget.labels[i],
                style: TextStyle(
                  fontSize: i == widget.index ? 19 : 12,
                  fontWeight: i == widget.index ? FontWeight.w800 : FontWeight.w600,
                  color: i == widget.index
                      ? tokens.accent
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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

// ============================ S2 · 连接验证 ============================

Future<void> showVerifySheet(BuildContext context, {required ServiceConfig config}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _VerifySheet(config: config),
  );
}

enum _VerifyKind { running, ok, cred, net }

class _VerifySheet extends ConsumerStatefulWidget {
  const _VerifySheet({required this.config});

  final ServiceConfig config;

  @override
  ConsumerState<_VerifySheet> createState() => _VerifySheetState();
}

class _VerifySheetState extends ConsumerState<_VerifySheet> {
  _VerifyKind _kind = _VerifyKind.running;
  String _detail = '探针发送中…';

  bool get _isS3 => widget.config.isS3;

  @override
  void initState() {
    super.initState();
    Future.microtask(_run);
  }

  /// 三态判定：凭据缺失本地预检直出（零请求）；verify 结果按协议文案归类
  /// （认证失败 → 凭据错误；异常/其他失败 → 网络失败）。
  Future<void> _run() async {
    setState(() {
      _kind = _VerifyKind.running;
      _detail = '探针发送中…';
    });
    final cfg = widget.config;
    String? secret;
    try {
      secret = await ref.read(credentialVaultProvider).read(cfg.id);
    } catch (_) {
      secret = null;
    }
    if (!mounted) return;
    if ((secret ?? '').isEmpty) {
      setState(() {
        _kind = _VerifyKind.cred;
        _detail = _isS3
            ? 'Secret Key 未存入 · 缤纷云需控制台创建子账户 Access Key/Secret Key，'
                '并为该子账户分配桶权限后在「服务配置」回填'
            : '应用密码未存入 · 坚果云「安全信任 → 应用密码」生成后在「服务配置」回填'
                '（应用密码而非登录密码）';
      });
      return;
    }
    RemoteStore? store;
    try {
      store = ref.read(remoteStoreFactoryProvider)(cfg);
      final res = await store.verify(cfg);
      if (!mounted) return;
      if (res.ok) {
        setState(() {
          _kind = _VerifyKind.ok;
          _detail = _isS3
              ? 'GET /?list-type=2&max-keys=1 → 200 · SigV4 签名校验通过 · 凭证与桶权限全通'
              : 'PROPFIND Depth:0 → 207 · 凭据与目录可达';
        });
      } else {
        final msg = res.message ?? '验证未通过';
        setState(() {
          _kind = msg.startsWith('认证失败') ? _VerifyKind.cred : _VerifyKind.net;
          _detail = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _kind = _VerifyKind.net;
        _detail = '$e';
      });
    } finally {
      store?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (title, color) = switch (_kind) {
      _VerifyKind.running => ('验证中…', tokens.accent),
      _VerifyKind.ok => ('连接通过', const Color(0xFF10B981)),
      _VerifyKind.cred => ('凭据错误', const Color(0xFFEF4444)),
      _VerifyKind.net => ('网络失败', const Color(0xFFF59E0B)),
    };
    final icon = switch (_kind) {
      _VerifyKind.ok => Icons.check_rounded,
      _VerifyKind.cred => Icons.error_outline_rounded,
      _VerifyKind.net => Icons.wifi_off_rounded,
      _VerifyKind.running => Icons.sync_rounded,
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('连接验证',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              _isS3
                  ? '探针 GET /?list-type=2&max-keys=1 · 响应按 utf8(bodyBytes) 解码'
                  : '探针 PROPFIND Depth:0 · 响应按 utf8(bodyBytes) 解码',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ProtoBadge(isS3: _isS3),
                const SizedBox(width: 8),
                Text(serviceDisplayName(widget.config),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('verify-state'),
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: .45), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        child: Icon(icon, size: 13, color: Colors.white),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(title,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_detail,
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Color(0xFF64748B),
                          height: 1.6)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('btn-reverify'),
                onPressed: _kind == _VerifyKind.running ? null : _run,
                child: const Text('重新验证'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================ S3 · 差异半屏 ============================

/// S3 → S4 的接力载荷（关闭差异半屏后由页面拉起进度半屏）。
class DiffRunRequest {
  const DiffRunRequest(this.diffs);

  final List<FileDiff> diffs;
}

Future<DiffRunRequest?> showDiffSheet(BuildContext context) {
  return showModalBottomSheet<DiffRunRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _DiffSheet(),
  );
}

/// 勾选口径：一条差异的传输字节（上传取本机、下载取云端）。
int _diffBytes(FileDiff d) => switch (d.status) {
      DiffStatus.onlyRemote => d.remote?.size ?? 0,
      _ => d.local?.size ?? d.remote?.size ?? 0,
    };

class _DiffSheet extends ConsumerStatefulWidget {
  const _DiffSheet();

  @override
  ConsumerState<_DiffSheet> createState() => _DiffSheetState();
}

class _DiffSheetState extends ConsumerState<_DiffSheet> {
  List<FileDiff> _diffs = const [];
  final Set<String> _off = {};
  bool _loading = true;
  String? _error;
  bool _sameOpen = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_scan);
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diffs = await ref.read(syncOrchestratorProvider).compare();
      if (!mounted) return;
      setState(() {
        _diffs = diffs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<FileDiff> _group(DiffStatus s) =>
      _diffs.where((d) => d.status == s).toList(growable: false);

  bool _selected(FileDiff d) => !_off.contains(d.relativePath);

  void _toggle(FileDiff d, bool v) {
    setState(() => v ? _off.remove(d.relativePath) : _off.add(d.relativePath));
  }

  void _selectAllOf(DiffStatus s) {
    setState(() {
      for (final d in _group(s)) {
        _off.remove(d.relativePath);
      }
    });
  }

  List<FileDiff> get _checkedActionable => _diffs
      .where((d) => d.status != DiffStatus.inSync && _selected(d))
      .toList(growable: false);

  ({int up, int down, int bytes}) get _sum {
    var up = 0, down = 0, bytes = 0;
    for (final d in _checkedActionable) {
      if (d.status == DiffStatus.onlyRemote) {
        down++;
      } else {
        up++;
      }
      bytes += _diffBytes(d);
    }
    return (up: up, down: down, bytes: bytes);
  }

  void _runWith(List<FileDiff> diffs) {
    if (diffs.isEmpty) {
      AppToast.show(context, '请先勾选要同步的文件');
      return;
    }
    Navigator.of(context).pop(DiffRunRequest(diffs));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final dir = () {
      try {
        return readActiveService(ref.read(syncConfigStoreProvider)).cloudDirName;
      } on StateError {
        return '未配置';
      }
    }();
    final sum = _sum;
    final same = _group(DiffStatus.inSync);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('差异对比',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800))),
                  TextButton(
                    key: const ValueKey('btn-diff-rescan'),
                    onPressed: _loading ? null : _scan,
                    child: const Text('重新扫描', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _loading
                      ? '正在比对本地快照目录与云端 $dir…'
                      : '本地快照目录 · $dir · 忽略规则两端同时剔除',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ),
            Flexible(
              child: _loading
                  ? const SizedBox(
                      height: 140,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('差异扫描失败：$_error',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFDC2626))),
                        )
                      // 全量子项一次性入树（SingleChildScrollView 非懒构建）：
                      // 一致组折叠头与勾选行不允许被视口裁掉。
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._section(
                                '仅本地',
                                _group(DiffStatus.onlyLocal),
                                up: true,
                              bulkLabel: '全选上传',
                              onBulk: () => _selectAllOf(DiffStatus.onlyLocal),
                            ),
                            ..._section(
                              '仅云端',
                              _group(DiffStatus.onlyRemote),
                              up: false,
                              bulkLabel: '全选下载',
                              onBulk: () => _selectAllOf(DiffStatus.onlyRemote),
                            ),
                            ..._section('已修改', _group(DiffStatus.modified), up: true),
                            // 一致组：默认折叠计数（原型 toggleSame）。
                            InkWell(
                              key: const ValueKey('diff-same-header'),
                              onTap: () => setState(() => _sameOpen = !_sameOpen),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(2, 13, 2, 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_rounded,
                                        size: 13, color: Color(0xFF64748B)),
                                    const SizedBox(width: 6),
                                    const Text('一致',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF64748B))),
                                    const SizedBox(width: 6),
                                    Text('${same.length} 条',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800)),
                                    const Spacer(),
                                    Text(_sameOpen ? '收起 ▴' : '展开 ▾',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              ),
                            ),
                            if (_sameOpen)
                              for (final d in same)
                                Opacity(
                                  opacity: .65,
                                  child: _plainRow(d),
                                ),
                            if (_diffs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('两端一致 · 无差异'),
                              ),
                            ],
                          ),
                        ),
                    ),
            // 合计行 + 同步已勾选（原型 .sumbar 吸底）。
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: tokens.card,
                border: Border(top: BorderSide(color: tokens.cardBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '上传 ${sum.up} · 下载 ${sum.down} · 共 ${formatBytes(sum.bytes)}',
                      key: const ValueKey('diff-sum'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('btn-diff-sync'),
                    onPressed: () => _runWith(_checkedActionable),
                    child: const Text('同步已勾选'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String title, List<FileDiff> rows,
      {required bool up, String? bulkLabel, VoidCallback? onBulk}) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        key: ValueKey('diff-group-$title'),
        padding: const EdgeInsets.fromLTRB(2, 13, 2, 4),
        child: Row(
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 13, color: const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(width: 6),
            Text('${rows.length}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (bulkLabel != null)
              PillChip(label: bulkLabel, onTap: onBulk),
          ],
        ),
      ),
      for (final d in rows) _checkRow(d, up: up),
    ];
  }

  Widget _checkRow(FileDiff d, {required bool up}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.scale(
            scale: .8,
            child: Checkbox(
              key: ValueKey('diff-chk-${d.relativePath}'),
              value: _selected(d),
              onChanged: (v) => _toggle(d, v ?? false),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _DirTag(up: up),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(d.relativePath,
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700)),
                ),
                if (d.status == DiffStatus.modified)
                  Text(
                    '两端内容不同 · 本机 ${formatBytes(d.local?.size ?? 0)} / 云端 ${formatBytes(d.remote?.size ?? 0)} · 冲突本机为准',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  ),
                if (d.staleHint)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: .55)),
                      ),
                      child: const Text('残留 · 台账记本机曾上传，本机已无此文件',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309))),
                    ),
                  ),
                if (!up && d.status == DiffStatus.onlyRemote)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _MiniBtn(
                        key: ValueKey('diff-get-${d.relativePath}'),
                        label: '下载',
                        onTap: () => _runWith([d]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(formatBytes(_diffBytes(d)),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          ),
        ],
      ),
    );
  }

  Widget _plainRow(FileDiff d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(d.relativePath,
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            ),
            Text('${formatBytes(_diffBytes(d))} · 一致',
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          ],
        ),
      );
}

/// 弹层内小动作钮（原型 .mini-btn）。
class _MiniBtn extends StatelessWidget {
  const _MiniBtn({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: tokens.accent)),
      ),
    );
  }
}

// ============================ S4 · 同步进度半屏 ============================

Future<void> showSyncProgressSheet(
  BuildContext context, {
  required SyncOrchestrator orchestrator,
  required Future<SyncOutcome> Function() task,
  required List<FileDiff> queue,
  ServiceConfig? config,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ProgressSheet(
        orchestrator: orchestrator, task: task, queue: queue, config: config),
  );
}

class _ProgressSheet extends ConsumerStatefulWidget {
  const _ProgressSheet({
    required this.orchestrator,
    required this.task,
    required this.queue,
    this.config,
  });

  final SyncOrchestrator orchestrator;
  final Future<SyncOutcome> Function() task;
  final List<FileDiff> queue;
  final ServiceConfig? config;

  @override
  ConsumerState<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends ConsumerState<_ProgressSheet> {
  SyncOutcome? _outcome;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final out = await widget.task();
      if (!mounted) return;
      setState(() {
        _outcome = out;
        _finished = true;
      });
      AppToast.show(
          context,
          out.canceled
              ? '同步已取消 · 无成功标记文件下次续传'
              : '同步完成 · 上传 ${out.up} · 下载 ${out.down} · 失败 ${out.failed.length}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _finished = true;
      });
      AppToast.show(context, '同步失败：$e');
    }
  }

  /// 队列渲染顺序与编排器执行顺序同构（非快照上传在前、快照最后、再下载段）：
  /// done 计数才能对上「第几格」；口径唯一来源 [SnapshotService.isSyncSnapshotName]。
  List<FileDiff> get _ordered {
    final uploads = widget.queue
        .where((d) => d.status == DiffStatus.onlyLocal || d.status == DiffStatus.modified)
        .toList();
    final downloads =
        widget.queue.where((d) => d.status == DiffStatus.onlyRemote).toList();
    bool isSnap(FileDiff d) =>
        SnapshotService.isSyncSnapshotName(p.basename(d.relativePath));
    return [
      ...uploads.where((d) => !isSnap(d)),
      ...uploads.where(isSnap),
      ...downloads,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ordered = _ordered;
    final totalBytes = ordered.fold<int>(0, (a, d) => a + _diffBytes(d));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<SyncTaskState>(
              valueListenable: widget.orchestrator.state,
              builder: (context, s, _) {
                final running = s.running;
                final done = s.done;
                final total = s.total;
                final doneBytes = ordered
                    .take(done.clamp(0, ordered.length))
                    .fold<int>(0, (a, d) => a + _diffBytes(d));
                final canceled = _outcome?.canceled ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(running ? '同步进行中' : '同步结束',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                        if (widget.config != null)
                          Text(
                              '${serviceDisplayName(widget.config!)} · 单任务串行',
                              style: const TextStyle(
                                  fontSize: 10.5, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$done / $total${s.current == null ? '' : ' · ${s.current!.relativePath}'}',
                          key: const ValueKey('sync-prog-line'),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                        Text('${formatBytes(doneBytes)} / ${formatBytes(totalBytes)}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      key: const ValueKey('sync-prog-bar'),
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2F7),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: tokens.gradient,
                                borderRadius: BorderRadius.circular(99))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < ordered.length; i++)
                      _row(ordered[i], i, done, running, canceled,
                          failedPaths: s.failedPaths),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('同步失败：$_error',
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFFDC2626))),
                      ),
                    if ((_outcome?.downloadedToExports ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            '已下载 ${_outcome!.downloadedToExports} 个云端文件到导出目录 · 未自动导入，请经「备份导出/导入」发起恢复',
                            key: const ValueKey('sync-import-guide'),
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF047857))),
                      ),
                    if ((_outcome?.failed.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('失败 ${_outcome!.failed.length} 个 · 明细见日志',
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDC2626))),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        PillChip(
                            // 人话口径：功能标签式（评审修复轮1——不直出
                            // 「HttpGate/requestIntervalMs」工程术语）。
                            label:
                                '请求间隔 ${widget.config?.requestIntervalMs ?? ServiceConfig.defaultRequestIntervalMs}ms · 防服务端频控'),
                        const Expanded(
                          child: Text('遇限流自动退避重发',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF94A3B8))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const ValueKey('btn-cancel-sync'),
                        onPressed: running
                            ? () => widget.orchestrator.cancel()
                            : (_finished || total == 0)
                                ? () => Navigator.of(context).pop()
                                : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: running ? const Color(0xFFDC2626) : null,
                          side: BorderSide(
                              color: running
                                  ? const Color(0xFFFCA5A5)
                                  : tokens.cardBorder),
                        ),
                        child: Text(running ? '取消' : '完成'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
      FileDiff d, int i, int done, bool running, bool canceled,
      {Set<String> failedPaths = const {}}) {
    final isCurrent = running && i == done;
    final String status;
    final Color color;
    if (failedPaths.contains(d.relativePath)) {
      // R3③：失败文件如实显「失败」——旧版只按 done 计数渲染，
      // 出现过「三行全绿完成 + 页脚失败 3 个」的矛盾画面。
      status = '失败';
      color = const Color(0xFFDC2626);
    } else if (i < done) {
      status = '完成 ${formatBytes(_diffBytes(d))}';
      color = const Color(0xFF10B981);
    } else if (isCurrent) {
      status = '传输中';
      color = context.tokens.accent;
    } else if (canceled) {
      status = '取消未传';
      color = const Color(0xFFB45309);
    } else {
      status = '排队 ${formatBytes(_diffBytes(d))}';
      color = const Color(0xFF94A3B8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Row(
        children: [
          _DirTag(up: d.status != DiffStatus.onlyRemote),
          const SizedBox(width: 9),
          Expanded(
            child: Text(d.relativePath,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(status,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

// ============================ S6 · 控流弹层 ============================

const List<int> _kThrottleTiers = [150, 300, 800];
const List<int> _kKeepOptions = [3, 5, 10, 20];

Future<void> showThrottleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _ThrottleSheet(),
  );
}

class _ThrottleSheet extends ConsumerStatefulWidget {
  const _ThrottleSheet();

  @override
  ConsumerState<_ThrottleSheet> createState() => _ThrottleSheetState();
}

class _ThrottleSheetState extends ConsumerState<_ThrottleSheet> {
  ServiceConfig? _cfg;
  int _keepN = kSyncKeepSnapshotsDefault;
  bool _wifi = false;
  bool _autoArc = false;
  bool _purge30 = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      _cfg = readActiveService(ref.read(syncConfigStoreProvider));
    } on StateError {
      _cfg = null;
    }
    final raw = prefs.getInt(kSyncKeepSnapshotsKey);
    _keepN = (raw == null || raw < 1) ? kSyncKeepSnapshotsDefault : raw;
    _wifi = prefs.getBool(kSyncWifiOnlyKey) ?? false;
    _autoArc = prefs.getBool(CloudCleanService.kAutoArchive) ?? false;
    _purge30 = prefs.getBool(CloudCleanService.kArchivePurge30) ?? false;
  }

  void _setAutoArc(bool v) {
    setState(() => _autoArc = v);
    ref.read(sharedPreferencesProvider).setBool(CloudCleanService.kAutoArchive, v);
  }

  void _setPurge30(bool v) {
    setState(() => _purge30 = v);
    ref.read(sharedPreferencesProvider)
        .setBool(CloudCleanService.kArchivePurge30, v);
  }

  void _toast(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  /// 档位写回当前 ServiceConfig（R10 按服务配置，非全局）。
  Future<void> _setInterval(int ms) async {
    final cfg = _cfg;
    if (cfg == null || cfg.requestIntervalMs == ms) return;
    final store = ref.read(syncConfigStoreProvider);
    final snap = store.load();
    final target = snap.services.where((c) => c.id == cfg.id).firstOrNull;
    if (target == null) return;
    target.requestIntervalMs = ms;
    try {
      await store.save(snap);
    } on StateError catch (e) {
      _toast('写入失败：${e.message}');
      return;
    }
    setState(() => _cfg = target);
    _toast('请求间隔已设为 ${ms}ms · 仅作用于该服务的同步请求排队');
  }

  void _setKeepN(int n) {
    if (n == _keepN) return;
    setState(() => _keepN = n);
    ref.read(sharedPreferencesProvider).setInt(kSyncKeepSnapshotsKey, n);
  }

  /// T19：自动同步引擎接入后消费 `sync_wifiOnly`——本期自动同步未接，
  /// 开关先存值（手动同步不受限）。
  void _setWifi(bool v) {
    setState(() => _wifi = v);
    ref.read(sharedPreferencesProvider).setBool(kSyncWifiOnlyKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final interval = cfg?.requestIntervalMs ?? ServiceConfig.defaultRequestIntervalMs;
    final keepIdx = _kKeepOptions.indexOf(_keepN);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('控流设置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('同步请求统一排队 · 按服务设置请求间隔',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const _SecTitle('节流档位 · 请求间隔'),
            Row(
              children: [
                for (final ms in _kThrottleTiers) ...[
                  Expanded(
                    child: _SegBtn(
                        key: ValueKey('throttle-seg-$ms'),
                        label: '${ms}ms',
                        on: interval == ms,
                        onTap: () => _setInterval(ms)),
                  ),
                  if (ms != _kThrottleTiers.last) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '请求间隔 · 非全局带宽 · 当前 ${interval}ms'
              '${cfg == null ? '（未配置服务）' : '（${serviceDisplayName(cfg)}）'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: context.cardDecoration,
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('429 / 503 退避',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                      'Retry-After 优先 · 2s→4s→8s · 单次上限 30s · 重发 ≤3 · 重发必重建请求对象',
                      style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ],
              ),
            ),
            const _SecTitle('历史快照份数 N · 同步对象 = 最新 N 份快照 + 日志'),
            NumberWheel(
              key: const ValueKey('keep-n-wheel'),
              labels: [for (final n in _kKeepOptions) '$n 份'],
              index: keepIdx < 0 ? 1 : keepIdx,
              onSel: (i) => _setKeepN(_kKeepOptions[i]),
            ),
            const SizedBox(height: 5),
            const Center(
              child: Text('超份数丢最旧 · care.syncExcluded 置位则快照排除呵护表并写入 manifest',
                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('仅 Wi-Fi 自动同步',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('每天节流 · 手动同步不受限',
                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('wifi-switch'),
                  value: _wifi,
                  onChanged: _setWifi,
                ),
              ],
            ),
            // R5d：云端自动归档（只移不删）+ 归档区 30 天清理（默认关）。
            Row(
              children: [
                const Expanded(
                  child: Text('同步后自动归档云端未引用附件',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  key: const ValueKey('auto-archive-switch'),
                  value: _autoArc,
                  onChanged: _setAutoArc,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text('归档区 30 天后清理',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  key: const ValueKey('archive-purge-switch'),
                  value: _purge30,
                  onChanged: _setPurge30,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('缓存',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B))),
                      Text('同目录清单 60s · 容量 5min · MKCOL 进程内记忆',
                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                const Text('列举超时 30s · 传输 10min',
                    style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// R5d：云端孤儿附件清理半屏（S7）。
///
/// 口径：打开即 force 拉云端清单 + 本地引用集算孤儿；勾选后两钮——
/// 「归档」move 到 media_archive/（默认动作、可回退）；「彻底删除」需
/// 二次确认弹窗。零孤儿显空态。文案功能标签式，无教学句。
Future<void> showCloudCleanSheet(BuildContext context,
    {required ServiceConfig config}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CloudCleanSheet(config: config),
  );
}

class _CloudCleanSheet extends ConsumerStatefulWidget {
  const _CloudCleanSheet({required this.config});

  final ServiceConfig config;

  @override
  ConsumerState<_CloudCleanSheet> createState() => _CloudCleanSheetState();
}

class _CloudCleanSheetState extends ConsumerState<_CloudCleanSheet> {
  late Future<List<FileEntry>> _future = _load();
  final Set<String> _checked = {};
  bool _busy = false;

  Future<List<FileEntry>> _load() {
    final store = ref.read(remoteStoreFactoryProvider)(widget.config);
    return ref.read(cloudCleanServiceProvider).cloudOrphans(store, widget.config);
  }

  void _rescan() {
    setState(() {
      _checked.clear();
      _future = _load();
    });
  }

  Future<void> _act({required bool archive}) async {
    final sel = _orphans.where((e) => _checked.contains(e.relativePath)).toList();
    if (sel.isEmpty) return;
    if (!archive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (bc) => AlertDialog(
          title: const Text('彻底删除'),
          content: Text('将从云端移除 ${sel.length} 个文件，不可恢复。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(bc, false), child: const Text('取消')),
            FilledButton(
                key: const ValueKey('cc-purge-confirm'),
                onPressed: () => Navigator.pop(bc, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final store = ref.read(remoteStoreFactoryProvider)(widget.config);
    final svc = ref.read(cloudCleanServiceProvider);
    final n = archive
        ? await svc.archive(store, widget.config, sel)
        : await svc.purge(store, widget.config, sel);
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.show(context, archive ? '已归档 $n 个文件' : '已删除 $n 个文件');
    _rescan();
  }

  List<FileEntry> _orphans = const [];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('清理云端',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: FutureBuilder<List<FileEntry>>(
                future: _future,
                builder: (context, s) {
                  if (!s.hasData) {
                    return const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator()));
                  }
                  _orphans = s.data!;
                  if (_orphans.isEmpty) {
                    return const SizedBox(
                      height: 160,
                      child: Center(
                          child: Text('云端无未引用附件',
                              key: ValueKey('cc-empty'),
                              style: TextStyle(fontSize: 13))),
                    );
                  }
                  return ListView.builder(
                    itemCount: _orphans.length,
                    itemBuilder: (context, i) {
                      final e = _orphans[i];
                      return CheckboxListTile(
                        key: ValueKey('cc-row-${e.relativePath}'),
                        dense: true,
                        value: _checked.contains(e.relativePath),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() =>
                                v == true
                                    ? _checked.add(e.relativePath)
                                    : _checked.remove(e.relativePath)),
                        title: Text(e.relativePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace')),
                        subtitle: Text(
                            '${(e.size / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(fontSize: 11)),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('cc-archive'),
                      onPressed:
                          _busy || _checked.isEmpty ? null : () => _act(archive: true),
                      child: Text(_checked.isEmpty
                          ? '归档'
                          : '归档（${_checked.length}）'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('cc-purge'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626)),
                      onPressed: _busy || _checked.isEmpty
                          ? null
                          : () => _act(archive: false),
                      child: const Text('彻底删除'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
