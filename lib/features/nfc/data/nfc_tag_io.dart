/// NFC 标签 IO（批2a · 冻结档 §6.2：`nfc_manager` **只此一套插件**）。
///
/// **本文件是全仓唯一 import `package:nfc_manager/**` 的地方**——插件细节不外泄：
/// 上层（写卡层/触发链）只认 [NfcTagProbe] 与 `PlatformException.code` 字符串，
/// 于是「五档失败分派」能在零依赖的域层被纯测（`nfc_write_state_test`）。
///
/// 功耗口径（§6.3）：**无定时器常驻、无后台巡检、无前台服务**；读卡会话只在写卡层
/// 打开期间存在，离开层（或重试前）必 [NfcManagerTagIo.stop]。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../domain/nfc_write_state.dart';

/// 一张标签的探针结果（域层可判定的最小集合）。
class NfcTagProbe {
  const NfcTagProbe({
    required this.isNdef,
    required this.isWritable,
    this.existingUri,
    this.maxSize = 0,
  });

  /// 能否按 NDEF 处理（false＝B4「认不出这张卡」）。
  final bool isNdef;

  /// 可写（false＝B3「只读卡」）。
  final bool isWritable;

  /// 标签里已有的第一条 URI 记录（`null`＝空卡或没有 URI 记录）。
  final String? existingUri;

  /// 标签报出的可写容量（B5：**N 取系统报数，不写死**）；报不出时为 0。
  final int maxSize;

  bool get hasContent => (existingUri ?? '').trim().isNotEmpty;
}

/// 单条 URI 记录的字节数（写前容量预判用；与 `NdefRecord.byteLength` 同口径：
/// 头部 3 字节 ＋ payload 长度，无 id、无长记录扩展）。
int nfcTagUriBytes(String uri) => 3 + utf8.encode(uri).length;

/// 标签 IO 抽象（测试注入缝：widget 用例注入假实现即可全程不碰真硬件）。
abstract class NfcTagIo {
  /// 系统 NFC 是否可用（未开或设备不支持都返回 false · B1/B2）。
  Future<bool> isEnabled();

  /// 跳系统 NFC 设置页（B2 的「去设置」）。
  Future<void> openSettings();

  /// 开一次**前台**读卡会话；读到标签回调 [onProbe]，失败回调 [onError]（带类别码）。
  Future<void> startRead({
    required void Function(NfcTagProbe probe) onProbe,
    required void Function(String code) onError,
  });

  /// 停会话（离开写卡层/重试前必调）。
  Future<void> stop();

  /// 把 [uri] 写成**单条 NDEF URI 记录**（本模块唯一一次 NDEF 写入）。
  Future<void> writeUri(String uri);
}

/// 系统 NFC 设置页通道（`MainActivity` 侧 `ACTION_NFC_SETTINGS`，回落 `ACTION_WIRELESS_SETTINGS`）。
///
/// 为什么自建通道：`url_launcher` 打不开系统设置页，而 B2 要求「去设置」是硬项。
/// 先例＝`MainActivity.requestOverlayPermission`（同为系统设置页跳转）。
const MethodChannel kNfcChannel = MethodChannel('lh/nfc');

/// `nfc_manager` 实现（生产用；测试一律注入假实现）。
class NfcManagerTagIo implements NfcTagIo {
  NfcTag? _tag;
  bool _running = false;

  @override
  Future<bool> isEnabled() async {
    try {
      return await NfcManager.instance.checkAvailability() ==
          NfcAvailability.enabled;
    } catch (_) {
      // catch-ok: 非 Android/iOS 平台（桌面/测试）与 ROM 拒答都归「不可用」，
      // 调用方据此出「系统 NFC 未开启/不支持」档，无需区分原因。
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await kNfcChannel.invokeMethod<void>('openSettings');
    } catch (_) {
      // catch-ok: 无设置页可跳（个别 ROM）时保持原态，用户可自行去系统设置开。
    }
  }

  @override
  Future<void> startRead({
    required void Function(NfcTagProbe probe) onProbe,
    required void Function(String code) onError,
  }) async {
    if (!await isEnabled()) {
      onError('nfc_disabled'); // 自造哨兵：域层映射到 errNfcOff（B2）
      return;
    }
    try {
      await NfcManager.instance.startSession(
        // NTAG21x 走 ISO14443-A；15693 是部分方卡，一并收（多收不会误报）。
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (tag) async {
          _tag = tag;
          try {
            onProbe(await probeOf(tag));
          } catch (e) {
            onError(codeOf(e));
          }
        },
      );
      _running = true;
    } catch (e) {
      onError(codeOf(e));
    }
  }

  @override
  Future<void> stop() async {
    _tag = null;
    if (!_running) return;
    _running = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // catch-ok: 会话本就可能已被系统收走（标签离开/切后台），停不掉不算失败。
    }
  }

  @override
  Future<void> writeUri(String uri) async {
    final tag = _tag;
    if (tag == null) {
      throw PlatformException(code: 'tag_not_found', message: '标签已离开');
    }
    final ndef = NdefAndroid.from(tag);
    if (ndef == null) {
      throw PlatformException(code: 'FormatException', message: '不是 NDEF 标签');
    }
    await ndef.writeNdefMessage(
      NdefMessage(records: [
        NdefRecord(
          // TNF 3＝absoluteUri：type 必须为空，payload 直接是 URI 字节。
          // （`ndef_record` 没有 `createUri` 工厂，故此处手构——本模块唯一的
          // 「照 NDEF 规格手写」点，其余地方只消费 URI 串。）
          typeNameFormat: TypeNameFormat.absoluteUri,
          type: Uint8List(0),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(utf8.encode(uri)),
        ),
      ]),
    );
  }

  /// 探针：把插件对象翻成域层可判定的最小集合。
  ///
  /// 只读判定用 `isWritable`（系统报的），**不试写**——试写会真的动到卡；
  /// 内容取 `cachedNdefMessage`（分发时系统已解析）优先，缺失再读一次。
  static Future<NfcTagProbe> probeOf(NfcTag tag) async {
    final ndef = NdefAndroid.from(tag);
    if (ndef == null) {
      return const NfcTagProbe(isNdef: false, isWritable: false);
    }
    NdefMessage? msg = ndef.cachedNdefMessage;
    if (msg == null) {
      try {
        msg = await ndef.getNdefMessage();
      } catch (_) {
        // catch-ok: 读内容失败不改变「是 NDEF 且可写」的事实，按空卡继续——
        // 真写不进去时由写入报错分档（B5/B6）兜住，比在这里猜一档更诚实。
        msg = null;
      }
    }
    return NfcTagProbe(
      isNdef: true,
      isWritable: ndef.isWritable,
      maxSize: ndef.maxSize,
      existingUri: firstUriOf(msg),
    );
  }
}

/// 取 NDEF 消息里**第一条 URI 记录**（其余记录忽略）；无则 null。
String? firstUriOf(NdefMessage? msg) {
  if (msg == null) return null;
  for (final r in msg.records) {
    final uri = nfcUriOfNdefRecord(
      tnf: tnfCodeOf(r.typeNameFormat),
      type: r.type,
      payload: r.payload,
    );
    if (uri != null && uri.trim().isNotEmpty) return uri;
  }
  return null;
}

/// `TypeNameFormat` → NDEF 的 TNF 数值（域层判定只认数值，不 import 插件枚举）。
int tnfCodeOf(TypeNameFormat t) => switch (t) {
      TypeNameFormat.empty => 0,
      TypeNameFormat.wellKnown => 1,
      TypeNameFormat.media => 2,
      TypeNameFormat.absoluteUri => 3,
      TypeNameFormat.external => 4,
      TypeNameFormat.unknown => 5,
      TypeNameFormat.unchanged => 6,
    };

/// 异常 → 类别码（`PlatformException.code` 原样透传；其余取运行时类名）。
///
/// 插件走 Pigeon，原生异常以 `exception.javaClass.simpleName` 当 code 传出
/// （见 `nfc_manager` 的 `Pigeon.kt: wrapError`）⇒ 这里拿到的就是**类别本身**。
String codeOf(Object e) {
  if (e is PlatformException) return e.code;
  final s = e.runtimeType.toString();
  return s.isEmpty ? 'error' : s;
}
