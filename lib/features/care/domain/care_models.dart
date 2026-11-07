/// 呵护（母婴）领域模型（交接 §3 数据模型口径）。
///
/// 红线：展示文本/图标一律由数据在应用层生成（见 care_format.dart），
/// 记录不落展示串；所有宝宝维度数据带 babyId 分档。
library;

import 'dart:convert';

/// 自然日 'YYYY-MM-DD'（D13 日界线 00:00，同 habit 模块口径）。
String careDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int careT2m(String t) {
  final p = t.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
}

String careM2t(int m) {
  final mm = ((m % 1440) + 1440) % 1440;
  return '${(mm ~/ 60).toString().padLeft(2, '0')}:${(mm % 60).toString().padLeft(2, '0')}';
}

/// 时长人性化：>=60 → '1h30′'/'2h'，否则 '45min'（原型 hms 同构）。
String careHms(int v) =>
    v >= 60 ? ('${v ~/ 60}h${v % 60 != 0 ? '${v % 60}′' : ''}') : '${v}min';

/// 年龄文案（原型 babyAgeStr 同构：≥12 月按「岁+月」，否则「M 个月 D 天」）。
String careAgeText(DateTime birth, DateTime t) {
  var mo = (t.year - birth.year) * 12 + t.month - birth.month;
  var dd = t.day - birth.day;
  if (dd < 0) {
    mo--;
    dd += DateTime(t.year, t.month, 0).day;
  }
  if (mo < 0) return '未出生';
  return mo >= 12
      ? '${mo ~/ 12} 岁 ${mo % 12} 个月'
      : '${mo > 0 ? '$mo 个月 ' : ''}$dd 天';
}

/// 月龄（小数，如 8.4 = 8 个月 12 天）。
double careAgeMonths(DateTime birth, DateTime at) {
  var mo = (at.year - birth.year) * 12 + at.month - birth.month;
  var dd = at.day - birth.day;
  if (dd < 0) {
    mo--;
    dd += DateTime(at.year, at.month, 0).day; // 上月天数
  }
  return mo + dd / 30.44;
}

/// 宝宝档案（原型 BABIES 行）。color 为头像渐变键（sky|amber|rose|emerald）。
class CareBaby {
  const CareBaby({
    required this.id,
    required this.name,
    required this.sex,
    required this.birth,
    required this.color,
    required this.avatar,
  });

  final int id;
  final String name;
  final String sex; // 女|男
  final DateTime birth;
  final String color;
  final String avatar;

  static CareBaby fromRow(Map<String, Object?> r) => CareBaby(
        id: r['id']! as int,
        name: r['name']! as String,
        sex: (r['sex'] as String?) ?? '女',
        birth: DateTime.parse(r['birth']! as String),
        color: (r['color'] as String?) ?? 'sky',
        avatar: (r['avatar'] as String?) ?? '🍼',
      );

  CareBaby copyWith({String? name, String? sex, DateTime? birth, String? color}) =>
      CareBaby(
        id: id,
        name: name ?? this.name,
        sex: sex ?? this.sex,
        birth: birth ?? this.birth,
        color: color ?? this.color,
        avatar: avatar,
      );
}

/// 记录人身份（原型 CARERS）。
class CareCarer {
  const CareCarer({required this.id, required this.name});
  final int id;
  final String name;

  static CareCarer fromRow(Map<String, Object?> r) =>
      CareCarer(id: r['id']! as int, name: r['name']! as String);
}

/// 过敏命中 {食物, 反应}（原型 ala 元素；反应可空）。
class AlaHit {
  const AlaHit({required this.f, this.r});
  final String f;
  final String? r;

  Map<String, Object?> toJson() => {'f': f, if (r != null && r!.isNotEmpty) 'r': r};
  static AlaHit fromJson(Map<String, Object?> j) =>
      AlaHit(f: j['f'] as String, r: j['r'] as String?);
}

/// 事件记录一行（原型 ALLLOGS 记录对象；day 独立成列，s/e 为 'HH:MM'）。
/// 字段全集 {k,s,e,dur,ml,tmp,seg,dia,color,tex,vol,name,unit,amt,note,rec,at}
/// + 辅食过敏 ala。补剂多条=多行（每行一个 name/amt）。
class CareRecord {
  const CareRecord({
    this.id,
    required this.babyId,
    required this.day,
    required this.k,
    required this.s,
    this.e,
    this.dur,
    this.ml,
    this.tmp,
    this.seg,
    this.dia,
    this.color,
    this.tex,
    this.vol,
    this.name,
    this.unit,
    this.amt,
    this.note,
    this.rec,
    this.at,
    this.ala,
  });

  final int? id;
  final int babyId;

  /// 'YYYY-MM-DD'
  final String day;

  /// 事件键：内置 key 或 'cus:名'。
  final String k;
  final String s;
  final String? e;
  final int? dur; // 分钟
  final double? ml;
  final double? tmp; // ℃
  final String? seg; // '左8′/右6′'
  final String? dia; // pee|poop|mix
  final String? color; // 便便颜色名
  final String? tex; // 糊状|水样|成形|蛋花样
  final String? vol; // 少|中|多
  final String? name;
  final String? unit;
  final String? amt;
  final String? note;
  final String? rec; // 记录人
  final String? at; // 入账时刻 'HH:MM'（缺省=s）
  final List<AlaHit>? ala;

  int get durOr0 => dur ?? 0;

  static CareRecord fromRow(Map<String, Object?> r) => CareRecord(
        id: r['id'] as int?,
        babyId: r['baby_id']! as int,
        day: r['day']! as String,
        k: r['k']! as String,
        s: r['s']! as String,
        e: r['e'] as String?,
        dur: r['dur'] as int?,
        ml: (r['ml'] as num?)?.toDouble(),
        tmp: (r['tmp'] as num?)?.toDouble(),
        seg: r['seg'] as String?,
        dia: r['dia'] as String?,
        color: r['color'] as String?,
        tex: r['tex'] as String?,
        vol: r['vol'] as String?,
        name: r['name'] as String?,
        unit: r['unit'] as String?,
        amt: r['amt'] as String?,
        note: r['note'] as String?,
        rec: r['rec'] as String?,
        at: r['at'] as String?,
        ala: r['ala'] == null
            ? null
            : (jsonDecode(r['ala']! as String) as List)
                .map((j) => AlaHit.fromJson(j as Map<String, Object?>))
                .toList(),
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'baby_id': babyId,
        'day': day,
        'k': k,
        's': s,
        'e': e,
        'dur': dur,
        'ml': ml,
        'tmp': tmp,
        'seg': seg,
        'dia': dia,
        'color': color,
        'tex': tex,
        'vol': vol,
        'name': name,
        'unit': unit,
        'amt': amt,
        'note': note,
        'rec': rec,
        'at': at ?? s,
        'ala': ala == null || ala!.isEmpty ? null : jsonEncode(ala!.map((a) => a.toJson()).toList()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };

  CareRecord copyWith({int? babyId, String? day}) => CareRecord(
        id: id,
        babyId: babyId ?? this.babyId,
        day: day ?? this.day,
        k: k,
        s: s,
        e: e,
        dur: dur,
        ml: ml,
        tmp: tmp,
        seg: seg,
        dia: dia,
        color: color,
        tex: tex,
        vol: vol,
        name: name,
        unit: unit,
        amt: amt,
        note: note,
        rec: rec,
        at: at,
        ala: ala,
      );
}

/// 周期日记录（care_cycle_days 行；state ''|s|p1|p）。
class CycleDay {
  const CycleDay({
    required this.day,
    this.state = '',
    this.flow,
    this.temp,
    this.ovu,
    this.syms = const [],
    this.note,
  });

  final String day;
  final String state; // ''=未记录 s=点滴 p1=经期第1天 p=经期持续
  final String? flow; // 少|中|多
  final double? temp; // 基础体温
  final String? ovu; // 弱阳|强阳
  final List<String> syms;
  final String? note;

  bool get isPeriod => state == 'p1' || state == 'p';

  static CycleDay fromRow(Map<String, Object?> r) => CycleDay(
        day: r['day']! as String,
        state: (r['state'] as String?) ?? '',
        flow: r['flow'] as String?,
        temp: (r['temp'] as num?)?.toDouble(),
        ovu: r['ovu'] as String?,
        syms: r['syms'] == null
            ? const []
            : (jsonDecode(r['syms']! as String) as List).cast<String>(),
        note: r['note'] as String?,
      );

  Map<String, Object?> toRow() => {
        'day': day,
        'state': state,
        'flow': flow,
        'temp': temp,
        'ovu': ovu,
        'syms': syms.isEmpty ? null : jsonEncode(syms),
        'note': note,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
}

/// 预测存档行（红线：每次修改经期起始重新预测并保留旧预测存档）。
class CyclePred {
  const CyclePred({
    required this.nextStart,
    required this.ovDay,
    required this.madeAt,
    this.superseded = false,
  });

  final DateTime nextStart;
  final DateTime? ovDay;
  final int madeAt;
  final bool superseded;

  static CyclePred fromRow(Map<String, Object?> r) => CyclePred(
        nextStart: DateTime.parse(r['next_start']! as String),
        ovDay: r['ov_day'] == null ? null : DateTime.parse(r['ov_day']! as String),
        madeAt: r['made_at']! as int,
        superseded: (r['superseded'] as int? ?? 0) == 1,
      );
}

/// 测量记录（体重/身高/头围；百分位应用层按 WHO 推导不落库）。
class CareMeasure {
  const CareMeasure({
    this.id,
    required this.babyId,
    required this.day,
    required this.w,
    required this.h,
    required this.head,
    this.rec,
  });

  final int? id;
  final int babyId;
  final String day;
  final double w;
  final double h;
  final double head;
  final String? rec;

  static CareMeasure fromRow(Map<String, Object?> r) => CareMeasure(
        id: r['id'] as int?,
        babyId: r['baby_id']! as int,
        day: r['day']! as String,
        w: (r['w']! as num).toDouble(),
        h: (r['h']! as num).toDouble(),
        head: (r['head']! as num).toDouble(),
        rec: r['rec'] as String?,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'baby_id': babyId,
        'day': day,
        'w': w,
        'h': h,
        'head': head,
        'rec': rec,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
}

/// 疫苗计划行（st 派生：done_day 非空=done；due<今天=late；否则 plan）。
class CareVaccine {
  const CareVaccine({
    this.id,
    required this.babyId,
    required this.name,
    required this.dose,
    required this.due,
    required this.kind,
    required this.lead,
    this.doneDay,
  });

  final int? id;
  final int babyId;
  final String name;
  final String dose;
  final String due; // 'YYYY-MM-DD'
  final String kind; // 免规|自费
  final int lead;
  final String? doneDay;

  bool get done => doneDay != null && doneDay!.isNotEmpty;

  String status(DateTime today) {
    if (done) return 'done';
    return due.compareTo(careDayKey(today)) < 0 ? 'late' : 'plan';
  }

  /// 距计划日天数（正=还有 N 天，负=已过 N 天）。
  int daysTo(DateTime today) =>
      DateTime.parse(due).difference(today.withoutTimeCare()).inDays;

  static CareVaccine fromRow(Map<String, Object?> r) => CareVaccine(
        id: r['id'] as int?,
        babyId: r['baby_id']! as int,
        name: r['name']! as String,
        dose: (r['dose'] as String?) ?? '第1剂',
        due: r['due']! as String,
        kind: (r['kind'] as String?) ?? '免规',
        lead: (r['lead'] as int?) ?? 7,
        doneDay: r['done_day'] as String?,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'baby_id': babyId,
        'name': name,
        'dose': dose,
        'due': due,
        'kind': kind,
        'lead': lead,
        'done_day': doneDay,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
}

/// 发育里程碑（day 空=观察中等待打点）。
class CareMilestone {
  const CareMilestone({
    this.id,
    required this.babyId,
    required this.name,
    required this.cat,
    this.day,
    this.done = false,
  });

  final int? id;
  final int babyId;
  final String name;
  final String cat; // 大运动|精细动作|语言|社交|认知
  final String? day;
  final bool done;

  static CareMilestone fromRow(Map<String, Object?> r) => CareMilestone(
        id: r['id'] as int?,
        babyId: r['baby_id']! as int,
        name: r['name']! as String,
        cat: (r['cat'] as String?) ?? '大运动',
        day: r['day'] as String?,
        done: (r['done'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'baby_id': babyId,
        'name': name,
        'cat': cat,
        'day': day,
        'done': done ? 1 : 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
}

/// 过敏史行（按宝宝分档；同食物唯一索引）。
class CareAllergy {
  const CareAllergy({this.id, required this.babyId, required this.food, this.reaction});
  final int? id;
  final int babyId;
  final String food;
  final String? reaction;

  static CareAllergy fromRow(Map<String, Object?> r) => CareAllergy(
        id: r['id'] as int?,
        babyId: r['baby_id']! as int,
        food: r['food']! as String,
        reaction: r['reaction'] as String?,
      );
}

/// 自定义事件（键 'cus:名'；改名走键迁移）。
class CareCustomEvent {
  const CareCustomEvent({required this.key, required this.name, required this.icon, required this.unit});
  final String key;
  final String name;
  final String icon;
  final String unit;

  static CareCustomEvent fromRow(Map<String, Object?> r) => CareCustomEvent(
        key: r['key']! as String,
        name: r['name']! as String,
        icon: (r['icon'] as String?) ?? '✨',
        unit: (r['unit'] as String?) ?? 'ml',
      );
}

extension CareDateX on DateTime {
  DateTime withoutTimeCare() => DateTime(year, month, day);
}
