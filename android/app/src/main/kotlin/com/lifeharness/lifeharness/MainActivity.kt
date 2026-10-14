package com.lifeharness.lifeharness

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/// V1.53.4⑥ 系统「打开方式」接收本地文件 → V1.64 批1 泛化多类型（工单
/// 交棒话术-20261004 §2 N-3 · 拍板 G）。冷启动经 configureFlutterEngine 里的
/// handle(intent) 入队；热启动（singleTop）经 onNewIntent 入队。Dart 侧经
/// MethodChannel `lh/intents` 的 takeOpenFile 单次消费（Map：kind/path/name/uri；
/// null=无待处理，kind ""=不支持类型），App 唤醒（resumed）时再取。
/// `lh/saf` 通道：saveAs＝「另存为」（备份/X-Ray 导出共用）；
/// writeBack＝按打开方式原始 content URI 覆写（授权失效/文件不在按码返回，不抛错）。
/// V1.64 批2（工单 交棒话术-20261004 §12）追加四枚本地导入用：pickTree（选目录·
/// 取持久化读授权）/ pickFiles（多选文件）/ listTree（回所选目录的根节点，只含
/// 目录与 .md/.markdown，深度与子项数封顶）/ readDoc（按 URI 读 UTF-8 正文）。
/// 轮6 换通道根因：flutter_file_dialog 在 onActivityResult 对 sourceFile `!!`
/// 冷投必 NPE（真机 0 字节事故），且拷贝强转 FileOutputStream——本实现无挂起态
/// 静默忽略过期结果、拷贝走通用流。
class MainActivity : FlutterActivity() {

    private var pendingUri: Uri? = null
    private var pendingName: String? = null

    // 批B：悬浮窗「■ 结束」入队（kind 回显）；Dart 侧 takePillEvent 单次消费
    // （与打开方式文件同模式——事件经意图拉起 app 前台后落在这里）。
    private var pendingPillEnd: String? = null

    /**
     * 悬浮窗「＋笔记」待处理动作（6135·与 app 内胶囊按钮对齐）。
     * 值为会话侧kind（read/media）；null＝无待处理。
     */
    private var pendingPillNote: String? = null

    // ---- lh/saf 挂起态（仅内存：进程死亡即失，结果过期被静默忽略）----
    private var safResult: MethodChannel.Result? = null
    private var safSource: String? = null

    // V1.64 批2：目录/多文件选择器的挂起态（同样仅内存；过期结果静默忽略）
    private var treeResult: MethodChannel.Result? = null
    private var filesResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 6133 热修：系统悬浮窗的显隐由原生自测「本进程有没有已 start 的
        // Activity」——BACK 退 app 会连 FlutterEngine/Dart 隔离区一起销毁，
        // 靠 Dart 推的显隐在真机上会永久缺席（详见 TimerPillService 顶部注释）。
        // 注册点必须在 onCreate（早于本次 onStart），否则首个计数会漏。
        AppVisibility.registerOnce(application)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent == null) return
        // 批B：悬浮窗「■ 结束」意图（点胶囊结束钮/通知结束动作）——入队等
        // Dart 侧 takePillEvent 消费。
        if (intent.action == ACTION_PILL_END) {
            pendingPillEnd = intent.getStringExtra(EXTRA_PILL_KIND) ?: "read"
            return
        }
        // 批B：悬浮窗「＋笔记」意图（6135·app 内胶囊同款双按钮）——同样入队
        // 等 Dart 侧 takePillEvent 消费后开书摘新建页。
        if (intent.action == ACTION_PILL_NOTE) {
            pendingPillNote = intent.getStringExtra(EXTRA_PILL_KIND) ?: "read"
            return
        }
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        pendingUri = uri
        pendingName = queryName(uri)
    }

    private fun queryName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path?.substringAfterLast('/')
        var name: String? = null
        try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0) name = c.getString(i)
                }
            }
        } catch (_: Exception) {
            // 个别 provider 不支持 query：回落 uri 尾段
        }
        return name ?: uri.lastPathSegment?.substringAfterLast('/')
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handle(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "lh/intents"
        ).setMethodCallHandler { call, result ->
            if (call.method == "takeOpenFile") {
                result.success(takeOpen())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "lh/saf"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveAs" -> safSaveAs(call, result)
                "writeBack" -> writeBack(call, result)
                "pickTree" -> safPickTree(result)
                "pickFiles" -> safPickFiles(result)
                "listTree" -> safListTree(call, result)
                "readDoc" -> safReadDoc(call, result)
                "createInTree" -> safCreateInTree(call, result)
                "ensureDirInTree" -> safEnsureDirInTree(call, result)
                else -> result.notImplemented()
            }
        }
        // 批B：app 外系统悬浮窗通道（工单 悬浮胶囊增强批-20261014 §7）。
        // 起服务只从 app 前台触发（Dart 侧 sync 口径）——规避 Android 14+
        // 后台起 FGS 限制；stopService 不受该限制。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "lh/pill"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "sync" -> {
                    val p = TimerPillService.PillPayload(
                        kind = call.argument<String>("kind") ?: "read",
                        title = call.argument<String>("title") ?: "",
                        status = call.argument<String>("status") ?: "",
                        seconds = call.argument<Int>("seconds") ?: 0,
                        // Dart int 过通道可能落成 Int 或 Long，按 Number 取。
                        startedAtMs = (call.argument<Number>("startedAt"))
                            ?.toLong() ?: 0L,
                        visible = call.argument<Boolean>("visible") ?: true,
                    )
                    try {
                        startForegroundService(TimerPillService.syncIntent(this, p))
                    } catch (_: Exception) {
                        // 起服务被权限/ROM 拒绝＝降级为无 app 外悬浮窗，不崩
                        // （6128 实伤：缺 FGS 基础权限时这里 SecurityException 即闪退）。
                    }
                    result.success(null)
                }
                // 6132 热修：Dart 侧诊断日志落 logcat tag lh_pill（release 可见，
                // 装机排障用；仅打点，不影响功能）。
                "log" -> {
                    android.util.Log.i(
                        TimerPillService.TAG,
                        "[dart] ${call.argument<String>("msg") ?: ""}",
                    )
                    result.success(null)
                }
                "stop" -> {
                    stopService(TimerPillService.stopIntent(this))
                    result.success(null)
                }
                "takePillEvent" -> result.success(takePill())
                else -> result.notImplemented()
            }
        }
    }

    /// 批B：跳系统「显示在其他应用上层」授权页（Android 11+ 无弹窗式授权，
    /// 走系统设置页；授权结果由 Dart 侧在 resumed 后经 canDrawOverlays 复探）。
    private fun requestOverlayPermission() {
        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            )
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
            } catch (_: Exception) {
                // 无设置页可跳：调用方保持关闭态（降级仅 app 内胶囊）。
            }
        }
    }

    /// 批B：悬浮窗一次性消费（null＝无待处理；与 [takeOpen] 同模式）。
    /// 6135：end（结束）优先于 note（＋笔记），二者在原生侧互斥入队。
    private fun takePill(): Map<String, String>? {
        val kind = pendingPillEnd ?: pendingPillNote ?: return null
        val type = if (pendingPillEnd != null) "end" else "note"
        pendingPillEnd = null
        pendingPillNote = null
        return mapOf("type" to type, "kind" to kind)
    }

    // ---- lh/saf：SAF「另存为」实现 ----

    private fun safSaveAs(call: MethodCall, result: MethodChannel.Result) {
        val src = call.argument<String>("srcPath")
        val name = call.argument<String>("fileName")
        if (src == null || name == null || !File(src).exists()) {
            result.error("bad_args", "源文件不存在", null)
            return
        }
        if (safResult != null) {
            result.error("busy", "保存层已在进行中", null)
            return
        }
        safResult = result
        safSource = src
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            startActivityForResult(intent, REQ_SAF_SAVE)
        } catch (e: Exception) {
            safResult = null
            safSource = null
            result.error("no_provider", e.localizedMessage, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAF_TREE) {
            val res = treeResult
            treeResult = null
            if (res == null) return // 过期结果：同 saveAs 口径静默忽略，不崩
            if (resultCode != RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            val tree = data.data!!
            // 工单 §3 红线：目录授权必须持久化（重启后还能按原挂载继续导入）。
            // 2026-10-11 真机反馈批③（拍板「挂载即双向」）：一次拿够读＋写；个别 provider
            // 只给只读（DocumentsUI 的「仅查看」档），拿写失败退回只读——导入照旧能用，
            // 写回那侧由 Dart 按 no_perm 出一行人话，不因授权档位让整条入口失败。
            try {
                contentResolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: Exception) {
                try {
                    contentResolver.takePersistableUriPermission(
                        tree, Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (e: Exception) {
                    res.error("no_perm", e.localizedMessage, null)
                    return
                }
            }
            res.success(tree.toString())
            return
        }
        if (requestCode == REQ_SAF_FILES) {
            val res = filesResult
            filesResult = null
            if (res == null) return
            if (resultCode != RESULT_OK || data == null) {
                res.success(emptyList<Map<String, Any>>())
                return
            }
            val uris = ArrayList<Uri>()
            data.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            }
            if (uris.isEmpty()) data.data?.let { uris.add(it) }
            res.success(uris.map { u ->
                try {
                    contentResolver.takePersistableUriPermission(
                        u, Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Exception) {
                    // 个别 provider 不给持久化读：本次导入仍可用，下次重进需重选。
                }
                mapOf("name" to (queryName(u) ?: ""), "uri" to u.toString(), "dir" to false)
            })
            return
        }
        if (requestCode != REQ_SAF_SAVE) return
        val res = safResult
        val src = safSource
        safResult = null
        safSource = null
        // 过期结果（进程在选择器期间被杀后冷启动投递，或重复回调）：
        // Dart 侧无人等待，静默忽略——旧插件正是在这里 `!!` 崩溃。
        if (res == null || src == null) return
        if (resultCode != RESULT_OK || data?.data == null) {
            res.success(null) // 用户取消
            return
        }
        val uri = data.data!!
        try {
            contentResolver.openOutputStream(uri, "w")?.use { out ->
                File(src).inputStream().use { input -> input.copyTo(out) }
            } ?: throw IOException("provider 未提供输出流")
            res.success(queryName(uri) ?: uri.lastPathSegment)
        } catch (e: Exception) {
            // 失败可见：Dart 侧兜底 toast＋日志。SAF 已建的空文件留给用户自清。
            res.error("save_failed", e.localizedMessage, null)
        }
    }

    /// V1.64 批1（拍板 G）：按打开方式记住的原始 content URI 覆写正文。
    /// 返回码（不抛 PlatformException）：ok / no_perm（授权失效——VIEW 给的临时
    /// 读授权本就未必可写、进程重启后必失效）/ missing（原文件已不在）/ error。
    private fun writeBack(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val src = call.argument<String>("srcPath")
        if (uriStr == null || src == null || !File(src).exists()) {
            result.success("missing")
            return
        }
        try {
            contentResolver.openOutputStream(Uri.parse(uriStr), "w")?.use { out ->
                File(src).inputStream().use { input -> input.copyTo(out) }
            } ?: throw IOException("provider 未提供输出流")
            result.success("ok")
        } catch (_: SecurityException) {
            result.success("no_perm")
        } catch (_: FileNotFoundException) {
            result.success("missing")
        } catch (_: Exception) {
            result.success("error")
        }
    }

    // ---- V1.64 批2（工单 交棒话术-20261004 §12 · N-1 本地导入）----

    private fun safPickTree(result: MethodChannel.Result) {
        if (treeResult != null) {
            result.error("busy", "选择层已在进行中", null)
            return
        }
        treeResult = result
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQ_SAF_TREE)
        } catch (e: Exception) {
            treeResult = null
            result.error("no_provider", e.localizedMessage, null)
        }
    }

    private fun safPickFiles(result: MethodChannel.Result) {
        if (filesResult != null) {
            result.error("busy", "选择层已在进行中", null)
            return
        }
        filesResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(intent, REQ_SAF_FILES)
        } catch (e: Exception) {
            filesResult = null
            result.error("no_provider", e.localizedMessage, null)
        }
    }

    /// 回**所选目录本身**这一个根节点（children 递归）；只收非隐藏目录与 .md/.markdown。
    private fun safListTree(call: MethodCall, result: MethodChannel.Result) {
        val treeStr = call.argument<String>("uri")
        if (treeStr.isNullOrEmpty()) {
            result.error("bad_args", "缺少目录 URI", null)
            return
        }
        val tree = Uri.parse(treeStr)
        // V1.66 导出位置批：扩展名过滤可参数化（备份列表要读 .lhbak，缺省仍是笔记档）。
        val exts = call.argument<List<String>>("exts") ?: NOTE_IMPORT_EXT
        try {
            val rootDoc = DocumentsContract.buildDocumentUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree)
            )
            result.success(docNode(tree, rootDoc, 0, exts))
        } catch (e: Exception) {
            // 授权过期/provider 拒绝：Dart 侧出一行人话提示，不静默。
            result.error("read_failed", e.localizedMessage, null)
        }
    }

    private fun safReadDoc(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        if (uriStr.isNullOrEmpty()) {
            result.error("bad_args", "缺少文件 URI", null)
            return
        }
        try {
            val text = contentResolver.openInputStream(Uri.parse(uriStr))
                ?.use { it.readBytes().toString(Charsets.UTF_8) }
            result.success(text ?: "")
        } catch (_: SecurityException) {
            result.error("no_perm", "授权已失效", null)
        } catch (e: Exception) {
            result.error("read_failed", e.localizedMessage, null)
        }
    }

    /// 真机反馈批③（工单 交棒话术-20261011 §4）：在已授权的目录树里落一个 .md 并写正文。
    /// 参数 tree＝目录 tree URI、relPath＝相对挂载根的子路径（可空，'/' 分隔）、
    /// name＝期望文件名、text＝正文。返回 Map：code=ok|no_perm|error，uri＝落盘文档 URI，
    /// name＝**实际**文件名（同名自动追加 (2)(3)…，与需求「同名追加序号」同口径）。
    /// 一律按码返回不抛错——写回失败必须可见但不许吞掉应用内的保存。
    ///
    /// **批3（N-2 导出）新增两个可选形参，缺省行为逐字节不变**（防改坏批2 的挂载写回）：
    /// `mime`＝文档类型（缺省 text/markdown；导出附件要 image/*）；
    /// `srcPath`＝给定时改按**字节流**拷这个本地文件（`text` 忽略——图片是二进制，写字符串必坏）。
    /// 目录一律由 `ensureDirInTree` 先建好（这里只查找，批2「老目录被删就落浅层」的语义不动）。
    private fun safCreateInTree(call: MethodCall, result: MethodChannel.Result) {
        val treeStr = call.argument<String>("tree")
        val want = call.argument<String>("name") ?: ""
        val text = call.argument<String>("text") ?: ""
        val rel = call.argument<String>("relPath") ?: ""
        val mimeArg = call.argument<String>("mime")
        val mime = if (mimeArg.isNullOrEmpty()) "text/markdown" else mimeArg
        val srcPath = call.argument<String>("srcPath")
        if (treeStr.isNullOrEmpty() || want.isEmpty()) {
            result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
            return
        }
        val tree = Uri.parse(treeStr)
        try {
            var parent = DocumentsContract.buildDocumentUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree)
            )
            for (seg in rel.split('/').filter { it.isNotEmpty() }) {
                val next = findChild(tree, parent, seg, true)
                if (next != null) parent = next
            }
            val dot = want.lastIndexOf('.')
            val base = if (dot > 0) want.substring(0, dot) else want
            val ext = if (dot > 0) want.substring(dot) else ""
            var candidate = want
            var n = 1
            while (findChild(tree, parent, candidate, false) != null && n < 50) {
                n++
                candidate = "$base($n)$ext"
            }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, DocumentsContract.getDocumentId(parent)
            )
            val doc = DocumentsContract.createDocument(
                contentResolver, children, mime, candidate
            )
            if (doc == null) {
                result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
                return
            }
            if (!srcPath.isNullOrEmpty()) {
                // 附件档（批3）：二进制按流拷，绝不用 write(String)——那会毁图。
                val src = File(srcPath)
                if (!src.exists()) {
                    result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
                    return
                }
                contentResolver.openOutputStream(doc, "w")?.use { out ->
                    src.inputStream().use { input -> input.copyTo(out) }
                } ?: throw IOException("provider 未提供输出流")
            } else {
                contentResolver.openOutputStream(doc, "w")?.use { out ->
                    out.write(text.toByteArray(Charsets.UTF_8))
                }
            }
            result.success(mapOf(
                "code" to "ok",
                "uri" to doc.toString(),
                "name" to candidate,
                // 人话位置（提示条要说「写到哪」）：relPath/实际文件名
                "localPath" to (if (rel.isEmpty()) candidate else "$rel/$candidate")
            ))
        } catch (_: SecurityException) {
            // 只读挂载（当初只拿到 READ）＝写回必失败，按码回给 Dart 出实话。
            result.success(mapOf("code" to "no_perm", "uri" to "", "name" to ""))
        } catch (_: Exception) {
            result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
        }
    }

    /// 建（或复用）一层子目录——导出包的 `_assets/` 与子目录节点都靠它（批3 N-2）。
    /// SAF 里「复用已有」必须先查：`createDocument(MIME_TYPE_DIR, name)` 撞上同名目录会自己
    /// 追加「 (2)」，导出两次就得到两个 `_assets (2)`——那是脏盘，不是幂等。
    private fun ensureChildDir(tree: Uri, parent: Uri, name: String): Uri? {
        findChild(tree, parent, name, true)?.let { return it }
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getDocumentId(parent)
        )
        return try {
            DocumentsContract.createDocument(
                contentResolver, children, DocumentsContract.Document.MIME_TYPE_DIR, name
            )
        } catch (_: Exception) {
            null
        }
    }

    /// 批3（N-2 导出）：在授权树里按 relPath 逐级建目录后再建（或复用）`name` 目录。
    /// 返回 Map：code=ok|no_perm|error ＋ uri（后续 createInTree 拿它当 tree 的锚不需要，
    /// 这里回的是目录文档 URI，仅供日志与人话路径核对）＋实际目录名。
    private fun safEnsureDirInTree(call: MethodCall, result: MethodChannel.Result) {
        val treeStr = call.argument<String>("tree")
        val want = call.argument<String>("name") ?: ""
        val rel = call.argument<String>("relPath") ?: ""
        if (treeStr.isNullOrEmpty() || want.isEmpty()) {
            result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
            return
        }
        val tree = Uri.parse(treeStr)
        try {
            var parent = DocumentsContract.buildDocumentUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree)
            )
            for (seg in rel.split('/').filter { it.isNotEmpty() }) {
                val next = ensureChildDir(tree, parent, seg)
                    ?: run {
                        result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
                        return
                    }
                parent = next
            }
            val dir = ensureChildDir(tree, parent, want)
            if (dir == null) {
                result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
                return
            }
            result.success(mapOf(
                "code" to "ok",
                "uri" to dir.toString(),
                "name" to want,
                "localPath" to (if (rel.isEmpty()) want else "$rel/$want")
            ))
        } catch (_: SecurityException) {
            // 只读授权（当初只拿到 READ）＝建目录必失败，按码回给 Dart 出实话。
            result.success(mapOf("code" to "no_perm", "uri" to "", "name" to ""))
        } catch (_: Exception) {
            result.success(mapOf("code" to "error", "uri" to "", "name" to ""))
        }
    }

    /// 在某目录下按显示名找一个子项（wantDir=true 只要目录，false 只要文件）。
    private fun findChild(tree: Uri, parent: Uri, name: String, wantDir: Boolean): Uri? {        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getDocumentId(parent)
        )
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null, null, null
        )?.use { c ->
            val idi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nmi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mmi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (c.moveToNext()) {
                if (c.getString(nmi) != name) continue
                val isDir = c.getString(mmi) == DocumentsContract.Document.MIME_TYPE_DIR
                if (isDir == wantDir) {
                    return DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(idi))
                }
            }
        }
        return null
    }

    private fun docNode(
        tree: Uri, doc: Uri, depth: Int,
        exts: List<String>
    ): Map<String, Any> {
        val name = queryName(doc) ?: ""
        val mime = queryString(doc, DocumentsContract.Document.COLUMN_MIME_TYPE) ?: ""
        val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
        var size = 0L
        var mtime = 0L
        if (!isDir) {
            size = try { queryString(doc, DocumentsContract.Document.COLUMN_SIZE)?.toLongOrNull() ?: 0L } catch (_: Exception) { 0L }
            mtime = try { queryString(doc, DocumentsContract.Document.COLUMN_LAST_MODIFIED)?.toLongOrNull() ?: 0L } catch (_: Exception) { 0L }
        }
        val children = ArrayList<Map<String, Any>>()
        if (isDir && depth < MAX_TREE_DEPTH) {
            val kids = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, DocumentsContract.getDocumentId(doc)
            )
            contentResolver.query(
                kids,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                ),
                null, null, null
            )?.use { c ->
                val idi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nmi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mmi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val szi = runCatching { c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE) }.getOrDefault(-1)
                val mti = runCatching { c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED) }.getOrDefault(-1)
                while (c.moveToNext()) {
                    if (children.size >= MAX_TREE_CHILDREN) break
                    val childName = c.getString(nmi) ?: continue
                    if (childName.startsWith(".")) continue
                    val childIsDir =
                        c.getString(mmi) == DocumentsContract.Document.MIME_TYPE_DIR
                    if (!childIsDir &&
                        exts.none { childName.lowercase().endsWith(it) }
                    ) continue
                    children.add(
                        docNode(
                            tree,
                            DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(idi)),
                            depth + 1,
                            exts
                        )
                    )
                }
            }
        }
        return mapOf(
            "name" to name,
            "uri" to doc.toString(),
            "dir" to isDir,
            // 文件档带字节与修改时间（V1.66 导出位置批：备份列表合并读要用）。
            "size" to size,
            "mtime" to mtime,
            // documentId 形如 `primary:Download/外来笔记夹`——去掉卷前缀给人看。
            "path" to (try {
                DocumentsContract.getDocumentId(doc).substringAfter(':', name)
            } catch (_: Exception) {
                name
            }),
            "children" to children
        )
    }

    /// 单列文本查询（个别 provider 不支持该列时返回 null，不影响主流程）。
    private fun queryString(doc: Uri, column: String): String? {
        return try {
            contentResolver.query(doc, arrayOf(column), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(column)
                    if (i >= 0) c.getString(i) else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val REQ_SAF_SAVE = 0x5AF1
        private const val REQ_SAF_TREE = 0x5AF3
        private const val REQ_SAF_FILES = 0x5AF4
        private const val MAX_TREE_DEPTH = 6
        private const val MAX_TREE_CHILDREN = 400
        private val NOTE_EXT = listOf(".md", ".markdown", ".txt")
        private val NOTE_IMPORT_EXT = listOf(".md", ".markdown")

        /// 批B：悬浮窗「■ 结束」意图（TimerPillService 与 Dart 侧共用）。
        const val ACTION_PILL_END = "com.lifeharness.pill.END"

        /** 悬浮窗「＋笔记」动作（6135·app 内胶囊同款双按钮）。 */
        const val ACTION_PILL_NOTE = "com.lifeharness.pill.NOTE"
        const val EXTRA_PILL_KIND = "pillKind"
    }

    /// 返回语义（Dart 侧 core/platform/open_intent.dart 同约定）：
    /// null ＝ 没有待处理文件；map kind="" ＝ 收到不支持的类型；
    /// 其余 ＝ kind(epub|note) + 已拷入私有缓存 `cacheDir/lh_open/<原文件名>`
    /// 的绝对路径 + 原文件名 + 原始 URI 字符串（回写锚点）。
    /// content 授权失效/读取失败按 null 处理（Dart 无感，不误弹）。
    private fun takeOpen(): Map<String, String>? {
        val uri = pendingUri ?: return null
        val raw = pendingName ?: (uri.path?.substringAfterLast('/') ?: "")
        pendingUri = null
        pendingName = null
        val name = raw.substringAfterLast('/').ifBlank { "file" }
        val lower = name.lowercase()
        val kind = when {
            lower.endsWith(".epub") -> "epub"
            NOTE_EXT.any { lower.endsWith(it) } -> "note"
            else -> ""
        }
        if (kind.isEmpty()) return mapOf("kind" to "")
        val dir = File(cacheDir, "lh_open").apply { mkdirs() }
        // 清掉上次暂存，避免缓存副本逐件累积（EPUB 可达百 MB 级）。
        dir.listFiles()?.forEach { it.delete() }
        val dst = File(dir, name)
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                dst.outputStream().use { out -> input.copyTo(out) }
            } ?: return null
            mapOf(
                "kind" to kind,
                "path" to dst.absolutePath,
                "name" to name,
                "uri" to uri.toString(),
            )
        } catch (_: Exception) {
            null
        }
    }
}
