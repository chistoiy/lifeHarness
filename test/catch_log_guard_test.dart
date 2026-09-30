import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 「catch 必带日志」架构守护（日志覆盖工单 §五-2 · L1~L5 铺完后上线）。
///
/// 口径：`lib/**` 里每一个异常处置块（`catch (...) {…}` 与不带 catch 的 `on X {…}` 回落）
/// 必须对自己**有交代**，满足任一条即合规：
/// 1. 块内调用 `AppLog.add / addKey / addStack / reportError`——自己留了痕；
/// 2. 块内 `rethrow` 或 `throw`——交给上层，上层出口已统一（`error_capture` → AppLog）；
/// 3. 块内或紧邻块上方（同前行/上一行）有 `catch-ok: 理由` 注释——人批准的有意回落
///    （`//` 与 `/* */` 两种形态都认）；
/// 4. 位于 [_infra] 面内——日志基建自己不能再往自己身上记。
/// 其余＝静默吞噬，必须进 [baseline] 登记（登记值＝登记时该文件违规数），此后**只许减不许增**；
/// 变小提示收紧，清零请**删掉登记项**让该文件回到默认面。
///
/// 重生成登记面（修完一批后跑一次，把输出贴回 [baseline]）：
/// `CATCH_GUARD_DUMP=1 flutter test test/catch_log_guard_test.dart`
/// 合规判定口径（供守护用例与自证用例共用）。
const _logRe =
    r'\b(?:AppLog\s*\.\s*(?:add|addKey|addStack|reportError)|reportError)\s*\(';
const _throwRe = r'\b(?:rethrow|throw)\b';
const _okRe = r'(?://|/\*)\s*catch-ok:';

void main() {
  const libDir = 'lib';

  /// 基建豁免面：日志自身链路。这些文件里的 catch 记日志会递归，不纳入守护。
  const infra = ['core/logging/'];

  // 上线时（2026-09-29 · L1~L5 收口后）在 **HEAD 干净树**实测登记的存量面：108 处 / 51 文件，只许减不许增。
  // 注意：登记面必须从 HEAD（`git worktree` 检出）取数，别在脏工作区跑 dump——
  //    并行会话未提交的新文件（如当时的 kits/domain/kit_datec.dart）会被误登记，
  //    干净 checkout 里那项找不到对应文件即判 stale 空转报红。
  // 干净 checkout 里那项找不到对应文件即判 stale 空转报红。
  // 其中 features/read(47) 属并行阅读器会话写区，由各自的留痕批次消项；
  // （原 features/kits 两项已随 V1.58 小工具整模块下架删除登记——文件本身不存在了。）
  // 域内动到哪个文件，就把它的登记改小或直接删项。
  const baseline = <String, int>{
    'core/ai/ai_config.dart': 1,
    'core/ai/ai_review.dart': 2,
    'core/ai/ai_validate.dart': 1,
    'core/backup/backup_service.dart': 3,
    'core/backup/lh_bak.dart': 4,
    'core/media/media_usage_scanner.dart': 1,
    'core/settings/user_settings.dart': 2,
    'core/sync/credential_vault.dart': 2,
    'core/sync/http_gate.dart': 1,
    'core/sync/s3_store.dart': 1,
    'core/sync/service_config.dart': 1,
    'core/sync/snapshot_service.dart': 4,
    'core/sync/sync_ledger.dart': 1,
    'core/sync/sync_orchestrator.dart': 1,
    'core/sync/sync_providers.dart': 1,
    'core/sync/webdav_store.dart': 5,
    'core/theme/theme_repository.dart': 2,
    'features/journal/presentation/diary_edit_page.dart': 1,
    'features/journal/presentation/note_edit_rich.dart': 1,
    'features/ledger/data/ledger_repository.dart': 2,
    'features/read/data/epub_cache.dart': 16,
    'features/read/data/epub_doc.dart': 2,
    'features/read/data/isbn_enrich.dart': 3,
    'features/read/data/read_import.dart': 2,
    'features/read/domain/book.dart': 2,
    'features/read/domain/book_quote.dart': 1,
    'features/read/domain/reader_cfg.dart': 1,
    'features/read/presentation/import/local_import_page.dart': 2,
    'features/read/presentation/read_providers.dart': 1,
    'features/read/presentation/read_settings_page.dart': 1,
    'features/read/presentation/reader/epub_state_ui.dart': 3,
    'features/read/presentation/reader/reader_appearance_sheet.dart': 2,
    'features/read/presentation/reader/reader_links.dart': 1,
    'features/read/presentation/reader/reader_models.dart': 2,
    'features/read/presentation/reader/reader_page.dart': 6,
    'features/read/presentation/shelf/shelf_page.dart': 1,
    'features/read/presentation/stats/quotes_lib_page.dart': 1,
    'features/settings/presentation/ai_page_form.dart': 2,
    'features/settings/presentation/log_page.dart': 3,
    'features/settings/presentation/sync_backup_sheet.dart': 3,
    'features/settings/presentation/sync_page.dart': 1,
    'features/settings/presentation/widgets/sync_diff_sheet.dart': 2,
    'features/settings/presentation/widgets/sync_progress_sheet.dart': 1,
    'features/settings/presentation/widgets/sync_service_edit_sheet.dart': 1,
    'features/settings/presentation/widgets/sync_throttle_sheet.dart': 2,
    'features/settings/presentation/widgets/sync_verify_sheet.dart': 2,
    'shared/calendar/lunar.dart': 1,
    'shared/linkage/ledger_mounts.dart': 1,
    'shared/widgets/image_attach.dart': 2,
    'shared/weather/weather_service.dart': 1,
  };

  test('catch 必带日志：静默吞噬不得新增（登记面只许减不许增）', () {
    final found = <String, List<int>>{};
    final blocks = <_CatchBlock>[];
    for (final f in Directory(
      libDir,
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      if (infra.any(rel.startsWith)) continue;
      blocks.addAll(_scanFile(rel, f.readAsStringSync()));
    }
    for (final b in blocks) {
      if (b.compliant()) continue;
      (found[b.path] ??= <int>[]).add(b.line);
    }

    if (Platform.environment['CATCH_GUARD_DUMP'] == '1') {
      final keys = found.keys.toList()..sort();
      stdout.writeln(
        '=== CATCH GUARD DUMP（共 ${blocks.length} 块 · 违规 ${found.values.expand((e) => e).length}）===',
      );
      for (final k in keys) {
        stdout.writeln("    '$k': ${found[k]!.length},");
      }
      stdout.writeln('=== DUMP END ===');
      stdout.writeln(
        '明细：${keys.map((k) => '$k [行 ${found[k]!.join(',')}]').join('\n')}',
      );
      return;
    }

    final over = <String>[], grown = <String>[], shrunk = <String>[];
    for (final k in found.keys) {
      final n = found[k]!.length;
      final b = baseline[k];
      if (b == null) {
        over.add('$k（$n 处，未登记）→ 行 ${found[k]!.join(',')}');
      } else if (n > b) {
        grown.add('$k（$n > 登记 $b）');
      } else if (n < b) {
        shrunk.add('$k（$n < 登记 $b，请调小或删项归还默认面）');
      }
    }
    final stale = baseline.keys.where((k) => !found.containsKey(k)).toList();
    expect(
      blocks.length,
      greaterThan(150),
      reason: '扫描面骤减（只扫到 ${blocks.length} 块）：多半是解析器坏了，守护正在空转。',
    );

    expect(
      over,
      isEmpty,
      reason:
          '出现未登记的静默 catch：要么补 AppLog 留痕，要么显式 `// catch-ok: 理由`，'
          '确需豁免再进本测试 baseline（登记＝允许存在的当前处数，之后只许减）。',
    );
    expect(grown, isEmpty, reason: '已登记文件的静默 catch 变多了：登记面只许减不许增。');
    expect(
      shrunk,
      isEmpty,
      reason: '以下文件已变小，棘轮要收紧（跑一次 CATCH_GUARD_DUMP=1 重生成）。',
    );
    expect(
      stale,
      isEmpty,
      reason: '以下登记项已无违规，请删掉（否则守护对它们悄悄空转）：${stale.join('、')}',
    );
  });

  // 正对照：分类器坏了会「零违规假绿」，这里用已知答案的合成样本钉判定面。
  test('守护自证：四种合规形态放过、静默吞噬抓到、extension on 不误判', () {
    const sample = '''
void a() { try { x(); } catch (e) { AppLog.add('\$e'); } }
void b() { try { x(); } catch (e) { rethrow; } }
void c() { try { x(); } catch (e) { AppLog.reportError(e, s); } }
void d() { try { x(); } catch (e) { /* catch-ok: 按约定取默认 */ return 0; } }
void d2() { try { x(); }
  // catch-ok: 有意静默，上文已留痕
  catch (e) { return; } }
void e() { try { x(); } catch (e) { return; } }
void f() { try { x(); } on SocketException { return; } }
extension G on BuildContext { void h() { try { x(); } catch (e) { return; } } }
''';
    final blocks = _scanFile('sample.dart', sample);
    if (Platform.environment['CATCH_GUARD_DUMP'] == '1') {
      for (final b in blocks) {
        stdout.writeln(
          '[PROBE] line=${b.line} ok=${b.compliant()} '
          'body=${b.body.replaceAll('\n', '\\n').trim()} || above=${b.above.replaceAll('\n', '\\n').trim()}',
        );
      }
    }
    final bad = blocks.where((b) => !b.compliant()).map((b) => b.line).toList();
    // 应判 3 处静默：e（吞）、f（on 回落吞）、h（吞）；a~d2 合规；extension G on … 不是异常块。
    expect(
      bad.length,
      3,
      reason: '应判 3 处静默吞噬，实际行号 $bad（样本共 ${blocks.length} 块）',
    );
    expect(
      blocks.length,
      8,
      reason: '应只认 8 个异常处置块（extension on 不算），实际 ${blocks.length}',
    );
  });
}

class _CatchBlock {
  _CatchBlock(this.path, this.line, this.body, this.above);
  final String path;
  final int line;
  final String body;
  final String above;

  bool compliant() =>
      RegExp(_logRe).hasMatch(body) ||
      RegExp(_throwRe).hasMatch(body) ||
      RegExp(_okRe).hasMatch(body) ||
      RegExp(_okRe).hasMatch(above);
}

/// 取一个文件里所有异常处置块：`catch (…) {…}` 与 `on X …{…}`（后者不含 catch 形态）。
List<_CatchBlock> _scanFile(String rel, String src) {
  final out = <_CatchBlock>[];
  // 先扫 catch，再扫独立 on 回落；命中位置重叠的跳过，避免一块计两次。
  final onRe = RegExp(r'\bon\s+[A-Za-z_][\w.]*\s*(?:\([^)]*\))?\s*\{');
  for (final re in [
    RegExp(r'\bcatch\s*(?:\((?:[^()]|\([^()]*\))*\))?\s*\{'),
    onRe,
  ]) {
    for (final m in re.allMatches(src)) {
      // on 回落式只认「紧跟在 } 之后」的异常子句：
      // `} on SocketException { … }`。否则 `extension X on BuildContext {`、
      // `mixin M on Foo {` 这类声明会被误判成异常处置块。
      if (re == onRe && _prevNonWs(src, m.start) != '}') continue;
      final open = src.indexOf('{', m.start + m.group(0)!.length - 1);
      if (open < 0) continue;
      final close = _matchBrace(src, open);
      if (close < 0) continue;
      out.add(
        _CatchBlock(
          rel,
          src.substring(0, m.start).split('\n').length,
          src.substring(open + 1, close),
          _aboveLines(src, m.start),
        ),
      );
    }
  }
  return out;
}

/// 命中点上方的「同前行 + 上一行」——`// catch-ok:` 批准注释只认这两行，
/// 不用固定字符回看窗口，否则相邻用例的注释会互相沾光。
String _aboveLines(String s, int i) {
  final lineStart = s.lastIndexOf('\n', i);
  if (lineStart < 0) return s.substring(0, i);
  final prevStart = s.lastIndexOf('\n', lineStart - 1);
  return s.substring(prevStart + 1, i);
}

/// [i] 之前第一个非空白字符（无则返回 null）。
String? _prevNonWs(String s, int i) {
  var j = i - 1;
  while (j >= 0 &&
      (s[j] == ' ' || s[j] == '\t' || s[j] == '\n' || s[j] == '\r')) {
    j--;
  }
  return j < 0 ? null : s[j];
}

/// 从 [open]（指向 `{`）找到配对 `}` 下标；跳过注释与字符串（含 `${}` 内插）。
int _matchBrace(String s, int open) {
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    final n = i + 1 < s.length ? s[i + 1] : '';
    if (c == '/' && n == '/') {
      i = s.indexOf('\n', i);
      if (i < 0) return -1;
      continue;
    }
    if (c == '/' && n == '*') {
      i = s.indexOf('*/', i);
      if (i < 0) return -1;
      i += 1;
      continue;
    }
    if (c == "'" || c == '"' || c == '`') {
      i = _skipString(s, i, c);
      continue;
    }
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

/// i 指向引号，返回串结束后的下标。
int _skipString(String s, int i, String q) {
  final triple = q != '`' && i + 2 < s.length && s[i + 1] == q && s[i + 2] == q;
  var j = i + (triple ? 3 : 1);
  while (j < s.length) {
    final c = s[j];
    if (c == r'\') {
      j += 2;
      continue;
    }
    if (c == r'$' && j + 1 < s.length && s[j + 1] == '{') {
      final close = _matchBrace(s, j + 1);
      j = close < 0 ? j + 1 : close;
      continue;
    }
    if (triple) {
      if (c == q && j + 2 < s.length && s[j + 1] == q && s[j + 2] == q) {
        return j + 3;
      }
      j++;
      continue;
    }
    if (c == '\n') return j; // 单行串未闭合（非法 Dart，容错截断）
    if (c == q) return j + 1;
    j++;
  }
  return s.length;
}
