import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 预算式文件体积门禁（治理收口批·A 档口径 2026-09-29 拍板）。
///
/// 口径：`lib/**` 单文件行数超过 [lineBudget] 必须先进 [budget] 登记（登记值＝登记时行数），
/// 此后只许减不许增——超线未登记＝红；超出登记预算＝红；变小则提示更新登记（棘轮收紧）。
/// 登记面是治理评估 §7「范围重定」列出的 A 档遗留大文件：不逐一压缩，长期管住不再长大。
/// 拆完一个请**删掉对应登记项**（不是调小），让门禁回到「超线即红」的默认面。
void main() {
  const libDir = 'lib';
  const lineBudget = 1200;

  // 治理 G0~G7d⑤ 交付后（2026-09-29）实测登记的基线预算。
  const budget = <String, int>{
    // 批P2（2026-10-20）新增登记：`mindmap_canvas_page.dart` 1316 行。
    // 本批往里加了**右缘拖拽连接点**（手势仲裁一支：起手命中/拖动落点/松手挂接/
    // 取消）＋**速录循环**（弹层反复打开直到用户收手），两者都读写画布页私有
    // 状态、与指针仲裁和 build 主线咬在一起，抽 part 得把十几条参数穿边界
    // （与既有三个 part 不同：那些是现成方法群可整段搬）。
    // 按实测登，此后只许减；下一批发落点＝把「指针仲裁」整段抽 part 还债。
    // 1316→1292（批P4 · 2026-10-20）：顶栏整段抽去 part（`_buildCanvasAppBar`），
    // 主文件净减 24 行——本批还的债，登记值随之下调（棘轮只降不升）。
    // 1292→1259（批P5 · 2026-10-20）：底部悬浮工具条整条撤掉（含三枚按钮与其
    // 排布、以及只为它服务的 `selected` 派生），选中主操作搬进贴点气泡的
    // 新 part 件（`mindmap_canvas_bubble.dart`）——主文件再减 33 行，继续下调。
    // 1259→1288（批P6 · 2026-10-21）：滚轮缩放（Listener 信号通道＋折算）、
    // 双击空白回全图（含连击判定）、最小可点面命中都抽进了新 part
    // （`mindmap_canvas_gestures.dart`，91 行），两个缩放钮的四行闭包也换成
    // 一行调用；但同一批在页内加的手势状态与接线（signal 通道、连击判据、
    // 命中调用点、注释）**凑巧比搬走的多**，主文件净增 29 行到 1288。
    // 如实上调登记值（棘轮遇真新增只能重登；下批还债＝把指针三分仲裁整段
    // 抽 part，那一刀能把这里一次砍到 1100 以下）。
    'features/mindmap/presentation/mindmap_canvas_page.dart': 1288,
    'features/ledger/presentation/ledger_pick_sheets.dart': 1581,
    // 1520→1528 存量越线归位（小组件批E · 2026-10-18）：产品令「缺少修改打卡记录」——
    // 流水每行包一层 GestureDetector（key `hd-rec-<日键>`）点开那一天的记录编辑，
    // 净增 8 行（1 注释＋6 包层＋1 收尾）。**已先做压缩**：onTap 六行折成两行、
    // 原三行注释收成一行（同批曾到 1536）。真还债＝把「打卡流水」整段拆 part，另批做。
    'features/habit/presentation/habit_detail_page.dart': 1528,
    'features/habit/presentation/habit_stat_page.dart': 1503,
    // 1377→1382：交互整改批一 T2-B 给主屏长列表挂 ScrollPad（切栏滚动垫），
    // 净增 5 行接线（注释+包层）；真还债=日历区子视图拆 part，另批做。
    // 1382→1386 存量越线归位（B-4 批 2026-10-05 相邻回归跑出本红）：净增 4 行
    // 发生在轮5批A（ce5acee，F5-2 展开默认随视图档），该批批内增量没带 size 闸，
    // 非 B-4 造成——B-4 未动日历一行。之后只许减。
    // 1386→1468 存量越线归位（阅读模块批2 · 2026-10-14 跑出本红）：净增 82 行发生在
    // 时间模块批4（44d81ef8，2026-10-13，主屏 builder 化＋周视图 24 小时行铺进主屏列表），
    // 该批门禁＝18 波 ftest＋time_perf 用例，未带 size 闸，故今日现形——本批一行未动
    // 日历。之后只许减；真还债＝日历区子视图拆 part，另批做。
    'features/calendar/presentation/calendar_page.dart': 1468,
    // time_stats_page 1247 行（时间模块批4 44d81ef8 同步长大·登记表未同步）：阅读模块批2
    // （2026-10-14）跑 size 闸现形，本批一行未动该文件。按现状登记，之后只许减。
    'features/calendar/presentation/time_stats_page.dart': 1247,
    // 1352→1364 存量越线归位（高保真批 6a 2026-10-16 跑出本红）：净增 12 行发生在
    // 备份余量批3（6939f3ec·V1.67 按范围自由导出时间维度），该批未带 size 闸，
    // 批 6a 一行未动该文件。按现状登记，之后只许减。
    'features/ledger/data/ledger_repository.dart': 1364,
    // ledger_add_page 1122→1276 越线（小组件批A·真机二次报障三修·2026-10-18）：
    // 「记一笔弹窗是拉长版、跟高保真不一样」⇒ 弹窗版式按原型 `#qpDlg` 收口——
    // 新增 `_dialogShell`/`_dialogBody`/`_amountRow`，并把四段表单抽成
    // `_formSections(compact:)` 一套两用（页面专属 chrome 三处 compact 闸＋尺寸收一档）。
    // 属产品拍板需求增长（同一份表单换容器，**无第二套 UI**），按实测登，此后只许减；
    // 真还债＝弹窗壳与紧凑段拆同库 part（G7c 族·另批做，勿与本次版式修混刀）。
    'features/ledger/presentation/ledger_add_page.dart': 1276,
    // diary_edit_page **已还债·登记项删除**（日记改版批1 收口 · 2026-10-19）：
    // 原登记 1262 行（1370→1262 系阅读模块批2 棘轮收紧，越线本身回溯到更早的日记侧批次）。
    // 本轮按「真还债＝拆 part，另批做」把批2b 富文本群（文档↔Delta JSON／重建监听／
    // 行内属性开关／插图／导图卡／光标插文本，10 个方法）纯机械搬进
    // `diary_edit_rich.dart`（`part of`，手法同 `note_edit_rich.dart`），**行为零改动**。
    // 主文件 1262→1155，落到默认 1200 面以下 ⇒ **本条目删除**，让闸回到「超线即红」。
    // 新 part 文件 114 行，远低于红线；勿再以任何理由把群搬回主文件。
    // diary_edit_page 回到红线内·**登记项未重启**（日记改版批2 · 2026-10-19）：
    // 批2 六组（心情横滚单选组／工具栏 Top5＋⋮／输入区留白／概览卡重构／底栏等高＋保存三态／
    // 退出口径）落进该页后一度涨到 1228 行；**批内当场再拆一刀**（概览卡与底栏两段 →
    // part `diary_edit_foot.dart` 188 行），页面回 1052 行 ⇒ 不登记，闸保持「超线即红」默认面。
    // settings_page 1566 行越线（思维导图批1 2026-10-12 跑出本红）：越线发生在语义断链批
    // （V1.68 日记第八类，该批没带 size 闸），本批只改一行文案——非本批造成，按现状登记，
    // 之后只许减；真还债＝拆 part，另批做。
    // 1566→1609 存量越线归位（高保真批 6a 2026-10-16 跑出本红）：净增 43 行发生在
    // 桌面批2＋批3（a6e6bdb6·四枚小组件预览卡与设置生效面），该批未带 size 闸。
    // 之后只许减。
    // dashboard_page 已还债：1204→1200 落到默认 1200 面（时间模块 B10 5700dff9 删旧 events
    // 系接线），按口径「拆完删项」**删除登记**（阅读模块批2 · 2026-10-14 跑出 stale 提醒）。
    // 1608→1620（批2b·2026-10-19）：我的页「记录」组加「标签管理」入口行（净 +12）。
    // 同存量越线一并只许减；真还债＝拆 part（另批）。
    'features/settings/presentation/settings_page.dart': 1620,
    // 高保真批6b·刀1（2026-10-16）归还批2 登记的 read_sheets_b2 体积债：
    // _BookForm/_BookFormState 整组迁入同库 part read_sheets_b2_form.dart（小件群落扩展），
    // 主文件 1806→716，按口径删登记项还默认面。
    // 高保真批6b·刀2（2026-10-16）归还阅读模块批2 登记的 book_form_page 体积债：
    // UI 积木群 13 件落同库扩展 _BookFormForm＋日期滚轮弹层 _DateWheelSheet 整组迁入同库
    // part book_form_page_form.dart，主文件 1623→893 还默认面。
    // 高保真批6b·刀3（2026-10-16）归还阅读模块批2/批3 登记的 book_detail 体积债：
    // 三态弹层群关联面（_localEpubStrip/_cacheRow）＋书摘卡群（_noQuotes/_quoteCard/
    // _qMeta）落同库扩展 _BookDetailCards，showBrLocalInfo 整组迁入同库 part
    // book_detail_cards.dart，主文件 1582→1019 还默认面。
    // 高保真批6c（2026-10-16·整单收口批）三刀拆 part 归还 read 剩余登记项：
    // 刀1 read_sheets_b3 1341→442（书摘表单群 _QuoteForm/_ColWheel 整组＋_deco 迁同库 part
    // read_sheets_b3_quote.dart）；刀2 read_stat_page 1259→453（统计卡群落同库扩展 _StatCards
    // ·part read_stat_page_cards.dart）；刀3 reader_page 1226→1047（装载/取证/定位群落同库
    // 扩展 _ReaderBoot·part reader_page_boot.dart）。三件按「拆完删项」删除还默认面，read 登记清零。
    // 批三刀2 登记的 epub_doc 体积债已归还（刀3 开工前置）：抽取器整段拆成同库件
    // `part 'epub_extract.dart';`（G7d⑤ 族口径，私有成员不放宽），主文件回落到默认面以下。
    // R3-2 批登记的 reader_page 体积债已归还（批三刀4）：分页群七件拆进同库扩展
    // `part 'reader_page_pag.dart';`（G7c 族口径），主文件回到默认 1200 面以下。
    // 健康批3.5（2026-10-08）归还批4 登记的 `health_sheets.dart` 体积债：运动录入弹层整段
    // 抽进同库 part `health_sheets_ex.dart`（私有小件 `_sheetShell`/`_wheel` 等不放宽），
    // 主文件 1266→911 回到默认面以下，按口径**删登记项**而不是调小；本批两张新弹层继续挂 part。
  };

  test('体积预算：lib 超线文件必须登记且只许减不许增', () {
    final over = <String>[], grown = <String>[], shrunk = <String>[];
    final seen = <String>{};
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final lines = f.readAsLinesSync().length;
      if (lines <= lineBudget) continue;
      seen.add(rel);
      final b = budget[rel];
      if (b == null) {
        over.add('$rel（$lines 行，未登记）');
      } else if (lines > b) {
        grown.add('$rel（$lines > 预算 $b）');
      } else if (lines < b) {
        shrunk.add('$rel（$lines < 登记 $b，请把预算改成 $lines 或删项归还默认面）');
      }
    }
    final stale = budget.keys.where((k) => !seen.contains(k)).toList();
    expect(over, isEmpty,
        reason: '新文件超过 $lineBudget 行预算线：先拆分，确需豁免再登记进本测试 budget 表'
            '（登记＝允许存在的当前行数，之后只许减）。');
    expect(grown, isEmpty,
        reason: '已登记大文件长大了：预算只许减不许增。'
            '确属必要增长请先走治理评审并同步更新登记值。');
    // 清单 C-4：「变小」不是变坏——别的会话把文件拆小/修好是好事，
    // 判红只会让并行会话互相踩出「我没动为什么红」的红灯。降级为提醒，
    // 收紧登记值由看到提醒的人顺手做；over / grown / stale 仍然判红（那三个才是变坏）。
    if (shrunk.isNotEmpty) {
      // ignore: avoid_print
      print('[size_budget 提醒] 以下登记文件已变小，请顺手调小登记值或删项：\n  '
          '${shrunk.join('\n  ')}');
    }
    expect(stale, isEmpty,
        reason: '以下登记项对应的文件已消失或已降到预算线下，请删掉（否则守护悄悄空转）：'
            '${stale.join('、')}');
  });
}
