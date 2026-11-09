import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/items/domain/item_extras.dart';

/// 物品实物属性批（I01/I05/I08/I10/I11/I12/I13/I14）纯函数守护。
/// 铁律：每条 test 同时断「正档 true」与「负档 false」，不写恒真的假绿。
void main() {
  group('I01 单图 / I14 多图', () {
    test('isValidPhotoPath 正档/负档', () {
      expect(isValidPhotoPath('/data/note_images/ab.jpg'), isTrue);
      expect(isValidPhotoPath('/data/note_images/ab.PNG'), isTrue);
      expect(isValidPhotoPath(null), isFalse);
      expect(isValidPhotoPath(''), isFalse);
      expect(isValidPhotoPath('/data/a.txt'), isFalse);
      expect(isValidPhotoPath('/data/noext'), isFalse);
      expect(isValidPhotoPath('/data/a.'), isFalse);
    });

    test('isValidPhotoGallery 正档/负档', () {
      expect(isValidPhotoGallery(['/x/a.jpg', '/x/b.png']), isTrue);
      expect(isValidPhotoGallery([]), isFalse);
      expect(isValidPhotoGallery(['/x/a.jpg', 'bad']), isFalse);
    });

    test('decodePhotos / encodePhotos 往返正档、脏值负档', () {
      final enc = encodePhotos(['/x/a.jpg', 'bad', '/x/b.webp']);
      expect(decodePhotos(enc), ['/x/a.jpg', '/x/b.webp']); // 负档：非法项被滤掉
      expect(decodePhotos('not-json'), isEmpty);
      expect(decodePhotos(null), isEmpty);
      expect(decodePhotos('{}'), isEmpty);
      expect(decodePhotos(enc).length, 2); // 正档
      expect(encodePhotos(['bad']), '[]');
    });
  });

  group('I05 位置两层树', () {
    test('isValidLocationPath 正档/负档', () {
      expect(isValidLocationPath('卧室/衣柜第二层'), isTrue);
      expect(isValidLocationPath('卧室'), isFalse);
      expect(isValidLocationPath('/衣柜'), isFalse);
      expect(isValidLocationPath('卧室/'), isFalse);
      expect(isValidLocationPath('a/b/c'), isFalse);
      expect(isValidLocationPath(' / '), isFalse);
      expect(isValidLocationPath(''), isFalse);
      expect(isValidLocationPath(null), isFalse);
    });

    test('encodeLocation / decodeLocation 正档/负档', () {
      expect(encodeLocation(' 卧室 ', ' 衣柜 '), '卧室/衣柜');
      final p = decodeLocation('卧室 / 衣柜');
      expect(p, isNotNull);
      expect(p!.l1, '卧室');
      expect(p.l2, '衣柜');
      expect(decodeLocation('卧室'), isNull);
      expect(decodeLocation(null), isNull);
    });

    test('buildLocationTree 正档聚合、脏值负档跳过', () {
      final tree = buildLocationTree([
        '卧室/衣柜',
        '卧室/抽屉',
        '书房/书架',
        '卧室/衣柜', // 重复二级去重
        'bad',
        null,
        '/x', // 一级为空＝非法
      ]);
      expect(tree.length, 2); // 正档：两级节点
      final bed = tree.firstWhere((n) => n.l1 == '卧室');
      expect(bed.children, ['抽屉', '衣柜']); // 去重 + 字典序
      final study = tree.firstWhere((n) => n.l1 == '书房');
      expect(study.children, ['书架']);
      expect(buildLocationTree(['bad', null]), isEmpty); // 负档
    });
  });

  group('I08 凭证附件', () {
    test('isValidAttachment 正档/负档', () {
      expect(
          isValidAttachment(
              const ItemAttachment(kind: '发票', path: '/x/a.pdf')),
          isTrue);
      expect(
          isValidAttachment(
              const ItemAttachment(kind: '说明书', path: '/x/m.pdf')),
          isTrue);
      expect(
          isValidAttachment(
              const ItemAttachment(kind: '未知类', path: '/x/a.pdf')),
          isFalse);
      expect(
          isValidAttachment(
              const ItemAttachment(kind: '发票', path: '   ')),
          isFalse);
    });

    test('decodeAttachments / encodeAttachments 正档往返、脏值负档', () {
      const list = [
        ItemAttachment(kind: '发票', path: '/x/a.pdf', name: 'a.pdf'),
        ItemAttachment(kind: '其他', path: '/x/b.jpg'),
      ];
      final back = decodeAttachments(encodeAttachments(list));
      expect(back.length, 2); // 正档
      expect(back.first.kind, '发票');
      expect(back.first.name, 'a.pdf');
      expect(decodeAttachments('{bad'), isEmpty); // 负档
      expect(decodeAttachments(null), isEmpty);
      expect(
          encodeAttachments([
            const ItemAttachment(kind: '未知', path: '/x/')
          ]),
          '[]'); // 非法项被滤成空数组
    });
  });

  group('I10 条码扫码', () {
    test('isValidBarcode 正档/负档', () {
      expect(isValidBarcode('6901234567892'), isTrue); // EAN-13
      expect(isValidBarcode('12345678'), isTrue); // EAN-8
      expect(isValidBarcode(' 6901234567892 '), isTrue); // 去空格
      expect(isValidBarcode('abc'), isFalse);
      expect(isValidBarcode('123'), isFalse);
      expect(isValidBarcode('6901234567892x'), isFalse);
      expect(isValidBarcode('123456789012345'), isFalse); // 15 位
      expect(isValidBarcode(''), isFalse);
      expect(isValidBarcode(null), isFalse);
    });

    test('barcodeMatches 快速搜索 正档/负档', () {
      expect(barcodeMatches('6901234567892', ' 6901234567892 '), isTrue);
      expect(barcodeMatches('6901234567892', '0000000000000'), isFalse);
      expect(barcodeMatches(null, '6901234567892'), isFalse);
      expect(barcodeMatches('6901234567892', ''), isFalse);
      expect(barcodeMatches('', ''), isFalse);
    });
  });

  group('I11 借出归还', () {
    test('isValidLoanDue 正档/负档', () {
      expect(isValidLoanDue('2026-12-31'), isTrue);
      expect(isValidLoanDue('2026/12/31'), isFalse);
      expect(isValidLoanDue('x'), isFalse);
      expect(isValidLoanDue(''), isFalse);
      expect(isValidLoanDue(null), isFalse);
    });

    test('isLoanOverdue 正档逾期、负档不逾期', () {
      final t = DateTime(2026, 9, 19);
      expect(
          isLoanOverdue(
              loanTo: '张三', loanDue: '2026-09-01', today: t),
          isTrue);
      expect(
          isLoanOverdue(
              loanTo: '', loanDue: '2026-09-01', today: t),
          isFalse); // 未借出
      expect(
          isLoanOverdue(
              loanTo: '张三', loanDue: '2026-10-01', today: t),
          isFalse); // 未到期
      expect(
          isLoanOverdue(loanTo: '张三', loanDue: null, today: t),
          isFalse);
      expect(
          isLoanOverdue(
              loanTo: '张三', loanDue: 'bad', today: t),
          isFalse);
    });
  });

  group('I13 自定义字段', () {
    test('isValidCustomFieldKey 正档/负档', () {
      expect(isValidCustomFieldKey('购买渠道'), isTrue);
      expect(isValidCustomFieldKey(null), isFalse);
      expect(isValidCustomFieldKey(''), isFalse);
      expect(isValidCustomFieldKey(' name '), isFalse); // 首尾空格
      expect(isValidCustomFieldKey('id'), isFalse); // 保留键
      expect(isValidCustomFieldKey('ID'), isFalse);
      expect(isValidCustomFieldKey('a' * 33), isFalse); // 超长
      expect(isValidCustomFieldKey('ab\u0001cd'), isFalse); // 控制字符
    });

    test('decodeCustomFields / encodeCustomFields 正档往返、脏值负档', () {
      const fields = {'渠道': '京东', '颜色': '银'};
      final back = decodeCustomFields(encodeCustomFields(fields));
      expect(back['渠道'], '京东'); // 正档
      expect(back.length, 2);
      expect(encodeCustomFields({'id': 'x'}) == '{}', isTrue); // 保留键被滤
      expect(decodeCustomFields('not-json'), isEmpty); // 负档
      expect(decodeCustomFields(null), isEmpty);
    });
  });

  group('I12 AI 拍照识别（产品 2026-11-09 裁定不做）', () {
    test('物品侧不再有该入口与在线服务门（防复活）', () {
      // 负档：三处实现位都不许再出现该入口；正档：本地实物属性仍在。
      final domain = File('lib/features/items/domain/item_extras.dart')
          .readAsStringSync();
      final sheet =
          File('lib/features/items/presentation/item_extras_sheet.dart')
              .readAsStringSync();
      final detail =
          File('lib/features/items/presentation/item_detail_page.dart')
              .readAsStringSync();
      expect(domain.contains('kAiPhotoRecognitionGate'), isFalse,
          reason: '负档：域件不许复活功能门');
      expect(domain.contains('class FeatureGate'), isFalse,
          reason: '负档：功能门类应随裁定删除');
      expect(sheet.contains('i-extras-ai-gray'), isFalse,
          reason: '负档：编辑弹层不许复活灰位卡');
      expect(detail.contains('AI 拍照识别'), isFalse,
          reason: '负档：详情页不许复活灰位文案');
      expect(domain.contains('class ItemExtras'), isTrue,
          reason: '正档：实物属性域件本身仍在');
    });
  });

  group('ItemExtras 列编解码与汇总（升级零数据风险）', () {
    test('toColumns / fromColumns 正档往返、缺列负档回落空值', () {
      final e = ItemExtras(
        photos: const ['/x/a.jpg'],
        locationPath: '卧室/衣柜',
        attachments: const [
          ItemAttachment(kind: '发票', path: '/x/b.pdf', name: 'b.pdf')
        ],
        barcode: '6901234567892',
        loanTo: '张三',
        loanAt: '2026-08-01',
        loanDue: '2026-09-01',
        customFields: const {'渠道': '京东'},
      );
      final back = ItemExtras.fromColumns(e.toColumns());
      expect(back.photos, ['/x/a.jpg']);
      expect(back.locationPath, '卧室/衣柜');
      expect(back.attachments.length, 1);
      expect(back.barcode, '6901234567892');
      expect(back.loanTo, '张三');
      expect(back.isLent, isTrue);
      expect(back.customFields['渠道'], '京东');

      final empty = ItemExtras.fromColumns(const {});
      expect(empty.photos, isEmpty); // 负档：老行缺列
      expect(empty.isLent, isFalse);
      final dirty = ItemExtras.fromColumns(const {
        kColPhotos: 'not-json',
        kColAttachments: '{',
        kColCustomFields: 'bad',
      });
      expect(dirty.photos, isEmpty);
      expect(dirty.attachments, isEmpty);
      expect(dirty.customFields, isEmpty);
    });

    test('空档案八列全 NULL（正档）/ 非空档案有值（负档）', () {
      final cols = const ItemExtras().toColumns();
      expect(cols.length, 8);
      expect(cols.values.every((v) => v == null), isTrue);
      final full = const ItemExtras(barcode: '6901234567892').toColumns();
      expect(full[kColBarcode], '6901234567892');
      expect(full.values.every((v) => v == null), isFalse);
    });

    test('extrasSummary 正档有值 / 负档空态', () {
      const e = ItemExtras();
      expect(extrasSummary(e), '未登记实物属性 · 点击补齐');
      const full = ItemExtras(
        photos: ['/x/a.jpg'],
        locationPath: '卧室/衣柜',
        barcode: '6901234567892',
        loanTo: '张三',
        loanDue: '2026-09-01',
        customFields: {'渠道': '京东'},
      );
      final s = extrasSummary(full);
      expect(s.contains('多图 1'), isTrue);
      expect(s.contains('位置 卧室/衣柜'), isTrue);
      expect(s.contains('条码 6901234567892'), isTrue);
      expect(s.contains('借出 张三'), isTrue);
      expect(s.contains('自定义 1'), isTrue);
      expect(s.contains('未登记'), isFalse);
    });
  });
}
