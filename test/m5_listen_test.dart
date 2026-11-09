/// M5 · 音乐特化架面（听后感流＋导入歌单）常驻守护（2026-11-08 · 产品点单全量完成）。
///
/// 源码级／纯函数级，不起整机、不建库、不跑 flutter 行为波。
/// 每条都给正档（isTrue/contains）＋负档（isFalse/isNot(contains)）同例对照，
/// 避免「被测分支没进也能绿」的假绿。
/// 四项必守：默认视图不变 / 听后感流存在 / 导入入口存在 / 2A 皮肤默认关路径未被改。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/media/presentation/media_playlist_parser.dart';

const _proto = 'prototype/index-media.html';
const _providers = 'lib/features/media/presentation/media_providers.dart';
const _shelf = 'lib/features/media/presentation/media_shelf_page.dart';
const _view = 'lib/features/media/presentation/media_music_view.dart';
const _parser = 'lib/features/media/presentation/media_playlist_parser.dart';
const _card = 'lib/features/media/presentation/widgets/media_card.dart';
const _set = 'lib/features/media/presentation/media_set_page.dart';

String _read(String rel) => File(rel).readAsStringSync();

void main() {
  // ==================== 纯函数级：导入歌单本地解析 ====================
  test('① parsePlaylistText 正档解析出曲目 / 负档空串与注释不产曲目', () {
    final pos = parsePlaylistText(
        '周杰伦 - 爱在西元前\r\nDaft Punk - Get Lucky\n');
    expect(pos.isNotEmpty, isTrue, reason: '正档必须解析出曲目');
    expect(pos, ['爱在西元前', 'Get Lucky']);

    final negEmpty = parsePlaylistText('');
    expect(negEmpty.isEmpty, isTrue, reason: '负档空串不得凭空产曲目');
    expect(negEmpty, isNot(contains('爱在西元前')));

    final negComment = parsePlaylistText('#EXTM3U\n#EXTINF:210,x\n   \n');
    expect(negComment.isEmpty, isTrue, reason: '负档注释/空行不得进列表');
  });

  test('② parsePlaylistText m3u/序号/去重：正档出数 / 负档注释不被当曲目、重复不翻倍', () {
    final m3u = parsePlaylistText('#EXTM3U\n#EXTINF:210,x\n晴天\n');
    expect(m3u, ['晴天']);
    expect(m3u.any((t) => t.contains('EXTINF')), isFalse,
        reason: '负档：元数据行不许被当曲目');

    final numbered = parsePlaylistText('1. 爱在西元前\n2) Get Lucky');
    expect(numbered.length, 2, reason: '正档：序号前缀两个都要解析出来');
    expect(numbered.first, '爱在西元前');

    final dedup = parsePlaylistText('晴天\n晴天\n');
    expect(dedup, ['晴天']);
    expect(dedup.length == 2, isFalse, reason: '负档：重复行不许翻倍');
  });

  test('③ m5FormatStamp 正档出时间戳 / 负档非正时刻为空串', () {
    final ok = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')
        .hasMatch(m5FormatStamp(1700000000000));
    expect(ok, isTrue, reason: '正档：有效毫秒必须格式化成 yyyy-MM-dd HH:mm');
    expect(m5FormatStamp(0), '', reason: '负档：0 时刻不许编一个时间');
    expect(m5FormatStamp(-1).isEmpty, isTrue);
  });

  // ==================== 源码级：默认视图不变 ====================
  test('④ 默认视图仍是现行扁平架面（provider 默认 false ＋ body 三元走 Column）', () {
    final prov = _read(_providers);
    expect(prov.contains("StateProvider<bool>((ref) => false)"), isTrue,
        reason: '正档：音乐视图开关必须默认 false');
    expect(prov.contains("StateProvider<bool>((ref) => true)"), isFalse,
        reason: '负档：默认 true 会把进屏首帧换成音乐视图');

    final shelf = _read(_shelf);
    expect(shelf.contains('musicView ? const MediaMusicView() : Column('), isTrue,
        reason: '正档：默认分支必须落回原 Column（扁平架面）');
    expect(shelf.contains('body: const MediaMusicView()'), isFalse,
        reason: '负档：不许把音乐视图写成默认 body');
    expect(shelf.contains('MediaItemCard('), isTrue,
        reason: '正档：扁平卡渲染点仍在');
    expect(
        shelf.contains('cardSkin: ref.watch(mediaCardSkinProvider).valueOrNull ?? false'),
        isTrue,
        reason: '正档：2A 皮肤贯通串不能被视图切换挤掉');
    expect(shelf.contains("ValueKey('mds-music-view')"), isTrue,
        reason: '正档：常规/音乐切换钮在册');
    expect(shelf.contains('音乐亦按 states 四档'), isTrue,
        reason: '正档：分区 chip 注释与 _stateTabs 行为对齐');
    expect(shelf.contains('音乐无分区面'), isFalse,
        reason: '负档：过时「音乐无分区面」注释已修');

    final proto = _read(_proto);
    expect(proto.contains("mShelfScene='flat'"), isTrue,
        reason: '正档：原型默认场景＝扁平');
    expect(proto.contains('mShelfScene=\'music\';mSortKey'), isFalse,
        reason: '负档：进架不许默认落在音乐视图');
    expect(proto.contains("if(mCurKind==='music'){body.innerHTML"), isFalse,
        reason: '负档：旧「选音乐类型即强制 feed」分支必须退役');
    expect(proto.contains("if(mShelfScene==='music'){body.innerHTML=sceneBar+"), isTrue,
        reason: '正档：音乐改由显式场景切换驱动');
  });

  // ==================== 源码级：听后感流存在 ====================
  test('⑤ 听后感流＝曲目/心情/短评/时间戳四要素，且走 media_notes 表 DAO（零迁移）', () {
    final view = _read(_view);
    expect(view.contains('听后感流'), isTrue);
    expect(view.contains('MediaListenCard'), isTrue);
    expect(view.contains('ref.watch(mediaMusicNotesProvider)'), isTrue,
        reason: '正档：列表必须走 provider 取在册行');
    expect(view.contains('const <MediaNote>['), isFalse,
        reason: '负档：不许用硬编码演示列表冒充数据流');
    expect(view.contains('note.body'), isTrue, reason: '曲目');
    expect(view.contains('note.tag'), isTrue, reason: '心情');
    expect(view.contains('note.thought'), isTrue, reason: '短评');
    expect(view.contains('m5FormatStamp(note.createdAt)'), isTrue, reason: '时间戳');

    final prov = _read(_providers);
    expect(prov.contains('.notes(kind: MediaItem.kMusic)'), isTrue,
        reason: '正档：复用既有 notes() DAO');
    expect(prov.contains('CREATE TABLE'), isFalse,
        reason: '负档：听后感不许多写一张表（零 DB 迁移）');
    expect(prov.contains('mediaMusicNotesProvider'), isTrue);

    // 新增/编辑入口与 DAO 接线
    expect(view.contains('m5OpenListenEditor'), isTrue);
    expect(view.contains('repo.addNote(MediaNote('), isTrue, reason: '新增入口');
    expect(view.contains('repo.updateNote(cur.copyWith('), isTrue, reason: '编辑入口');

    final proto = _read(_proto);
    expect(proto.contains('MMOMENTS.map(mMomentHTML)'), isTrue,
        reason: '正档：原型听后感流在册');
    expect(proto.contains('class="mds-chip mm-mood"'), isTrue,
        reason: '正档：原型心情 chip 在册');
    expect(proto.contains('mds-pl-strip'), isTrue);
  });

  // ==================== 源码级：导入歌单入口存在（纯本地／零网络／零依赖） ====================
  test('⑥ 导入歌单入口＝纯本地解析＋origin=import 落库，零网络零新增依赖', () {
    final view = _read(_view);
    expect(view.contains("ValueKey('mds-import-playlist')"), isTrue,
        reason: '正档：导入入口按钮在册');
    expect(view.contains('导入歌单'), isTrue);
    expect(view.contains('parsePlaylistText(_ctrl.text)'), isTrue,
        reason: '正档：必须调纯本地解析函数');
    expect(view.contains('MediaNote.kOriginImport'), isTrue,
        reason: '正档：导入曲目落 origin=import');
    expect(view.contains('m5OpenPlaylistImport'), isTrue);
    expect(view.contains('package:http'), isFalse,
        reason: '负档：零网络＝不许出现 http 包');
    expect(view.contains('HttpClient'), isFalse);
    expect(view.contains('dio'), isFalse);

    final parser = _read(_parser);
    expect(parser.contains('List<String> parsePlaylistText(String raw)'), isTrue);
    // raw string 里不能用 \" 转义引号（会把字符串提前收口），改用不含引号的
    // 行首 import 判定：注释行以 // 开头，不会命中。
    expect(RegExp(r'^import\s', multiLine: true).hasMatch(parser), isFalse,
        reason: '负档：解析件零新增依赖（无真实 import 语句；注释提及不算）');

    final proto = _read(_proto);
    expect(proto.contains('onclick="mImportPlaylist()">导入歌单'), isTrue,
        reason: '正档：原型导入入口在册');
    expect(proto.contains('id="m-m5'), isFalse,
        reason: '负档：不新增原型屏 id');
    expect(proto.contains('id="m-music"'), isFalse);
  });

  // ==================== 源码级：2A 可选皮肤默认关路径未被改 ====================
  test('⑦ media.cardSkin 默认关＝卡片仍是原 Column 不套 Stack，6 例守护链路完好', () {
    final card = _read(_card);
    expect(card.contains('this.cardSkin = false'), isTrue,
        reason: '正档：默认关');
    expect(card.contains('this.cardSkin = true'), isFalse,
        reason: '负档：不许把默认改成开');
    expect(card.contains('boxShadow: cardSkin ? mdsSkinShadows(dark) : null'), isTrue);
    // 该件是纯 CRLF，跨行字面串匹配必假红；用 \s* 兼容 CR/LF 两态。
    expect(RegExp(r'child:\s*cardSkin\s*\?\s*Stack\(').hasMatch(card), isTrue,
        reason: '正档：Stack 只在 cardSkin 开时条件挂载（卡体那层）');
    expect(card.contains(': face,'), isTrue,
        reason: '正档：默认关子节点仍是原 face(Column)');
    expect(RegExp(r'^        child: Stack\(', multiLine: true).hasMatch(card), isFalse,
        reason: '负档：Container.child 不许无条件套 Stack（8 空格行首锚，避开 face 内部 Stack）');

    final set = _read(_set);
    expect(set.contains("'media.cardSkin': 'false'"), isTrue,
        reason: '正档：KV 回落默认关');
    expect(set.contains("'media.cardSkin': 'true'"), isFalse,
        reason: '负档：预设不许改成开');
    expect(set.contains("_bool('media.cardSkin', '实物卡材质')"), isTrue);

    final shelf = _read(_shelf);
    expect(
        shelf.contains('cardSkin: ref.watch(mediaCardSkinProvider).valueOrNull ?? false'),
        isTrue,
        reason: '正档：两个调用点之一的架面贯通串仍在');

    final proto = _read(_proto);
    expect(proto.contains('cardSkin:false'), isTrue,
        reason: '正档：原型开关默认关');
    expect(proto.contains('<style id="mclab-skin">'), isTrue);
    expect(proto.contains('cardSkin:true'), isFalse,
        reason: '负档：原型默认不许开');
  });

  // ==================== 源码级：色值棘轮（新增 Dart 件零硬编码色值） ====================
  test('⑧ 新增 Dart 件禁硬编码 Color(0x...)，全用主题色/令牌语义', () {
    for (final p in <String>[_view, _parser]) {
      final src = _read(p);
      expect(RegExp(r'Color\s*\(\s*0[xX]').hasMatch(src), isFalse,
          reason: '负档：$p 不许出现硬编码色值');
      expect(src.contains('Theme.of(context).colorScheme') || p == _parser, isTrue,
          reason: '正档：视图件颜色吃主题色');
    }
    // 原型选中态/淡底一律挂 --accent-NN 令牌，不写死靛紫当最终色
    final proto = _read(_proto);
    expect(proto.contains('background:var(--accent-12);border-color:var(--accent-42)'), isTrue,
        reason: '正档：选中态挂 --accent 派生令牌');
    expect(proto.contains('html.dark .mds-scene-btn.on,.mds-scene-btn.on{'), isTrue,
        reason: '正档：深档权重陷阱并列写');
  });
}
