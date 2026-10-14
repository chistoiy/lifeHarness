import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 架构守护测试（《开发计划书》§2.1 模块解耦规范的可执行化）。
///
/// 规则：
/// R1 `features/<mod>/**` 不得 import 其他 feature（跨模块只经 shared/linkage 或事件总线）。
/// R2 `core/**` 不得 import `features/**`（组合根白名单除外）。
/// R3 feature 的 domain/data 层不得 import 任何 presentation（模型/仓库层纯净，可单测）。
/// R4 `for` 循环的增量子句必须有副作用（防空增量静默死循环，见 2026-09-20 事故）。
/// R5 `lib/core/sync/**` 除 `http_gate.dart` 外不得直连 http
///   （精化口径：违例 = `http.Client(` 实例化、`IOClient`、前驱标识符非
///   httpGate/gate 的 `.send(`；`package:http` import 放行——store 需构造
///   BaseRequest 交给 gate，出口唯一性由前两条保证，R10）；
///   附加断言：`x-bitiful-limit-rate`、`?stat` 在 lib/ 全库 0 命中（T14 前先行钉住）。
/// R6 `context.go('/x')` 的字面目标必须是 ShellRoute 内的 tab 路径
///   （栈路由只许 push——go 清栈会让该页成为栈底，返回键直接退出 app；
///   tab 集合从 app_router 的 ShellRoute 块现场解析，加/撤栏目自动跟随）。
/// R9 原书样式翻译器（`features/read/data/epub_css.dart`）源码内出现
///   「按 class 名的字面量映射」即判红——只许 CSS 属性名/值关键字白名单（§5.4 通用性红线的机器闸）。
/// 违反任何一条即测试失败——新增跨模块依赖必须先过架构评审并更新本白名单。
void main() {
  const libDir = 'lib';
  // 组合根：允许装配各 feature 页面/Provider 的文件。
  const compositionRoots = {
    'core/router/app_router.dart',
  };

  /// 去掉字符串字面量/注释，避免把关键词出现在文案或注释里误判（R4/R5 共用）。
  String strip(String src) {
    final out = StringBuffer();
    var i = 0;
    while (i < src.length) {
      final c = src[i];
      if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
        i += 2;
        while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }
      if (c == "'" || c == '"') {
        final triple = src.startsWith(c * 3, i);
        final q = triple ? c * 3 : c;
        i += q.length;
        while (i < src.length) {
          if (src[i] == r'\') {
            i += 2;
            continue;
          }
          if (src.startsWith(q, i)) {
            i += q.length;
            break;
          }
          i++;
        }
        out.write('S'); // 占位，保持结构
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  /// lib 下全部 .dart 文件（rel → 源码原文）。
  /// 清单 D-1：整个守护文件原本要递归扫 lib 三遍（collectImports 内部一遍、
  /// `sources` 一遍、R4 又走一遍目录），改成**记忆化一次遍历**共享——
  /// 覆盖与红灯语义完全不变，只是不再重复读同一批文件。
  Map<String, String> readAllSources() {
    final result = <String, String>{};
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      result[rel] = f.readAsStringSync();
    }
    return result;
  }

  Map<String, String>? sourcesCache;
  Map<String, String> collectSources() => sourcesCache ??= readAllSources();

  // 文件 → 其 import 解析出的 lib 相对路径列表。
  Map<String, List<String>> collectImports() {
    final result = <String, List<String>>{};
    for (final entry in collectSources().entries) {
      final rel = entry.key;
      final imports = <String>[];
      for (final line in entry.value.split('\n')) {
        final m = RegExp(r"""^import\s+['"]([^'"]+)['"]""").firstMatch(line);
        if (m == null) continue;
        final uri = m.group(1)!;
        if (uri.startsWith('package:lifeharness/')) {
          imports.add(uri.substring('package:lifeharness/'.length));
        } else if (uri.startsWith('dart:') || !uri.contains('.')) {
          continue;
        } else if (!uri.startsWith('package:') && !uri.startsWith('file:')) {
          // 相对 import：解析为 lib 相对路径。
          final resolved = p.normalize(p.join(p.dirname(rel), uri));
          if (resolved.startsWith('../')) continue; // 出了 lib/（外部包）
          imports.add(p.posix.joinAll(p.split(resolved)));
        }
      }
      result[rel] = imports;
    }
    return result;
  }

  final sources = collectSources();
  final imports = collectImports();

  /// 清单 D-1：`strip()`（去字符串/注释的逐字符扫描）原本 R4/R5/R7 各跑一遍全量源码，
  /// 这里按文件缓存一次结果供三处共用。
  final stripped = <String, String>{
    for (final entry in sources.entries) entry.key: strip(entry.value),
  };
  String strippedOf(String rel) => stripped[rel]!;

  // AI 增强页族（G7d⑤ 起主文件 + 同库 part 组）：R7 provider 直取豁免、
  // R8 端点键扫描跳过共用本口径；族外任何 features 文件仍然红。
  bool aiPageFamily(String rel) =>
      rel.startsWith('features/settings/presentation/ai_');

  test('R1 features 不得互相 import（跨模块必须走 shared/linkage）', () {
    // 2026-10-12 思维导图批1 刀2 变异实锤：旧写法 split('/').first 取到的是
    // 「features」字面量（文件键与 import 键同段），target != mod 永不成立＝守护空转。
    // 修为取第二段（模块名）；本刀红＝守护恢复咬合的证据。
    // 存量越线登记（R1 修好后首次暴露，均早于思维导图批1；登记=允许现状、
    // 只许减；真还债＝各自改走 shared/linkage，另批做）：
    const legacyEdges = <String, Set<String>>{
      'features/dashboard/presentation/widgets/today_schedule_card.dart': {
        'calendar',
      },
      'features/days/presentation/days_providers.dart': {'todo'},
      'features/journal/presentation/journal_page.dart': {'read'},
      // 存量越线登记（阅读模块批2 · 2026-10-14 跑出本红）：日记编辑页直取
      // `features/calendar`（旧 events 表退役后，日记摘要与计时条切「时间块」单源，
      // 见时间模块 B10 5700dff9 2026-10-13）。该批门禁未带本闸，故今日现形——
      // 本批一行未动 journal/calendar。真还债＝改走 shared/linkage 聚合服务，另批做。
      'features/journal/presentation/diary_edit_page.dart': {'calendar'},
    };
    final violations = <String>[];
    for (final entry in imports.entries) {
      final seg = entry.key.split('/');
      if (seg.first != 'features' || seg.length < 2) continue;
      final mod = seg[1];
      for (final imp in entry.value) {
        final iseg = imp.split('/');
        if (iseg.first != 'features' || iseg.length < 2) continue;
        final target = iseg[1];
        if (target != mod &&
            !(legacyEdges[entry.key]?.contains(target) ?? false)) {
          violations.add('${entry.key} → features/$target');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'feature 间直接依赖会互相牵连（改 A 崩 B、测试漏测）。'
            '请经 shared/linkage 聚合服务或事件总线传递。');
  });

  test('R2 core 不得依赖 features（组合根白名单除外）', () {
    final violations = <String>[];
    for (final entry in imports.entries) {
      if (!entry.key.startsWith('core/')) continue;
      if (compositionRoots.contains(entry.key)) continue;
      for (final imp in entry.value) {
        if (imp.startsWith('features/')) {
          violations.add('${entry.key} → $imp');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'core 是通用底座，反向依赖 feature 会导致其无法独立复用与测试。'
            '跨模块 UI 聚合请放 shared/linkage（如 timer_bar_overlay）。');
  });

  test('R3 feature domain/data 不得依赖 presentation', () {
    final violations = <String>[];
    for (final entry in imports.entries) {
      final seg = entry.key.split('/');
      if (seg.first != 'features' || !['domain', 'data'].contains(seg[1])) continue;
      for (final imp in entry.value) {
        if (imp.contains('/presentation/')) {
          violations.add('${entry.key} → $imp');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'domain/data 是模块对外稳定层，依赖 UI 层会阻碍仓库级单测与后续插件化。');
  });

  test('R4 for 循环增量子句必须有副作用（防空增量静默死循环）', () {
    /// 取出 `for (...)` 的括号内容（含跨行），返回 [内容, 结束下标]。
    List<Object>? header(String s, int open) {
      var depth = 0;
      for (var i = open; i < s.length; i++) {
        if (s[i] == '(') depth++;
        if (s[i] == ')') {
          depth--;
          if (depth == 0) return [s.substring(open + 1, i), i];
        }
      }
      return null;
    }

    final violations = <String>[];
    for (final entry in stripped.entries) {
      final rel = entry.key;
      final src = entry.value; // 清单 D-1：复用共享的 strip 结果，不再重扫目录
      for (final m in RegExp(r'\bfor\s*\(').allMatches(src)) {
        final open = src.indexOf('(', m.start);
        final h = header(src, open);
        if (h == null) continue;
        final head = h[0] as String;
        final parts = <String>[];
        var depth = 0;
        var start = 0;
        for (var i = 0; i < head.length; i++) {
          final c = head[i];
          if (c == '(' || c == '[' || c == '{') depth++;
          if (c == ')' || c == ']' || c == '}') depth--;
          if (c == ';' && depth == 0) {
            parts.add(head.substring(start, i));
            start = i + 1;
          }
        }
        parts.add(head.substring(start));
        if (parts.length != 3) continue; // for-in / for (;;)
        final inc = parts[2].trim();
        if (inc.isEmpty) continue;
        // 裸标识符或数字字面量 = 无副作用 = 条件永远不变 → 死循环。
        if (RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(inc) ||
            RegExp(r'^[0-9]+$').hasMatch(inc)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          violations.add('$rel:$line  `for (...; ...; $inc )`');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'for 的增量子句若是裸变量/字面量（如把 `h++` 写成 `h`）就没有副作用，'
            '条件恒真 → 同帧同步死循环：单核 100%、列表无界增长直至 OOM，'
            '且不让出事件循环所以 --timeout 也杀不掉。'
            '请写 `i++` / `i += n`，构建列表优先用 List.generate。');
  });

  test('R5 sync 层唯一出口：除 http_gate.dart 外禁直连 http（R10 绕行守护）', () {
    // 精化裁决（T12 评审前修）：封的是「自建出口」，不是 http 类型本身——
    // T13/T14 的 store 需要 import package:http 构造 BaseRequest 交给 gate，
    // 一刀切禁 import 会误杀合法通道。违例收敛为三类：
    // ① `http.Client(` 实例化（自建连接池）；② `IOClient`（自建底层 client）；
    // ③ 前驱标识符 ∉ {httpGate, gate} 的 `.send(`（绕开节流+退避直发）。
    final bannedInstantiate = RegExp(r'http\.Client\s*\(');
    final bannedIoClient = RegExp(r'\bIOClient\b');
    final bannedSend = RegExp(r'(\w*)\.send\s*\(');
    const sendAllowPrefixes = {'httpGate', 'gate'}; // gate = 注入形参名白名单
    final violations = <String>[];
    void report(String rel, String stripped, Match m, String what) {
      final line = '\n'.allMatches(stripped.substring(0, m.start)).length + 1;
      violations.add('$rel:$line $what');
    }

    for (final entry in sources.entries) {
      final rel = entry.key;
      if (!rel.startsWith('core/sync/')) continue;
      if (rel.endsWith('http_gate.dart')) continue; // 唯一出口自身豁免
      final stripped = strippedOf(entry.key); // 清单 D-1：复用共享 strip 结果
      for (final m in bannedInstantiate.allMatches(stripped)) {
        report(rel, stripped, m, m[0]!);
      }
      for (final m in bannedIoClient.allMatches(stripped)) {
        report(rel, stripped, m, 'IOClient');
      }
      for (final m in bannedSend.allMatches(stripped)) {
        if (!sendAllowPrefixes.contains(m[1])) {
          report(rel, stripped, m, m[0]!);
        }
      }
    }
    expect(violations, isEmpty,
        reason: '所有云端请求必须经 httpGate.send 发出（按服务节流 + 429/503 退避）。'
            '绕行会丢频控保护导致整目录同步被服务端限流打死。'
            '合法通道：import package:http 构造 BaseRequest，交给 httpGate.send。');
  });

  test('R5 附加：x-bitiful-limit-rate 与 ?stat 在 lib/ 全库 0 命中（T14 先行钉住）',
      () {
    // 缤纷云频控头/统计查询串在 S3 实现（T14）落地前不允许任何地方出现；
    // T14 若确需引入，须走架构评审更新本守护而不是直接删断言。
    final hits = <String>[];
    final reLimit = RegExp(r'x-bitiful-limit-rate', caseSensitive: false);
    // 清单 C-1：只认「?stat 到此为止」——后面跟字母/数字/下划线的（?status 等）不算。
    final reStat = RegExp(r'\?stat(?![A-Za-z0-9_])');
    for (final entry in sources.entries) {
      // 原文扫描（不 strip）：这两串只会出现在字符串字面量/URL 拼接里，
      // 去字符串后就查不到了；代价是注释提及也算命中——本期正是要求零提及。
      if (reLimit.hasMatch(entry.value)) hits.add('${entry.key} x-bitiful-limit-rate');
      // 清单 C-1：`?stat` 原本是 5 字符前缀匹配，将来任何 `?status=`、`?stable=`
      // 都会被误判成缤纷云统计口径而红灯。收紧成「?stat 后面不接标识符字符」，
      // 并把这条的扫描面收到 `core/sync/`（缤纷云专用口径只可能出现在同步层）。
      if (entry.key.startsWith('core/sync/') && reStat.hasMatch(entry.value)) {
        hits.add('${entry.key} ?stat');
      }
    }
    expect(hits, isEmpty, reason: '未过架构评审的缤纷云专用口径不得提前进入 lib/');
  });

  test('R6 context.go 的字面目标必须是 ShellRoute 内 tab（栈路由只许 push）', () {
    // 缺陷类：`go()` 清空整个导航栈。目标若是**栈路由**（/read/shelf、
    // /days/detail、/settings/ai…），壳层被清掉后该页成为栈底，系统返回键
    // 直接退出 app——违反拍板口径「返回最终落到底部模块页 → 二次返回退出」
    // （V1.42 真机反馈①，book_mgr_page 曾踩）。
    // tab 路径集合从 app_router 的 ShellRoute 块现场解析，不手抄：
    // 以后加/撤栏目、改路由表，守护自动跟随。
    final routerSrc = sources['core/router/app_router.dart'];
    expect(routerSrc, isNotNull, reason: '路由表文件必须存在，否则本守护空转');
    var shellPaths = _shellRoutePaths(routerSrc!).toSet();
    // 治理G6：壳路由已下沉 features/*/presentation/*_routes.dart（...xShellRoutes()）。
    // 守护跟随下沉：把各域 *_routes.dart 中 `ShellRoutes()` 函数体里的 path 并入。
    for (final e in sources.entries) {
      if (!e.key.endsWith('_routes.dart')) continue;
      final fn = RegExp(
              r'List<GoRoute>\s+(\w+)ShellRoutes\(\)\s*=>\s*\[([\s\S]*?)\];')
          .allMatches(e.value);
      for (final m in fn) {
        for (final p in RegExp(r"""path:\s*'([^']+)'""")
            .allMatches(m.group(2)!)) {
          shellPaths.add(p.group(1)!);
        }
      }
    }
    expect(shellPaths, containsAll({'/', '/todo', '/settings', '/journal'}),
        reason: 'ShellRoute 解析异常（拿到的是空集/错集）');

    final reGo = RegExp(r"""\.go\(\s*['"](/[^'"]*)['"]""");
    final violations = <String>[];
    for (final entry in sources.entries) {
      if (entry.key == 'core/router/app_router.dart') continue; // 壳层自身跳转
      for (final m in reGo.allMatches(entry.value)) {
        final lineStart = entry.value.lastIndexOf('\n', m.start) + 1;
        final lineText = entry.value.substring(
            lineStart, entry.value.indexOf('\n', m.start));
        final t = lineText.trimLeft();
        if (t.startsWith('//') || t.startsWith('///')) continue; // 注释里的反例
        final path = m.group(1)!.split('?').first;
        if (!shellPaths.contains(path)) {
          final line =
              '\n'.allMatches(entry.value.substring(0, m.start)).length + 1;
          violations.add('${entry.key}:$line go(\'$path\')');
        }
      }
    }
    expect(violations, isEmpty,
        reason: '栈路由请用 context.push/goNamed 保栈；go 清栈会让返回键直接退出 app。'
            '确需「保存后回某页」请回 tab 路径或用 pushReplacement。');
  });

  test('R7 AI 能力调用唯一入口：features 只许 aiRunWithReview（禁直取 AiService/AiClient）', () {
    // 口径见《需求清单》§六 设计原则 8（V1.53 定案）：业务模块只传
    // `taskId + vars`，端点/模型/协议/Key/三重门控/发送前审阅/留痕
    // （运行日志 + token 台账 + AI 使用记录）全部收在 core/ai 一处。
    // 绕行不只是风格问题：它**静默丢掉审阅弹层与留痕**——用户看不到发出去了
    // 什么、查不到失败原因，V1.53 的 ai_calls 也会缺这一条。
    // AI 增强页自身（配置端点 / 连通性验证 / 提示词管理）允许取 provider。
    // G7d⑤ 起该页拆为同库 part 族，豁免按 main() 顶部 aiPageFamily 族口径。
    // 棘轮豁免：定案时已存在的绕行点，整改后**必须删掉对应登记**（下方有反向断言）。
    const pendingFix = <String>{}; // 阅读侧已于 2026-09-28 改走 aiRunWithReview
    final bannedProvider = RegExp(r'\baiServiceProvider\b|\bAiService\s*\(|\bAiClient\s*\(');
    final bannedRequest = RegExp(r'\.request\s*\(');
    final violations = <String>[], tolerated = <String>[];
    int lineOf(String src, int at) =>
        '\n'.allMatches(src.substring(0, at)).length + 1;

    for (final entry in sources.entries) {
      final rel = entry.key;
      if (!rel.startsWith('features/')) continue;
      final stripped = strippedOf(entry.key); // 清单 D-1：复用共享 strip 结果
      final hits = <String>[];
      for (final m in bannedProvider.allMatches(stripped)) {
        hits.add('${lineOf(stripped, m.start)}:${m[0]}');
      }
      for (final m in bannedRequest.allMatches(stripped)) {
        hits.add('${lineOf(stripped, m.start)}:${m[0]} 能力调用绕行');
      }
      if (hits.isEmpty) continue;
      final line = '$rel ← ${hits.join(' / ')}';
      final okProviderOnly = aiPageFamily(rel) &&
          !bannedRequest.hasMatch(stripped);
      if (okProviderOnly || pendingFix.contains(rel)) {
        tolerated.add(line);
      } else {
        violations.add(line);
      }
    }
    expect(violations, isEmpty,
        reason: 'AI 能力调用必须走 core/ai/ai_review.dart 的 aiRunWithReview(context, ref, '
            '{taskId, vars})：它承载门控、发送前审阅、取消竞速、日志与用量留痕。'
            '新增能力点=在 assets/ai_prompts/prompts.json 加一条 + 模块侧调 aiRunWithReview，'
            '不要 import aiServiceProvider / AiService / AiClient。');
    // 反向守护：豁免清单不许虚设——登记的例外若已不再命中，说明整改完成，须删登记。
    final toleratedFiles = tolerated.map((e) => e.split(' ← ').first).toSet();
    expect(pendingFix.difference(toleratedFiles), isEmpty,
        reason: 'pendingFix 里的绕行点已消失，请把对应条目从 R7 豁免清单删掉（否则守护悄悄失效）。');
    // 打印当前被容忍的例外，收口时看得见（不红，但不许遗忘）。
    // ignore: avoid_print
    if (tolerated.isNotEmpty) print('R7 暂豁免（待整改）：\n  ${tolerated.join('\n  ')}');
  });

  test('R8 AI 能力点登记闭环：提示词资产 ↔ 能力矩阵一一对应', () {
    // 口径见《需求清单》§六 原则 9（V1.53.1 定案）：新增一个 AI 能力＝
    // prompts.json 加一条（含 module 归属）+ AI 增强页 kAiCapRows 登记一行授权入口。
    // 漏登记＝用户在能力矩阵里根本看不到它＝gate 永远回「该能力未授权」＝功能静默不可用；
    // 反过来矩阵留死行也会让人以为开了 AI 却没有任何调用点。
    final tasks =
        (((jsonDecode(File('assets/ai_prompts/prompts.json').readAsStringSync())
                    as Map)['tasks'] ??
                const [])
            as List)
            .cast<Map>();
    expect(tasks.length, greaterThan(10),
        reason: '提示词包解析为空＝守护空转（资产路径变了要同步这里）');

    // ① 八字段齐全：id/module/name/system/user/expect 非空，placeholders/sample 存在。
    const mustNonEmpty = ['id', 'module', 'name', 'system', 'user', 'expect'];
    const mustPresent = [...mustNonEmpty, 'placeholders', 'sample'];
    final malformed = <String>[];
    for (final t in tasks) {
      final id = '${t['id'] ?? '(无 id)'}';
      for (final k in mustPresent) {
        if (!t.containsKey(k)) {
          malformed.add('$id 缺字段 $k');
          break;
        }
      }
      for (final k in mustNonEmpty) {
        final v = t[k];
        if (v is! String || v.trim().isEmpty) malformed.add('$id 的 $k 为空');
      }
    }
    expect(malformed, isEmpty,
        reason: '能力点必须写全 id/module/name/system/user/expect（placeholders/sample 可为空数组/空串），'
            'module 为空会让能力矩阵按模块分组时无处安放。');

    // ② 能力矩阵登记面（从 AI 增强页源码现场解析）。
    final page = sources['features/settings/presentation/ai_page.dart'] ?? '';
    final capIds = RegExp(r"""tasks:\s*\[([^\]]*)\]""")
        .allMatches(page)
        .expand((m) => RegExp("'([^']+)'").allMatches(m.group(1) ?? ''))
        .map((m) => m.group(1)!)
        .toSet();
    expect(capIds, isNotEmpty, reason: '能力矩阵解析为空＝守护空转');

    // 连通性验证小工具不受能力矩阵门控（它先于能力配置存在，是配 Key 的手段）。
    const capExempt = {'tool.verify'};

    final unregistered =
        tasks.map((t) => '${t['id']}').where((id) => !capExempt.contains(id) && !capIds.contains(id)).toSet();
    expect(unregistered, isEmpty,
        reason: '这些能力点在提示词包里但没在能力矩阵登记，用户无从授权（功能必然不可用）：'
            '${unregistered.join(', ')}。请在 lib/features/settings/presentation/ai_page.dart 的 '
            'kAiCapRows 加一行（label 用「模块：能力」格式，禁 emoji）。');

    final deadRows = capIds.where((id) => !tasks.any((t) => '${t['id']}' == id)).toSet();
    expect(deadRows, isEmpty,
        reason: '能力矩阵里有 $deadRows 的授权行，但提示词包没有这个能力点＝死行：'
            '要么补进 assets/ai_prompts/prompts.json，要么删掉这一行。');

    // ③ 端点/模型/协议/Key 的 prefs 键只许出现在 core/ai 与 AI 增强页（业务模块零感知）。
    final endpointKeys = RegExp(
        r"""['"](ai\.base_url|ai\.model|ai\.protocol|ai\.providers|ai\.activeProvider|ai_api_key|ai_key:)""");
    final leaks = <String>[];
    for (final e in sources.entries) {
      if (!e.key.startsWith('features/')) continue;
      if (aiPageFamily(e.key)) continue; // G7d⑤：AI 增强页族（主文件 + part）
      if (endpointKeys.hasMatch(e.value)) leaks.add(e.key);
    }
    expect(leaks, isEmpty,
        reason: '业务模块直接读写端点/Key 的 prefs 键＝绕开服务商层：'
            '${leaks.join(', ')}。端点三要素与 Key 只在 core/ai/* 与 AI 增强页处理。');
  });

  /// R9 原书样式翻译器＝通用性红线（预研 `docs/预研/原书样式保真CSS画像-20261002.md` §5.4
  /// 产品拍板 ＋ 批三工单 §3B「第一刀清单」：CSS 抽取器与这条源码守护**同批落**）。
  ///
  /// 闸的口径：`lib/features/read/data/epub_css.dart` 里凡是**类名形态**的字符串字面量
  /// （ASCII、字母起头、只含字母/数字/下划线/连字符）**必须**是 CSS 属性名或 CSS 值关键字
  /// （见 [kEpubCssAllowedLiterals]）。出现 `'note'`／`'reign-title'`／`'book-title'`
  /// 这种「按 class 名特判」即判红。
  ///
  /// 为什么钉这么死：总原则＝**完全按原书展示**，且「将来再来别的精编本书不许定制代码」——
  /// `.note`→绿 一旦写进代码，换一本 class 名不同的精编本书就全线失效，等于把通鉴做成了特例。
  /// 画像 §5.1 那张 class→语义 表是**证据**（证明信息在包里、以 class 级联承载），不是实现依据。
  ///
  /// 范围说明：只扫翻译器本体。命名色表 `css_named_colors.dart` 是 CSS 标准值的事实查阅件
  /// （不是 class→样式 映射）；`epub_doc.dart` 里的 `note|footnote|annotation` 判定是
  /// **需求 R3-2① 已定的止血口径**（注释体一律小字正文色），早于本批、不属特判。
  test('R9 原书样式翻译器禁 class 名映射（只许属性名白名单）', () {
    const rel = 'features/read/data/epub_css.dart';
    final src = sources[rel];
    expect(src, isNotNull,
        reason: '翻译器文件被改名/挪走会让 R9 静默失效——请同步这条守护的扫描面。');
    // 逐行剥 `//` 注释：class 名只会出现在注释（画像引用）里，不剥就把文档当代码判红。
    // 本文件不放含 `//` 的字面量（无 URL），所以按行截断安全。
    final code = src!.split('\n').map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    }).join('\n');
    final shapes = RegExp(r"'([A-Za-z][A-Za-z0-9_-]*)'")
        .allMatches(code)
        .map((m) => m.group(1)!)
        .toSet();
    expect(shapes.length, greaterThan(80),
        reason: 'R9 空转自检：类名形态字面量只扫到 ${shapes.length} 个，扫描面大概变了');
    final offenders = shapes.difference(kEpubCssAllowedLiterals).toList()..sort();
    expect(offenders, isEmpty,
        reason: '这些字面量既不是 CSS 属性名也不是 CSS 值关键字，出现在翻译器里就是'
            '「按 class 名特判」：${offenders.join(', ')}。'
            '总原则＝完全按原书展示、别的精编本书不许定制代码（预研 §5.4）；'
            '要加词请确认它是 CSS 属性名/值关键字，并在本测试的白名单里注明出处。');
  });

  test('守护自身有效性：确认真实扫到了文件', () {
    expect(imports.length, greaterThan(20));
    expect(imports.keys.where((k) => k.startsWith('features/')).length,
        greaterThan(10));
    expect(sources.containsKey('core/sync/http_gate.dart'), isTrue,
        reason: 'R5 的豁免文件必须真实存在，否则守护退化为空转');
  });
}

/// R9 白名单：翻译器里允许的**类名形态字面量**＝CSS 属性名 ∪ CSS 值关键字 ∪ 边的形态名。
/// 出处逐条可查（CSS 规范属性名/关键字），不是「某本书的 class 表」——新增词必须先确认它是
/// 属性或值，并把出处写进本注释；否则就是按书特判，R9 会判红。
const Set<String> kEpubCssAllowedLiterals = {
  // —— CSS 属性名（含 logical／webkit 变体在源码里带前缀，形如 -webkit-margin-start 不是类名形态，不入本表）
  'background',
  'background-color',
  'background-image',
  'background-position',
  'background-repeat',
  'background-size',
  'border',
  'border-block-end',
  'border-block-start',
  'border-bottom',
  'border-bottom-color',
  'border-bottom-style',
  'border-bottom-width',
  'border-color',
  'border-inline-end',
  'border-inline-start',
  'border-left',
  'border-left-color',
  'border-left-style',
  'border-left-width',
  'border-right',
  'border-right-color',
  'border-right-style',
  'border-right-width',
  'border-style',
  'border-top',
  'border-top-color',
  'border-top-style',
  'border-top-width',
  'border-width',
  'clear',
  'color',
  'column-count',
  'column-width',
  'columns',
  'direction',
  'display',
  'fill',
  'float',
  'font-size',
  'font-style',
  'font-weight',
  'letter-spacing',
  'line-height',
  'margin',
  'margin-block-end',
  'margin-block-start',
  'margin-bottom',
  'margin-inline-end',
  'margin-inline-start',
  'margin-left',
  'margin-right',
  'margin-top',
  'padding',
  'padding-bottom',
  'padding-inline-end',
  'padding-inline-start',
  'padding-left',
  'padding-right',
  'padding-top',
  'stroke',
  'text-align',
  'text-decoration',
  'text-decoration-color',
  'text-decoration-line',
  'text-decoration-style',
  'text-indent',
  'word-spacing',
  'writing-mode',
  // —— CSS 值关键字与单位
  'bold',
  'bolder',
  'currentcolor',
  'dashed',
  'dotted',
  'double',
  'em',
  'groove',
  'hidden',
  'hsl',
  'inherit',
  'initial',
  'inset',
  'italic',
  'justify',
  'large',
  'larger',
  'lighter',
  'line-through',
  'match-parent',
  'medium',
  'none',
  'normal',
  'oblique',
  'outset',
  'overline',
  'pc',
  'pt',
  'px',
  'rem',
  'rgb',
  'ridge',
  'rtl',
  'small',
  'smaller',
  'solid',
  'transparent',
  'underline',
  'unset',
  'wavy',
  'x-large',
  'x-small',
  'xx-large',
  'xx-small',
  // —— 边/形态名（四边简写展开、装饰线分解用的内部名，非 class 名）
  'all',
  'top',
  'right',
  'bottom',
  'left',
  'start',
  'end',
  'center',
  'through',
  'vertical',
  'table',
  'important',
};

/// 取 `ShellRoute(...)` 调用括号内出现的全部 `path: '...'`（= 底部导航可达的
/// tab 路径集合）。括号配平扫描，避免正则误吞后续顶层路由。
Set<String> _shellRoutePaths(String src) {
  final at = src.indexOf('ShellRoute(');
  if (at < 0) return const {};
  var depth = 0, end = -1;
  for (var i = at + 'ShellRoute'.length; i < src.length; i++) {
    if (src[i] == '(') {
      depth++;
    } else if (src[i] == ')') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) return const {};
  return RegExp(r"""path:\s*'([^']+)'""")
      .allMatches(src.substring(at, end))
      .map((m) => m.group(1)!)
      .toSet();
}
