import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-10-07 产品令「待办页面底部的回收站移除」「主页的插件中心移除掉」的防复活守护。
///
/// 两条都是**入口下架**，不是功能下架：回收站本体（七类聚合屏 `/settings/trash`）与
/// 插件中心的占位屏都还在，摘的只是主页宫格与待办页末卡这两枚入口。
/// 所以守护是双向的：入口不许回来，留下的入口不许被顺手删掉。
void main() {
  const todoPage = 'lib/features/todo/presentation/todo_page.dart';
  const todoTrashEntry =
      'lib/features/todo/presentation/widgets/todo_trash_entry.dart';
  const dash = 'lib/features/dashboard/presentation/dashboard_page.dart';
  const settings = 'lib/features/settings/presentation/settings_page.dart';
  const recmg = 'lib/features/settings/presentation/recmg_page.dart';
  const noteDrawer =
      'lib/features/journal/presentation/widgets/note_tree_drawer.dart';
  const aiPage = 'lib/features/settings/presentation/ai_page.dart';
  const aiVerify = 'lib/features/settings/presentation/ai_page_verify.dart';
  const mediaClean =
      'lib/features/settings/presentation/media_clean_page.dart';

  test('待办页底部回收站入口已整件下架', () {
    expect(File(todoTrashEntry).existsSync(), isFalse,
        reason: '入口件还在＝随时可能被重新挂回页面');
    final src = File(todoPage).readAsStringSync();
    expect(src.contains('TodoTrashEntry'), isFalse, reason: '页面不得再引用入口件');
    expect(src.contains('todo-trash-entry'), isFalse);
    expect(src.contains('/settings/trash'), isFalse,
        reason: '待办页不再自带跳回收站的路径');
  });

  test('主页宫格不再有插件中心瓦片', () {
    final src = File(dash).readAsStringSync();
    final mods = src.substring(src.indexOf('static const _mods'));
    expect(mods.contains('插件中心'), isFalse);
    expect(mods.contains('pstore'), isFalse, reason: '也不该留路由占位');
  });

  test('留下的三枚回收站入口不能被顺手删掉', () {
    // 2026-10-07 待办页末卡下架后，进回收站的活入口＝「我的」页行 / 笔记抽屉行 / 数据库概览行。
    expect(File(settings).readAsStringSync().contains('/settings/trash'), isTrue,
        reason: '「我的」页入口是保留面');
    expect(File(noteDrawer).readAsStringSync().contains('/settings/trash?seg=note'), isTrue,
        reason: '笔记抽屉入口是保留面');
    expect(File(recmg).existsSync(), isTrue);
  });

  test('日记天气住在记录管理，不再占「我的」主页一行', () {
    // 2026-10-07 产品令「把日记天气挪到记录管理里面」。
    // 只断代码形态（`title:` 与入口 key），不断裸词——注释里也会提到这个词（守护别断注释里也有的词）。
    final mine = File(settings).readAsStringSync();
    expect(mine.contains("title: '日记天气'"), isFalse, reason: '主页不留该行');
    expect(mine.contains('entry-weather'), isFalse);
    expect(mine.contains('showWeatherCitySheet'), isFalse);
    final r = File(recmg).readAsStringSync();
    expect(r.contains("title: '日记天气'"), isTrue);
    expect(r.contains('showWeatherCitySheet'), isTrue,
        reason: '挪位置不许把城市选择能力一起挪丢');
  });

  test('AI 增强页：服务商收成一行＋选单，重复的 Key 配置卡不复活', () {
    final ai = File(aiPage).readAsStringSync();
    expect(ai.contains("'Key 配置'"), isFalse, reason: '与服务商卡重复的整卡已摘');
    expect(ai.contains('ai-key-field'), isFalse, reason: '页面不再自带 Key 输入框');
    expect(ai.contains('ai-cur-endpoint'), isTrue, reason: '当前服务商那一行是活入口');
    expect(ai.contains('_openProviderPicker'), isTrue);
    expect(RegExp(r'\bDropdownButton\s*[<(]').hasMatch(ai), isFalse,
        reason: '收成一行走半屏选单，不引 DropdownButton（U5 禁词闸在册）');
    expect(ai.contains('ai-verify-btn'), isTrue,
        reason: 'API 验证入口必须留在服务商卡里');
    expect(File(aiVerify).existsSync(), isTrue, reason: '验证页本体还在');
  });

  test('图片存储清理有全选钮', () {
    expect(File(mediaClean).readAsStringSync().contains("'mc-all'"), isTrue);
  });

  test('插件中心整簇下架：设置页占位行与壳原型那屏都不许回来', () {
    // 2026-10-07 产品拍板「插件中心 删屏」。插件化平台的调研与设计文档仍在，
    // 摘的是**入口与演示屏**——日后要做＝另批先过原型门，别从这堆残留里复活。
    expect(File(settings).readAsStringSync().contains("title: '插件中心'"), isFalse,
        reason: '设置页占位行（注释里提这个词是留痕，不算残留）');
    final shell = File('prototype/index.html').readAsStringSync();
    for (final gone in ['p-pstore', 'renderPstore', 'sheetPSDetail', 'id="sheetPlugin"']) {
      expect(shell.contains(gone), isFalse, reason: '$gone 残留');
    }
    // 唯一副本留在影音游专版（冻结文件），注册表的家必须跟着改过去，别留「家在壳、壳里没屏」。
    final reg = File('prototype/_modules.json').readAsStringSync();
    expect(reg.contains('"id": "p-pstore"'), isTrue, reason: '屏条目留着（影音游侧仍有副本）');
    expect(reg.split('"id": "p-pstore"')[1].contains('index-media.html'), isTrue,
        reason: '家已改指唯一留副本的专版文件');
  });
}
