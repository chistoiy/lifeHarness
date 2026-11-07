import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/database/schema.dart';
import '../../features/care/data/care_repository.dart';
import '../../features/care/domain/care_events.dart';

/// 母婴呵护 ⇄ 其他模块 挂载出口（**批1b 新建**：此前本模块无 `*_mounts.dart`）。
///
/// 先例＝`habit_mounts.dart` / `read_mounts.dart`：跨模块读母婴数据一律经本文件，
/// 消费方（如 `features/nfc/**`）**禁 import `features/care/**`**（架构守护 R1）。
///
/// 当前唯一消费方＝NFC 卡片批1b 的「呵护宝宝」目标选择器：一级＝宝宝档案、
/// 二级＝记录类型。后续别的模块要读母婴数据，请在本文件加函数，勿各自直连表。

/// 一个宝宝档案（一级选择项）。
class MaternityBabyOption {
  const MaternityBabyOption({required this.id, required this.name});

  final int id;
  final String name;
}

/// 宝宝档案列表（同源母婴模块 `CareRepository.babies()`，按 id 升序）。
///
/// 删档＝母婴侧**级联真删**（`deleteBaby` 清八类分档数据），故这里查不到的行
/// 就是真失效——绑了该宝宝的卡会被判「已失效」。
Future<List<MaternityBabyOption>> maternityBabyOptions([Database? db]) async {
  final repo = CareRepository(db ?? AppDatabase.instance.db);
  final list = await repo.babies();
  return [
    for (final b in list) MaternityBabyOption(id: b.id, name: b.name.trim()),
  ];
}

/// 某宝宝档案是否还在（NFC「呵护宝宝」目标失效判据）。
Future<bool> maternityBabyExists(int babyId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tCareBabies,
      columns: ['id'], where: 'id = ?', whereArgs: [babyId], limit: 1);
  return rows.isNotEmpty;
}

/// 一个记录类型（二级选择项）。
class CareKindOption {
  const CareKindOption({required this.id, required this.name});

  /// 记录类型键（＝`care_logs.k` 列的值，如 `nurse`／`sleep`／`diaper`）。
  final String id;
  final String name;
}

/// 记录类型列表（**内置 12 类**，同源母婴模块事件注册表）。
///
/// 口径：`kBuiltinEvents` 按 `kEventBaseKeys` 序，**剔掉 `custom`**——`custom`
/// 是「自定义」占位定义（真自定义记录类型在 `care_custom_events` 表里，键形如
/// `cus:名`，不是一条可绑定的固定类型）。同口径先例＝`care_stats_page.dart`
/// （统计页同样 `kEventBaseKeys.where((k) => k != 'custom')`）。
///
/// 纯函数（零 IO）：类型表是编译期常量，选择器不必为它查库。
List<CareKindOption> maternityCareKindOptions() => [
      for (final k in kEventBaseKeys)
        if (k != 'custom')
          CareKindOption(id: k, name: kBuiltinEvents[k]?.name ?? k),
    ];

/// 某记录类型是否为已知内置类型。
bool maternityCareKindExists(String kindId) =>
    kindId != 'custom' && kBuiltinEvents.containsKey(kindId);

/// 记录类型的显示名（查不到回落键本身——**不猜、不显示空串**）。
String? maternityCareKindName(String kindId) {
  if (!maternityCareKindExists(kindId)) return null;
  final def = kBuiltinEvents[kindId];
  return def == null ? kindId : def.name;
}
