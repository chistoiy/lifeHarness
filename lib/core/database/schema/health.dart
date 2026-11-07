// 健康管理模块（需求 V1.48 + V1.48.1 · 落地口径＝《docs/健康管理模块开发计划-20260927.md》）
//
// 表结构两条主线：
// · V1.48 五类按日记录（喝水/睡眠/运动/身体数据/用药）+ 目标；
// · V1.48.1 档案中心（health_profile 及其派生：标签/体征/症状/报告/提醒）。
// **所有记录表都带 profile_id**，跨档案一律不聚合（§11.1 末行）；「本人」档案 id=1 随建表种子落库，不可删。
// 派生数据（达标度/热力格/周报/配速/依从率…）不落库，读取侧实时算（§2.2）。
// 存储恒公制原值（kg/km/分钟/秒），单位切换只影响展示与输入换算（§五.10）。

const String tHealthProfile = 'health_profile';
const String tHealthProfileTag = 'health_profile_tag';
const String tHealthWater = 'health_water';
const String tHealthSleep = 'health_sleep';
const String tHealthExercise = 'health_exercise';
const String tHealthBody = 'health_body';
const String tHealthDrug = 'health_drug';
const String tHealthDrugLog = 'health_drug_log';
const String tHealthGoal = 'health_goal';
const String tHealthVital = 'health_vital';
const String tHealthSymptom = 'health_symptom';
const String tHealthReport = 'health_report';
const String tHealthReportMetric = 'health_report_metric';
const String tHealthRemind = 'health_remind';

/// 本模块全部表名（备份排除、概览登记、守护在册清单都吃这一份，别再各处手抄）。
const List<String> healthTables = [
  tHealthProfile,
  tHealthProfileTag,
  tHealthWater,
  tHealthSleep,
  tHealthExercise,
  tHealthBody,
  tHealthDrug,
  tHealthDrugLog,
  tHealthGoal,
  tHealthVital,
  tHealthSymptom,
  tHealthReport,
  tHealthReportMetric,
  tHealthRemind,
];

/// 「本人」档案固定 id：不可删、不可改名成别人（§11.1）。
const int selfProfileId = 1;

final List<String> healthSchemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS $tHealthProfile (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    rel TEXT NOT NULL DEFAULT '本人',
    sex TEXT NOT NULL DEFAULT '',
    birth TEXT,
    height_cm REAL,
    base_kg REAL,
    rest_sys INTEGER,
    rest_dia INTEGER,
    rest_hr INTEGER,
    note TEXT,
    archived INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  // 病史 / 过敏 / 长期用药三类标签，一行一条，sort 控展示序。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthProfileTag (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    kind TEXT NOT NULL,
    text TEXT NOT NULL,
    sort INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hp_tag_profile ON $tHealthProfileTag(profile_id,kind)',
  // 喝水：一天一行只存杯数，毫升数由 cupMl 在展示层换算（不落库）。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthWater (
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    cups INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (profile_id, date)
  )
  ''',
  // 睡眠：date＝归属日＝醒来日；分期四列全空＝未记录分期；跨天由 duration_min 吸收（写入侧算一次）。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthSleep (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    bed_time TEXT NOT NULL,
    wake_time TEXT NOT NULL,
    duration_min INTEGER NOT NULL,
    quality TEXT,
    deep_min INTEGER,
    light_min INTEGER,
    rem_min INTEGER,
    awake_min INTEGER,
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hsleep_profile_date ON $tHealthSleep(profile_id,date)',
  // 运动：source＝手动/计时/设备导入（设备导入本期只留字段与灰位）。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthExercise (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    type TEXT NOT NULL,
    distance_km REAL,
    duration_min INTEGER NOT NULL,
    pace_sec INTEGER,
    kcal INTEGER,
    note TEXT,
    source TEXT NOT NULL DEFAULT '手动',
    started_at INTEGER,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hex_profile_date ON $tHealthExercise(profile_id,date)',
  // 身体数据：同日重记＝覆盖（UPSERT 走这个唯一索引）；height_cm 按行存快照，历史 BMI 不漂移。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthBody (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    kg REAL,
    height_cm REAL,
    fat_pct REAL,
    waist_cm REAL,
    hip_cm REAL,
    neck_cm REAL,
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hbody_profile_date ON $tHealthBody(profile_id,date)',
  // 用药档案：删除＝置 archived，打卡流水保留（「删除但保留记录」口径）。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthDrug (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    spec TEXT,
    unit TEXT NOT NULL DEFAULT '片',
    dose REAL NOT NULL DEFAULT 1,
    times TEXT NOT NULL DEFAULT '[]',
    remind INTEGER NOT NULL DEFAULT 0,
    end_date TEXT,
    archived INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hdrug_profile ON $tHealthDrug(profile_id,archived)',
  // 打卡流水：一个时刻一行；撤销＝删行或改 state，留痕靠 created_at。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthDrugLog (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    drug_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    time TEXT NOT NULL,
    state TEXT NOT NULL,
    note TEXT,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hdruglog_slot ON $tHealthDrugLog(drug_id,date,time)',
  // 目标：键＝water/sleep/week_ex/weight/waist/hip/neck；缺键＝未设（读取侧回落默认）。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthGoal (
    profile_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    value REAL NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (profile_id, key)
  )
  ''',
  // 五类体征：kind 决定用哪几列（血压用 sys/dia，心率用 hr，其余用 val）；异常判定在读取侧算。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthVital (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    time TEXT NOT NULL,
    kind TEXT NOT NULL,
    sys INTEGER,
    dia INTEGER,
    hr INTEGER,
    val REAL,
    slot TEXT,
    diet_note TEXT,
    note TEXT,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hvital_profile_kind ON $tHealthVital(profile_id,kind,date)',
  // 症状：药物不良反应＝drug_related=true，不另建表；`trigger`/`desc` 是 SQL 关键词，列名改 trig/desc_txt。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthSymptom (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    time TEXT,
    name TEXT NOT NULL,
    level INTEGER NOT NULL DEFAULT 0,
    parts TEXT,
    duration_min INTEGER,
    trig TEXT,
    relief TEXT,
    desc_txt TEXT,
    ongoing INTEGER NOT NULL DEFAULT 0,
    drug_related INTEGER NOT NULL DEFAULT 0,
    photos TEXT,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hsymptom_profile_date ON $tHealthSymptom(profile_id,date)',
  // 报告：files 存 JSON 路径数组；note_ref 与笔记双向链接（批7 接线）。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthReport (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    name TEXT NOT NULL,
    hospital TEXT,
    doctor_advice TEXT,
    files TEXT,
    kind TEXT NOT NULL DEFAULT 'img',
    note_ref INTEGER,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hreport_profile ON $tHealthReport(profile_id,date)',
  // 检验项：偏高/偏低按行内参考范围实时判，不落状态列。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthReportMetric (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    value REAL,
    unit TEXT,
    ref_lo REAL,
    ref_hi REAL,
    sort INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hmetric_report ON $tHealthReportMetric(report_id)',
  // 提醒：服药/测量/复诊三类；排程接线在批8，本期只落 enabled/scheduled 两列。
  '''
  CREATE TABLE IF NOT EXISTS $tHealthRemind (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    at_time TEXT NOT NULL,
    repeat TEXT NOT NULL DEFAULT '每天',
    date TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    scheduled INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_hremind_profile ON $tHealthRemind(profile_id,enabled)',
  // 「本人」档案：id 钉死 1，rel 供 UI 显示，不可删（删除入口对它禁用）。
  "INSERT OR IGNORE INTO $tHealthProfile(id,name,rel,sex,archived,created_at) "
      "VALUES($selfProfileId,'本人','本人','',0,0)",
];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
  // 36→37（V1.48/V1.48.1 健康模块落地）：新模块只建表不搬数据。
  36: [
    ...healthSchemaStatements,
  ]
};
