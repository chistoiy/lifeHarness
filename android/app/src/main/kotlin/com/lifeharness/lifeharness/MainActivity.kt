package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
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

    // ---- 桌面模块批1（2026-10-15）：`lh://` 启动路由队列 ----
    // 冷启动意图**先入队不丢弃**（B15）：handle() 在 configureFlutterEngine 之前就跑，
    // 那时 Dart 还没起来；Dart 侧首帧完成后才 takeLaunchRoute 取一次。
    private var pendingLaunch: MutableMap<String, Any?>? = null

    /**
     * 本 Activity 是否处于前台（resumed）。
     *
     * 用途（批3 · 2026-10-17 产品令）：贴卡时若 App **不在前台**（桌面/别的 App），
     * 系统仍会因 AAR 把本 Activity 拉到前台——这是 Android 的硬限制（NFC 事件必须
     * 交给某个组件才能处理）。Dart 侧据此在「静默执行完」后立刻 [moveTaskToBack]，
     * 把用户送回原来的界面，只留一条横幅通知。
     *
     * ⚠ 为什么不能用「冷启动/热启动」判：App 退到后台后 Activity 仍存活，再贴卡走
     * `onNewIntent`（热启动）——可它同样是被 NFC 拉起来的。**只有 resumed 才是
     * 「用户本来就在 App 里」**。onNewIntent 早于本次 onResume，此刻读到的值正好是
     * 「拉起来之前」的真实前后台态。
     */
    private var resumed = false

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    override fun onDestroy() {
        // 批3d（2026-10-17 真机实锤）：引擎已改为「常驻」——Activity 销毁只是界面
        // 走了，引擎与 Dart 隔离区还活着（[provideFlutterEngine] 走 FlutterEngineCache
        // ＋ [shouldDestroyEngineWithHost] 恒 false），故这里**没有任何清理动作**。
        //
        // 早先在这里把引擎引用置空，导致「引擎明明活着却判成进程刚起」⇒ 透明中转
        // 界面每次都走冷启动转交 ⇒ 主界面被反复拉起（真机 logcat：`removedForAddTask`
        // 删掉旧 task、`Displayed +228ms`、`relay → main：冷启动转交` 反复出现）。
        super.onDestroy()
    }

    /**
     * 批3d：引擎常驻的**取用端**——Activity 重建时复用同一个引擎。
     *
     * 为什么这么做：透明中转界面（[NfcRelayActivity]）要靠「引擎是否活着」决定
     * 零闪现直投还是冷启动转交。只要引擎随 Activity 一起死，就必然反复冷启动、
     * 反复闪一下主界面（真机 8166 实测）。缓存住引擎后，用户从桌面贴卡时界面
     * 全程不出现，业务在后台跑完只留一条横幅。
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(ENGINE_ID)

    /**
     * 批3d：**禁止**引擎随 Activity 销毁（常驻的代价＝进程活着就常驻，可接受：
     * 贴卡/悬浮窗都靠它，且进程本就被系统按内存压力回收）。
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

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
        // 批3c 排障行（2026-10-17）：只记「系统给了本 Activity 什么 intent」——
        // **只记 action 与 scheme/host，不记 path/query（cardId 在 path 里·C11 红线）**。
        // 判据：NDEF_DISCOVERED ＋ scheme=lh ⇒ 系统正常派发（问题在 Dart 执行链）；
        // action=MAIN 且无 data ⇒ 系统走了 AAR 的 startApp 兜底（NDEF filter 未命中），
        // 此时 Dart 侧永远收不到 NFC 路由——真机「闪一下 App 页面、日志无 NFC 行」即此。
        // 真机复现「贴卡没反应」时：`adb logcat -s LH-NFC`。
        Log.d(
            "LH-NFC",
            "intent action=${intent.action} scheme=${intent.data?.scheme} host=${intent.data?.host}"
        )
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
        // 桌面模块批1：`lh://` 自有寻址（URL Scheme 与桌面快捷方式/小组件点击走同一分支；
        // NFC 的 ACTION_NDEF_DISCOVERED 由系统另派发，其 data 仍是 lh:// URI，
        // 解析口径同源 C36）。**必须在既有 content/file 分支之前判**——
        // lh:// 不会被那些 filter 匹配，但先判能让未知 lh path 干净落兜底。
        if (intent.action == Intent.ACTION_VIEW && intent.data?.scheme == LH_SCHEME) {
            enqueueLaunch(intent.data!!)
            return
        }
        // NFC 卡片模块批2（冻结档 §4.4 · C36/C37）：标签里的 `lh://nfc/<cardId>` 由系统
        // 以 NDEF_DISCOVERED 派发（Manifest 的 host=nfc filter 保证 scheme/host 已匹配）。
        // **与上面 ACTION_VIEW 共用同一出口 enqueueLaunch**——原生的活只到「解析出 cardId
        // 投进 pendingLaunch」，总闸/去抖/查表/执行全归 Dart（C42/B35/B43），原生一字不判业务。
        // ⚠ 常量值取自 `NfcAdapter.ACTION_NDEF_DISCOVERED`（＝"android.nfc.action.NDEF_DISCOVERED"）；
        //   用字面量而非 import NfcAdapter，避免为读一个字符串引整个 nfc 包。
        if (intent.action == ACTION_NDEF_DISCOVERED &&
            intent.data?.scheme == LH_SCHEME
        ) {
            enqueueLaunch(intent.data!!)
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
        // 批3d：引擎常驻后本方法会在**同一个引擎**上被反复回调（每次 Activity 重建）。
        // 装配只做一次——`super.configureFlutterEngine` 会跑 GeneratedPluginRegistrant，
        // 重复跑等于把插件实例挂两份（通知插件尤其敏感：initialize 在旧实例上做过，
        // 新实例接手通道后 show 会报未初始化）。
        if (wiredEngine !== flutterEngine) {
            wiredEngine = flutterEngine
            super.configureFlutterEngine(flutterEngine)
            // 把引擎挂进缓存 ⇒ Activity 销毁后引擎仍在，贴卡可零闪现直投
            // （[provideFlutterEngine] 下次从这里取回同一个引擎）。
            FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
            wireChannels(flutterEngine)
        }
        // 意图入队每建一次界面都要跑（新 Activity 的 intent 可能带待处理路由）。
        handle(intent)
    }

    /** 通道装配（每引擎一次·见 [configureFlutterEngine]）。 */
    private fun wireChannels(flutterEngine: FlutterEngine) {
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
                    } catch (e: Exception) {
                        // 起服务被权限/ROM 拒绝＝降级为无 app 外悬浮窗，不崩
                        // （6128 实伤：缺 FGS 基础权限时这里 SecurityException 即闪退）。
                        // 批3d：留痕——贴卡在后台起计时时若被拒，用户看到的就是
                        // 「贴了卡、胶囊没出来」，logcat 这一行能一刀切开。
                        Log.w("LH-NFC", "起悬浮窗服务被拒：${e.javaClass.simpleName}")
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
        // 桌面模块批1：`lh://` 启动路由单次消费（B15：首帧后 Dart 才取，
        // 冷启动意图一直留在 pendingLaunch 里不丢）。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "lh/launch"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takeLaunchRoute" -> result.success(takeLaunch())
                // 批3（2026-10-17 产品令）：把界面让回去。贴卡触发的是「不需要看界面」
                // 的动作（打卡/计时）时，Dart 执行完调这里退回原界面，只留横幅通知。
                // 用 moveTaskToBack 而非 finish：Activity 留在后台，下次贴卡仍是热启动。
                "moveTaskToBack" -> {
                    // 批3d：引擎常驻后本方法可能在**已销毁**的 Activity 上被调用
                    // （透明中转路径下界面根本没建过），直接调会抛 IllegalStateException。
                    if (!isFinishing && !isDestroyed) {
                        moveTaskToBack(true)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // NFC 卡片模块批2（工单 §0 第 3 条）：系统 NFC 设置页跳转。
        // B2「系统 NFC 未开启 → 主钮『去设置』」是需求硬项，而 url_launcher 打不开
        // 系统设置页；先例＝本文件 requestOverlayPermission（同为系统设置页跳转）。
        // 通道只此一个方法，**不含任何业务**——NFC 业务一律在 Dart 侧。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSettings" -> {
                    openNfcSettings()
                    result.success(null)
                }
                // 批3d 排障口（2026-10-17）：release 包也能把 Dart 侧的贴卡链路打点
                // 落到 logcat（`adb logcat -s LH-NFC`）。**只记结果枚举与人话，
                // 不记 cardId**（C11 红线）。与 `lh/pill` 的 log 方法同模式。
                "log" -> {
                    Log.i("LH-NFC", "[dart] ${call.argument<String>("msg") ?: ""}")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // 桌面模块批1：动态快捷方式（长按菜单）＋ 铺到桌面。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "lh/desktop"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncShortcuts" -> {
                    val ids = (call.argument<List<String>>("actions") ?: emptyList())
                        .filter { LH_LABELS.containsKey(it) }
                        .distinct()
                        .take(LH_MENU_MAX)
                    val schemes = (call.argument<List<String>>("schemes") ?: emptyList())
                        .take(ids.size)
                    result.success(syncShortcuts(ids, schemes))
                }
                "requestPinShortcut" -> {
                    val scheme = call.argument<String>("scheme")
                    val actionId = call.argument<String>("action")
                    if (scheme.isNullOrEmpty() || actionId.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        result.success(requestPin(actionId, scheme))
                    }
                }
                "isPinSupported" -> {
                    result.success(
                        try {
                            shortcutManager()?.isRequestPinShortcutSupported == true
                        } catch (_: Exception) {
                            false
                        }
                    )
                }
                // 桌面模块批2（F2-4/§4.2③）：把**指定某一枚**小组件固定到桌面。
                //
                // 2026-10-15 产品改口：原先这里是 `addWidget` —— 先弹一个 App 自己拼的
                // `AlertDialog`（4 项列表）让用户选，再走系统确认。那个框纯系统默认外观、
                // 与 App 卡片体系完全不搭，且「列表勾选」与「添加」两个语义挤在一起很拧。
                // 现改为：设置页每张卡自带「添加到桌面」按钮，直接把 provider 传进来，
                // **App 侧不再有中间选择框**，用户点哪枚就是哪枚。
                "pinWidget" -> {
                    pinWidgetById(call.argument<String>("widget"))
                    result.success(true)
                }
                // 2026-10-15 8148 装机实锤：设置页的「今日概览（2×2）」「快捷记录（4×1）」
                // 原本是**死开关**（只有配置页读写、两枚 Provider 一次没读）。现钉死为
                // 「是否添加这枚」的总开关，且**关掉要真从桌面消失** —— Dart 侧拨完即调此处。
                "applyWidgetFlags" -> {
                    LhWidget.applyEnabledFlags(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// NFC 卡片模块批2：跳系统 NFC 设置页（B2 的「去设置」）。
    /// 部分 ROM 没有 `ACTION_NFC_SETTINGS` 页，回落无线与网络设置；都没有则静默
    /// （调用方保持原态，用户可自行去系统设置开）。
    private fun openNfcSettings() {
        try {
            startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
            } catch (_: Exception) {
                // 无设置页可跳：不动原态，不崩。
            }
        }
    }

    /// 批B：跳系统「显示在其他应用上层」授权页（Android 11+ 无弹窗式授权，
    /// 走系统设置页；授权结果由 Dart 侧在 resumed 后经 canDrawOverlays 复探）。
    private fun requestOverlayPermission() {        try {
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
        /**
         * `lh/nfc` 通道名：NFC 设置页跳转（Dart→原生）＋ 贴卡事件投递（原生→Dart，
         * 由透明中转界面 [NfcRelayActivity] 使用）。**禁第二处字面量**。
         */
        const val NFC_CHANNEL = "lh/nfc"

        /**
         * 常驻引擎的缓存键（批3d）。**禁第二处字面量**。
         *
         * 全进程只有一个引擎：Activity 重建复用它、透明中转界面靠它投递贴卡事件。
         */
        const val ENGINE_ID = "lh_main"

        /**
         * 已装配过的引擎（批3d）：同一引擎只跑一次 `configureFlutterEngine` 的装配段，
         * 免插件实例挂两份（Activity 重建会再次回调该生命周期）。
         */
        private var wiredEngine: FlutterEngine? = null

        /**
         * 活着的引擎（null＝进程刚起、还没跑过 Flutter）；中转界面据此分流。
         *
         * **唯一真源＝FlutterEngineCache**（批3d）：不要去缓存某个 FlutterEngine
         * 引用——Activity 销毁后那个引用可能指向已销毁的实例，判活必出错。
         */
        fun aliveEngine(): FlutterEngine? = FlutterEngineCache.getInstance().get(ENGINE_ID)

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

        // ===== 桌面模块批1（2026-10-15）· 与 Dart 侧 desktop_actions.dart 同源 =====
        /** 自有 scheme（Manifest 注册的就是它；禁第二处字面量）。 */
        const val LH_SCHEME = "lh"

        /**
         * NFC 卡片模块批2：NDEF 标签派发的 action 字符串。
         *
         * 值＝`NfcAdapter.ACTION_NDEF_DISCOVERED`，**与 Manifest 那条 intent-filter
         * 逐字一致**（`android.nfc.action.NDEF_DISCOVERED`）。用字面量避免引 nfc 包。
         */
        const val ACTION_NDEF_DISCOVERED = "android.nfc.action.NDEF_DISCOVERED"

        /**
         * 白名单：`lh://<ns>/<key>` 的 path 段 → 动作 id。
         * 与 Dart 侧 `kLaunchPathWhitelist` **逐条一致**（守护 desktop_scheme_parse_test /
         * desktop_ns_registry_test）。一字不多；扩容只允许「加 ns」并回写冻结档（C19）。
         */
        private val LH_WHITELIST = mapOf(
            "inbox/new" to "inbox",
            "todo/new" to "todo",
            "journal/edit" to "journal",
            "ledger/add" to "ledger",
            "items/new" to "items",
            "habit/check" to "habit",
            "today" to "today",
        )

        /** ns 常量表（C19/B17）；表外 ns 按未知 path 走 unknownRouteFallback。 */
        private val LH_NS = setOf(
            "inbox", "todo", "journal", "ledger", "items", "habit", "today", "nfc",
        )

        /** 长按菜单系统硬限 4（§4.1）；Dart 侧也截断，两边都兜。 */
        private const val LH_MENU_MAX = 4

        /**
         * `lh://<seg>` 原值（**段取自 [LH_WHITELIST]，禁散落 scheme 字面量** · C19）。
         *
         * 批2 起小组件点击/铺桌面的 `PendingIntent` 与既有三路共用同一出口（C15/C9）；
         * 表外段一律拒（表外 ns 按未知 path 走兜底，不在此拼 URI）。
         */
        internal fun lhScheme(seg: String): String {
            require(LH_WHITELIST.containsKey(seg)) { "表外寻址段禁拼 URI：$seg" }
            return "$LH_SCHEME://$seg"
        }
    }

    // ===================== 桌面模块批1 · `lh://` 解析与投递 =====================
    //
    // 口径与 Dart 侧 `resolveLaunchPath` 逐条一致；**不在原生解释 nfc 业务**
    // （C36：只解析出 cardId 并原样投过去，格式校验归 NFC 模块 B35）。

    /** 解析并入队一条 `lh://` 意图（B15：入队不丢弃，等 Dart 首帧后取）。 */
    private fun enqueueLaunch(uri: Uri) {
        // ⚠ URI 分解口径（V1.67 热修 · 真机伤）：`lh://<ns>/<key>` 里 **`ns` 落在
        //   authority(host)**，只有 `<key>` 落在 path —— 只取 `uri.path` 会得到 "/add"
        //   （ns 整个丢掉）⇒ ns 校验必失败 ⇒ 意图被静默丢弃 ⇒ 四路点击全落回首页。
        //   归一化寻址段＝ host ＋ path（host 空时回落 path，兼容 `lh:/ledger/add`）。
        //   与 Dart 侧 `desktop_actions.launchSegOf` 同口径（守护 desktop_intent_shape_test）。
        val host = uri.host.orEmpty()
        var seg = if (host.isEmpty()) uri.path.orEmpty() else host + uri.path.orEmpty()
        seg = seg.trim()
        while (seg.startsWith("/")) seg = seg.substring(1)
        if (seg.isEmpty()) return
        val ns = seg.substringBefore('/')
        if (ns !in LH_NS) return // 表外 ns 静默丢弃（B17/C19：不当页面，不回显）
        val action = if (ns == "nfc") {
            val cardId = seg.substringAfter('/', "")
            if (cardId.isEmpty()) return
            "nfc:$cardId" // 原样透传，不解释
        } else {
            LH_WHITELIST[seg] ?: return // 未知 path → 静默（B4 兜底在 Dart 侧）
        }
        // 带参（B5：非数字面不参与判定，原样交给 Dart；敏感参数不写日志）
        val args = HashMap<String, String>()
        for (k in uri.queryParameterNames) {
            val v = uri.getQueryParameter(k) ?: continue
            args[k] = v
        }
        pendingLaunch = HashMap<String, Any?>().apply {
            put("action", action)
            put("args", args)
            // 批3：投递这一刻 App 是否在前台（见 [resumed] 的注释）。Dart 侧据此
            // 决定「静默执行完要不要把界面让回去」——NFC 拉起的那次必然是 false。
            put("fromBackground", !resumed)
        }
    }

    /**
     * 单次消费（B15/B16）：读到即清空，防重放。
     * 返回 null ＝ 无待处理；Dart 侧门禁未开时**不会调到这里**，队列仍在。
     */
    private fun takeLaunch(): Map<String, Any?>? {
        val r = pendingLaunch
        pendingLaunch = null
        return r
    }

    /**
     * C15 的 Intent 构造规则（全模块唯一出口，四路共用）：
     * `ACTION_VIEW` ＋ `setData(lh://…)` ＋ `setClass` ＋ flags。
     *
     * ⚠ **禁只 setAction 不 setData**：Manifest 既有 5 组 content/file 打开方式 filter，
     * 只带 action 的 Intent 会误匹配到它们（这正是当初关掉 embedding 深链的原因）。
     *
     * 批2 起小组件 `PendingIntent` 走同一实现（[lhLaunchIntent]），禁第二套（C15/C9）。
     */
    private fun launchIntent(scheme: String): Intent = lhLaunchIntent(this, scheme)

    /** 设置页改动后重建动态快捷方式（长按菜单，最多 [LH_MENU_MAX] 枚）。 */
    private fun syncShortcuts(actionIds: List<String>, schemes: List<String>): Int {
        val n = actionIds.size.coerceAtMost(LH_MENU_MAX)
        val shortcuts = ArrayList<ShortcutInfo>(n)
        for (i in 0 until n) {
            val id = actionIds[i]
            val sc = schemes.getOrNull(i) ?: continue
            val label = LH_LABELS[id] ?: continue
            shortcuts.add(
                ShortcutInfo.Builder(this, "lh_$id")
                    .setShortLabel(label)
                    .setLongLabel(label)
                    .setIcon(lhIcon(id))
                    .setIntent(launchIntent(sc))
                    .build()
            )
        }
        return try {
            shortcutManager()?.setDynamicShortcuts(shortcuts)
            shortcuts.size
        } catch (_: Exception) {
            0 // 设备不支持/ROM 限制：降级为无长按菜单，不崩
        }
    }

    /** 铺到桌面（固定快捷方式，不限量）；不支持返回 false（B2 由设置页禁用按钮）。
     *
     *  ⚠ 标签必须取**该动作自己**的短标签（[LH_LABELS]，与长按菜单同源）——
     *  曾写死 `LH_LABELS["today"]`，导致铺「记一笔」的桌面图标也显示「今天」。
     *  守卫：`desktop_intent_shape_test`（原生源码断言）。
     */
    private fun requestPin(actionId: String, scheme: String): Boolean = try {
        val sm = shortcutManager()
        if (sm == null || !sm.isRequestPinShortcutSupported) {
            false
        } else {
            sm.requestPinShortcut(
                ShortcutInfo.Builder(this, "lh_pin_${actionId}_${System.currentTimeMillis()}")
                    .setShortLabel(LH_LABELS[actionId] ?: "lifeHarness")
                    .setIcon(lhIcon(actionId))
                    .setIntent(launchIntent(scheme))
                    .build(),
                null,
            )
            true
        }
    } catch (_: Exception) {
        false
    }

    /** ShortcutManager 取用统一出口（拿不到就降级，不抛）。 */
    private fun shortcutManager(): ShortcutManager? = try {
        getSystemService(ShortcutManager::class.java)
    } catch (_: Exception) {
        null
    }

    // ===================== 桌面模块批2 · 小组件 =====================

    /**
     * 设置页「添加到桌面」：系统没有公开的「打开小部件中心」入口（冻结档 §4.9 降级矩阵），
     * 故先用系统对话框选一枚小组件，再走 `requestPinAppWidget` 的系统弹窗。
     * 不支持时给一行手动添加提示（B2 同口径）。
     */
    /**
     * 按 id 取小组件 provider 类并请求落桌（2026-10-15 产品改口）。
     *
     * id 与 Dart 侧 `pinDesktopWidget` 的入参逐字一致（守护测试交叉核对）；
     * 取不到就静默返回——不猜、不弹兜底框。
     */
    private fun pinWidgetById(id: String?) {
        val cls = when (id) {
            "overview" -> TodayOverviewWidget::class.java
            "quick" -> QuickRecordWidget::class.java
            "todo" -> TodoListWidget::class.java
            "ledger" -> LedgerOverviewWidget::class.java
            else -> null
        } ?: return
        pinWidget(cls)
    }

    /** 调起系统「固定到桌面」弹窗；系统不支持时提示手动拖出（B2）。 */
    private fun pinWidget(cls: Class<*>) {
        val supported = Build.VERSION.SDK_INT >= 26 &&
            AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported
        if (supported) {
            AppWidgetManager.getInstance(this)
                .requestPinAppWidget(ComponentName(this, cls), null, null)
        } else {
            Toast.makeText(this, R.string.lh_widget_add_unsupported, Toast.LENGTH_LONG).show()
        }
    }

    /** 长按菜单短标签（≤6 字，与 Dart 侧 shortLabel 同源）。 */
    private val LH_LABELS = mapOf(
        "inbox" to "速记",
        "todo" to "待办",
        "ledger" to "记一笔",
        "habit" to "打卡",
        "journal" to "日记",
        "items" to "物品",
        "today" to "今天",
    )

    /**
     * 快捷方式图标（按动作取；字形取自原型 `ACTIONS[].icon`，见 res/drawable/ic_lh_*.xml）。
     *
     * ⚠ 必须逐动作设置：不设 `setIcon` 时系统一律回落到应用图标 ⇒ 长按菜单 4 枚图标全一样
     * （V1.67 真机报障）。守卫：`desktop_intent_shape_test`（原生源码断言 `LH_ICONS[id]`）。
     */
    private val LH_ICONS = mapOf(
        "inbox" to R.drawable.ic_lh_inbox,
        "todo" to R.drawable.ic_lh_todo,
        "ledger" to R.drawable.ic_lh_ledger,
        "habit" to R.drawable.ic_lh_habit,
        "journal" to R.drawable.ic_lh_journal,
        "items" to R.drawable.ic_lh_items,
        "today" to R.drawable.ic_lh_today,
    )

    /** 取某动作的快捷方式图标；表外/取不到回落应用图标（不崩）。 */
    private fun lhIcon(id: String): Icon =
        Icon.createWithResource(this, LH_ICONS[id] ?: R.mipmap.ic_launcher)

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

/**
 * C15 唯一出口（文件级）：四路入口（长按菜单／铺桌面／小组件／外部 `lh://`）共用同一
 * 构造规则 —— `ACTION_VIEW` ＋ `setData(parse(lh://…))` ＋ `setClass(MainActivity)` ＋ flags。
 *
 * ⚠ **禁只 setAction 不 setData**：Manifest 既有 5 组 content/file 打开方式 filter，
 * 只带 action 的 Intent 会误匹配到它们（C13 关掉 embedding 深链正是为了这个）。
 *
 * 批2：小组件 `PendingIntent` 也经此处（`LhWidget.clickIntent`），全模块只有这一处实现。
 */
internal fun lhLaunchIntent(context: Context, scheme: String): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(scheme))
        .setClass(context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
