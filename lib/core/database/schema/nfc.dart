// NFC 卡片模块（需求模块 19 · V1.68 · 2026-10-15 产品立项）。
//
// 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md（V3【方案冻结】）
// ＋执行工单 docs/handoff/NFC卡片模块-批1数据层与管理屏.md §2。
//
// 三条口径在字段层钉死，别在 UI 侧补：
// · **标签只存编号**（C1）：物理标签上只写 `lh://nfc/<cardId>` 一条 URI 记录，
//   名称/目标/图标全在本机表 ⇒ 改卡片数据**零贴卡**（若靠重写标签，用户每改一次都得再贴一次）。
// · **`written_at` 是写入态的唯一判据**（C31）：NULL＝未写入，毫秒＝最后成功写入时刻。
//   **禁靠读标签反推**——写入态是历史事实，读标签只能得知"现在有没有内容"，
//   无法区分"从没写过"与"写过又被清空"。UID 只读卡另用 `tag_kind='uid'` 显示「只读卡」。
// · **`id` 是 12 位 base62 随机串**（C33）：`Random.secure()` 取 `0-9a-zA-Z`。
//   禁 uuid／时间戳／自增——uuid 长度不可控会让冻结档 §5.7 的容量核算当场失真，
//   时间戳/自增可枚举并泄露创建顺序。标签上可印前 8 位短码供人眼识别，
//   但**短码绝不作判据**（B33：新建卡可能与旧卡撞前 8 位）。
//
// v47→v48 迁移（mig[47]）与基础 DDL **同源引一份语句表**（本模块只建表零搬数据，
// 无 v45 那种"老口径不带新列"的历史包袱，故无须拆两份）。

const String tNfcCards = 'nfc_cards';

/// 本模块全部表名（备份登记、守护清单都吃这一份）。
const List<String> nfcTables = [tNfcCards];

/// 卡片目标类型四值（冻结档 §2.0 目标表）。存 `target_kind` 列。
/// `timer_duration`（定时长）是**可选-批3**，列位先留好。
class NfcTargetKind {
  const NfcTargetKind._();

  /// 动作表 7 枚（`target_ref`＝动作 id）。`nav` 是**前缀形态**：
  /// 具体哪一枚由 `target_ref` 里的动作 id 决定，不另设七枚枚举值。
  static const String nav = 'nav';

  /// 时间分类（`target_ref`＝`categories.id`）。
  static const String timerCat = 'timer_cat';

  /// 书架某本书（`target_ref`＝`books.id`）。
  static const String readBook = 'read_book';

  /// 定时长（`target_ref`＝分钟数字符串）——可选-批3。
  static const String timerDuration = 'timer_duration';

  static const List<String> all = [nav, timerCat, readBook, timerDuration];
}

/// 标签形态两值（`tag_kind` 列）。
class NfcTagKind {
  const NfcTagKind._();

  /// NDEF URI `lh://nfc/<id>`——轨 A，能力全（可冷启动分发）。
  static const String ndef = 'ndef';

  /// UID 指纹——轨 B，**仅批3 可选**，且**仅 App 前台亮屏**可用；多为只读卡，只登记不写。
  static const String uid = 'uid';
}

/// 建表语句（**基础 DDL 与 mig[47] 同源**）。
const List<String> nfcCreateStatements = <String>[
  '''
  CREATE TABLE IF NOT EXISTS $tNfcCards (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    target_kind TEXT NOT NULL,
    target_ref TEXT,
    tag_key TEXT UNIQUE,
    tag_kind TEXT,
    created_at INTEGER NOT NULL,
    last_used_at INTEGER,
    use_count INTEGER NOT NULL DEFAULT 0,
    written_at INTEGER
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_nfc_tag_key ON $tNfcCards(tag_key)',
  'CREATE INDEX IF NOT EXISTS idx_nfc_created ON $tNfcCards(created_at)',
];

/// 本域承接的版本迁移条目（聚合于 `DbSchema.migrations`·键互斥）。
/// 键语义＝仓内循环 `for v=from; v<to; migrations[v]` ⇒ **键 47 ＝「47→48 升级语句」**。
/// 48（NFC 批1 · 冻结档 F1-1）：建 `nfc_cards` 一张表（新模块只建表零搬数据）。
/// IF NOT EXISTS 保证重放不撞；**老口径语句表一字不加**——老库 44→48 直升不撞 duplicate column
/// （v45/v47 既有教训：mindmap 批2 因老口径带新列导致直升崩，详见 schema/mindmap.dart 段注）。
final Map<int, List<String>> mig = {
  47: [...nfcCreateStatements],
};