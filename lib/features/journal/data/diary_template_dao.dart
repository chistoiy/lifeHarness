import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/diary_template.dart';

/// 日记模板 DAO（diary_templates + template_sections，V1.28 真结构）。
class DiaryTemplateDao {
  DiaryTemplateDao(this.db);

  final Database db;

  /// 全部模板（内置在前，按 sort/id）。
  Future<List<DiaryTemplate>> list() async {
    final rows = await db.query(DbSchema.tDiaryTemplates,
        orderBy: 'builtin DESC, sort ASC, id ASC');
    final out = <DiaryTemplate>[];
    for (final r in rows) {
      final secs = await db.query(DbSchema.tTemplateSections,
          where: 'template_id = ?', whereArgs: [r['id']], orderBy: 'idx ASC');
      out.add(DiaryTemplate(
        id: r['id'] as int,
        name: r['name'] as String,
        builtin: (r['builtin'] as int) == 1,
        sections: secs
            .map((s) => TemplateSection(
                title: s['title'] as String, placeholder: s['placeholder'] as String?))
            .toList(),
      ));
    }
    return out;
  }

  /// 新建自定义模板（名称 + 分节），返回 id。
  Future<int> create(DiaryTemplate t) async {
    final id = await db.insert(DbSchema.tDiaryTemplates,
        {'name': t.name, 'builtin': 0, 'sort': 100});
    final b = db.batch();
    for (var i = 0; i < t.sections.length; i++) {
      b.insert(DbSchema.tTemplateSections, {
        'template_id': id,
        'idx': i,
        'title': t.sections[i].title,
        'placeholder': t.sections[i].placeholder,
      });
    }
    await b.commit(noResult: true);
    return id;
  }

  /// 删除模板（仅自定义；内置由 UI 层禁止调用）。
  Future<void> remove(int id) async {
    await db.delete(DbSchema.tTemplateSections,
        where: 'template_id = ?', whereArgs: [id]);
    await db.delete(DbSchema.tDiaryTemplates, where: 'id = ?', whereArgs: [id]);
  }
}
