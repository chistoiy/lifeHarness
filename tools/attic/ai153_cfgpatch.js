// 一次性补丁：AiConfig.load() 两处构造补 recordBody/callKeepDays + 两个 setter。
const fs = require('fs');
const p = 'lib/core/ai/ai_config.dart';
let s = fs.readFileSync(p, 'utf8');
const before = s.length;
function rep(from, to, hits) {
  const n = s.split(from).length - 1;
  if (n !== hits) throw new Error('命中数不符 ' + JSON.stringify(from.slice(0, 50)) + ': got ' + n + ' want ' + hits);
  s = s.split(from).join(to);
}

// ① 已落 providers 的分支（8 空格缩进）
rep(`        verifyReason: v['reason'] as String?,
      );`,
    `        verifyReason: v['reason'] as String?,
        recordBody: _prefs.getBool(_kRecordBody) ?? true,
        callKeepDays: _prefs.getInt(_kCallKeepDays) ?? kAiCallDefaultKeepDays,
      );`, 1);

// ② 种子/旧键迁移分支（6 空格缩进）
rep(`      verifyReason: v['reason'] as String?,
    );`,
    `      verifyReason: v['reason'] as String?,
      recordBody: _prefs.getBool(_kRecordBody) ?? true,
      callKeepDays: _prefs.getInt(_kCallKeepDays) ?? kAiCallDefaultKeepDays,
    );`, 1);

// ③ setter 挂在 setVerifyResult 之后
rep(`  Map<String, bool> _decodeBoolMap(String? raw) {`,
    `  /// 是否留存发送与返回正文（关闭后新调用只记用量，已存正文不动，需单独清除）。
  Future<void> setRecordBody(bool on) => _prefs.setBool(_kRecordBody, on);

  /// 使用记录保留天数（0=不限）。
  Future<void> setCallKeepDays(int days) =>
      _prefs.setInt(_kCallKeepDays, days < 0 ? 0 : days);

  Map<String, bool> _decodeBoolMap(String? raw) {`, 1);

// ④ 默认值常量（类外顶层，供 UI 与仓储共用同一口径）
rep(`/// 旧版本单值端点匹配不到预置时合成的条目 id（升级兼容用）。`,
    `/// 使用记录默认保留天数（V1.53 拍板：30 天）。
const kAiCallDefaultKeepDays = 30;

/// 旧版本单值端点匹配不到预置时合成的条目 id（升级兼容用）。`, 1);

if (Math.abs(s.length - before) > 2000) throw new Error('体积异常');
fs.writeFileSync(p, s, 'utf8');
console.log('OK', before, '->', s.length);
