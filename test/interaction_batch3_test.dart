import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/shared/widgets/ui_kit.dart';

/// 交互整改批三 · T9（表单校验落字段旁 + 保存钮防重入）常驻用例。
///
/// 两档：① 原语本体（`FieldError` 有错才占位、无错不占位）；
/// ② 源码守护——六处高频表单的「必填/金额」短句不许再走提示条，
/// 且必须存在就地报错的接法（`errorText:` 或 `FieldError(`），
/// 防止「删掉 toast 就等于做完」的假交付。
/// 逐页的就地报错与防重入行为断言在各自页面用例文件里
/// （ledger_l2/l9/l10/l11、ledger_l8_cats_page、todo_page、todo_insights）。
void main() {
  group('1 · LH-K32 FieldError 原语', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Column(children: [child]))));
    }

    testWidgets('有错才出文字，样式＝10.5/w700 玫红', (tester) async {
      await pump(tester, const FieldError('请填写对方'));
      expect(find.text('请填写对方'), findsOneWidget);
      final style = tester
          .widget<Text>(find.text('请填写对方'))
          .style!;
      expect(style.fontSize, 10.5);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, const Color(0xFFF43F5E));
    });

    testWidgets('无错不占位（null 与空串都不渲染 Text）', (tester) async {
      await pump(tester, const FieldError(null));
      expect(find.byType(Text), findsNothing);
      await pump(tester, const FieldError(''));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('2 · 源码守护：高频表单不许再把校验弹成提示条', () {
    // 六处落点＝工单 T9 点名的高频表单（记账 L2/借贷/心愿/周期账单/分类弹层＋新建待办）。
    const zone = [
      'lib/features/ledger/presentation/ledger_add_page.dart',
      'lib/features/ledger/presentation/ledger_debt_page.dart',
      'lib/features/ledger/presentation/ledger_wish_page.dart',
      'lib/features/ledger/presentation/ledger_recur_page.dart',
      'lib/features/ledger/presentation/ledger_pick_sheets.dart',
      'lib/features/todo/presentation/widgets/todo_add_sheet.dart',
    ];
    // 提示条调用里出现「请填写/请输入/请选择/请先…」这类必填校验短句＝回潮
    // （单行式；跨行写法另由逐页行为用例拦）。失败原因类「请求失败」不在此列。
    final toastGuard = RegExp(
        r"(AppToast\.show|_toast)\([^)]*'请(填写|输入|选择|先)[^']*'");

    for (final path in zone) {
      test('$path 无校验类提示条', () {
        final src = File(path).readAsStringSync();
        expect(toastGuard.hasMatch(src), isFalse,
            reason: '校验反馈必须落字段旁（errorText / FieldError），不借道提示条');
      });

      test('$path 有就地报错接法', () {
        final src = File(path).readAsStringSync();
        expect(src.contains('errorText') || src.contains('FieldError('), isTrue,
            reason: '删掉 toast 不等于交付：字段旁必须真有错误呈现');
      });
    }

    test('保存路径防重入已接（六处各自盯住自己的 saving 标志）', () {
      final expected = {
        'lib/features/ledger/presentation/ledger_add_page.dart':
            'if (_saving) return;',
        'lib/features/ledger/presentation/ledger_debt_page.dart':
            'if (_saving) return;',
        'lib/features/ledger/presentation/ledger_wish_page.dart':
            'if (_saving) return;',
        'lib/features/ledger/presentation/ledger_recur_page.dart':
            'if (_saving) return;',
        // 分类弹层：ledger_pick_sheets 体积棘轮已满（登记 1581＝现值），
        // 本批只接就地报错，防重入随该文件拆 part 的批做。
        'lib/features/todo/presentation/widgets/todo_add_sheet.dart':
            'if (_saving) return;',
        'lib/features/todo/presentation/widgets/todo_list_view.dart':
            'if (_saving) return;',
      };
      for (final e in expected.entries) {
        expect(File(e.key).readAsStringSync().contains(e.value), isTrue,
            reason: '${e.key} 缺防重入守卫 ${e.value}');
      }
    });

    test('待办一键升紧急：按钮在写入期间必须禁用（不许连点重复改库）', () {
      final src =
          File('lib/features/todo/presentation/widgets/todo_list_view.dart')
              .readAsStringSync();
      expect(src.contains('onPressed: _saving ? null : _escalate'), isTrue,
          reason: '批量 await 的按钮要有可见的禁用帧，否则连点=重复写');
    });
  });
}
