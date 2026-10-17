import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';

// 20261004 缺陷回归：`lhbak` 不在 Android 插件 MIME 表，FileType.custom 直抛
// PlatformException（Unsupported filter）→ 选择器从未弹起＝「点了没反应」。
// 现口径：先试 custom，被拒降级 FileType.any；取消不重试；双双失败异常上抛给 UI 兜底。
void main() {
  late Future<FilePickerResult?> Function(FileType, List<String>?) orig;
  setUp(() => orig = BackupService.pickFilesImpl);
  tearDown(() => BackupService.pickFilesImpl = orig);

  FilePickerResult one(String path) => FilePickerResult(
      [PlatformFile(name: path.split('/').last, path: path, size: 10)]);

  test('custom 被平台拒 → 降级 FileType.any 并返回所选路径', () async {
    final calls = <(FileType, List<String>?)>[];
    BackupService.pickFilesImpl = (type, exts) async {
      calls.add((type, exts));
      if (type == FileType.custom) {
        throw PlatformException(code: 'FilePicker', message: 'Unsupported filter');
      }
      return one('/sdcard/Download/a.lhbak');
    };
    expect(await BackupService.defaultPickFile(), '/sdcard/Download/a.lhbak');
    expect(
      calls.map((e) => '${e.$1.name}|${e.$2?.join(",") ?? "-"}').toList(),
      ['custom|lhbak', 'any|-'],
    );
  });

  test('custom 正常支持（xlsx 类已知扩展名同构）→ 不触发降级第二跳', () async {
    var n = 0;
    BackupService.pickFilesImpl = (type, exts) async {
      n++;
      return one('/x.lhbak');
    };
    expect(await BackupService.defaultPickFile(), '/x.lhbak');
    expect(n, 1);
  });

  test('custom 取消（null）→ 静默回原态，不再弹全文件版', () async {
    var n = 0;
    BackupService.pickFilesImpl = (type, exts) async {
      n++;
      return null;
    };
    expect(await BackupService.defaultPickFile(), isNull);
    expect(n, 1);
  });

  test('custom 与 any 双双被拒 → 异常上抛由 UI 层可见提示（不吞）', () async {
    BackupService.pickFilesImpl = (type, exts) async =>
        throw PlatformException(code: 'FilePicker');
    expect(() => BackupService.defaultPickFile(),
        throwsA(isA<PlatformException>()));
  });
}
