package com.lifeharness.lifeharness

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// V1.53.4⑥ 系统「打开方式」接收本地 EPUB。
/// 冷启动经 configureFlutterEngine 里的 handle(intent) 入队；热启动（singleTop）
/// 经 onNewIntent 入队。Dart 侧经 MethodChannel `lh/intents` 的 takeEpubUri
/// 单次消费（取一次即清空），App 唤醒（resumed）时再取。
class MainActivity : FlutterActivity() {

    private var pendingUri: Uri? = null
    private var pendingName: String? = null

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
            if (call.method == "takeEpubUri") {
                result.success(takeEpub())
            } else {
                result.notImplemented()
            }
        }
    }

    /// 返回语义（Dart 侧同约定）：
    /// null ＝ 没有待处理文件；"" ＝ 收到了非 .epub 文件（Dart toast「只支持 EPUB」）；
    /// 其余 ＝ 已拷入私有缓存 `cacheDir/lh_open/<原文件名>` 的绝对路径。
    /// content 授权失效/读取失败按 null 处理（Dart 无感，不误弹）。
    private fun takeEpub(): String? {
        val uri = pendingUri ?: return null
        val raw = pendingName ?: "book.epub"
        pendingUri = null
        pendingName = null
        val name = raw.substringAfterLast('/').ifBlank { "book.epub" }
        if (!name.lowercase().endsWith(".epub")) return ""
        val dir = File(cacheDir, "lh_open").apply { mkdirs() }
        // 清掉上次暂存，避免缓存副本逐本累积（一本可达百 MB 级）。
        dir.listFiles()?.forEach { it.delete() }
        val dst = File(dir, name)
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                dst.outputStream().use { out -> input.copyTo(out) }
            } ?: return null
            dst.absolutePath
        } catch (_: Exception) {
            null
        }
    }
}
