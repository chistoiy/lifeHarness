part of 'sync_sheets.dart';

// 治理G7d②：S2 连接验证弹层自 sync_sheets 整块外提（行为零改动）。
// 三态＝连接通过/凭据错误/网络失败（S2 口径）；凭据缺失时本地预检直出、不发请求。
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
