/// 发送前数据最小化（需求清单 §六 原则 4）· 竞品补全清单 C01 第 0 批。
///
/// 三条口径：
/// ① 只打码**身份/凭据类串**（手机号 / 邮箱 / 证件号 / 密钥 / 口令字段），
///    不动金额、日期、书名、标签、商户名——打码业务字段会让归类与解析
///    静默降级，等于用隐私之名破坏功能。
/// ② 对所有能力点生效、默认开启、无开关；幂等，重复调用不吃掉相邻文本。
/// ③ 审阅层、实际请求、`ai_calls` 留痕三者共用本文件的输出
///    （由 `AiService.renderForSend` 统一取用），杜绝「看到 A、发出 B、记成 C」。
///
/// **本批不做**：「仅摘要发送」模式。它要改变发送内容的语义（发什么、发多少），
/// 须产品先拍板摘要定义并过原型门；详见
/// `docs/handoff/评估结论-20261106-GitHub竞品对标深度差补全清单.md` §2 C01。
/// 端点验证通道（`AiService.verifyEndpoint`）的 prompt 由用户手填、不注入业务数据，
/// 本批不纳入；日后若接入业务变量，一律改走 `renderForSend`。
library;

/// 邮箱：user@host.tld。先于数字串处理，避免 `13800138000@qq.com` 只被截半。
final _reEmail = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+');

/// 二代身份证 18 位（末位可为 X）。`(\D|^)` 与 `(?!\d)` 夹住，避免从长订单号里
/// 截出一段误判；替换时把前导字符原样放回。
final _reIdCard = RegExp(r'(\D|^)(\d{17}[\dXx])(?!\d)', caseSensitive: false);

/// 中国大陆手机号 11 位。同样要求数字边界。
final _reMobile = RegExp(r'(\D|^)(1[3-9]\d{9})(?!\d)');

/// 常见密钥形态：`sk-...` 与 `Bearer ...`。
final _reApiKey = RegExp(
    r'(sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{8,})',
    caseSensitive: false);

/// 口令/令牌字段值：`token: xxx`、`api_key="xxx"`、`密码：xxx` 等。
/// 值字符类排除空白与常见分隔，防止吃掉相邻正文。
final _reSecretField = RegExp(
    r'''((?:api[_-]?key|token|password|passwd|secret|密码|口令)\s*["']?\s*[:=：]\s*["']?)([^\s"',;&]+)''',
    caseSensitive: false);

/// 发往端点前统一过一遍。**幂等**：打码标记内无数字串/密钥形态，二次调用结果不变。
String redactForSend(String text) {
  var out = text;
  out = out.replaceAll(_reEmail, '[邮箱]');
  out = out.replaceAllMapped(_reIdCard, (m) => '${m.group(1) ?? ''}[证件号]');
  out = out.replaceAllMapped(_reMobile, (m) => '${m.group(1) ?? ''}[手机号]');
  out = out.replaceAllMapped(_reApiKey, (m) => '[密钥]');
  out = out.replaceAllMapped(_reSecretField, (m) => '${m.group(1)}[已隐藏]');
  return out;
}
