import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/nfc/data/nfc_tag_io.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:lifeharness/features/nfc/domain/nfc_write_state.dart';
import 'package:nfc_manager/ndef_record.dart' show TypeNameFormat;

/// NFC 写卡状态机常驻用例（批2a · 冻结档 §4.3/§4.5/§4.6 ＋ 工单 §3）。
///
/// 全部是**纯逻辑**（零 Flutter 依赖、零硬件）：写卡层的五档失败分派、占用二态、
/// 30s 超时分支、文案表逐字，都在这里钉死——真机只验「能不能贴」，不验这些判定。
void main() {
  group('文案表（逐字照原型 NFC_STATE_TEXT）', () {
    test('七态文案逐字', () {
      expect(nfcWriteCopyOf(NfcWriteState.waiting).main, '把卡片贴到手机背面');
      expect(nfcWriteCopyOf(NfcWriteState.waiting).hint, '保持贴住不要移动');
      expect(nfcWriteCopyOf(NfcWriteState.reading).main, '正在读这张卡…');
      expect(nfcWriteCopyOf(NfcWriteState.writing).main, '正在写入…');
      expect(nfcWriteCopyOf(NfcWriteState.done).main, '已写入');
      expect(nfcWriteCopyOf(NfcWriteState.done).hint, '可以移开了');
      expect(nfcWriteCopyOf(NfcWriteState.occupied).hint, '覆盖后原内容会消失');
      expect(nfcWriteCopyOf(NfcWriteState.occupiedOwn).hint,
          '这张卡属于另一张卡片记录，只能取消');
      expect(nfcWriteCopyOf(NfcWriteState.errReadonly).main, '这张卡是只读的');
      expect(nfcWriteCopyOf(NfcWriteState.errNonNdef).hint,
          '请用 NDEF 可写标签（NTAG213/215/216）');
      expect(nfcWriteCopyOf(NfcWriteState.errCapacity).main, '卡片容量不足');
      expect(nfcWriteCopyOf(NfcWriteState.errBroken).main, '写入中断');
      expect(nfcWriteCopyOf(NfcWriteState.errNfcOff).hint, '去系统设置里打开后再试');
    });

    test('idle 不在文案表内（回空文案，层内不该停在 idle）', () {
      expect(nfcWriteCopyOf(NfcWriteState.idle).main, '');
      expect(nfcWriteCopyOf(NfcWriteState.idle).hint, '');
    });
  });

  group('读到标签后的分派（§4.3 reading 分支）', () {
    test('非 NDEF ⇒ 认不出（先于只读判定——非 NDEF 谈不上可写性）', () {
      expect(
        nfcWriteStateAfterRead(isNdef: false, isWritable: false, hasContent: false),
        NfcWriteState.errNonNdef,
      );
      expect(
        nfcWriteStateAfterRead(isNdef: false, isWritable: true, hasContent: true),
        NfcWriteState.errNonNdef,
      );
    });

    test('只读 ⇒ 换卡档（即使卡是空的）', () {
      expect(
        nfcWriteStateAfterRead(isNdef: true, isWritable: false, hasContent: false),
        NfcWriteState.errReadonly,
      );
    });

    test('空白可写 ⇒ 直接写', () {
      expect(
        nfcWriteStateAfterRead(isNdef: true, isWritable: true, hasContent: false),
        NfcWriteState.writing,
      );
    });

    test('已有内容 ⇒ 占用确认；本机另一张卡 ⇒ 仅可取消', () {
      expect(
        nfcWriteStateAfterRead(isNdef: true, isWritable: true, hasContent: true),
        NfcWriteState.occupied,
      );
      expect(
        nfcWriteStateAfterRead(
          isNdef: true,
          isWritable: true,
          hasContent: true,
          isOwnOtherCard: true,
        ),
        NfcWriteState.occupiedOwn,
      );
    });

    test('已有内容但就是本卡 ⇒ 不必确认，直接重写', () {
      expect(
        nfcWriteStateAfterRead(
          isNdef: true,
          isWritable: true,
          hasContent: true,
          isSelfCard: true,
        ),
        NfcWriteState.writing,
      );
    });

    test('占用二态与覆盖钮：只有普通占用给「覆盖写入」', () {
      expect(nfcWriteIsOccupy(NfcWriteState.occupied), isTrue);
      expect(nfcWriteCanOverwrite(NfcWriteState.occupied), isTrue);
      expect(nfcWriteIsOccupy(NfcWriteState.occupiedOwn), isTrue);
      expect(nfcWriteCanOverwrite(NfcWriteState.occupiedOwn), isFalse);
    });
  });

  group('五档失败分派（F2-2：以系统报错类别为准）', () {
    test('原生异常类名 → 对应档位', () {
      expect(nfcWriteFailureOf('TagLostException'), NfcWriteState.errBroken);
      expect(nfcWriteFailureOf('IllegalStateException'), NfcWriteState.errBroken);
      expect(nfcWriteFailureOf('IOException'), NfcWriteState.errCapacity);
      expect(nfcWriteFailureOf('FormatException'), NfcWriteState.errNonNdef);
      expect(nfcWriteFailureOf('tag_not_found'), NfcWriteState.errBroken);
    });

    test('本模块自造哨兵：系统 NFC 未开 ⇒ 去设置档', () {
      expect(nfcWriteFailureOf('nfc_disabled'), NfcWriteState.errNfcOff);
    });

    test('未知/空码 ⇒ 兜底「写入中断」（可重试），不给「认不出卡」这种误导档', () {
      expect(nfcWriteFailureOf(null), NfcWriteState.errBroken);
      expect(nfcWriteFailureOf(''), NfcWriteState.errBroken);
      expect(nfcWriteFailureOf('SomeRomSpecificThing'), NfcWriteState.errBroken);
    });

    test('错误态才出重试钮；文案：只读＝换卡／NFC 关＝去设置／其余＝重试', () {
      expect(nfcWriteIsError(NfcWriteState.errReadonly), isTrue);
      expect(nfcWriteIsError(NfcWriteState.errNfcOff), isTrue);
      expect(nfcWriteIsError(NfcWriteState.done), isFalse);
      expect(nfcWriteRetryLabel(NfcWriteState.errReadonly), '换卡');
      expect(nfcWriteRetryLabel(NfcWriteState.errNfcOff), '去设置');
      expect(nfcWriteRetryLabel(NfcWriteState.errCapacity), '重试');
      expect(nfcWriteRetryLabel(NfcWriteState.errBroken), '重试');
    });
  });

  group('容量预判与超时（B5/B7/B34）', () {
    test('放不下 ⇒ 容量档；够 ⇒ null（不预判，交给写入）', () {
      expect(
        nfcWriteCapacityPrecheck(messageBytes: 40, maxSize: 30),
        NfcWriteState.errCapacity,
      );
      expect(nfcWriteCapacityPrecheck(messageBytes: 40, maxSize: 144), isNull);
    });

    test('标签报不出容量（maxSize<=0）⇒ 不预判（不冤枉好卡）', () {
      expect(nfcWriteCapacityPrecheck(messageBytes: 40, maxSize: 0), isNull);
      expect(nfcWriteCapacityPrecheck(messageBytes: 40, maxSize: -1), isNull);
    });

    test('30s 超时只对 waiting 生效（已读到卡后的读/写过程不掐）', () {
      expect(nfcWriteShouldTimeout(NfcWriteState.waiting), isTrue);
      expect(nfcWriteShouldTimeout(NfcWriteState.reading), isFalse);
      expect(nfcWriteShouldTimeout(NfcWriteState.writing), isFalse);
      expect(nfcWriteShouldTimeout(NfcWriteState.occupied), isFalse);
      expect(nfcWriteShouldTimeout(NfcWriteState.errBroken), isFalse);
    });

    test('超时窗口与对勾停留常量', () {
      expect(kNfcWriteTimeoutMs, 30000);
      expect(kNfcWriteDoneHold, const Duration(milliseconds: 1200));
    });

    test('呼吸圆环只在等待/读/写三态转（§4.5）', () {
      expect(nfcWriteIsBusy(NfcWriteState.waiting), isTrue);
      expect(nfcWriteIsBusy(NfcWriteState.reading), isTrue);
      expect(nfcWriteIsBusy(NfcWriteState.writing), isTrue);
      expect(nfcWriteIsBusy(NfcWriteState.done), isFalse);
      expect(nfcWriteIsBusy(NfcWriteState.occupied), isFalse);
    });
  });

  group('标签 URI 口径（C1）与读回解析', () {
    test('构造与反解往返一致', () {
      const id = 'aB3xY9zQ1mN0';
      final uri = nfcTagUriOf(id);
      expect(uri, 'lh://nfc/$id');
      expect(nfcCardIdOfTagUri(uri), id);
    });

    test('非法/非本模块 URI 一律 null（不猜 · B35）', () {
      expect(nfcCardIdOfTagUri(null), isNull);
      expect(nfcCardIdOfTagUri(''), isNull);
      expect(nfcCardIdOfTagUri('https://example.com/nfc/aB3xY9zQ1mN0'), isNull);
      expect(nfcCardIdOfTagUri('lh://ledger/add'), isNull);
      expect(nfcCardIdOfTagUri('lh://nfc/短了'), isNull); // 非 12 位 base62
      expect(nfcCardIdOfTagUri('lh://nfc/aB3xY9zQ1mN0/extra'), isNull); // 多余层级
      expect(nfcCardIdOfTagUri('lh://nfc/aB3xY9zQ1mN-'), isNull); // 非 base62 字符
    });

    test('单条 URI 记录的字节数（写前容量预判用）', () {
      // 3 字节头 ＋ 'lh://nfc/' 9 ＋ 12 位 id ＝ 24
      expect(nfcTagUriBytes(nfcTagUriOf('aB3xY9zQ1mN0')), 24);
    });

    test('读回：TNF absoluteUri（3）直接解 payload', () {
      final payload = utf8.encode('lh://nfc/aB3xY9zQ1mN0');
      expect(
        nfcUriOfNdefRecord(tnf: 3, type: const [], payload: payload),
        'lh://nfc/aB3xY9zQ1mN0',
      );
    });

    test('读回：TNF wellKnown（1）+ 类型 U ⇒ 按前缀码解', () {
      // 0x04 = 'https://'
      final payload = <int>[0x04, ...utf8.encode('example.com/x')];
      expect(
        nfcUriOfNdefRecord(tnf: 1, type: const [0x55], payload: payload),
        'https://example.com/x',
      );
      // 0x00 = 无前缀（我方 lh:// 走这一档）
      final own = <int>[0x00, ...utf8.encode('lh://nfc/aB3xY9zQ1mN0')];
      expect(
        nfcUriOfNdefRecord(tnf: 1, type: const [0x55], payload: own),
        'lh://nfc/aB3xY9zQ1mN0',
      );
    });

    test('读回：非 URI 记录（文本/未知 TNF）⇒ null，不猜', () {
      expect(
        nfcUriOfNdefRecord(tnf: 1, type: const [0x54], payload: utf8.encode('hi')),
        null,
      );
      expect(nfcUriOfNdefRecord(tnf: 0, type: const [], payload: const []), null);
      expect(nfcUriOfNdefRecord(tnf: 5, type: const [], payload: const [1, 2]), null);
    });

    test('读回：payload 不是合法 UTF-8 ⇒ null（脏标签不炸写卡层）', () {
      expect(
        nfcUriOfNdefRecord(tnf: 3, type: const [], payload: const [0xFF, 0xFE]),
        null,
      );
    });

    test('探针 hasContent 判据：空白串不算有内容', () {
      const empty = NfcTagProbe(isNdef: true, isWritable: true, existingUri: '  ');
      const filled = NfcTagProbe(
        isNdef: true,
        isWritable: true,
        existingUri: 'lh://nfc/aB3xY9zQ1mN0',
      );
      expect(empty.hasContent, isFalse);
      expect(filled.hasContent, isTrue);
    });
  });

  group('插件对象 → 域层判定值（tnf 映射 · 防「改插件版本把数值挪了」）', () {
    test('TypeNameFormat 数值映射与 NDEF 规范一致', () {
      expect(tnfCodeOf(TypeNameFormat.empty), 0);
      expect(tnfCodeOf(TypeNameFormat.wellKnown), 1);
      expect(tnfCodeOf(TypeNameFormat.media), 2);
      expect(tnfCodeOf(TypeNameFormat.absoluteUri), 3);
      expect(tnfCodeOf(TypeNameFormat.external), 4);
      expect(tnfCodeOf(TypeNameFormat.unknown), 5);
      expect(tnfCodeOf(TypeNameFormat.unchanged), 6);
    });

    test('异常 → 类别码：PlatformException 取 code（原生类名），其余取运行时类名', () {
      expect(codeOf(PlatformException(code: 'IOException', message: 'x')),
          'IOException');
      expect(codeOf(StateError('x')), 'StateError');
    });
  });
}
