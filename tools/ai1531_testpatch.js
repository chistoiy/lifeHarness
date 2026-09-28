// 一次性补丁：V1.53.1 服务商测试用例改用大视口 + 视口内点击/输入。
// 已执行过就不要再跑（会把已改好的行当未命中而报错）。
const fs = require('fs');
const p = 'test/ai_provider_v1531_test.dart';
let s = fs.readFileSync(p, 'utf8');
const before = s.length;

function rep(from, to, expectHits) {
  const n = s.split(from).length - 1;
  if (n !== expectHits) throw new Error('命中数不符: ' + JSON.stringify(from.slice(0, 60)) + ' got ' + n + ' want ' + expectHits);
  s = s.split(from).join(to);
}

rep('await useSurface(tester);',
    'await useSurface(tester, const Size(560, 2000));', 6);

// 「添加服务商」用例：逐步补齐缺项校验，点击/输入一律走 tapKey/typeKey。
rep(`    // 空名称 → 行内提示（弹层里页面 SnackBar 会被遮罩挡住，故走行内红字）。
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-prov-form-err')), findsOneWidget);
    expect(storedProviders(), isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('ai-prov-f-name')), '公司中转站');
    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-url')),
        'relay.example.com/v1/api');
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await tester.pump();
    expect(find.textContaining('http:// 或 https://'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-url')),
        'https://relay.example.com/v1/api');
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await tester.pump();
    expect(find.text('请填写模型名'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('ai-prov-f-model')), 'deepseek-chat');
    await tester.tap(find.byKey(const ValueKey('ai-prov-f-key')));
    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-key')),
        'sk-relay');
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await settle5(tester);`,
    `    // 空名称 → 行内提示（模态弹层里页面 SnackBar 被遮罩挡住，故走行内红字）。
    await tapKey(tester, 'ai-prov-save');
    expect(find.byKey(const ValueKey('ai-prov-form-err')), findsOneWidget);
    expect(storedProviders(), isEmpty);

    await typeKey(tester, 'ai-prov-f-name', '公司中转站');
    await typeKey(tester, 'ai-prov-f-url', 'relay.example.com/v1/api');
    await tapKey(tester, 'ai-prov-save');
    expect(find.textContaining('http:// 或 https://'), findsOneWidget);

    await typeKey(tester, 'ai-prov-f-url', 'https://relay.example.com/v1/api');
    await tapKey(tester, 'ai-prov-save');
    expect(find.text('请填写模型名'), findsOneWidget);

    await typeKey(tester, 'ai-prov-f-model', 'deepseek-chat');
    await typeKey(tester, 'ai-prov-f-key', 'sk-relay');
    await tapKey(tester, 'ai-prov-save');`, 1);

rep("    final relay = stored.firstWhere((e) => e['name'] == '公司中转站') as Map;",
    "    final relay = stored.firstWhere((e) => (e as Map)['name'] == '公司中转站') as Map;", 1);

// http 明文用例
rep(`    await openForm(tester, 'ai-prov-add');
    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-name')),
        '家里 Ollama');
    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-url')),
        'http://192.168.31.9:11434/v1');
    await tester.enterText(
        find.byKey(const ValueKey('ai-prov-f-model')), 'qwen2.5:7b');
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-prov-http-row')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await tester.pump();
    expect(find.textContaining('http 明文端点需先确认'), findsOneWidget);
    expect(storedProviders(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('ai-prov-http-ok')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await settle5(tester);`,
    `    await openForm(tester, 'ai-prov-add');
    await typeKey(tester, 'ai-prov-f-name', '家里 Ollama');
    await typeKey(tester, 'ai-prov-f-url', 'http://192.168.31.9:11434/v1');
    await typeKey(tester, 'ai-prov-f-model', 'qwen2.5:7b');
    expect(find.byKey(const ValueKey('ai-prov-http-row')), findsOneWidget);

    await tapKey(tester, 'ai-prov-save');
    expect(find.textContaining('http 明文端点需先确认'), findsOneWidget);
    expect(storedProviders(), isEmpty);

    await tapKey(tester, 'ai-prov-http-ok');
    await tapKey(tester, 'ai-prov-save');`, 1);

// 编辑预置条目用例
rep(`    await openForm(tester, 'ai-prov-edit-glm');
    expect(find.text('编辑服务商 · 智谱 GLM'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-url')),
        'https://open.bigmodel.cn/api/paas/v4/');
    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-model')),
        'glm-4.5-air');
    await tester.tap(find.byKey(const ValueKey('ai-prov-proto-anthropic')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await settle5(tester);`,
    `    await openForm(tester, 'ai-prov-edit-glm');
    expect(find.text('编辑服务商 · 智谱 GLM'), findsOneWidget);
    await typeKey(tester, 'ai-prov-f-url', 'https://open.bigmodel.cn/api/paas/v4/');
    await typeKey(tester, 'ai-prov-f-model', 'glm-4.5-air');
    await tapKey(tester, 'ai-prov-proto-anthropic');
    await tapKey(tester, 'ai-prov-save');`, 1);

// 删除用例
rep(`    await openForm(tester, 'ai-prov-edit-kimi');
    await tester.enterText(
        find.byKey(const ValueKey('ai-prov-f-key')), 'sk-kimi');
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await settle5(tester);
    await clearToasts(tester);
    expect(await vault.readOwn('kimi'), 'sk-kimi');

    await tester.tap(find.byKey(const ValueKey('ai-prov-del-kimi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-prov-del-confirm')), findsOneWidget,
        reason: '破坏性操作两段式');
    await tester.tap(find.byKey(const ValueKey('ai-prov-del-confirm')));
    await settle5(tester);`,
    `    await openForm(tester, 'ai-prov-edit-kimi');
    await typeKey(tester, 'ai-prov-f-key', 'sk-kimi');
    await tapKey(tester, 'ai-prov-save');
    await clearToasts(tester);
    expect(await vault.readOwn('kimi'), 'sk-kimi');

    await tapKey(tester, 'ai-prov-del-kimi');
    expect(find.byKey(const ValueKey('ai-prov-del-confirm')), findsOneWidget,
        reason: '破坏性操作两段式');
    await tapKey(tester, 'ai-prov-del-confirm');`, 1);

// 掩码用例
rep(`    await openForm(tester, 'ai-prov-edit-openai');
    var field = tester.widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')));
    expect(field.obscureText, isTrue);
    expect(find.text('该服务商还没有 Key · 填入后即刻存入系统加密区'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('ai-prov-f-key')),
        'sk-openai-abcdef');
    await tester.tap(find.byKey(const ValueKey('ai-prov-save')));
    await settle5(tester);
    await clearToasts(tester);

    await openForm(tester, 'ai-prov-edit-openai');
    await settle5(tester);
    field = tester.widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')));`,
    `    await openForm(tester, 'ai-prov-edit-openai');
    var field = tester.widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')));
    expect(field.obscureText, isTrue);
    expect(find.text('该服务商还没有 Key · 填入后即刻存入系统加密区'), findsOneWidget);

    await typeKey(tester, 'ai-prov-f-key', 'sk-openai-abcdef');
    await tapKey(tester, 'ai-prov-save');
    await clearToasts(tester);

    await openForm(tester, 'ai-prov-edit-openai');
    await settle5(tester);
    field = tester.widget<TextField>(find.byKey(const ValueKey('ai-prov-f-key')));`, 1);

rep(`    await tester.tap(find.byKey(const ValueKey('ai-prov-f-eye')));
    await tester.pump();
    expect(`, `    await tapKey(tester, 'ai-prov-f-eye');
    expect(`, 1);

const after = s.length;
if (after < before - 3000 || after > before + 3000) {
  throw new Error('体积异常: before=' + before + ' after=' + after);
}
fs.writeFileSync(p, s, 'utf8');
console.log('OK before=' + before + ' after=' + after);
