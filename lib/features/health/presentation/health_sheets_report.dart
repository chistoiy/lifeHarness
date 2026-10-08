part of 'health_sheets.dart';
// ==================== 检查报告上传（批3.5b · 原型 `sheetHReportAdd`） ====================

/// 上传一张检查报告（原型 `rpaOpen`/`rpaSave`）。
///
/// 五条口径写在最近处：
/// · **一次只建档＋附件**：检验项要建档后逐条录入（原型预览条原话），所以这里存完报告就收起，
///   检验项从卡片明细里的「＋ 检验项」进（`showHealthMetricSheet`）；
/// · 三种来源＝拍照／相册／PDF，图片走共享插图链 `pickAndStoreImage`（直达来源，不再多一层），
///   PDF 走 `pickAndStorePdf` 注入缝；两者同存应用目录 `note_images/`（工单 §2「不另造目录」）；
/// · 缩略位**第 7 格起不给「＋」**（原型 `rpaPics` 的 `<6` 判据），报告本身不限量；
/// · 名称必填——缺名 toast 且**不落库**、弹层不关（原型 `rpaSave` 同形）；医院留空落 '—'；
/// · 原型那张「关联笔记 ›」钮是 `toast(…（模拟）)`，真实双向链接属批7 共享面 → **不铺假入口**（偏离见工单 §2）。
Future<void> showHealthReportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ReportAddSheet(),
  );
}

class _ReportAddSheet extends ConsumerStatefulWidget {
  const _ReportAddSheet();

  @override
  ConsumerState<_ReportAddSheet> createState() => _ReportAddSheetState();
}

class _ReportAddSheetState extends ConsumerState<_ReportAddSheet> {
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _hosp = TextEditingController();
  late final TextEditingController _advice = TextEditingController();

  /// 已选附件的应用目录路径（图片与 PDF 混存一列，顺序即录入序）。
  final List<String> _files = [];

  /// 选中的就诊日期；null＝未动过 chips，build 时按固定钟取今天（所以**不能写 `late`**：
  /// `late String?` 在不赋值前读一次就抛 LateInitializationError，起手空白态正是这条路）。
  String? _date;

  @override
  void dispose() {
    for (final c in [_name, _hosp, _advice]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addImage(ImageSource src) async {
    if (!rpCanAddAttach(_files.length)) {
      AppToast.show(context, '缩略位最多 $rpAttachMax 格');
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    final path = await pickAndStoreImage(context,
        bg: scheme.surface, fg: scheme.onSurface, direct: src);
    if (path == null || !mounted) return;
    setState(() => _files.add(path));
    AppToast.show(context, '已插入 1 张 · 仅存本机');
  }

  Future<void> _addPdf() async {
    if (!rpCanAddAttach(_files.length)) {
      AppToast.show(context, '缩略位最多 $rpAttachMax 格');
      return;
    }
    final path = await pickAndStorePdf(context);
    if (path == null || !mounted) return;
    setState(() => _files.add(path));
    AppToast.show(context, '已导入 PDF · 原文件仅存本机');
  }

  Future<void> _save() async {
    final nm = _name.text.trim();
    if (nm.isEmpty) {
      AppToast.show(context, rpNeedNameTx);
      return;
    }
    // 跨弹层的写库不带发起页的失效 ref（既定坑）：先抓 container，pop 之后只用它。
    final container = ProviderScope.containerOf(context, listen: false);
    final now = container.read(healthClockProvider)();
    final rec = HealthReport(
      profileId: container.read(activeHealthProfileProvider),
      date: _date ?? dayKey(now),
      name: nm,
      hospital: _trimmed(_hosp) ?? '—',
      doctorAdvice: _trimmed(_advice),
      files: [..._files],
      kind: rpKindOf(_files),
    );
    await container.read(healthRepositoryProvider).addReport(rec);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    // 新建必然 0 项检验项（`rpSavedTx` 因此走「待录入检验项」那半句）。
    AppToast.show(context, rpSavedTx(nm, 0));
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

    return _sheetShell(
      context,
      title: '上传检查报告',
      children: [
        Row(
          key: const ValueKey('hra-src'),
          children: [
            Expanded(child: _srcTile(context, 'hra-src-cam', '拍照', Icons.photo_camera_outlined,
                () => _addImage(ImageSource.camera))),
            const SizedBox(width: 8),
            Expanded(child: _srcTile(context, 'hra-src-img', '相册', Icons.photo_library_outlined,
                () => _addImage(ImageSource.gallery))),
            const SizedBox(width: 8),
            Expanded(child: _srcTile(context, 'hra-src-pdf', 'PDF', Icons.description_outlined, _addPdf)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          key: const ValueKey('hra-pics'),
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < _files.length; i++)
              _attachTile(context, 'hra-file-$i', _files[i],
                  onTap: () => setState(() => _files.removeAt(i))),
            if (rpCanAddAttach(_files.length))
              _attachTile(context, 'hra-pic-add', null, onTap: () => _addImage(ImageSource.gallery)),
          ],
        ),
        const SizedBox(height: 12),
        Text('日期', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          key: const ValueKey('hra-dates'),
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PillChip(
                    key: ValueKey('hra-date-$d'),
                    label: '${d == today ? '今天' : d.substring(5)} ${dayWd(d).substring(1)}',
                    selected: d == date,
                    onTap: () => setState(() => _date = d),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(context, '就诊医院', 'hra-hosp', _hosp, '如 市一院')),
            const SizedBox(width: 8),
            Expanded(child: _field(context, '报告名称', 'hra-name', _name, '如 血常规')),
          ],
        ),
        const SizedBox(height: 8),
        _field(context, '医生建议', 'hra-advice', _advice, '如 一周后复查血脂'),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('hra-preview'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(rpDraftTx(_files.length),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hra-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(key: const ValueKey('hra-save'), onPressed: _save, child: const Text('保存报告')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _srcTile(BuildContext context, String key, String label, IconData icon,
      VoidCallback onTap) {
    return GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 62,
        alignment: Alignment.center,
        decoration: context.cardDecoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: context.tokens.accent),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// 缩略格：有路径就画缩略（PDF 画记号），空路径那格就是「＋」；点格＝移除（原型 `rpaRm`）。
  Widget _attachTile(BuildContext context, String key, String? path, {required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final isPdf = path != null && path.toLowerCase().endsWith('.pdf');
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: path == null
            ? Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant)
            : isPdf
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_outlined, size: 14, color: scheme.onSurfaceVariant),
                      Text('PDF', style: TextStyle(fontSize: 7.5, color: scheme.onSurfaceVariant)),
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(File(path),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined,
                              size: 14, color: scheme.onSurfaceVariant)),
                      Positioned(
                        bottom: 2,
                        child: Text('移除',
                            style: TextStyle(fontSize: 7.5, color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// PDF 选择＋落盘的**注入缝**（生产＝file_picker 选中后按内容寻址拷进 `note_images/`；
/// 测试换替身避开平台通道，同 `BackupService.pickFilesImpl` 的做法）。
Future<String?> Function(BuildContext) pickAndStorePdf = _pickAndStorePdfImpl;

Future<String?> _pickAndStorePdfImpl(BuildContext context) async {
  FilePickerResult? r;
  try {
    r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
  } on PlatformException catch (e) {
    // 平台拒自定义扩展名 → 降级全文件选择（同备份选择器既定口径，不静默吞）。
    AppLog.add('报告 PDF 选择器扩展名被平台拒（降级全文件）：$e', level: LhLevel.warn);
    r = await FilePicker.platform.pickFiles(type: FileType.any);
  }
  final src = r == null || r.files.isEmpty ? null : r.files.single.path;
  if (src == null) return null;
  try {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(dir.path, 'note_images'));
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final bytes = File(src).readAsBytesSync();
    final hash = crypto.sha256.convert(bytes).toString();
    final dest = p.join(outDir.path, '$hash.pdf');
    final f = File(dest);
    // 同步写：FakeAsync widget 测试里异步 writeAsBytes 永不完成（已知坑），且同内容只落一份。
    if (!await f.exists()) f.writeAsBytesSync(bytes);
    return dest;
  } catch (e) {
    AppLog.add('报告 PDF 落盘失败：$e', level: LhLevel.warn);
    if (context.mounted) AppToast.show(context, 'PDF 导入失败 · 请重试');
    return null;
  }
}

// ==================== 检验项录入（批3.5b · 原型 `sheetHMetric`） ====================

/// 滚轮的**量程身份** key：同一根滚轮只要档位范围没换就复用 State（内部滚动位置与甩动动画归它管）；
/// 点了项目库里另一个项目＝量程整个换掉，key 变、旧 State 不复用。选中档不进 key（见三柱那段的注释）。
Key _rangeKey(String prefix, HkWheel w) =>
    ValueKey('$prefix-${w.count}-${w.labels.first}-${w.labels.last}');

/// 给一张报告逐条录检验项（原型 `hmkOpen`/`hmkAdd`/`hmkList`）。
///
/// 四条口径写在最近处：
/// · 项目库十枚**点芯片就带入**名称/单位/参考范围，并把数值滚轮收窄到 `(下限-1, 上限+1)`、
///   默认档落参考中点（原型 `hmkLib`）——量程由 `hkWheelsFor` 一处算，弹层不摆第二个量程表；
/// · 判档预览（`hmkTip`）跟着三柱实时改口，**边界值算正常**这条也在域层，不在这拼字符串；
/// · 「加入本报告」后**弹层不关**（原型 `hmkAdd` 只刷新已录列表）：一张报告动辄十几项，
///   录一项关一层等于把用户赶回卡片再进来一次；
/// · 已录行末「删」＝按 id＋归属报告双闸删行，列表就地少一行、卡片角标随 tick++ 重算。
Future<void> showHealthMetricSheet(BuildContext context,
        {required HealthReport report, required List<ReportMetric> metrics}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MetricSheet(report: report, metrics: metrics),
    );

class _MetricSheet extends ConsumerStatefulWidget {
  const _MetricSheet({required this.report, required this.metrics});

  final HealthReport report;
  final List<ReportMetric> metrics;

  @override
  ConsumerState<_MetricSheet> createState() => _MetricSheetState();
}

class _MetricSheetState extends ConsumerState<_MetricSheet> {
  late final TextEditingController _name = TextEditingController();

  /// 本地镜像＝录入序（原型 `r.ms.push`）；每次写库成功后同步这一份，
  /// 弹层列表与页面上的卡片同吃 tick++ 重取，不会各数各的。
  late final List<ReportMetric> _ms = [...widget.metrics];

  late HkWheels _w = hkWheelsFor();

  @override
  void initState() {
    super.initState();
    // 原型 `hmkNameIn` 的 `oninput="hmkTip()"`：手打项目名也要当场把判档预览改口，
    // 不是只有点项目库／滚滚轮才刷新。
    _name.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_rebuild);
    _name.dispose();
    super.dispose();
  }

  String get _nm => _name.text.trim();

  /// 项目库芯片：名字写进输入框，三柱按该项量程重铺（原型 `hmkLib` 的三件事一件不落）。
  void _pickLib(HkLibItem m) {
    setState(() {
      _name.text = m.name;
      _w = hkWheelsFor(refLo: m.refLo, refHi: m.refHi);
    });
  }

  Future<void> _add() async {
    if (_nm.isEmpty) {
      AppToast.show(context, rpNeedMetricNameTx);
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    // 单位为空串＝这一项没有单位（原型 `|| ''`），落库写 null：
    // 「空」和「单位真的是空字符串」在表里不该长一个样，回读侧 `rpMetricValueTx` 两态都出纯数值。
    final unit = hkUnitOf(_nm);
    final m = ReportMetric(
      reportId: widget.report.id,
      name: _nm,
      value: _w.val.value,
      unit: unit.isEmpty ? null : unit,
      refLo: _w.lo.value,
      refHi: _w.hi.value,
    );
    final id = await container.read(healthRepositoryProvider).addMetric(m);
    if (!mounted) return;
    setState(() => _ms.add(m.copyWith(id: id)));
    container.read(healthTickProvider.notifier).state++;
    AppToast.show(context, rpMetricAddedTx(_nm));
  }

  Future<void> _remove(ReportMetric m) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container
        .read(healthRepositoryProvider)
        .deleteMetric(widget.report.id!, m.id!);
    if (!mounted) return;
    setState(() => _ms.removeWhere((e) => e.id == m.id));
    container.read(healthTickProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tip = _nm.isEmpty
        ? rpTipHintTx
        : rpTipTx(
            name: _nm, value: _w.val.value, lo: _w.lo.value, hi: _w.hi.value);
    return _sheetShell(
      context,
      title: '录入检验项目',
      children: [
        Text(rpMetricSub(widget.report, _ms.length),
            key: const ValueKey('hmk-sub'),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        Text('常用项目库',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('hmk-lib'),
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final m in hkLib)
              _keyed(
                  _chip(context,
                      label: m.name,
                      on: _nm == m.name,
                      onTap: () => _pickLib(m)),
                  ValueKey('hmk-lib-${m.name}')),
          ],
        ),
        const SizedBox(height: 10),
        _field(context, '项目名称', 'hmk-name', _name, '点上方项目库带入 · 或自定义'),
        const SizedBox(height: 10),
        // 三柱并排各占一份：LHWheel 不包 Expanded 会拿到 w=Infinity（CupertinoPicker 当场炸）。
        // key 只挂**量程身份**（档数＋首末档），不挂选中档：滚轮自己会在 didUpdateWidget 里认档，
        // key 里带上 index 等于每滚一格就重建一次 State——正在甩动的动画连同控制器一起被拆掉。
        // 换项目库＝量程整个换掉，此时 key 变、旧 State 不复用（批2.5 既定坑）。
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _wheel(context,
                  label: '数值',
                  labels: _w.val.labels,
                  key: _rangeKey('hmkVal', _w.val),
                  index: _w.val.index,
                  onSelect: (v) => setState(() => _w = _withVal(v)),
                  keyPrefix: 'hmkVal'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _wheel(context,
                  label: '参考下限',
                  labels: _w.lo.labels,
                  key: _rangeKey('hmkLo', _w.lo),
                  index: _w.lo.index,
                  onSelect: (v) => setState(() => _w = _withLo(v)),
                  keyPrefix: 'hmkLo'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _wheel(context,
                  label: '参考上限',
                  labels: _w.hi.labels,
                  key: _rangeKey('hmkHi', _w.hi),
                  index: _w.hi.index,
                  onSelect: (v) => setState(() => _w = _withHi(v)),
                  keyPrefix: 'hmkHi'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(tip,
            key: const ValueKey('hmk-tip'),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hmk-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                  key: const ValueKey('hmk-add'),
                  onPressed: _add,
                  child: const Text('加入本报告')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('已录项目',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        if (_ms.isEmpty)
          Text(rpNoMetricTx,
              key: const ValueKey('hmk-empty'),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
        else
          Column(
            key: const ValueKey('hmk-list'),
            children: [
              for (final m in _ms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    key: ValueKey('hmk-row-${m.id}'),
                    children: [
                      Expanded(
                          child: Text(m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11))),
                      Text(rpMetricValueTx(m),
                          style:
                              const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Text(rpMetricRefTx(m),
                          style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      TextButton(
                        key: ValueKey('hmk-del-${m.id}'),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact),
                        onPressed: () => _remove(m),
                        child: Text('删',
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.error,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // 三柱各自换档＝在同一份量程表上挪选中位（量程不动，避免每滚一下就把柱表重造一次）。
  HkWheels _withVal(int i) => HkWheels(
      val: HkWheel(values: _w.val.values, index: i), lo: _w.lo, hi: _w.hi);
  HkWheels _withLo(int i) => HkWheels(
      val: _w.val, lo: HkWheel(values: _w.lo.values, index: i), hi: _w.hi);
  HkWheels _withHi(int i) => HkWheels(
      val: _w.val, lo: _w.lo, hi: HkWheel(values: _w.hi.values, index: i));
}
