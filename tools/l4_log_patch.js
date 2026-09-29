/* L4 日志批 · 呵护 / 习惯 / 日记笔记 / 收集箱 补日志覆盖（只加日志，零行为改动）
   口径来源：docs/日志覆盖工单-20260929.md §三 L4 行（记录写入失败 · 打卡结算 · 清洗异常）
   用法：node tools/l4_log_patch.js
   护栏：逐条命中断言；登记文件与 1200 行边界文件（care/event_sheet、habit_detail、habit_stat、diary_edit）一律不动。 */
const fs = require("fs");

function load(F) {
  const s = fs.readFileSync(F, "utf8");
  const crlf = s.includes("\r\n");
  return { s, nl: (t) => (crlf ? t.replace(/\n/g, "\r\n") : t) };
}

let applied = 0;
function apply(edits) {
  let bad = 0;
  for (const [F, old0, new0, want] of edits) {
    if (!fs.existsSync(F)) { console.error("!! 文件不存在 " + F); process.exit(1); }
    const { s, nl } = load(F);
    const old_ = nl(old0), neu = nl(new0);
    const n = s.split(old_).length - 1;
    if (n !== want) {
      console.error("!! [" + F + "] 命中 " + n + " 次，期望 " + want + "\n   锚点首行：" + old0.split("\n")[0].trim().slice(0, 72));
      bad++; continue;
    }
    fs.writeFileSync(F, s.split(old_).join(neu));
    applied++;
    console.log("OK  " + F.replace(/^lib\/features\//, "") + "  +" + (neu.length - old_.length) + "B");
  }
  if (bad) { console.error("!! " + bad + " 条未命中"); process.exit(1); }
  console.log("完成：共应用 " + applied + " 处编辑");
}

const AL = "import '../../../core/logging/app_log.dart';\n";

apply([
  /* ================= 习惯 ================= */
  ["lib/features/habit/data/habit_repository.dart",
   "import '../../../core/database/schema.dart';\n",
   "import '../../../core/database/schema.dart';\n" + AL, 1],

  ["lib/features/habit/data/habit_repository.dart",
   "    final today = dayKey(DateTime.now());\n    if (day.compareTo(today) > 0) {\n      throw ArgumentError('未来日不可写入（时钟防护）：$day > $today');\n    }\n",
   "    final today = dayKey(DateTime.now());\n    if (day.compareTo(today) > 0) {\n      AppLog.add('习惯未来日写入被拒（时钟防护）：$day > $today',\n          level: LhLevel.warn);\n      throw ArgumentError('未来日不可写入（时钟防护）：$day > $today');\n    }\n", 1],

  ["lib/features/habit/data/habit_repository.dart",
   "    await _touchWatermark(day);\n    await recomputeStats(habitId);\n  }\n",
   "    await _touchWatermark(day);\n    final stats = await recomputeStats(habitId);\n    // 一次打卡＝一条留痕，且把结算值直接写进行文：事后不必再翻流水重算。\n    AppLog.addKey('习惯落账：$habitId · $day · checked=${checked ?? '不改'} '\n        'value=${clearValue ? '清空' : (value ?? '不改')} · origin=$origin '\n        '· 结算 streak=${stats.$1}/best=${stats.$2}');\n  }\n", 1],

  ["lib/features/habit/data/habit_repository.dart",
   "        whereArgs: [old.first['id']],\n      );\n    });\n    await recomputeStats(habitId);\n  }\n",
   "        whereArgs: [old.first['id']],\n      );\n    });\n    final stats = await recomputeStats(habitId);\n    AppLog.addKey('习惯撤销流水：$habitId · $day · 结算 streak=${stats.$1}/best=${stats.$2}');\n  }\n", 1],

  ["lib/features/habit/data/habit_repository.dart",
   "      'note': note,\n      'created_at': DateTime.now().millisecondsSinceEpoch,\n    });\n  }\n\n  /// 触发记录（新→旧）。\n",
   "      'note': note,\n      'created_at': DateTime.now().millisecondsSinceEpoch,\n    });\n    // 落账行已由 upsertEntry 出，这里只补「触发」这层语义（负向习惯的主数据）。\n    AppLog.addKey('习惯触发登记：$habitId · $day · 量=${amount ?? amountText ?? '-'} '\n        '原因=${reasons.join('/')}');\n  }\n\n  /// 触发记录（新→旧）。\n", 1],

  ["lib/features/habit/data/habit_repository.dart",
   "    });\n    await recomputeStats(h.id);\n  }\n\n  Future<List<String>> freezesOf(String habitId) async => [\n",
   "    });\n    final stats = await recomputeStats(h.id);\n    AppLog.addKey('习惯用宽限抵签：${h.id} · $day · frozen 只保连续不算达成 '\n        '· 结算 streak=${stats.$1}/best=${stats.$2}');\n  }\n\n  Future<List<String>> freezesOf(String habitId) async => [\n", 1],

  ["lib/features/habit/data/habit_repository.dart",
   "      checkAt: at == null\n          ? null\n          : _hhmm(DateTime.fromMillisecondsSinceEpoch(at)),\n    );\n  }\n",
   "      checkAt: at == null\n          ? null\n          : _hhmm(DateTime.fromMillisecondsSinceEpoch(at)),\n    );\n    AppLog.addKey('习惯待确认达成入账：pend#${p['id']} · ${p['habit_id']} · '\n        '${p['day']} · 来源=${p['src']}（落账行随后）');\n  }\n", 1],

  /* ================= 呵护 ================= */
  ["lib/features/care/data/care_repository.dart",
   "import '../../../core/database/schema.dart';\n",
   "import '../../../core/database/schema.dart';\n" + AL, 1],

  ["lib/features/care/data/care_repository.dart",
   "      await tx.delete(DbSchema.tCareBabies, where: 'id = ?', whereArgs: [id]);\n    });\n",
   "      await tx.delete(DbSchema.tCareBabies, where: 'id = ?', whereArgs: [id]);\n    });\n    // 删档是不可逆的级联清理，必须留一条「删了谁」的硬证据。\n    AppLog.addKey('呵护删档级联清理：宝宝 #$id（记录/测量/疫苗/里程碑/过敏 + 档案行）');\n", 1],

  ["lib/features/care/data/care_repository.dart",
   "  Future<int> addLog(CareRecord r) =>\n      db.insert(DbSchema.tCareLogs, r.toRow());\n",
   "  Future<int> addLog(CareRecord r) async {\n    final id = await db.insert(DbSchema.tCareLogs, r.toRow());\n    AppLog.addKey('呵护记录落库：#$id 宝宝 ${r.babyId} · ${r.day} · 事件 ${r.k}');\n    return id;\n  }\n", 1],

  ["lib/features/care/data/care_repository.dart",
   "      return true;\n    } catch (_) {\n      return false;\n    }\n",
   "      return true;\n    } catch (e) {\n      // 同宝宝同食物唯一：重名会走到这里，UI 只提示一次，库里查不到就靠这条。\n      AppLog.add('呵护过敏项未写入（重名或异常）：$food · $e', level: LhLevel.warn);\n      return false;\n    }\n", 1],

  /* ================= 日记 / 笔记 ================= */
  ["lib/features/journal/domain/journal_repository.dart",
   "import 'dart:convert';\n\nimport '../data/journal_dao.dart';\n",
   "import 'dart:convert';\n\n" + AL + "import '../data/journal_dao.dart';\n", 1],

  ["lib/features/journal/domain/journal_repository.dart",
   "  Future<JournalEntry> save(JournalEntry e) async {\n    final now = DateTime.now();\n",
   "  Future<JournalEntry> save(JournalEntry e) async {\n    final now = DateTime.now();\n    // 编辑页每次手动保存都会走这里（自动保存不写库），频率可控。\n    AppLog.addKey('日记保存落库：${e.id == null ? '新增一篇' : '更新 #${e.id}'} · '\n        '日 ${e.day.toString().substring(0, 10)} · 结构化=${e.structured}');\n", 1],

  ["lib/features/journal/domain/journal_repository.dart",
   "  Future<void> remove(int id) => dao.remove(id);\n\n  Future<void> removeAll(Iterable<int> ids) async {\n    for (final id in ids) {\n      await dao.remove(id);\n    }\n  }\n",
   "  Future<void> remove(int id) async {\n    await dao.remove(id);\n    AppLog.addKey('日记删除单篇：#$id');\n  }\n\n  Future<void> removeAll(Iterable<int> ids) async {\n    for (final id in ids) {\n      await dao.remove(id);\n    }\n    AppLog.addKey('日记批量删除：${ids.length} 篇（${ids.join('/')}）');\n  }\n", 1],

  ["lib/features/journal/domain/journal_entry.dart",
   "import 'dart:convert';\n\nimport 'note.dart';\n",
   "import 'dart:convert';\n\n" + AL + "import 'note.dart';\n", 1],

  ["lib/features/journal/domain/journal_entry.dart",
   "      } catch (_) {/* 非 JSON 回退语法扫描 */}\n",
   "      } catch (err) {\n        // 解不开就按 Markdown 扫：图片引用可能漏判，「图片没进回收站」类问题看这条。\n        AppLog.add('日记正文非 quill JSON，回退语法扫描：$err',\n            level: LhLevel.warn);\n      }\n", 1],

  ["lib/features/journal/domain/journal_entry.dart",
   "    } catch (_) {\n      return raw.split(',').where((e) => e.isNotEmpty).toList();\n    }\n",
   "    } catch (err) {\n      AppLog.add('日记标签非 JSON，按逗号拆分兜底：$err', level: LhLevel.warn);\n      return raw.split(',').where((e) => e.isNotEmpty).toList();\n    }\n", 1],

  ["lib/features/journal/domain/note.dart",
   "import 'dart:convert';\n\n/// 模块3 笔记条目",
   "import 'dart:convert';\n\n" + AL + "\n/// 模块3 笔记条目", 1],

  ["lib/features/journal/domain/note.dart",
   "      return sb.toString();\n    } catch (_) {\n      return content;\n    }\n",
   "      return sb.toString();\n    } catch (err) {\n      AppLog.add('笔记正文非 quill JSON，摘要回退原文：$err', level: LhLevel.warn);\n      return content;\n    }\n", 1],

  ["lib/features/journal/presentation/widgets/note_sheets.dart",
   "import '../../../../core/providers.dart';\n",
   "import '../../../../core/logging/app_log.dart';\nimport '../../../../core/providers.dart';\n", 1],

  ["lib/features/journal/presentation/widgets/note_sheets.dart",
   "  } catch (_) {\n    if (context.mounted) AppToast.show(context, '生成图片失败 · 请重试');\n",
   "  } catch (err) {\n    AppLog.add('笔记图片卡片生成失败：$err', level: LhLevel.error);\n    if (context.mounted) AppToast.show(context, '生成图片失败 · 请重试');\n", 1],

  ["lib/features/journal/presentation/widgets/note_sheets.dart",
   "  } catch (_) {\n    if (pageCtx.mounted) AppToast.show(pageCtx, '导出失败 · 请重试');\n",
   "  } catch (err) {\n    AppLog.add('笔记导出失败（$ext）：$err', level: LhLevel.error);\n    if (pageCtx.mounted) AppToast.show(pageCtx, '导出失败 · 请重试');\n", 1],

  /* ================= 收集箱 ================= */
  ["lib/features/inbox/presentation/inbox_page.dart",
   "import '../../../core/ai/ai_review.dart';\n",
   "import '../../../core/ai/ai_review.dart';\n" + AL, 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "        ref.invalidate(todosProvider);\n        _toast('✅ 已转为待办（重要不紧急）· 可在四象限改判');\n",
   "        ref.invalidate(todosProvider);\n        AppLog.addKey('收集箱分流→待办：#${t.id} 「${_brief(src)}」（原条 #${item.id}）');\n        _toast('✅ 已转为待办（重要不紧急）· 可在四象限改判');\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "        ref.invalidate(journalsProvider);\n        _toast('📔 已插入今晚日记草稿');\n",
   "        ref.invalidate(journalsProvider);\n        AppLog.addKey('收集箱分流→今晚日记：#${saved.id}（原条 #${item.id}）');\n        _toast('📔 已插入今晚日记草稿');\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "        await dao.route(item.id!, 'note', id);\n        _toast('📝 已存为笔记（编辑器 M1 开放）');\n",
   "        await dao.route(item.id!, 'note', id);\n        AppLog.addKey('收集箱分流→笔记：#$id（原条 #${item.id}）');\n        _toast('📝 已存为笔记（编辑器 M1 开放）');\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "        if (books.isEmpty) {\n          _toast('书架还没有书 · 先去阅读书架添加一本书');\n          return;\n        }\n",
   "        if (books.isEmpty) {\n          AppLog.add('收集箱分流→摘录被拒：书架无在读书目', level: LhLevel.warn);\n          _toast('书架还没有书 · 先去阅读书架添加一本书');\n          return;\n        }\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "        if (qid == null) {\n          _toast('这条摘录已存在 · 未重复入账');\n          return;\n        }\n",
   "        if (qid == null) {\n          AppLog.add('收集箱分流→摘录未入账（同书同句已存在）', level: LhLevel.warn);\n          _toast('这条摘录已存在 · 未重复入账');\n          return;\n        }\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "        _toast('已存为阅读摘录（联动 L6）');\n        return;\n    }\n",
   "        AppLog.addKey('收集箱分流→阅读摘录：#$qid · 书 $picked（原条 #${item.id}）');\n        _toast('已存为阅读摘录（联动 L6）');\n        return;\n    }\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "  Future<void> _dismiss(InboxItem item) async {\n    await ref.read(inboxDaoProvider).remove(item.id!);\n    ref.invalidate(inboxItemsProvider);\n",
   "  Future<void> _dismiss(InboxItem item) async {\n    await ref.read(inboxDaoProvider).remove(item.id!);\n    ref.invalidate(inboxItemsProvider);\n    // 未落任何模块就删掉＝原文只存在于这一条里，事后想查必须有痕迹。\n    AppLog.addKey('收集箱条目直接删除：#${item.id} 「${_brief(item.rawText)}」');\n", 1],

  ["lib/features/inbox/presentation/inbox_page.dart",
   "  Future<void> _triage(InboxItem item, String target, {String? text}) async {\n",
   "  /// 日志用摘要：只取前 16 字，避免整段原文进环形缓冲。\n  static String _brief(String s) =>\n      s.replaceAll(RegExp(r'\\s+'), ' ').length > 16\n          ? '${s.replaceAll(RegExp(r'\\s+'), ' ').substring(0, 16)}…'\n          : s.replaceAll(RegExp(r'\\s+'), ' ');\n\n  Future<void> _triage(InboxItem item, String target, {String? text}) async {\n", 1],
]);
