import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/logging/app_log.dart';
import '../domain/care_events.dart';
import '../domain/care_models.dart';
import '../domain/cycle_calc.dart';

/// 呵护模块仓储（交接 §3/§5 红线口径）。
///
/// 硬约束：
/// - 所有宝宝维度读写一律带 baby_id 条件；删档走单事务级联清理
///   （替代原型 shiftDict 字典重排，历史数据不留孤儿）；
/// - 自定义事件改名=键迁移：同事务回写 care_custom_events.key 与 care_logs.k
///   与 care_event_order.key（红线 8）；
/// - 记录展示文本不落库；量/起止二次编辑直接改行（决策 4）；
/// - 配置键一律 `care.` 前缀落 settings 表 KV（先例 habit.*/ledger.*），
///   其中 `care.syncExcluded`＝模块级 WebDAV 同步排除（红线 7，默认开）。
class CareRepository {
  CareRepository(this.db);

  final Database db;

  // ==================== 设置 KV ====================

  Future<String?> kv(String key) async {
    final rows = await db.query(DbSchema.tSettings,
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
        DbSchema.tSettings,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<int> kvInt(String key, int def) async =>
      int.tryParse(await kv(key) ?? '') ?? def;
  Future<void> setKvInt(String key, int v) => setKv(key, '$v');

  Future<bool> kvBool(String key, bool def) async {
    final v = await kv(key);
    return v == null ? def : v == 'true';
  }

  Future<void> setKvBool(String key, bool v) => setKv(key, v ? 'true' : 'false');

  /// 红线 7：周期/母婴数据默认排除 WebDAV 同步（模块级，默认开）。
  Future<bool> syncExcluded() async => kvBool('care.syncExcluded', true);
  Future<void> setSyncExcluded(bool v) => setKvBool('care.syncExcluded', v);

  /// 全部 care.rm.* 提醒开关/选项 KV（p-careRemind 一次取齐）。
  Future<Map<String, String>> reminderKvs() async {
    final rows = await db.rawQuery(
        "SELECT key, value FROM ${DbSchema.tSettings} WHERE key LIKE 'care.rm.%'");
    return {for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')};
  }

  // ==================== 宝宝档案 ====================

  Future<List<CareBaby>> babies() async {
    final rows = await db.query(DbSchema.tCareBabies, orderBy: 'id ASC');
    return rows.map(CareBaby.fromRow).toList();
  }

  Future<int> addBaby({
    required String name,
    required String sex,
    required String birth,
    required String color,
    String avatar = '🍼',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert(DbSchema.tCareBabies, {
      'name': name,
      'sex': sex,
      'birth': birth,
      'color': color,
      'avatar': avatar,
      'created_at': now,
      'updated_at': now,
    });
    await setKv('care.curBaby', '$id'); // 建档即切换（原型 saveBabyProfile→switchBaby）
    return id;
  }

  Future<void> updateBaby(CareBaby b) => db.update(
        DbSchema.tCareBabies,
        {
          'name': b.name,
          'sex': b.sex,
          'birth': careDayKey(b.birth),
          'color': b.color,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [b.id],
      );

  /// 删除档案：单事务级联清理八类分档数据（记录/测量/疫苗/里程碑/过敏史），
  /// 并把当前档回落到相邻档案（决策 11「落相邻档」）。
  Future<void> deleteBaby(int id) async {
    await db.transaction((tx) async {
      for (final t in [
        DbSchema.tCareLogs,
        DbSchema.tCareMeasures,
        DbSchema.tCareVaccines,
        DbSchema.tCareMilestones,
        DbSchema.tCareAllergies,
      ]) {
        await tx.delete(t, where: 'baby_id = ?', whereArgs: [id]);
      }
      await tx.delete(DbSchema.tCareBabies, where: 'id = ?', whereArgs: [id]);
    });
    // 删档是不可逆的级联清理，必须留一条「删了谁」的硬证据。
    AppLog.addKey('呵护删档级联清理：宝宝 #$id（记录/测量/疫苗/里程碑/过敏 + 档案行）');
    final cur = await kvInt('care.curBaby', 0);
    if (cur == id) {
      final rest = await babies();
      if (rest.isEmpty) {
        await setKv('care.curBaby', '');
      } else {
        await setKv('care.curBaby', '${rest.first.id}');
      }
    }
  }

  Future<int?> curBabyId() async {
    final raw = int.tryParse(await kv('care.curBaby') ?? '');
    if (raw != null &&
        (await db.query(DbSchema.tCareBabies,
                where: 'id = ?', whereArgs: [raw], limit: 1))
            .isNotEmpty) {
      return raw;
    }
    final first = await babies();
    return first.isEmpty ? null : first.first.id;
  }

  Future<void> setCurBaby(int id) => setKv('care.curBaby', '$id');

  /// 每宝宝累计记录数（档案卡「累计 N 条记录」）。
  Future<Map<int, int>> logCountsByBaby() async {
    final rows = await db.rawQuery(
        'SELECT baby_id, COUNT(*) c FROM ${DbSchema.tCareLogs} GROUP BY baby_id');
    return {for (final r in rows) r['baby_id']! as int: r['c']! as int};
  }

  // ==================== 记录人 ====================

  Future<List<CareCarer>> carers() async {
    final rows = await db.query(DbSchema.tCareCarers, orderBy: 'sort ASC, id ASC');
    return rows.map(CareCarer.fromRow).toList();
  }

  Future<String> curCarer() async {
    final name = await kv('care.curCarer');
    final list = await carers();
    if (name != null && list.any((c) => c.name == name)) return name;
    return list.isEmpty ? '妈妈' : list.first.name;
  }

  Future<void> setCurCarer(String name) => setKv('care.curCarer', name);

  /// 新增身份（重名拦截由 UI 层守卫后调用；返回 false=重名未写）。
  Future<bool> addCarer(String name) async {
    final exists = (await carers()).any((c) => c.name == name);
    if (exists) return false;
    final list = await carers();
    await db.insert(DbSchema.tCareCarers,
        {'name': name, 'sort': (list.isEmpty ? 0 : list.last.id) + 1});
    await setCurCarer(name); // 新增即设为默认记录人（原型行为）
    return true;
  }

  /// 改名（历史署名保留＝不改 care_logs.rec，仅提示文案差异 · 决策 11）。
  Future<bool> renameCarer(int id, String name) async {
    final list = await carers();
    if (list.any((c) => c.name == name && c.id != id)) return false;
    final old = list.firstWhere((c) => c.id == id);
    await db.update(DbSchema.tCareCarers, {'name': name},
        where: 'id = ?', whereArgs: [id]);
    if (await kv('care.curCarer') == old.name) await setCurCarer(name);
    return true;
  }

  /// 删除身份：至少保留 1；删中默认自动回落首个；历史署名保留。
  Future<String?> delCarer(int id) async {
    final list = await carers();
    if (list.length <= 1) return null;
    final old = list.firstWhere((c) => c.id == id);
    await db.delete(DbSchema.tCareCarers, where: 'id = ?', whereArgs: [id]);
    if (await kv('care.curCarer') == old.name) {
      await setCurCarer(list.firstWhere((c) => c.id != id).name);
    }
    return old.name;
  }

  // ==================== 事件体系（顺序 + 自定义） ====================

  /// 速记区顺序：库内行 + 补齐缺失键（内置/自定义新增自动入列尾）。
  Future<List<String>> evOrder(Map<String, CareCustomEvent> customs) async {
    final rows =
        await db.query(DbSchema.tCareEventOrder, orderBy: 'sort ASC, key ASC');
    final keys = rows.map((r) => r['key']! as String).toList();
    final valid = <String>[
      for (final k in keys)
        if (kBuiltinEvents.containsKey(k) || customs.containsKey(k)) k,
    ];
    final missing = [
      ...kEventBaseKeys.where((k) => !valid.contains(k)),
      ...customs.keys.where((k) => !valid.contains(k)),
    ];
    return [...valid, ...missing];
  }

  Future<void> saveEvOrder(List<String> order) async {
    await db.transaction((tx) async {
      await tx.delete(DbSchema.tCareEventOrder);
      for (var i = 0; i < order.length; i++) {
        await tx.insert(DbSchema.tCareEventOrder, {'key': order[i], 'sort': i});
      }
    });
  }

  Future<Map<String, CareCustomEvent>> customEvents() async {
    final rows = await db.query(DbSchema.tCareCustomEvents);
    return {
      for (final r in rows) r['key']! as String: CareCustomEvent.fromRow(r),
    };
  }

  /// 新建自定义事件（重名返回 false）。
  Future<bool> addCustomEvent(String name, String icon, String unit) async {
    final key = 'cus:$name';
    final exists = (await db.query(DbSchema.tCareCustomEvents,
            where: 'key = ?', whereArgs: [key], limit: 1))
        .isNotEmpty;
    if (exists) return false;
    await db.insert(DbSchema.tCareCustomEvents,
        {'key': key, 'name': name, 'icon': icon, 'unit': unit});
    return true;
  }

  /// 改名＝键迁移（同事务回写记录与顺序表）；新名冲突返回 false。
  Future<bool> renameCustomEvent(
      String oldKey, String name, String icon, String unit) async {
    final newKey = 'cus:$name';
    if (newKey != oldKey) {
      final clash = (await db.query(DbSchema.tCareCustomEvents,
              where: 'key = ?', whereArgs: [newKey], limit: 1))
          .isNotEmpty;
      if (clash) return false;
    }
    await db.transaction((tx) async {
      await tx.rawUpdate(
          'UPDATE ${DbSchema.tCareCustomEvents} SET key=?, name=?, icon=?, unit=? WHERE key=?',
          [newKey, name, icon, unit, oldKey]);
      await tx.rawUpdate(
          'UPDATE ${DbSchema.tCareLogs} SET k=? WHERE k=?', [newKey, oldKey]);
      await tx.rawUpdate(
          'UPDATE ${DbSchema.tCareEventOrder} SET key=? WHERE key=?',
          [newKey, oldKey]);
    });
    return true;
  }

  /// 换图标/单位（不改名）。
  Future<void> updateCustomEvent(
      String key, String name, String icon, String unit) async {
    await db.update(DbSchema.tCareCustomEvents,
        {'name': name, 'icon': icon, 'unit': unit},
        where: 'key = ?', whereArgs: [key]);
  }

  Future<void> delCustomEvent(String key) async {
    await db.delete(DbSchema.tCareCustomEvents, where: 'key = ?', whereArgs: [key]);
    await db.delete(DbSchema.tCareEventOrder, where: 'key = ?', whereArgs: [key]);
  }

  // ==================== 事件记录 ====================

  Future<List<CareRecord>> logs(int babyId) async {
    final rows = await db.query(DbSchema.tCareLogs,
        where: 'baby_id = ?', whereArgs: [babyId], orderBy: 'day DESC, s ASC, id ASC');
    return rows.map(CareRecord.fromRow).toList();
  }

  Future<int> addLog(CareRecord r) async {
    final id = await db.insert(DbSchema.tCareLogs, r.toRow());
    AppLog.addKey('呵护记录落库：#$id 宝宝 ${r.babyId} · ${r.day} · 事件 ${r.k}');
    return id;
  }

  Future<void> updateLog(CareRecord r) async {
    final row = r.toRow()..remove('created_at')..remove('baby_id');
    await db.update(DbSchema.tCareLogs, row, where: 'id = ?', whereArgs: [r.id]);
  }

  Future<void> delLog(int id) =>
      db.delete(DbSchema.tCareLogs, where: 'id = ?', whereArgs: [id]);

  // ==================== 周期 ====================

  Future<Map<String, CycleDay>> cycleDays() async {
    final rows = await db.query(DbSchema.tCareCycleDays);
    return {
      for (final r in rows) r['day']! as String: CycleDay.fromRow(r),
    };
  }

  /// 日记录保存（sheetCycleDay）。state=p1 时触发重新预测：
  /// 旧预测行置 superseded 存档 + 写入新预测行（红线「保留旧预测存档」）。
  Future<void> saveCycleDay(CycleDay d) async {
    await db.insert(
        DbSchema.tCareCycleDays, d.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (d.state == 'p1') await refreshPrediction();
  }

  Future<void> deleteCycleDay(String day) =>
      db.delete(DbSchema.tCareCycleDays, where: 'day = ?', whereArgs: [day]);

  Future<List<CyclePred>> predictions() async {
    final rows = await db.query(DbSchema.tCareCyclePred,
        orderBy: 'made_at DESC', limit: 20);
    return rows.map(CyclePred.fromRow).toList();
  }

  /// 重算并存档预测（当前生效预测=最大 made_at 未 superseded 行）。
  Future<void> refreshPrediction() async {
    final days = await cycleDays();
    final runs = periodRuns(days);
    final now = DateTime.now();
    final last = runs.isEmpty ? null : runs.last;
    final len = (avgCycleLen(runs) ?? 28).round();
    await db.update(DbSchema.tCareCyclePred, {'superseded': 1},
        where: 'superseded = 0');
    if (last == null) return;
    final next = last.start.add(Duration(days: len));
    final ov = next.subtract(const Duration(days: 14));
    await db.insert(DbSchema.tCareCyclePred, {
      'next_start': careDayKey(next),
      'ov_day': careDayKey(ov),
      'made_at': now.millisecondsSinceEpoch,
      'superseded': 0,
    });
  }

  /// 当前生效预测（无存档则按规则即时推导，不落库）。
  Future<CyclePred?> currentPrediction() async {
    final rows = await db.query(DbSchema.tCareCyclePred,
        where: 'superseded = 0', orderBy: 'made_at DESC', limit: 1);
    if (rows.isNotEmpty) return CyclePred.fromRow(rows.first);
    final days = await cycleDays();
    final runs = periodRuns(days);
    if (runs.isEmpty) return null;
    final len = (avgCycleLen(runs) ?? 28).round();
    final next = runs.last.start.add(Duration(days: len));
    return CyclePred(
      nextStart: next,
      ovDay: next.subtract(const Duration(days: 14)),
      madeAt: 0,
    );
  }

  /// 今日感受保存（p-care 卡）：并入日记录行（syms/note）。
  Future<void> saveTodaySymptoms(DateTime day, List<String> syms, String note) async {
    final key = careDayKey(day);
    final existing = await db.query(DbSchema.tCareCycleDays,
        where: 'day = ?', whereArgs: [key], limit: 1);
    final base =
        existing.isEmpty ? CycleDay(day: key) : CycleDay.fromRow(existing.first);
    await db.insert(
        DbSchema.tCareCycleDays,
        CycleDay(
          day: key,
          state: base.state,
          flow: base.flow,
          temp: base.temp,
          ovu: base.ovu,
          syms: syms,
          note: note.isEmpty ? null : note,
        ).toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== 测量 / 疫苗 / 里程碑 / 过敏 ====================

  Future<List<CareMeasure>> measures(int babyId) async {
    final rows = await db.query(DbSchema.tCareMeasures,
        where: 'baby_id = ?', whereArgs: [babyId], orderBy: 'day DESC, id DESC');
    return rows.map(CareMeasure.fromRow).toList();
  }

  Future<int> addMeasure(CareMeasure m) =>
      db.insert(DbSchema.tCareMeasures, m.toRow());

  Future<void> updateMeasure(CareMeasure m) => db.update(
        DbSchema.tCareMeasures,
        {'w': m.w, 'h': m.h, 'head': m.head, 'rec': m.rec},
        where: 'id = ?',
        whereArgs: [m.id],
      );

  Future<void> delMeasure(int id) =>
      db.delete(DbSchema.tCareMeasures, where: 'id = ?', whereArgs: [id]);

  Future<List<CareVaccine>> vaccines(int babyId) async {
    final rows = await db.query(DbSchema.tCareVaccines,
        where: 'baby_id = ?', whereArgs: [babyId], orderBy: 'due ASC');
    return rows.map(CareVaccine.fromRow).toList();
  }

  Future<int> addVaccine(CareVaccine v) =>
      db.insert(DbSchema.tCareVaccines, v.toRow());

  Future<void> updateVaccine(CareVaccine v) => db.update(
        DbSchema.tCareVaccines,
        {
          'name': v.name,
          'dose': v.dose,
          'due': v.due,
          'kind': v.kind,
          'lead': v.lead,
          'done_day': v.doneDay,
        },
        where: 'id = ?',
        whereArgs: [v.id],
      );

  Future<void> delVaccine(int id) =>
      db.delete(DbSchema.tCareVaccines, where: 'id = ?', whereArgs: [id]);

  Future<List<CareMilestone>> milestones(int babyId) async {
    final rows = await db.query(DbSchema.tCareMilestones,
        where: 'baby_id = ?', whereArgs: [babyId], orderBy: 'id ASC');
    return rows.map(CareMilestone.fromRow).toList();
  }

  Future<int> addMilestone(CareMilestone m) =>
      db.insert(DbSchema.tCareMilestones, m.toRow());

  Future<void> updateMilestone(CareMilestone m) => db.update(
        DbSchema.tCareMilestones,
        {'name': m.name, 'cat': m.cat, 'day': m.day, 'done': m.done ? 1 : 0},
        where: 'id = ?',
        whereArgs: [m.id],
      );

  Future<void> delMilestone(int id) =>
      db.delete(DbSchema.tCareMilestones, where: 'id = ?', whereArgs: [id]);

  Future<List<CareAllergy>> allergies(int babyId) async {
    final rows = await db.query(DbSchema.tCareAllergies,
        where: 'baby_id = ?', whereArgs: [babyId], orderBy: 'id ASC');
    return rows.map(CareAllergy.fromRow).toList();
  }

  /// 添加过敏食物（同宝宝同食物唯一；已有返回 false）。
  Future<bool> addAllergy(int babyId, String food, String? reaction) async {
    try {
      await db.insert(DbSchema.tCareAllergies, {
        'baby_id': babyId,
        'food': food,
        'reaction': reaction,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      // 同宝宝同食物唯一：重名会走到这里，UI 只提示一次，库里查不到就靠这条。
      AppLog.add('呵护过敏项未写入（重名或异常）：$food · $e', level: LhLevel.warn);
      return false;
    }
  }

  Future<void> delAllergy(int id) =>
      db.delete(DbSchema.tCareAllergies, where: 'id = ?', whereArgs: [id]);

  // ==================== 一帧快照 ====================

  /// 一次取齐（CarePage 与各弹层共用；写库后 careTouch 失效重取）。
  Future<CareData> loadAll() async {
    final babies = await this.babies();
    final curId = await curBabyId();
    final carers = await this.carers();
    final curCarer = await this.curCarer();
    final customs = await customEvents();
    final order = await evOrder(customs);
    final cycleDays = await this.cycleDays();
    final currentBaby =
        babies.where((b) => b.id == curId).firstOrNull;
    final logs = currentBaby == null ? const <CareRecord>[] : await this.logs(currentBaby.id);
    final allergies = currentBaby == null
        ? const <CareAllergy>[]
        : await this.allergies(currentBaby.id);
    final measures = currentBaby == null
        ? const <CareMeasure>[]
        : await this.measures(currentBaby.id);
    final vaccines = currentBaby == null
        ? const <CareVaccine>[]
        : await this.vaccines(currentBaby.id);
    final miles = currentBaby == null
        ? const <CareMilestone>[]
        : await milestones(currentBaby.id);
    return CareData(
      babies: babies,
      currentBaby: currentBaby,
      carers: carers,
      curCarer: curCarer,
      evOrder: order,
      customs: customs,
      logs: logs,
      allergies: allergies,
      measures: measures,
      vaccines: vaccines,
      milestones: miles,
      cycleDays: cycleDays,
      syncExcluded: await syncExcluded(),
      reminders: await reminderKvs(),
      logCounts: await logCountsByBaby(),
      evIcons: const {},
    );
  }
}

/// 一帧呵护域数据（主页两侧 + 各弹层共用一次取齐）。
class CareData {
  const CareData({
    required this.babies,
    required this.currentBaby,
    required this.carers,
    required this.curCarer,
    required this.evOrder,
    required this.customs,
    required this.logs,
    required this.allergies,
    required this.measures,
    required this.vaccines,
    required this.milestones,
    required this.cycleDays,
    required this.syncExcluded,
    required this.reminders,
    required this.logCounts,
    required this.evIcons,
  });

  final List<CareBaby> babies;
  final CareBaby? currentBaby;
  final List<CareCarer> carers;
  final String curCarer;
  final List<String> evOrder;
  final Map<String, CareCustomEvent> customs;

  /// 当前宝宝记录：day DESC, s ASC。
  final List<CareRecord> logs;
  final List<CareAllergy> allergies;
  final List<CareMeasure> measures;
  final List<CareVaccine> vaccines;
  final List<CareMilestone> milestones;
  final Map<String, CycleDay> cycleDays;
  final bool syncExcluded;
  final Map<String, String> reminders;
  final Map<int, int> logCounts;

  /// 预留：事件图标覆盖（当前图标存注册表/自定义表内，恒空）。
  final Map<String, String> evIcons;

  /// 按日分组（日键降序；日内 s ASC 原序保留）。
  Map<String, List<CareRecord>> get logsByDay {
    final m = <String, List<CareRecord>>{};
    for (final r in logs) {
      (m[r.day] ??= []).add(r);
    }
    return m;
  }

  List<CareRecord> logsOfDay(String day) => logs.where((r) => r.day == day).toList();

  /// 记录展示辅助：解析事件键→定义（含自定义）。
  EvDef evOf(String key) => resolveEv(key, customs);

  String titleOf(CareRecord r) => careLogTitle(r, customs);

  String iconOf(CareRecord r) => careIconOf(r);

  /// 今日列表计数（p-baby「今日 · N 条」）。
  int get todayCount => logsOfDay(careDayKey(DateTime.now())).length;
}
