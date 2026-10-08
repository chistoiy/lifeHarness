part of 'health_sheets.dart';
// ==================== 症状录入（批3.5a · 原型 `sheetHSymptom`） ====================

/// 症状增改一张表单（原型 `syOpen`/`sySave`）：新增与点流水行改档共用。
///
/// 五条口径写在最近处：
/// · 常用症状＝十枚种子＋用户自定义（`healthSymNamesProvider` 单源）；「+ 加入」写 prefs 后
///   tick++，**同一张弹层里的 chips 当场多出这一枚**（设置当场生效，不「下次进屏才有」）；
/// · 疼痛是**就地 11 段分级条**（点数字即选，色带按 `symColorHex` 上），不做两段式弹层；
///   条下方读数＝「6 分 · 中度」，色档六档与文案三档两套口径由域层给，这里不各写一遍；
/// · 部位**多选全量存**（库里 `,` 连接），原型只取第一枚，本实现不丢用户选的其余部位（偏离见工单 §2）；
/// · 持续时长滚轮＝5~1440 分钟、5 分钟一档（原型 `hNums(5,1440,5)`）；**默认档 10 分钟**
///   （原型新增时的可见选中档），不是需求外的「猜一个 30」；
/// · 照片最多 4 张（§182），走共享插图链 `pickAndStoreImage`（落盘＝应用目录，仅存本机）。
Future<void> showHealthSymptomSheet(BuildContext context, {SymptomRecord? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SymptomSheet(editing: editing),
  );
}

class _SymptomSheet extends ConsumerStatefulWidget {
  const _SymptomSheet({this.editing});

  final SymptomRecord? editing;

  @override
  ConsumerState<_SymptomSheet> createState() => _SymptomSheetState();
}

class _SymptomSheetState extends ConsumerState<_SymptomSheet> {
  // late＋在初始化器里读 widget：字段初始化期 widget 尚未赋值（批3 首跑当场抓到的坑）。
  late String _name = widget.editing?.name ?? symSeedNames.first;
  late int _pain = widget.editing?.level ?? 0;
  late final List<String> _parts = [...?widget.editing?.parts];

  late String? _date = widget.editing?.date;

  /// 新增默认 20:00（原型 `s?+s.t.slice(0,2):20`）；改档按存量时刻就近归到 5 分钟档。
  late int _h = _hh(widget.editing?.time);
  late int _mIdx = _mmIdx(widget.editing?.time);
  late int _durIdx = _durIdxOf(widget.editing?.durationMin);
  late bool _on = widget.editing?.ongoing ?? false;
  late bool _dg = widget.editing?.drugRelated ?? false;
  late final List<String> _pics = [...?widget.editing?.photos];

  late final TextEditingController _trig = TextEditingController(text: widget.editing?.trig ?? '');
  late final TextEditingController _relief =
      TextEditingController(text: widget.editing?.relief ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.editing?.desc ?? '');
  late final TextEditingController _nameIn = TextEditingController();

  static int _hh(String? t) {
    final m = hhmmToMin(t);
    return m == null ? 20 : (m ~/ 60).clamp(0, 23);
  }

  static int _mmIdx(String? t) {
    final m = hhmmToMin(t);
    return m == null ? 0 : ((m % 60) / 5).round().clamp(0, 11);
  }

  /// 存量分钟不在 5 分钟档上时**就近归档**（滚轮的档位集合就是可选集合，不假装能选中间值）。
  static int _durIdxOf(int? min) =>
      min == null ? _newDurIdx : (((min - symDurLo) / symDurStep).round()).clamp(0, symDurCount - 1);

  /// 新增时的可见默认档＝10 分钟（原型 index 1）。
  static const int _newDurIdx = 1;

  int get _durMin => symDurLo + _durIdx * symDurStep;

  String get _time =>
      '${_h.toString().padLeft(2, '0')}:${(_mIdx * 5).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final c in [_trig, _relief, _desc, _nameIn]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 加自定义名：写 prefs → tick++（chips 与屏上常用列表同一份读数），选中它。
  Future<void> _addName() async {
    final v = _nameIn.text.trim();
    if (v.isEmpty) {
      AppToast.show(context, '请先填写症状名');
      return;
    }
    final st = ref.read(healthSettingsProvider);
    final cur = [...st.symCustomNames()];
    if (!cur.contains(v) && !symSeedNames.contains(v)) cur.add(v);
    await st.setSymCustomNames(cur);
    if (!mounted) return;
    setState(() {
      _name = v;
      _nameIn.clear();
    });
    ref.read(healthTickProvider.notifier).state++;
    AppToast.show(context, '已加入常用症状');
  }

  Future<void> _pickPhoto() async {
    if (!symCanAddPhoto(_pics.length)) {
      AppToast.show(context, '照片最多 $symPhotoMax 张');
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    // 直达相册（日记「＋相册」同形）：不再多一层来源弹层，四格点哪格就是加一张。
    final path = await pickAndStoreImage(context,
        bg: scheme.surface, fg: scheme.onSurface, direct: ImageSource.gallery);
    if (path == null || !mounted) return;
    setState(() => _pics.add(path));
    AppToast.show(context, '已插入照片 ${_pics.length} 张 · 仅存本机');
  }

  Future<void> _save() async {
    // 跨弹层的写库不带发起页的失效 ref（既定坑）：先抓 container，pop 之后只用它。
    final container = ProviderScope.containerOf(context, listen: false);
    final pid = container.read(activeHealthProfileProvider);
    final now = container.read(healthClockProvider)();
    final rec = SymptomRecord(
      id: widget.editing?.id,
      profileId: pid,
      date: _date ?? dayKey(now),
      time: _time,
      name: _name,
      level: _pain,
      parts: [..._parts],
      durationMin: _durMin,
      trig: _trimmed(_trig),
      relief: _trimmed(_relief),
      desc: _trimmed(_desc),
      ongoing: _on,
      drugRelated: _dg,
      photos: [..._pics],
      createdAt: widget.editing?.createdAt ?? 0,
    );
    final repo = container.read(healthRepositoryProvider);
    if (rec.id == null) {
      await repo.addSymptom(rec);
    } else {
      await repo.updateSymptom(rec);
    }
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    AppToast.show(context, symSavedTx(rec));
    Navigator.of(context).pop();
  }

  static String? _trimmed(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(healthClockProvider)();
    final today = dayKey(now);
    final days = [for (var i = 0; i < 8; i++) dayKey(now.subtract(Duration(days: i)))];
    final date = _date ?? today;
    final names = ref.watch(healthSymNamesProvider);
    // 改档时存量名字可能已被移出常用（自定义可删），先把它并进选项，别让选中态整排熄灭。
    final opts = names.contains(_name) ? names : [_name, ...names];
    final durLabels = [for (var i = 0; i < symDurCount; i++) '${symDurLo + i * symDurStep}'];

    return _sheetShell(
      context,
      title: widget.editing == null ? '记录症状' : '修改 $date 的症状',
      children: [
        Text('症状', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('hsy-names'),
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final n in opts)
              _keyed(
                  _chip(context,
                      label: n, on: n == _name, onTap: () => setState(() => _name = n)),
                  ValueKey('hsy-name-$n')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('hsy-name-in'),
                controller: _nameIn,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                    isDense: true,
                    hintText: '自定义症状名',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              key: const ValueKey('hsy-name-add'),
              onPressed: _addName,
              child: const Text('+ 加入', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('疼痛等级', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        _painBar(context),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('无痛', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text(symPainTx(_pain),
                key: const ValueKey('hsy-pain-tx'),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('无法忍受', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 12),
        Text('发生部位', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('hsy-parts'),
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final x in symParts)
              _keyed(
                  _chip(context,
                      label: x,
                      on: _parts.contains(x),
                      onTap: () => setState(() => _parts.contains(x)
                          ? _parts.remove(x)
                          : _parts.add(x))),
                  ValueKey('hsy-part-$x')),
          ],
        ),
        const SizedBox(height: 12),
        Text('日期', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          key: const ValueKey('hsy-dates'),
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PillChip(
                    key: ValueKey('hsy-date-$d'),
                    label: '${d == today ? '今天' : d.substring(5)} ${dayWd(d).substring(1)}',
                    selected: d == date,
                    onTap: () => setState(() => _date = d),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 三柱并排各占一份：Row 直接子项宽度不受限，LHWheel 不包 Expanded 会拿到
            // w=Infinity（CupertinoPicker 的 LayoutBuilder 当场炸 performLayout）。
            Expanded(
              child: _wheel(context,
                  label: '时',
                  labels: [for (var i = 0; i < 24; i++) i.toString().padLeft(2, '0')],
                  index: _h,
                  onSelect: (v) => setState(() => _h = v),
                  keyPrefix: 'hsyHH'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _wheel(context,
                  label: '分',
                  labels: [for (var i = 0; i < 12; i++) (i * 5).toString().padLeft(2, '0')],
                  index: _mIdx,
                  onSelect: (v) => setState(() => _mIdx = v),
                  keyPrefix: 'hsyMM'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _wheel(context,
                  label: '持续 · 分钟',
                  labels: durLabels,
                  // 挂「档位个数+选中档」的 key：列表换掉时让柱重建，不复用旧 State（批2.5 既定坑）。
                  key: ValueKey('hsyDur-$symDurCount-$_durIdx'),
                  index: _durIdx,
                  onSelect: (v) => setState(() => _durIdx = v),
                  keyPrefix: 'hsyDur'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('开始 $date $_time · 持续 ${symDurTx(_durMin)}',
            key: const ValueKey('hsy-when'),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(context, '诱发因素', 'hsy-trig', _trig, '如 熬夜后')),
            const SizedBox(width: 8),
            Expanded(child: _field(context, '缓解因素', 'hsy-relief', _relief, '如 休息后好转')),
          ],
        ),
        const SizedBox(height: 8),
        _field(context, '感受描述', 'hsy-desc', _desc, '如 右侧太阳穴跳痛'),
        const SizedBox(height: 10),
        Text('照片（最多 $symPhotoMax 张·仅存本机）',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(
          key: const ValueKey('hsy-pics'),
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < _pics.length; i++)
              ImageSquareCard(
                key: ValueKey('hsy-photo-$i'),
                path: _pics[i],
                fg: scheme.onSurface,
                delKey: ValueKey('hsy-photo-del-$i'),
                onDelete: () => setState(() => _pics.removeAt(i)),
              ),
            if (symCanAddPhoto(_pics.length))
              GestureDetector(
                key: const ValueKey('hsy-pic-add'),
                onTap: _pickPhoto,
                child: Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Icon(Icons.add_a_photo_outlined, size: 20, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
                child: Text('正在发作', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            Switch(
                key: const ValueKey('hsy-on'),
                value: _on,
                onChanged: (v) => setState(() => _on = v)),
          ],
        ),
        Row(
          children: [
            const Expanded(
                child: Text('与用药相关', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            Switch(
                key: const ValueKey('hsy-drug'),
                value: _dg,
                onChanged: (v) => setState(() => _dg = v)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hsy-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                  key: const ValueKey('hsy-save'),
                  onPressed: _save,
                  child: const Text('保存')),
            ),
          ],
        ),
      ],
    );
  }

  /// 11 段就地分级条（原型 `syPainRow`）：选中段上色，其余留中性底——点一下即选，不弹层。
  Widget _painBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('hsy-pain'),
      children: [
        for (var i = 0; i <= 10; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 10 ? 0 : 3),
              child: GestureDetector(
                key: ValueKey('hsy-pain-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _pain = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _pain ? Color(symColorHex(i)) : scheme.onSurface.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('$i',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: i == _pain ? Colors.white : scheme.onSurfaceVariant)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _field(BuildContext context, String label, String key, TextEditingController c, String hint) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      TextField(
        key: ValueKey(key),
        controller: c,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      ),
    ],
  );
}
