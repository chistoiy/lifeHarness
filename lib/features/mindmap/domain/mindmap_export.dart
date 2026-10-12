/// 导出序列化层（批2 F4-5 · 冻结方案 §2.5/§4.10）。
///
/// 同一序列化层多渲染器：md（缩进大纲，零 `#`＝再导入走同一缩进通道完全保真）、
/// opml（标准 2.0 outline）、HTML（自包含单文件·§4.10 冻结规格）。
/// PNG 走画布离屏绘制（UI 层，`shared/export/png_encode.dart` 编码尾段）。
///
/// HTML 硬口径（§4.10，变异刀1 钉点）：
/// · 单文件零外链（CSS/JS 内联，不引 CDN/外部字体）；
/// · 可操作三件：折叠/展开、点节点看**挂载笔记的标题与摘要**（导出时快照）、
///   画布平移缩放；**不含编辑**；
/// · 初始坐标＝App 同一 `TreeLayoutEngine` 输出（调用侧布局后传入）；
/// · 深浅色跟随 `prefers-color-scheme`（内联两套令牌）；
/// · **挂载正文默认只导标题不导正文**——正文是否带由调用侧决定传不传
///   `noteBodies`（导出弹层开关默认关；本文件不提供「默认带正文」路径）；
/// · 横向预设：`landscape` 预设位（落法 C：文件自带横向布局预设）。
library;

import 'dart:ui' show Offset, Size;

import 'mindmap_layout.dart' show MmEdgeKind;
import 'mindmap_models.dart';

// ==================== md ====================

/// 缩进大纲（两空格/级）——与 `md_parse.dart` 缩进通道互为逆操作：
/// 导出件再导入走同一缩进通道（零 `#` ⇒ 主通道判定必落缩进）＝完全保真。
/// 多根＝多个顶层行（解析侧各成树，C6 多根语义 round-trip 成立）。
String mmExportMarkdown(List<MindmapNode> rows) {
  final children = <int?, List<MindmapNode>>{};
  for (final n in rows) {
    children.putIfAbsent(n.parentId, () => []).add(n);
  }
  for (final list in children.values) {
    list.sort((a, b) => a.sort.compareTo(b.sort));
  }
  final buf = StringBuffer();
  void walk(int? parentId, int depth) {
    for (final n in children[parentId] ?? const <MindmapNode>[]) {
      buf.write('  ' * depth);
      buf.writeln(n.title.replaceAll('\n', ' '));
      walk(n.id, depth + 1);
    }
  }

  walk(null, 0);
  return buf.toString();
}

// ==================== opml ====================

String _xmlAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// OPML 2.0（标准大纲交换格式；`text` 必备属性，`_note` 可选备注）。
String mmExportOpml(String mapTitle, List<MindmapNode> rows) {
  final children = <int?, List<MindmapNode>>{};
  for (final n in rows) {
    children.putIfAbsent(n.parentId, () => []).add(n);
  }
  for (final list in children.values) {
    list.sort((a, b) => a.sort.compareTo(b.sort));
  }
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln('<opml version="2.0">');
  buf.writeln('  <head><title>${_xmlAttr(mapTitle)}</title></head>');
  buf.writeln('  <body>');
  void walk(int? parentId, int depth) {
    for (final n in children[parentId] ?? const <MindmapNode>[]) {
      final pad = '  ' * (depth + 2);
      final note = n.note.isEmpty ? '' : ' _note="${_xmlAttr(n.note)}"';
      buf.writeln('$pad<outline text="${_xmlAttr(n.title)}"$note>');
      walk(n.id, depth + 1);
      buf.writeln('$pad</outline>');
    }
  }

  walk(null, 0);
  buf.writeln('  </body>');
  buf.writeln('</opml>');
  return buf.toString();
}

// ==================== HTML ====================

/// 一个节点的导出快照行（displayTitle 已由调用侧合成：挂载笔记标题优先、
/// 失效回落节点自身标题——与画布显示口径一致）。
class MmExportNode {
  MmExportNode({
    required this.id,
    required this.parentId,
    required this.displayTitle,
    this.note,
    this.noteTitle,
    this.noteBody,
    this.folded = false,
  });

  final int id;
  final int? parentId;
  final String displayTitle;

  /// 节点备注（非挂载正文）。
  final String? note;

  /// 挂载笔记标题快照（§4.10：点节点跳「标题与摘要」的标题侧）。
  final String? noteTitle;

  /// 挂载笔记正文快照——**仅导出弹层显式勾选才传**（§4.10 隐私硬口径）。
  final String? noteBody;

  final bool folded;
}

/// 自包含 HTML。`boundsWidth/boundsHeight`＝布局外沿（fit 初始视口用）。
String mmExportHtml({
  required String mapTitle,
  required List<MmExportNode> nodes,
  required Map<int, Offset> baseline,
  required Map<int, Size> sizes,
  required double boundsWidth,
  required double boundsHeight,
  required bool landscapePreset,

  /// 批4：连线画法随布局形态（`stair`＝纵向阶梯贝塞尔／`branch`·`radial`
  /// ＝父中心到子中心直线）。不传按 `stair`＝批2 既有行为逐值不变。
  MmEdgeKind edgeKind = MmEdgeKind.stair,
  required String exportedAt,
}) {
  final data = <String, Object?>{
    'title': mapTitle,
    'landscape': landscapePreset,
    'bounds': [boundsWidth, boundsHeight],
    'edgeKind': edgeKind.name,
    'exportedAt': exportedAt,
    'nodes': [
      for (final n in nodes)
        {
          'id': n.id,
          'pid': n.parentId,
          't': n.displayTitle,
          'x': baseline[n.id]?.dx ?? 0,
          'y': baseline[n.id]?.dy ?? 0,
          'w': sizes[n.id]?.width ?? 120,
          'h': sizes[n.id]?.height ?? 36,
          'note': (n.note == null || n.note!.isEmpty) ? null : n.note,
          'nt': n.noteTitle,
          'nb': n.noteBody,
          'fold': n.folded,
        },
    ],
  };
  // `<` 全转义：标题里出现 `</script>` 不会断内联 script（JSON 层合法转义）。
  final json = _jsonEncode(data).replaceAll('<', '\\u003c');
  return _htmlTemplate
      .replaceAll('__TITLE__', _htmlEsc(mapTitle))
      .replaceAll('__DATA__', json);
}

String _htmlEsc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// 极简 JSON 编码（只为导出数据；字符串/数字/bool/null/列表/映射）。
String _jsonEncode(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) {
    return v.toDouble() == v.roundToDouble()
        ? v.round().toString()
        : v.toString();
  }
  if (v is String) {
    final esc = v
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$esc"';
  }
  if (v is List) return '[${v.map(_jsonEncode).join(',')}]';
  if (v is Map) {
    return '{${v.entries.map((e) => '${_jsonEncode(e.key.toString())}:${_jsonEncode(e.value)}').join(',')}}';
  }
  return '"$v"';
}

/// HTML 模板。raw 三引号＋占位符替换（无 dart 插值冲突）；JS 内不用模板字面量。
const String _htmlTemplate = r'''
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root{--bg:#ffffff;--fg:#1f1f23;--node-bg:#f4f4f6;--node-bd:#d9d9de;--line:#bcbcc4;--sel:#6c4ce0;--muted:#8a8a92;--panel:#ffffff;}
@media (prefers-color-scheme:dark){:root{--bg:#151518;--fg:#e8e8ec;--node-bg:#242428;--node-bd:#3a3a40;--line:#4a4a52;--sel:#a78bfa;--muted:#77777e;--panel:#1e1e22;}}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
html,body{margin:0;height:100%;background:var(--bg);color:var(--fg);font-family:system-ui,'Noto Sans CJK SC',sans-serif;overflow:hidden;}
#bar{position:fixed;top:0;left:0;right:0;height:44px;display:flex;align-items:center;gap:8px;padding:0 12px;background:var(--panel);border-bottom:1px solid var(--node-bd);z-index:10;}
#bar b{font-size:15px;}
#bar span{color:var(--muted);font-size:12px;}
#bar .sp{flex:1;}
#bar button{border:1px solid var(--node-bd);background:var(--node-bg);color:var(--fg);border-radius:6px;padding:6px 10px;font-size:13px;cursor:pointer;}
#bar button.on{border-color:var(--sel);color:var(--sel);}
#vp{position:absolute;top:44px;bottom:0;left:0;right:0;overflow:hidden;touch-action:none;cursor:grab;}
#cv{position:absolute;transform-origin:0 0;}
#edges{position:absolute;left:0;top:0;overflow:visible;}
.nd{position:absolute;background:var(--node-bg);border:1px solid var(--node-bd);border-radius:8px;padding:7px 12px;min-height:36px;display:flex;align-items:center;gap:6px;font-size:14px;white-space:pre-wrap;word-break:break-word;cursor:pointer;user-select:none;}
.nd.sel{border-color:var(--sel);box-shadow:0 0 0 2px color-mix(in srgb,var(--sel) 30%,transparent);}
.nd .fold{color:var(--sel);font-size:11px;border:1px solid var(--sel);border-radius:10px;padding:0 6px;line-height:16px;}
.nd .mm{color:var(--muted);font-size:11px;}
#detail{position:fixed;left:12px;right:12px;bottom:12px;max-height:45%;overflow:auto;background:var(--panel);border:1px solid var(--node-bd);border-radius:12px;padding:14px 16px;z-index:20;display:none;}
#detail h3{margin:0 0 6px;font-size:15px;}
#detail .sub{color:var(--muted);font-size:12px;margin-bottom:8px;}
#detail .body{font-size:13px;line-height:1.7;white-space:pre-wrap;word-break:break-word;font-family:'Noto Serif CJK SC',serif;}
#detail .x{position:absolute;top:8px;right:12px;color:var(--muted);cursor:pointer;font-size:18px;}
</style>
</head>
<body>
<div id="bar"><b id="bt"></b><span id="bs"></span><div class="sp"></div>
<button id="zout">−</button><button id="zin">＋</button><button id="fit">fit</button>
<button id="lsp">横向</button></div>
<div id="vp"><div id="cv"><svg id="edges"></svg><div id="nodes"></div></div></div>
<div id="detail"><span class="x" id="dx">✕</span><h3 id="dt"></h3><div class="sub" id="ds"></div><div class="body" id="db"></div></div>
<script>var DATA=__DATA__;</script>
<script>
(function(){
var byId={},kids={};
DATA.nodes.forEach(function(n){byId[n.id]=n;if(n.pid!=null){(kids[n.pid]=kids[n.pid]||[]).push(n.id);}});
var vp=document.getElementById('vp'),cv=document.getElementById('cv'),nodesEl=document.getElementById('nodes'),edges=document.getElementById('edges');
var scale=1,tx=20,ty=20,sel=null;
function visible(n){var p=n.pid;while(p!=null){var par=byId[p];if(!par)return true;if(par.fold)return false;p=par.pid;}return true;}
function render(){
  nodesEl.innerHTML='';edges.innerHTML='';
  var svg='';var frag=document.createDocumentFragment();
  DATA.nodes.forEach(function(n){
    if(!visible(n))return;
    var d=document.createElement('div');d.className='nd';d.dataset.id=n.id;
    d.style.left=n.x+'px';d.style.top=n.y+'px';d.style.maxWidth=(n.w+60)+'px';
    if(sel===n.id)d.classList.add('sel');
    var t=document.createElement('span');t.textContent=n.t;d.appendChild(t);
    if(n.nt){var m=document.createElement('span');m.className='mm';m.textContent='笔记';d.appendChild(m);}
    if(n.fold&&kids[n.id]){var f=document.createElement('span');f.className='fold';f.textContent='+'+countDesc(n.id);d.appendChild(f);}
    d.addEventListener('click',function(e){e.stopPropagation();pick(n);});
    frag.appendChild(d);
    if(n.pid!=null&&byId[n.pid]&&visible(n)&&visible(byId[n.pid])){
      var p=byId[n.pid];
      /* 批4：连线画法跟布局形态（DATA.edgeKind）。纵向大纲走父底→子顶的
         竖向贝塞尔；横向树/放射走父中心→子中心直线（套阶梯公式会斜穿节点）。 */
      var d;
      if(DATA.edgeKind==='stair'){
        var x1=p.x+p.w/2,y1=p.y+p.h,x2=n.x+n.w/2,y2=n.y;
        d='M'+x1+' '+y1+' C'+x1+' '+(y1+14)+' '+x2+' '+(y2-14)+' '+x2+' '+y2;
      }else{
        d='M'+(p.x+p.w/2)+' '+(p.y+p.h/2)+' L'+(n.x+n.w/2)+' '+(n.y+n.h/2);
      }
      svg+='<path d="'+d+'" fill="none" stroke="var(--line)" stroke-width="1.5"/>';
    }
  });
  edges.innerHTML=svg;nodesEl.appendChild(frag);
  applyT();
}
function countDesc(id){var c=0;(function w(i){(kids[i]||[]).forEach(function(k){c++;w(k);});})(id);return c;}
function applyT(){cv.style.transform='translate('+tx+'px,'+ty+'px) scale('+scale+')';}
function fit(){var b=DATA.bounds;var vw=vp.clientWidth-40,vh=vp.clientHeight-40;scale=Math.min(1,vw/Math.max(1,b[0]),vh/Math.max(1,b[1]));if(scale<=0)scale=0.2;tx=20;ty=20;applyT();}
function pick(n){sel=n.id;var dt=document.getElementById('dt'),ds=document.getElementById('ds'),db=document.getElementById('db');
  dt.textContent=n.t;
  ds.textContent=n.nt?('来自笔记：'+n.nt):(n.note?'备注':'（未挂笔记）');
  db.textContent=n.nb||n.note||'';
  document.getElementById('detail').style.display='block';render();}
document.getElementById('dx').onclick=function(){document.getElementById('detail').style.display='none';};
vp.addEventListener('click',function(){if(sel!=null){sel=null;render();}});
// 平移（单指/鼠标拖）
vp.addEventListener('pointerdown',function(e){if(e.button)return;var sx=e.clientX,sy=e.clientY,ox=tx,oy=ty;vp.setPointerCapture(e.pointerId);vp.style.cursor='grabbing';
 function mv(ev){tx=ox+ev.clientX-sx;ty=oy+ev.clientY-sy;applyT();}
 function up(){vp.removeEventListener('pointermove',mv);vp.removeEventListener('pointerup',up);vp.style.cursor='grab';}
 vp.addEventListener('pointermove',mv);vp.addEventListener('pointerup',up);});
// 双指捏合缩放
var pinch0=null;
vp.addEventListener('touchstart',function(e){if(e.touches.length===2){var dx=e.touches[0].clientX-e.touches[1].clientX,dy=e.touches[0].clientY-e.touches[1].clientY;pinch0={d:Math.hypot(dx,dy),s:scale};}},{passive:true});
vp.addEventListener('touchmove',function(e){if(e.touches.length===2&&pinch0){var dx=e.touches[0].clientX-e.touches[1].clientX,dy=e.touches[0].clientY-e.touches[1].clientY;scale=Math.max(0.1,Math.min(4,pinch0.s*Math.hypot(dx,dy)/pinch0.d));applyT();}},{passive:true});
vp.addEventListener('touchend',function(){pinch0=null;});
vp.addEventListener('wheel',function(e){e.preventDefault();scale=Math.max(0.1,Math.min(4,scale*(e.deltaY<0?1.1:0.9)));applyT();},{passive:false});
document.getElementById('zin').onclick=function(){scale=Math.min(4,scale*1.2);applyT();};
document.getElementById('zout').onclick=function(){scale=Math.max(0.1,scale/1.2);applyT();};
document.getElementById('fit').onclick=fit;
// 横向预设（落法 C：文件自带，浏览器想转就转；开关只翻转容器比例）
var lsp=false;
document.getElementById('lsp').onclick=function(){lsp=!lsp;this.classList.toggle('on',lsp);
  var b=DATA.bounds;document.getElementById('cv').style.width=(lsp?Math.max(b[1]*1.6,b[0]):b[0])+'px';fit();};
// bootstrap
document.getElementById('bt').textContent=DATA.title;
document.getElementById('bs').textContent=DATA.nodes.length+' 节点 · 导出于 '+DATA.exportedAt+(DATA.landscape?' · 横向预设':'');
render();fit();
})();
</script>
</body>
</html>
''';
