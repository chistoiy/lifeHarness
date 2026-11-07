import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/sync/diff_service.dart';
import 'package:lifeharness/core/sync/remote_store.dart';

/// Task 15：DiffService 三档一致性（【云盘】§8 same() 片段 + R8 + D2/D5）。
///
/// 纪律（§9）：纯函数单测，不碰网络不碰磁盘。
void main() {
  FileEntry e(String path,
          {int size = 10,
          String? etag,
          String? digest,
          DateTime? modified}) =>
      FileEntry(
        relativePath: path,
        size: size,
        etag: etag,
        digest: digest,
        modified: modified,
      );

  List<FileDiff> diff(
          {List<FileEntry> local = const [],
          List<FileEntry> remote = const [],
          Set<String> ignore = const {},
          Set<String> ledger = const {}}) =>
      computeDiff(
          local: local,
          remote: remote,
          ignorePatterns: ignore,
          ledgerKnown: ledger);

  group('computeDiff 四态', () {
    test('onlyLocal / onlyRemote / modified / inSync 各一', () {
      final r = diff(
        local: [
          e('a.txt', etag: 'X'),
          e('b.txt', etag: 'B1'),
          e('c.txt', etag: 'C1'),
        ],
        remote: [
          e('a.txt', etag: 'X'),
          e('b.txt', etag: 'B2'),
          e('d.txt', etag: 'D1'),
        ],
      );
      expect(r.map((d) => d.status), [
        DiffStatus.inSync, // a.txt 双强 ETag 相等
        DiffStatus.modified, // b.txt 双强 ETag 不等
        DiffStatus.onlyLocal, // c.txt
        DiffStatus.onlyRemote, // d.txt
      ]);
      expect(r.map((d) => d.relativePath), ['a.txt', 'b.txt', 'c.txt', 'd.txt']);
      // 条目回填：编排层下载/上传要用
      expect(r[2].remote, isNull);
      expect(r[2].local!.relativePath, 'c.txt');
      expect(r[3].local, isNull);
      expect(r[3].remote!.etag, 'D1');
    });

    test('输出按 relativePath 字典序稳定排序', () {
      final r = diff(
        local: [e('z.txt'), e('m/a.txt'), e('m/b.txt'), e('a.txt')],
        remote: [e('m/a.txt'), e('m/b.txt')],
      );
      expect(r.map((d) => d.relativePath),
          ['a.txt', 'm/a.txt', 'm/b.txt', 'z.txt']);
    });
  });

  group('sameEntry 三档（R8），绝不 mtime', () {
    test('size 不等直接 false，哪怕 ETag 相同', () {
      expect(sameEntry(e('f', size: 1, etag: 'X'), e('f', size: 2, etag: 'X')),
          isFalse);
    });

    test('双端弱 ETag 同值（W/"abc"）→ 退默认档 size 相等即 true', () {
      expect(
          sameEntry(e('f', etag: 'W/"abc"'), e('f', etag: 'W/"abc"')), isTrue);
    });

    test('一方弱一方强 → 不比 ETag，退 size 档', () {
      expect(sameEntry(e('f', etag: 'W/"abc"'), e('f', etag: 'abc')), isTrue);
      expect(sameEntry(e('f', etag: 'W/"abc"'), e('f', etag: 'zzz')), isTrue);
      expect(sameEntry(e('f', etag: 'W/"abc"'), e('f', size: 9, etag: 'zzz')),
          isFalse);
    });

    test('双强 ETag → 比 ETag，不等即 modified', () {
      expect(sameEntry(e('f', etag: 'E1'), e('f', etag: 'E1')), isTrue);
      expect(sameEntry(e('f', etag: 'E1'), e('f', etag: 'E2')), isFalse);
    });

    test('任一侧无 etag → 默认档只比 size', () {
      expect(sameEntry(e('f', etag: 'E1'), e('f', etag: null)), isTrue);
      expect(sameEntry(e('f', size: 3, etag: 'E1'), e('f', size: 4)), isFalse);
    });

    test('digest 档命中：远端 32hex（带引号大写）→ 摘要相等即 true', () {
      const md5 = 'd41d8cd98f00b204e9800998ecf8427e';
      expect(
          sameEntry(
              e('f', digest: md5), e('f', etag: '"${md5.toUpperCase()}"')),
          isTrue);
    });

    test('digest 档不命中：同 size 摘要不同 → false（modified）', () {
      expect(
          sameEntry(
              e('f', digest: 'a' * 32), e('f', etag: '"${'b' * 32}"')),
          isFalse);
    });

    test('分片 ETag `d41…-7` 非 32hex → digest 档不启用不误报', () {
      const multipart = 'd41d8cd98f00b204e9800998ecf8427e-7';
      expect(
          sameEntry(
              e('f', digest: 'd41d8cd98f00b204e9800998ecf8427e',
                  etag: multipart),
              e('f', etag: '"$multipart"')),
          isTrue); // 双强 ETag 相等，摘要档被 32hex 门槛挡住
    });

    test('modified 填相反值不影响判定（防 mtime 兜底回归，已知坑表）', () {
      final t1 = DateTime.utc(2020, 1, 1);
      final t2 = DateTime.utc(2026, 9, 25);
      // 刚同步完：云端 LastModified 必然新于本地 → 仍应 inSync
      expect(sameEntry(e('f', etag: 'E', modified: t1), e('f', etag: 'E', modified: t2)),
          isTrue);
      expect(sameEntry(e('f', modified: t1), e('f', modified: t2)), isTrue);
      // 双强 ETag 不等的 modified 也不因时间先后翻转
      expect(
          sameEntry(e('f', etag: 'E1', modified: t2), e('f', etag: 'E2', modified: t1)),
          isFalse);
    });
  });

  group('D5 忽略规则双侧剔除', () {
    test('`.DS_Store` 仅云端版被 `*.DS_Store` 剔除，不报 onlyRemote', () {
      final r = diff(
        local: [e('notes/app.md'), e('notes/.DS_Store')],
        remote: [e('notes/app.md'), e('notes/.DS_Store'), e('photos/.DS_Store')],
        ignore: {'*.DS_Store'},
      );
      // 双侧全部剔除后只剩 app.md 一对 inSync，云端 .DS_Store 不再是差异。
      expect(r.map((d) => d.status), [DiffStatus.inSync]);
      expect(r.map((d) => d.relativePath), ['notes/app.md']);
    });

    test('`prefix*` 前缀档对 basename 生效', () {
      final r = diff(
        local: [e('docs/report_2026.pdf')],
        remote: [e('docs/report_2026.pdf'), e('docs/tmp_x.md')],
        ignore: {'tmp*'},
      );
      expect(r.map((d) => d.status), [DiffStatus.inSync]);
      expect(r.map((d) => d.relativePath), ['docs/report_2026.pdf']);
    });

    test('未命中忽略规则的差异照常上报', () {
      final r = diff(
        local: [e('a.txt')],
        remote: [e('a.txt'), e('b.log')],
        ignore: {'*.tmp'},
      );
      final b = r.firstWhere((d) => d.relativePath == 'b.log');
      expect(b.status, DiffStatus.onlyRemote);
    });
  });

  group('D2 台账 staleHint', () {
    test('台账空集：onlyRemote 不报残留', () {
      final r = diff(remote: [e('new.txt')]);
      expect(r.single.status, DiffStatus.onlyRemote);
      expect(r.single.staleHint, isFalse);
    });

    test('台账命中该路径 → staleHint=true；未命中不误报', () {
      final r = diff(
        remote: [e('gone.txt'), e('fresh.txt')],
        ledger: {'gone.txt'},
      );
      expect(r.firstWhere((d) => d.relativePath == 'gone.txt').staleHint,
          isTrue);
      expect(r.firstWhere((d) => d.relativePath == 'fresh.txt').staleHint,
          isFalse);
    });

    test('非 onlyRemote 一律不挂 staleHint', () {
      final r = diff(
        local: [e('x.txt', etag: 'E1')],
        remote: [e('x.txt', etag: 'E2')],
        ledger: {'x.txt'},
      );
      expect(r.single.status, DiffStatus.modified);
      expect(r.single.staleHint, isFalse);
    });
  });

  group('路径大小写敏感钉死（原文精确匹配，不 lower）', () {
    test('Readme.md 与 readme.md 视为两个文件', () {
      final r = diff(local: [e('Readme.md', etag: 'X')], remote: [e('readme.md', etag: 'X')]);
      expect(r.map((d) => d.status),
          containsAll([DiffStatus.onlyLocal, DiffStatus.onlyRemote]));
      expect(r.where((d) => d.status == DiffStatus.inSync), isEmpty);
    });
  });

  group('normEtag（§8 片段口径）', () {
    test('去引号；弱前缀判定后内层再去引号、W/ 原样保留', () {
      expect(normEtag('"abc"'), 'abc');
      expect(normEtag('W/"abc"'), 'W/abc');
      expect(normEtag('W/abc'), 'W/abc');
      expect(normEtag('  "abc" \n'), 'abc');
      expect(normEtag(null), '');
      expect(normEtag(''), '');
    });
  });
}
