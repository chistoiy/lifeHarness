/// 日记模板（V1.28 真结构存储：diary_templates + template_sections）。
class TemplateSection {
  const TemplateSection({required this.title, this.placeholder});
  final String title;
  final String? placeholder;
}

class DiaryTemplate {
  const DiaryTemplate({
    this.id,
    required this.name,
    this.builtin = false,
    this.sections = const [],
  });

  final int? id;
  final String name;
  final bool builtin;
  final List<TemplateSection> sections;

  /// 自由书写（虚拟模板 id=null，不在表中）。
  static const freeWrite = DiaryTemplate(id: null, name: '自由书写');

  bool get structured => sections.isNotEmpty;
}
