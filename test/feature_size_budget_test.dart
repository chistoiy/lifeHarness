import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 单 feature 总行数预算门禁（高保真体量整改批 6a·2026-10-16 立）。
///
/// 动机：`size_budget_test.dart` 只管单文件行数、**不管模块总量**——read 可以
/// 一直长到任意大而那道闸不红（工单 §1.2：read 48,940 行＝第二名 2.7 倍）。
/// 本闸补这一面：`lib/features/<name>/` 整棵子树的 `.dart` 行数总和＝该 feature
/// 总量，超过 [featureBudget] 登记值＝红，**只许减不许增**（棘轮，同 size_budget
/// 家族口径）。拆完/还债请把登记值调小（不要删项——默认面是「全部登记」）。
///
/// 判红三类：① 总量超登记＝长大；② 新 feature 目录未登记＝新模块必须登记现值；
/// ③ 登记项对应目录消失＝删项。变小只提醒不判红（拆小是好事，同 C-4 口径）。
/// 纯静态扫描，无需 pump。
void main() {
  const featuresDir = 'lib/features';

  // 立闸时实测基线（2026-10-16·工作区 HEAD `2b12d608` 干净树）：read 48,940 行/99 文件
  // ＝工单 §1.2 靶子数；其余 feature 同法取现值。此后只许减不许增。
  const featureBudget = <String, int>{
    // 48940→48984（高保真批6b·2026-10-16·工单 §3 批6b 规定动作）：read 三刀拆 part
    // 的机械开销＝三个新 part 件 header/治理注释＋_BookFormBits 扩展包裹＋根库 part
    // 指令，净 +44 行（无功能代码增减）。此后只许减；真还债＝批6c 拆剩余越线件时
    // 顺带收紧。
    // 48984→48991（高保真批6c·刀1·2026-10-16·工单 §3 批6c 规定动作）：新 part 件
    // header 治理注释 7 行＋根库 part 指令 1 行＝机械开销净 +7 行（无功能代码
    // 增减）。刀2/刀3 续拆逐刀实测续登；read 三件 size_budget 登记项拆完删项后本表只许减。
    // 48991→49002（高保真批6c·刀2·2026-10-16·工单 §3 批6c 规定动作）：新 part 件
    // header 治理注释＋_StatCards 扩展包裹两行＋根库 part 指令＋1 处 setState
    // ignore＝机械开销净 +11 行（无功能代码增减）。刀3 续拆后实测续登；read 三件
    // size_budget 登记项拆完删项后本表只许减。
    // 48984→49020（高保真批6c·2026-10-16·整单收口批·工单 §3 批6c 规定动作）：
    // 三刀拆 part 的机械开销合计＝三个新 part 件 header/治理注释＋两枚扩展包裹＋
    // 根库 part 指令＋10 处 setState ignore，净 +36 行（无功能代码增减）。
    // read 三件 size_budget 登记项已删（登记清零）·此后只许减。
    'read': 49020,
    // ledger 18045→18132（小组件批A·工单 §7.1 记一笔弹窗·2026-10-18）：记账页加
    // dialogMode 外壳（_dialogShell／_leave／参数与文档注释）净 +87 行——同一份表单
    // 换容器、无第二套 UI；属产品拍板需求增长，按实测登，此后只许减。
    // 18132→18286（同批·真机二次报障三修·2026-10-18）：「记一笔弹窗是拉长版、跟高保真
    // 不一样」⇒ 版式按原型 `#qpDlg` 收口（卡片 322×72%·字段区可滚＋键盘钉底·页面专属
    // chrome 三处 compact 闸），净 +154 行；同属产品拍板需求增长，按实测登，此后只许减。
    'ledger': 18286,
    'media': 13573,
    // nfc 4723（批A 收口轮 2026-10-18 新登记）：NFC 卡片模块批1~批3f 累计
    // （数据层/管理屏/写卡层/触发链/有状态 toggle/回执/自绘横幅·`b4e98058`→批3f）；
    // 之后只许减。
    'nfc': 4723,
    // widget 1079（同轮新登记）：小组件模块批A 五层（域/存储/选择器/挂载编排）；
    // 批B（计时/快捷动作两枚）起若越档先走治理评审再登，不默认放行。
    // 1079→1097（同批·真机二次报障 2026-10-18）：选择器加 `onlyTab`（只开一个分区·
    // 收起 tab 行）——打卡枚误绑书目的根因修，净 +18 行；按实测登，此后只许减。
    'widget': 1097,
    'health': 12862,
    // settings 12516→12648（批A 收口轮 2026-10-18 同步·非本刀净增）：两笔产品令
    // 功能增长未同步登记——NFC 批1b（`b4e98058`·管理屏入口 +49）与批A 配置页刀
    // （`ed834d9f`·设置页「添加小组件」＋打卡枚行 +93）；按实测登，此后只许减。
    // 12648→12742（同批·真机二次报障三修 2026-10-18）：「app 内添加说在系统选项中设、
    // 实际没有系统选择」⇒ 按 pin 返回值分流＋手动拖出三步引导弹层（`_showManualAddGuide`），
    // 净 +94 行；按实测登，此后只许减。
    // 12742→12810（小组件批C·真机三修 2026-10-18）：产品令「app 内没有添加 1×1 小组件的
    // 能力」⇒ 设置页小组件卡加「模块瓦片（1×1）」行＋`_addModuleTile`（选模块→pin），
    // 并给引导弹层加 `widgetName`/`pinned` 两个参数（原文案写死「打卡-单习惯」），
    // 净 +68 行；选择层本身落在 `shared/widgets/module_tile_picker.dart`（不进 feature 预算）。
    // 按实测登，此后只许减。
    'settings': 12809,
    // 12212→13080（日记改版批1a·2026-10-19）：三档视图（轨道/列表/INS）落地的净增。
    // 拆解＝新增四件 783 行（layout_kit 153 纯逻辑 / track_view 265 画面 / wall 156 画面 /
    // page_track 209 从 journal_page 抽出，抽出部分与 page 内新增相抵后 page 仍微增），
    // 余量为 journal_page 的档位分支与收藏点亮出口。按实测登，此后只许减；
    // 批1b/1c（吸附日期块、图墙翻月）若再加行，须先把 1a 的列表分支合并掉再谈。
    // 13080→13193（日记改版批1b·2026-10-19）：日期块吸顶（`SliverPersistentHeader pinned`）
    // ＋左栏四档分层（日号 22/月·周·时刻 10）的净增。轨道视图由「一块一 box」改成
    // 「一块两条 sliver」（`trackBlockSlivers`），并补了块高预估 `trackDateBlockHeight`。
    // 按实测登，此后只许减；1c（图墙翻月）若再加行，先合并列表档分支。
    // 13193→13325（日记改版批1c·2026-10-19）：图墙翻月。图墙加月份标题 + 前/后月钮
    //（范围 [本月-24, 本月]，不给未来）；页面侧加 `_wallMonthOff` 与「年→月→日」全量索引
    //（翻到 3 月时不能再用只装本月的 byDayAll）。按实测登，此后只许减。
    // ⚠ journal_page.dart 已 1185 行（红线 1200），下一批再动它必须先拆分。
    'journal': 13325,
    // habit 12141→12150（同轮同步）：NFC 批3（`52bb9e1e`）贴卡触发链落 habit 侧
    // 反馈 +9；按实测登，此后只许减。
    // 12150→12165（小组件批A·真机三报 2026-10-18）：「带数值的打卡只显示一个打卡、
    // 不显示数值修改能力」⇒ 记量步进阶梯从 `habit_sheets`（presentation）迁
    // `domain/habit_calc` 的 `habitStepOf`，让桌面小组件与记量弹层共用同一档位：
    // 迁出 −23 行、迁入 +41 行（含 domain 侧口径注释），弹层留 6 行转发；净 +15 行
    // ＝注释与转发开销，无第二份实现。按实测登，此后只许减。
    // 12165→12288（批E·2026-10-18 产品令「缺少修改打卡记录，删除或修改（打卡时间、
    // 数值这一类的）」）：记量弹层**扩成按日记录编辑**（`showHabitLogSheet(day:)`），
    // 新增打卡时刻可改（time picker）＋保存时保留原 origin/backfilled；详情页两处入口
    // （日历今天格、打卡流水每行）改开它。+123 行全在既有弹层内，**未新起第二套 UI**
    //（另造一套记录编辑页约 230 行）。按实测登，此后只许减。
    // 12288→12280（同批收口）：压缩详情页包层注释与 onTap 折行后回落 8 行，顺手收紧。
    'habit': 12280,
    'care': 10909,
    'mindmap': 6540,
    'calendar': 5874,
    'items': 4248,
    'days': 3492,
    'todo': 3143,
    'goals': 2809,
    'dashboard': 1401,
    'inbox': 593,
  };

  test('feature 总量预算：lib/features 单模块总行数只许减不许增', () {
    final grown = <String>[], shrunk = <String>[], unregistered = <String>[];
    final seen = <String>{};
    for (final feat
        in Directory(featuresDir).listSync().whereType<Directory>()) {
      final name = p.basename(feat.path);
      var lines = 0;
      for (final f in feat.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        lines += f.readAsLinesSync().length;
      }
      seen.add(name);
      final b = featureBudget[name];
      if (b == null) {
        unregistered.add('$name（$lines 行，未登记）');
      } else if (lines > b) {
        grown.add('$name（$lines > 预算 $b）');
      } else if (lines < b) {
        shrunk.add('$name（$lines < 登记 $b，请把预算改成 $lines）');
      }
    }
    final stale = featureBudget.keys.where((k) => !seen.contains(k)).toList();
    expect(grown, isEmpty,
        reason: 'feature 总量长大了：预算只许减不许增。确属必要增长请先走治理评审'
            '并同步调大登记值（默认不许）。');
    expect(unregistered, isEmpty,
        reason: '新 feature 目录未登记总量上限：把现值登记进 featureBudget（'
            '之后只许减）。');
    // 变小不是变坏——拆分/删代码让模块变轻是好事，判红只会让并行会话互相踩出
    // 「我没动为什么红」。降级为提醒，收紧登记值由看到提醒的人顺手做。
    if (shrunk.isNotEmpty) {
      // ignore: avoid_print
      print('[feature_size_budget 提醒] 以下 feature 已变小，请顺手调小登记值：\n  '
          '${shrunk.join('\n  ')}');
    }
    expect(stale, isEmpty,
        reason: '以下登记项对应 feature 目录已消失，请删掉（否则守护悄悄空转）：'
            '${stale.join('、')}');
  });
}
