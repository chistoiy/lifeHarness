import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_symptom.dart';

/// 健康批3.5a · 症状规格单源（事实源＝`tools/health/v2_js.js` 的 `syRender`/`syDur`/`syColor`/
/// `syCloud`/`syEnd`/`sySave`，页面与弹层都从这里取读数，所以判据在这一件里钉死就够）。
///
/// 七组判定（工单执行面板第 3 项「常驻用例」）：
/// · 疼痛**色带六档**（`floor(l/2)` 夹紧 5）与**文案三档**（<4 轻 / <7 中 / 其余重）是两套口径，
///   各钉各的边界——刀①把 `~/2` 摘成 `l/5` 就是为了让色档表红；
/// · 持续时长三档（分钟/一位小数小时/天）跨过 60 与 1440 两个界；
/// · 直方图永远 11 桶且越界夹紧（0 与 10 之外不另开桶）；
/// · 部位筛选按**包含**判（多部位记录两边都算命中），空部位按「全身」兜底；
/// · 词云吃三源、只留长度 >1 的词、同频按首次出现序、上限 18、字号与透明度按比值现算；
/// · 「标记结束」＝ongoing 落下**且**时长 +15（少一半就是假实现）；
/// · 提示条原话逐字对原型（改一个字都会被读成「功能变了」）。
void main() {
  SymptomRecord rec({
    int? id,
    String name = '头痛',
    int level = 0,
    List<String> parts = const [],
    int? min,
    String? trig,
    String? relief,
    String? desc,
    bool ongoing = false,
    bool drug = false,
    List<String> photos = const [],
    String date = '2026-09-18',
    String time = '08:00',
  }) =>
      SymptomRecord(
        id: id,
        profileId: 1,
        date: date,
        time: time,
        name: name,
        level: level,
        parts: parts,
        durationMin: min,
        trig: trig,
        relief: relief,
        desc: desc,
        ongoing: ongoing,
        drugRelated: drug,
        photos: photos,
      );

  group('疼痛：色带六档与文案三档是两套口径', () {
    test('色档表＝0~1 落第 0 档、每 2 分升一档、10 分钉在第 5 档', () {
      // `max(0,min(10,level)) ~/ 2` 再 clamp(0,5)：0/1→0，2/3→1，…，10→5（10~/2=5 已在末档）。
      expect([for (var l = 0; l <= 10; l++) symColorIndex(l)], [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5]);
      expect(symColorIndex(-3), 0, reason: '越界先夹 0~10，脏数据不能负索引炸表');
      expect(symColorIndex(99), 5);
    });

    test('色值取自六档渐变原色，且与档位一一对应', () {
      expect(symPainRamp, [0xFF10B981, 0xFF84CC16, 0xFFEAB308, 0xFFF59E0B, 0xFFF97316, 0xFFEF4444]);
      for (var i = 0; i < symPainRamp.length; i++) {
        expect(symColorHex(i * 2), symPainRamp[i]);
      }
      expect(symColorHex(10), symPainRamp.last);
    });

    test('文案三档边界：3 轻 / 4 中 / 6 中 / 7 重', () {
      expect(symTier(0), '轻度');
      expect(symTier(3), '轻度');
      expect(symTier(4), '中度');
      expect(symTier(6), '中度');
      expect(symTier(7), '重度');
      expect(symTier(10), '重度');
    });

    test('条下读数＝「6 分 · 中度」', () {
      expect(symPainTx(6), '6 分 · 中度');
      expect(symPainTx(0), '0 分 · 轻度');
    });
  });

  group('持续时长三档文案（原型 syDur）', () {
    test('分钟 / 一位小数小时 / 天，跨 60 与 1440 两个界', () {
      expect(symDurTx(null), '0 分钟');
      expect(symDurTx(30), '30 分钟');
      expect(symDurTx(59), '59 分钟');
      expect(symDurTx(60), '1.0 小时', reason: '一位小数：60 分不是「1 小时」整数写法');
      expect(symDurTx(90), '1.5 小时');
      expect(symDurTx(100), '1.7 小时', reason: '100/60=1.666… → 四舍五入一位小数');
      expect(symDurTx(1439), '24.0 小时');
      expect(symDurTx(1440), '1 天');
      expect(symDurTx(2880), '2 天');
    });
  });

  group('疼痛直方图（11 桶·越界夹紧）', () {
    test('每档落一根柱，零次留 0 而不是缺桶', () {
      final hist = symHist([rec(level: 0), rec(level: 3), rec(level: 3), rec(level: 10)]);
      expect(hist.length, 11);
      expect(hist, [1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 1]);
      expect(symHistMax(hist), 2);
    });

    test('全零时分母取 1（归一化不炸除）', () {
      final hist = symHist(const []);
      expect(hist.every((n) => n == 0), isTrue);
      expect(symHistMax(hist), 1);
    });

    test('越界读数并进 0 与 10 两端桶，不开第 12 桶', () {
      final hist = symHist([rec(level: -5), rec(level: 17)]);
      expect(hist.length, 11);
      expect(hist.first, 1);
      expect(hist.last, 1);
    });
  });

  group('部位筛选＝包含匹配（多部位两边都算命中）', () {
    final a = rec(id: 1, name: '头痛', parts: ['头部', '四肢']);
    final b = rec(id: 2, name: '腹痛', parts: ['胸腹']);
    final c = rec(id: 3, name: '乏力'); // 空部位＝全身兜底
    final all = [a, b, c];

    test('「全部」不过滤，其余按包含判', () {
      expect(symByPart(all, '全部'), all);
      expect(symByPart(all, '头部'), [a]);
      expect(symByPart(all, '四肢'), [a], reason: '同一条记录两个部位，筛哪个都在');
      expect(symByPart(all, '胸腹'), [b]);
    });

    test('空部位记录只在「全部」与「全身」下出现', () {
      expect(symByPart(all, '全身'), [c]);
      expect(symByPart(all, '关节'), isEmpty);
    });
  });

  group('高频描述词云（三源·只留 >1·前 18·比值现算）', () {
    test('症状名／感受描述／诱发因素三源都进榜，标点与空格切词', () {
      final cloud = symWordCloud([
        rec(name: '头痛', desc: '跳痛，恶心', trig: '熬夜后 失眠'),
      ]);
      expect(cloud.map((w) => w.w).toSet(), {'头痛', '跳痛', '恶心', '熬夜后', '失眠'});
      expect(cloud.first.w, '头痛', reason: '全同频时按首次出现序（非稳定 sort 侥幸不可依赖）');
    });

    test('单字与空串进不了榜（刀②摘掉 length>1 守卫就在这里红）', () {
      final cloud = symWordCloud([rec(name: '痛', desc: '很 疼, 啊。难受')]);
      expect(cloud.map((w) => w.w), ['难受'], reason: '「很」「疼」「啊」都是单字，只有「难受」够长');
    });

    test('按频次降序·同频按首次出现序·上限 18', () {
      final many = rec(
          name: '头晕',
          desc: [for (var i = 1; i <= 20; i++) '词$i'].join(' '),
          trig: '乏力 乏力 乏力');
      final cloud = symWordCloud([many]);
      expect(cloud.length, 18, reason: '21 个候选词只留 18 枚（原型 slice(0,18)）');
      expect(cloud.first, (w: '乏力', n: 3, ratio: 1.0), reason: '最高频的排第一，比值对最高频归一');
      expect(cloud[1].w, '头晕');
      // 其余 16 枚＝词1..词16（各 1 次，按出现序截断）。
      expect([for (final w in cloud.skip(2)) w.w], [for (var i = 1; i <= 16; i++) '词$i']);
      expect(cloud[2].ratio, 1 / 3);
    });

    test('字号 10+比值×8、透明度 .45+.55×比值', () {
      expect(symCloudFont(1), 18);
      expect(symCloudFont(0), 10);
      expect(symCloudOpacity(1), 1.0);
      expect(symCloudOpacity(0), 0.45);
    });

    test('空文本＝空榜（卡右上角出「暂无文本」）', () {
      expect(symWordCloud(const []), isEmpty);
      expect(symCloudTx(0), '暂无文本');
      expect(symCloudTx(7), '7 个高频词');
    });
  });

  group('流水：倒序与两行文案', () {
    test('按日期倒序，同日按 id 倒序补稳', () {
      final xs = symListDesc([
        rec(id: 1, date: '2026-09-17'),
        rec(id: 2, date: '2026-09-18'),
        rec(id: 3, date: '2026-09-18'),
      ]);
      expect(xs.map((e) => e.id), [3, 2, 1]);
    });

    test('主行带「发作中」，副行把日期/时刻/部位/持续/照片/描述拼成一串', () {
      expect(symRowMain(rec(ongoing: true)), '头痛 · 发作中');
      expect(symRowMain(rec()), '头痛');
      expect(
          symRowSub(rec(
              parts: ['头部', '四肢'], min: 90, desc: '跳痛', photos: ['a', 'b'])),
          '2026-09-18 08:00 · 头部·四肢 · 持续 1.5 小时 · 照片 2 · 跳痛');
      expect(symRowSub(rec(time: '')), '2026-09-18 · 全身 · 持续 0 分钟',
          reason: '没有时刻就不留空冒号；没部位按「全身」兜底');
    });

    test('发作计数与空态文案（原型 syLiveN / syLive 空分支）', () {
      final live = symLive([rec(id: 1, ongoing: true), rec(id: 2)]);
      expect(live.map((e) => e.id), [1]);
      expect(symLiveTx(live.length), '1 项');
      expect(symLiveTx(0), '无');
      expect(symLiveEmptyTx, '当前无发作中症状');
      expect(symEmptyTx, '该档案暂无症状记录');
    });
  });

  group('写侧三条口径', () {
    test('「标记结束」＝ongoing 落下且时长 +15（只做一半就是假实现）', () {
      final r = rec(id: 7, min: 30, ongoing: true);
      final e = r.ended();
      expect(e.ongoing, isFalse);
      expect(e.durationMin, 45);
      expect(e.id, 7, reason: '同一条记录改档，不是新增一行');
      expect(rec(id: 8, ongoing: true).ended().durationMin, 15, reason: '未填时长按 0 起算 +15');
      expect(symEndTx, '已标记结束 · 持续时长 +15 分钟');
    });

    test('保存提示条按原话，用药相关才追加后半句', () {
      expect(symSavedTx(rec(name: '头痛', level: 6)), '已记录 头痛 6 分');
      expect(symSavedTx(rec(name: '头痛', level: 6, drug: true)), '已记录 头痛 6 分 · 已标为用药相关');
      expect(symDelTx, '删除该条症状记录');
    });

    test('常用名单＝十枚种子＋自定义（trim·去重·保序）', () {
      expect(symSeedNames.length, 10);
      expect(symNamesWith(['胃痛', ' 头痛 ', '']).length, 11,
          reason: '空串与种子重名都不新增，只加「胃痛」一枚');
      expect(symNamesWith(['胃痛']).sublist(10), ['胃痛'], reason: '自定义接在种子后面，种子序不动');
    });

    test('照片上限 4 张：第 5 张不再给加格', () {
      expect([for (var n = 0; n <= 4; n++) symCanAddPhoto(n)], [true, true, true, true, false]);
      expect(symPhotoMax, 4);
    });
  });
}
