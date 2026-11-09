// 期4 · JS 求值桥：优先真 Bellard QuickJS(qjs.exe)，回落 Node 代引擎
// 注入 Legado 宿主面子集：java.*/cookie.*，供 @js: 规则执行。
import 'dart:convert';
import 'dart:io';

class JsBridge {
  JsBridge({this.verbose = false}) : engine = _detectEngine();
  final bool verbose;
  final String engine; // 'qjs' = 真 QuickJS 2026-06-04 · 'node' = 代引擎
  static final usedApis = <String>{}; // 桥 API 使用统计（期4立项依据）

  static String _detectEngine() =>
      File('qjs/qjs.exe').existsSync() ? 'qjs' : 'node';

  static const _marker = '__LHJSOUT__';

  /// 执行一段 Legado 风格 js：result 为输入与隐式返回值。
  String run(String js, String result,
      {String baseUrl = '', String key = ''}) {
    return engine == 'qjs'
        ? _runQjs(js, result, baseUrl, key)
        : _runNode(js, result, baseUrl, key);
  }

  void _recordApis(String js) {
    for (final m in RegExp(r'\b(java|cookie)\.(\w+)').allMatches(js)) {
      usedApis.add('${m.group(1)}.${m.group(2)}');
    }
  }

  // ---------- qjs ----------
  String _runQjs(String js, String result, String baseUrl, String key) {
    final prelude = '''
var result=${jsonEncode(result)};
var baseUrl=${jsonEncode(baseUrl)};
var key=${jsonEncode(key)}; var page=1;
var java={
  log:function(){}, toast:function(){}, longToast:function(){},
  ajax:function(u){ try{ var p=std.popen("curl -sL --max-time 25 -A Mozilla/5.0 "+String(u),"r"); var s=p.readAll(); p.close(); return s; }catch(e){ return ""; } },
  get:function(u){ return java.ajax(typeof u==="string"?u:""); },
  post:function(u,b){ try{ var p=std.popen("curl -sL --max-time 25 -X POST --data "+String(b)+" "+String(u),"r"); var s=p.readAll(); p.close(); return s; }catch(e){ return ""; } },
  put:function(k,v){ java.__m[k]=String(v); },
  getString:function(k){ return java.__m[k]||""; },
  base64Decode:function(s){ return String(s); },
  encodeURI:function(s){ return encodeURIComponent(String(s)); },
  timeFormat:function(t){ return new Date(Number(t)).toISOString(); },
  androidId:function(){ return "probe-android-id"; },
  cacheFile:function(u){ return java.ajax(u); },
  getElement:function(){ return ""; },
};
java.__m={};
var cookie={getCookie:function(){return "";},setCookie:function(){},replaceCookie:function(){},removeCookie:function(){}};
''';
    final body = '$prelude\nvar __last=result;\n'
        'try { __last = eval(${jsonEncode(js)}); } catch(e) { console.error(String(e)); }\n'
        'if (typeof __last !== "undefined" && __last !== null) result = __last;\n'
        'console.log("$_marker" + JSON.stringify({result: String(result)}));\n';
    final dir = Directory('tmpjs')..createSync(recursive: true);
    final f = File('${dir.path}/lh_case.js')..writeAsStringSync(body);
    final r = Process.runSync('qjs/qjs.exe', ['--std', f.path],
        stdoutEncoding: utf8);
    final out = r.stdout as String;
    final idx = out.lastIndexOf(_marker);
    if (idx < 0) {
      throw StateError('qjs 执行失败: ${(r.stderr as String).trim()}');
    }
    _recordApis(js);
    final j = jsonDecode(out.substring(idx + _marker.length)) as Map;
    return '${j['result']}';
  }

  // ---------- node（代引擎） ----------
  String _runNode(String js, String result, String baseUrl, String key) {
    final payload = jsonEncode({
      'js': js,
      'result': result,
      'baseUrl': baseUrl,
      'key': key,
    });
    final harness = r'''
const input=JSON.parse(require('fs').readFileSync(process.argv[2],'utf8'));
const java={
  log:(...a)=>console.error('[js]',...a),
  toast:()=>{}, longToast:()=>{},
  ajax:(u)=>require('child_process').execFileSync(
      'curl',['-sL','--max-time','25','-A','Mozilla/5.0',String(u)],
      {maxBuffer:1<<26}).toString(),
  get:(u,fn)=>java.ajax(typeof u==='string'?u:JSON.stringify(u)),
  post:(u,b,h)=>require('child_process').execFileSync(
      'curl',['-sL','--max-time','25','-A','Mozilla/5.0','-X','POST',
       '--data',String(b),String(u)],{maxBuffer:1<<26}).toString(),
  put:(k,v)=>{input.__put=input.__put||{};input.__put[k]=String(v);},
  getString:(k)=>(input.__put||{})[k]||'',
  base64Decode:s=>Buffer.from(String(s),'base64'),
  base64Encode:s=>Buffer.from(String(s)).toString('base64'),
  hexDecodeToString:s=>Buffer.from(String(s),'hex').toString(),
  encodeURI:(s,c)=>encodeURIComponent(String(s)),
  timeFormat:t=>new Date(Number(t)).toISOString(),
  androidId:()=>'probe-android-id',
  cacheFile:(u)=>java.ajax(u),
  getElement:(r)=>'', getStringFromElements:()=>'',
};
const jar={};
const cookie={
  getCookie:u=>jar[u]||'',
  setCookie:(u,c)=>{jar[u]=String(c);},
  replaceCookie:(u,c)=>{jar[u]=String(c);},
  removeCookie:u=>{delete jar[u];},
};
let out;
try{
  const f=new Function('java','cookie','baseUrl','key',
    'var result='+JSON.stringify(input.result)+';\n'+
    'var __last=eval('+JSON.stringify(input.js)+');\n'+
    'if(typeof __last!=="undefined"&&__last!==null) result=__last;\n'+
    'return result;');
  out=f(java,cookie,input.baseUrl,input.key);
}catch(e){
  process.stdout.write(JSON.stringify({ok:false,err:String(e)}));
  process.exit(0);
}
process.stdout.write(JSON.stringify({ok:true,result:out===null||out===undefined?'':String(out),
  cookieJar:jar}));
''';
    final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lhjs_${DateTime.now().microsecondsSinceEpoch}.json');
    tmp.writeAsStringSync(payload);
    final hf =
        File('${Directory.systemTemp.path}${Platform.pathSeparator}lhjs_harness.js')
          ..writeAsStringSync(harness);
    ProcessResult r;
    try {
      r = Process.runSync('node', [hf.path, tmp.path], stdoutEncoding: utf8);
    } catch (_) {
      r = Process.runSync('node', [hf.path, tmp.path],
          runInShell: true, stdoutEncoding: utf8);
    }
    tmp.deleteSync();
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    if (j['ok'] != true) {
      if (verbose) stderr.writeln('  [js失败] ${j['err']}');
      throw StateError('JS执行失败: ${j['err']}');
    }
    _recordApis(js);
    return j['result'] as String;
  }
}
