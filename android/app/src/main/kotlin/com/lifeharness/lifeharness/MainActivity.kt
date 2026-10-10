package com.lifeharness.lifeharness

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
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

    // ---- lh/saf 挂起态（仅内存：进程死亡即失，结果过期被静默忽略）----
    private var safResult: MethodChannel.Result? = null
    private var safSource: String? = null

    // V1.64 批2：目录/多文件选择器的挂起态（同样仅内存；过期结果静默忽略）
    private var treeResult: MethodChannel.Result? = null
    private var filesResult: MethodChannel.Result? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent == null) return
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
                else -> result.notImplemented()
            }
        }
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
            try {
                // 工单 §3 红线：目录授权必须持久化（重启后还能按原挂载继续导入）。
                contentResolver.takePersistableUriPermission(
                    tree, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (e: Exception) {
                res.error("no_perm", e.localizedMessage, null)
                return
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
        try {
            val rootDoc = DocumentsContract.buildDocumentUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree)
            )
            result.success(docNode(tree, rootDoc, 0))
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

    private fun docNode(tree: Uri, doc: Uri, depth: Int): Map<String, Any> {
        val name = queryName(doc) ?: ""
        val mime = queryString(doc, DocumentsContract.Document.COLUMN_MIME_TYPE) ?: ""
        val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
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
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                ),
                null, null, null
            )?.use { c ->
                val idi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nmi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mmi = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                while (c.moveToNext()) {
                    if (children.size >= MAX_TREE_CHILDREN) break
                    val childName = c.getString(nmi) ?: continue
                    if (childName.startsWith(".")) continue
                    val childIsDir =
                        c.getString(mmi) == DocumentsContract.Document.MIME_TYPE_DIR
                    if (!childIsDir &&
                        NOTE_IMPORT_EXT.none { childName.lowercase().endsWith(it) }
                    ) continue
                    children.add(
                        docNode(
                            tree,
                            DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(idi)),
                            depth + 1
                        )
                    )
                }
            }
        }
        return mapOf(
            "name" to name,
            "uri" to doc.toString(),
            "dir" to isDir,
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
