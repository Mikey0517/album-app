package com.example.album_app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.security.KeyStore
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.system.exitProcess

/**
 * 使用 Android 系统 Photo Picker，同时在拿到 URI 后请求原始文件。
 * 普通 image_picker 会复制照片；带位置信息的照片会被系统脱敏，小米
 * Motion Photo 的内嵌视频也可能随之丢失。这里申请 ACCESS_MEDIA_LOCATION
 * 并调用 setRequireOriginal()，尽量保留原始字节。
 */
class MainActivity : FlutterFragmentActivity() {
    private companion object {
        /**
         * 重启用的 PendingIntent 请求码，固定值。配合 FLAG_CANCEL_CURRENT：
         * 同一个请求码 + 同一个启动 Intent，每次调度都会把上一次留下的
         * PendingIntent 取消掉，不会复用旧 Intent。
         */
        const val RELAUNCH_REQUEST_CODE = 1001

        /**
         * setAlarmClock 的触发时间走墙钟（RTC），所以这里是「现在 + 900ms」。
         * 必须明显大于 [EXIT_DELAY_MS]，给旧进程留出「回执 + 退出」的时间：
         * 闹钟若在旧进程还活着时触发，新 Activity 会落回旧进程，补丁就没被
         * 重新装载。900ms 对用户只是不到一秒的黑屏。
         */
        const val RELAUNCH_WALL_CLOCK_DELAY_MS = 900L

        /**
         * 降级用的普通闹钟走单调时钟（elapsedRealtime），同样要明显大于
         * [EXIT_DELAY_MS]，理由同上。
         */
        const val RELAUNCH_DELAY_MS = 600L

        /** 回执之后隔多久结束自己；必须小于上面两个延迟。 */
        const val EXIT_DELAY_MS = 300L

        // 删除失败的原因码：Dart 侧翻译成用户能看懂的一句话，原始异常只进 logcat。
        // "All requested items must be referenced by specific ID" 对用户没有意义。
        const val REASON_UNSUPPORTED_URI = "unsupported_uri"
        const val REASON_UNRESOLVED_PICKER = "unresolved_picker"
        const val REASON_NOT_FOUND = "not_found"
        const val REASON_USER_CANCELLED = "user_cancelled"
        const val REASON_SYSTEM_REJECTED = "system_rejected"

        // createDeleteRequest 只认这两个媒体集合，以及 media 这个 authority。
        const val COLLECTION_IMAGES = "images"
        const val COLLECTION_VIDEO = "video"
        const val MEDIA_AUTHORITY = "media"
    }

    private val channelName = "album/media_picker"
    private val secureStoreChannel = "album/secure_store"
    private val keyAlias = "album_app_credentials"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingLimit = 100

    private val pickNine = registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(9)
    ) { uris -> handlePicked(uris) }

    private val pickHundred = registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(100)
    ) { uris -> handlePicked(uris) }

    private val requestMediaLocation = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ -> launchPicker() }

    // 隐藏空间：任意类型的文件都用系统的“打开文档”选择器，选完复制进 App 私有目录。
    private var pendingHiddenFileResult: MethodChannel.Result? = null
    private var pendingHiddenFileDir: String? = null
    private val pickHiddenDocuments = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris -> handleHiddenFilesPicked(uris) }

    // 删除原图的批处理会话：整批被系统拒绝时退回单条，并且删完一条继续下一条，
    // 不能只删第一张就收工（小米等厂商会拒绝「一次删多张」的请求）。
    private var pendingDeleteSession: DeleteSession? = null
    // 留着给 Dart 侧显示，方便没有 adb 时也能知道系统为什么拒绝。
    private var lastDeleteError: String? = null
    // 这一批失败的原因码（见 REASON_*）；原始异常文本只给 logcat 看。
    private var lastDeleteReason: String? = null

    /** 一次删除请求的进度：remaining 是还没处理完的，requested 是正在等系统确认的。 */
    private class DeleteSession(
        val result: MethodChannel.Result,
        val total: Int,
        val firstRejection: String?,
        val remaining: MutableList<DeleteCandidate>
    ) {
        var requested: List<DeleteCandidate> = emptyList()
        var deleted: Int = 0
        var lastReason: String? = null
    }

    private val deleteLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        val session = pendingDeleteSession ?: return@registerForActivityResult
        val approved = result.resultCode == Activity.RESULT_OK
        val requested = session.requested
        session.requested = emptyList()
        if (!approved) {
            session.lastReason = REASON_USER_CANCELLED
            session.remaining.clear()
            finishDeleteSession()
            return@registerForActivityResult
        }
        session.deleted += requested.size
        session.remaining.removeAll { candidate ->
            requested.any { it.uri == candidate.uri }
        }
        // 整批被拒时我们只弹了其中一条：继续删剩下的，别停在这一张。
        requestNextDelete()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerSecureStore(flutterEngine)
        registerImageEncoder(flutterEngine)
        registerMediaStore(flutterEngine)
        registerAppControl(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickMultiple" -> {
                        if (pendingResult != null) {
                            result.error("busy", "已有选择器正在打开", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        pendingLimit = (call.argument<Int>("limit") ?: 100).coerceAtLeast(1)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.ACCESS_MEDIA_LOCATION
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestMediaLocation.launch(Manifest.permission.ACCESS_MEDIA_LOCATION)
                        } else {
                            launchPicker()
                        }
                    }
                    "pickHiddenFiles" -> {
                        if (pendingHiddenFileResult != null) {
                            result.error("busy", "已有文件选择器正在打开", null)
                            return@setMethodCallHandler
                        }
                        val targetDir = call.argument<String>("targetDir")
                        if (targetDir.isNullOrBlank()) {
                            result.error("bad_args", "缺少目标目录", null)
                            return@setMethodCallHandler
                        }
                        pendingHiddenFileResult = result
                        pendingHiddenFileDir = targetDir
                        try {
                            // 任意类型：*/*
                            pickHiddenDocuments.launch(arrayOf("*/*"))
                        } catch (e: Exception) {
                            pendingHiddenFileResult = null
                            pendingHiddenFileDir = null
                            result.error("picker_unavailable", "无法打开文件选择器", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchPicker() {
        val request = PickVisualMediaRequest(
            ActivityResultContracts.PickVisualMedia.ImageAndVideo
        )
        if (pendingLimit <= 9) {
            pickNine.launch(request)
        } else {
            pickHundred.launch(request)
        }
    }

    private fun pickerResult(
        items: List<Map<String, String>>,
        failed: Int
    ): Map<String, Any> = mapOf("items" to items, "failed" to failed)

    /** 隐藏空间的导入：把选中的任意类型文件复制进 [pendingHiddenFileDir]。 */
    private fun handleHiddenFilesPicked(uris: List<Uri>?) {
        val result = pendingHiddenFileResult ?: return
        val targetDir = pendingHiddenFileDir
        pendingHiddenFileResult = null
        pendingHiddenFileDir = null
        if (uris.isNullOrEmpty() || targetDir.isNullOrBlank()) {
            result.success(mapOf("items" to emptyList<Map<String, Any>>(), "failed" to 0))
            return
        }
        Thread {
            val dir = File(targetDir).apply { mkdirs() }
            val picked = ArrayList<Map<String, Any>>()
            var failed = 0
            for (uri in uris) {
                try {
                    picked.add(copyHiddenFile(uri, dir))
                } catch (e: Exception) {
                    failed++
                    Log.w("AlbumHidden", "复制文件失败: $uri", e)
                }
            }
            runOnUiThread {
                result.success(mapOf("items" to picked, "failed" to failed))
            }
        }.start()
    }

    private fun copyHiddenFile(uri: Uri, dir: File): Map<String, Any> {
        val name = queryDisplayName(uri) ?: "file_${System.currentTimeMillis()}"
        val mime = contentResolver.getType(uri) ?: ""
        val safeName = name.replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]"), "_")
        val target = File(dir, "${UUID.randomUUID()}_$safeName")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "无法读取文件流" }
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return mapOf(
            "path" to target.absolutePath,
            "name" to name,
            "mime" to mime,
            "size" to target.length()
        )
    }

    /** 文件选择器给的 Uri 只保证当次可读；展示名从 OpenableColumns 拿。 */
    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) cursor.getString(index) else null
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }

    private fun handlePicked(uris: List<Uri>?) {
        val result = pendingResult ?: return
        if (uris.isNullOrEmpty()) {
            pendingResult = null
            result.success(pickerResult(emptyList(), 0))
            return
        }
        val limit = pendingLimit
        Thread {
            val picked = ArrayList<Map<String, String>>()
            var failed = 0
            for ((index, uri) in uris.take(limit).withIndex()) {
                // 不同厂商的选择器给的 URI 形态各不相同；删原图出问题时这行是唯一线索。
                Log.i("AlbumPicker", "picked uri: $uri")
                try {
                    picked.add(copyOriginal(uri, index))
                } catch (e: Exception) {
                    // 常见原因是手机存储空间不足，Dart 侧会提示用户。
                    failed++
                    Log.w("AlbumPicker", "复制媒体失败: $uri", e)
                }
            }
            runOnUiThread {
                pendingResult = null
                result.success(pickerResult(picked, failed))
            }
        }.start()
    }

    private fun copyOriginal(uri: Uri, index: Int): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_MEDIA_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            try {
                MediaStore.setRequireOriginal(uri)
            } catch (_: Exception) {
                // Photo Picker URI 不一定支持 setRequireOriginal，继续按原 URI 读取。
            }
        }
        val resolver = contentResolver
        var name = "media_${System.currentTimeMillis()}_$index"
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val value = cursor.getString(0)
                        if (!value.isNullOrBlank()) name = value
                    }
                }
        } catch (_: Exception) {
        }
        val mime = resolver.getType(uri) ?: ""
        if (!name.contains('.')) {
            name = when {
                mime.startsWith("video/") -> "$name.mp4"
                mime == "image/png" -> "$name.png"
                mime == "image/webp" -> "$name.webp"
                else -> "$name.jpg"
            }
        }
        val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        // 放在 filesDir 而不是 cacheDir：系统在存储紧张时会清理 cache，
        // 正在排队上传的副本一旦被清掉就只能让用户重新选择。
        val dir = File(filesDir, "picked_media").apply { mkdirs() }
        val target = File(dir, "${UUID.randomUUID()}_$safeName")
        resolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "无法读取媒体流" }
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return mapOf(
            "path" to target.absolutePath,
            "name" to name,
            "mime" to mime,
            "uri" to uri.toString()
        )
    }

    // ---- 上传后删除手机相册里的原图 ----

    private fun registerMediaStore(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "album/media_store")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteUris" -> {
                        val raw = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        deleteMedia(raw, result)
                    }
                    // 删除前先核一遍：是不是「带具体 ID 的 MediaStore 单项 URI」、
                    // 条目还在不在、到底落在 images 还是 video。查库要 IPC，放后台线程。
                    "resolveDeleteUris" -> {
                        val raw = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        resolveDeleteUris(raw, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 逐条预校验，返回顺序和入参一一对应。
     * uri 为 null 表示这条不能交给系统删，reason 说明原因（见 REASON_*）。
     */
    private fun resolveDeleteUris(items: List<Map<String, Any>>, result: MethodChannel.Result) {
        Thread {
            val claimed = HashSet<Long>()
            val resolved = items.map { item ->
                // 这一步在后台线程：允许为「选择器只给了副本」的条目回查原图。
                val candidate = validateDeleteCandidate(item, allowMatch = true, claimed = claimed)
                mapOf<String, Any?>(
                    "uri" to candidate.uri?.toString(),
                    "video" to candidate.isVideo,
                    "reason" to candidate.reason
                )
            }
            runOnUiThread { result.success(mapOf("items" to resolved)) }
        }.start()
    }

    /**
     * 删除手机相册里的原图：API 30+ 走系统确认弹窗，其余（或系统不接受）走直接删除。
     *
     * createDeleteRequest 只接受带具体 ID 的 MediaStore 单项 URI。一批里混进一个别的
     * 形态（picker URI、别的 authority、拼错的集合），系统会整批抛
     * IllegalArgumentException: All requested items must be referenced by specific ID，
     * 一条都删不掉。所以进批之前每条都必须过 [validateDeleteCandidate]，
     * 不合格的单算失败，绝不塞进同一批。
     */
    private fun deleteMedia(items: List<Map<String, Any>>, result: MethodChannel.Result) {
        if (items.isEmpty()) {
            result.success(mapOf("deleted" to 0, "failed" to 0))
            return
        }
        if (pendingDeleteSession != null) {
            result.error("busy", "上一次删除还没结束", null)
            return
        }
        lastDeleteError = null
        lastDeleteReason = null
        val candidates = items.map { validateDeleteCandidate(it) }
        val deletable = candidates.filter { it.uri != null }
        val firstRejection = candidates.firstOrNull { it.reason != null }?.reason
        if (deletable.isEmpty()) {
            result.success(
                mapOf(
                    "deleted" to 0,
                    "failed" to items.size,
                    "reason" to (firstRejection ?: REASON_UNSUPPORTED_URI)
                )
            )
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 不同厂商对批量删除的限制差别很大（小米尤其严格）：先整批交给系统，
            // 被拒再退回逐条，且逐条要一直处理到没有剩余，而不是只弹第一张。
            pendingDeleteSession = DeleteSession(
                result = result,
                total = items.size,
                firstRejection = firstRejection,
                remaining = deletable.toMutableList()
            )
            requestNextDelete()
            return
        }
        // API < 30，或系统连逐条确认都不给：自己删（有写权限才删得掉）。
        var deleted = 0
        for (candidate in deletable) {
            val uri = candidate.uri ?: continue
            try {
                if (contentResolver.delete(uri, null, null) > 0) deleted++
            } catch (e: Exception) {
                recordDeleteError(e)
                Log.w("AlbumMediaStore", "删除失败: $uri", e)
            }
        }
        result.success(
            mapOf(
                "deleted" to deleted,
                "failed" to items.size - deleted,
                "reason" to (lastDeleteReason ?: firstRejection)
            )
        )
    }

    /**
     * 按「整批 → 对半 → 单条」的顺序试到能被系统接住为止；删完一批继续下一批，
     * 直到没有剩余。
     *
     * 小米等厂商会拒绝一次删多张的请求（createDeleteRequest 直接抛异常），以前
     * 这里退到单条后就直接收工，于是「删原图」只删掉了第一张。现在被拒就换更小
     * 的批次继续，单条也弹不出来才算失败。
     */
    private fun requestNextDelete() {
        val session = pendingDeleteSession ?: return
        if (session.remaining.isEmpty()) {
            finishDeleteSession()
            return
        }
        val sizes = intArrayOf(session.remaining.size, session.remaining.size / 2, 1)
        for (size in sizes) {
            if (size <= 0) continue
            val batch = session.remaining.take(size)
            if (launchDeleteRequest(batch)) {
                session.requested = batch
                return
            }
        }
        // 连单条都弹不出来：剩下的都算失败。
        session.lastReason = lastDeleteReason ?: REASON_SYSTEM_REJECTED
        session.remaining.clear()
        finishDeleteSession()
    }

    /**
     * 把一批交给系统确认框；返回 false 表示连请求都没建起来（厂商拒绝 / 弹不出来）。
     * 这里只负责「弹」，「删了几条、还剩几条」由 ActivityResult 回调接着算。
     */
    private fun launchDeleteRequest(batch: List<DeleteCandidate>): Boolean {
        val uris = batch.mapNotNull { it.uri }
        if (uris.isEmpty()) return false
        val sender = try {
            MediaStore.createDeleteRequest(contentResolver, uris).intentSender
        } catch (e: Exception) {
            recordDeleteError(e)
            Log.w("AlbumMediaStore", "createDeleteRequest 被拒（${uris.size} 项）", e)
            return false
        }
        return try {
            deleteLauncher.launch(IntentSenderRequest.Builder(sender).build())
            true
        } catch (e: Exception) {
            recordDeleteError(e)
            Log.w("AlbumMediaStore", "无法弹出系统删除确认框", e)
            false
        }
    }

    /** 整批删完（或用户取消/弹不出来）后收尾，Dart 侧只收到一次结果。 */
    private fun finishDeleteSession() {
        val session = pendingDeleteSession ?: return
        pendingDeleteSession = null
        val failed = (session.total - session.deleted).coerceAtLeast(0)
        val reason = when {
            failed <= 0 -> null
            session.lastReason != null -> session.lastReason
            session.firstRejection != null -> session.firstRejection
            lastDeleteReason != null -> lastDeleteReason
            else -> REASON_SYSTEM_REJECTED
        }
        session.result.success(
            mapOf(
                "deleted" to session.deleted,
                "failed" to failed,
                "reason" to reason
            )
        )
    }

    private fun recordDeleteError(e: Exception) {
        lastDeleteReason = REASON_SYSTEM_REJECTED
        if (lastDeleteError != null) return
        val message = e.message?.take(120)
        lastDeleteError = if (message.isNullOrBlank()) e.javaClass.simpleName
        else "${e.javaClass.simpleName}: $message"
    }

    /** 按拍摄时间回查到的候选原图：id + 文件大小（用来在连拍里挑最像的那张）。 */
    private data class MatchCandidate(val id: Long, val size: Long)

    /**
     * 一条待删项的校验结论：uri 非空就是可以交给 createDeleteRequest 的
     * content://media/<volume>/<images|video>/<id>；为空时 reason 说明为什么剔除。
     */
    private data class DeleteCandidate(
        val uri: Uri?,
        val isVideo: Boolean,
        val reason: String?
    ) {
        companion object {
            fun rejected(isVideo: Boolean, reason: String) =
                DeleteCandidate(null, isVideo, reason)
        }
    }

    /** media URI 的四段：content://media/<volume>/<images|video>/<id>。 */
    private data class MediaItemParts(val volume: String, val collection: String, val id: Long)

    /** 条目还在不在：查得到 / 明确查不到 / 查不了（没有读权限，空表不能当结论）。 */
    private enum class Existence { PRESENT, MISSING, UNKNOWN }

    private fun validateDeleteCandidate(
        item: Map<String, Any>,
        allowMatch: Boolean = false,
        claimed: MutableSet<Long>? = null
    ): DeleteCandidate =
        validateDeleteCandidate(item["uri"] as? String, item["video"] == true, allowMatch, claimed)

    /**
     * 一条待删项到底能不能交给系统删。
     *
     * 删除接口只认 MediaStore 的单项 URI，所以先把各种来路的地址换成
     * content://media/<volume>/<images|video>/<id>：
     * 1) Photo Picker：content://media/picker/...，先试 MediaStore.getMediaUri，
     *    换不出来就用末尾的媒体 id 按声明类型拼一个；
     * 2) DocumentsUI 回退（没有系统相册选择器的机型）：
     *    content://...media.documents/document/image%3A<id>，id 就是媒体 id；
     * 3) 本来就是 MediaStore 单项 URI 的，直接按 id + 集合核对。
     * 拼出来的 URI 再按 id 查一次库：明确查不到就剔除；查不了（没有读权限）交给
     * 系统确认框判定。
     */
    private fun validateDeleteCandidate(
        raw: String?,
        declaredVideo: Boolean,
        allowMatch: Boolean = false,
        claimed: MutableSet<Long>? = null
    ): DeleteCandidate {
        val parsed = raw?.takeIf { it.isNotBlank() }
            ?.let { runCatching { Uri.parse(it) }.getOrNull() }
            ?: return DeleteCandidate.rejected(declaredVideo, REASON_UNSUPPORTED_URI)
        val picker = isPickerUri(parsed)
        val parts = when {
            picker -> resolvePickerUri(parsed, declaredVideo)?.let { mediaItemParts(it) }
            else -> mediaItemParts(parsed) ?: documentParts(parsed)
        } ?: (if (allowMatch) matchPickedMedia(parsed, claimed) else null) ?: run {
            Log.i(
                "AlbumMediaStore",
                "换不成相册条目，剔除：${parsed.authority} ${parsed.path}"
            )
            return DeleteCandidate.rejected(
                declaredVideo,
                if (picker) REASON_UNRESOLVED_PICKER else REASON_UNSUPPORTED_URI
            )
        }
        return resolveDeletableUri(parts)
    }

    /**
     * 按 id 找一条真能交给系统的 MediaStore URI。
     *
     * 先按解析出的 volume/集合查；查不到再换另一个 external volume，最后再换另一个
     * 集合（声明类型可能和真实集合相反）。没有读权限时 query 会返回空表，按 UNKNOWN
     * 处理：交给系统确认框判定，不在这里剔除。
     */
    private fun resolveDeletableUri(parts: MediaItemParts): DeleteCandidate {
        val isVideo = parts.collection == COLLECTION_VIDEO
        val primary = ContentUris.withAppendedId(collectionUri(parts.volume, parts.collection), parts.id)
        when (probeExistence(primary, isVideo)) {
            Existence.PRESENT, Existence.UNKNOWN -> return DeleteCandidate(primary, isVideo, null)
            Existence.MISSING -> {}
        }
        val otherVolume = when (parts.volume) {
            MediaStore.VOLUME_EXTERNAL -> MediaStore.VOLUME_EXTERNAL_PRIMARY
            MediaStore.VOLUME_EXTERNAL_PRIMARY -> MediaStore.VOLUME_EXTERNAL
            else -> null
        }
        if (otherVolume != null) {
            val alt = ContentUris.withAppendedId(
                collectionUri(otherVolume, parts.collection), parts.id
            )
            when (probeExistence(alt, isVideo)) {
                Existence.PRESENT, Existence.UNKNOWN -> return DeleteCandidate(alt, isVideo, null)
                Existence.MISSING -> {}
            }
        }
        // 声明的类型可能和真实集合相反（视频被拼进了 images）：换另一边再确认一次。
        val otherCollection = if (isVideo) COLLECTION_IMAGES else COLLECTION_VIDEO
        val otherIsVideo = otherCollection == COLLECTION_VIDEO
        val swapped = ContentUris.withAppendedId(
            collectionUri(parts.volume, otherCollection), parts.id
        )
        return when (probeExistence(swapped, otherIsVideo)) {
            Existence.PRESENT, Existence.UNKNOWN -> DeleteCandidate(swapped, otherIsVideo, null)
            Existence.MISSING -> DeleteCandidate.rejected(isVideo, REASON_NOT_FOUND)
        }
    }

    /**
     * DocumentsUI 回退时拿到的是 document URI：
     * content://com.android.providers.media.documents/document/image%3A123。
     *
     * getDocumentId 解出来的 document id 形如 `image:123` / `video:123`，冒号后面
     * 就是 MediaStore 的媒体 id；换成标准单项 URI 后校验/删除都走同一条路。
     */
    private fun documentParts(uri: Uri): MediaItemParts? {
        if (uri.scheme != "content") return null
        val documentId = try {
            DocumentsContract.getDocumentId(uri)
        } catch (_: Exception) {
            // 不是标准的 documents URI：有的实现把 document id 放在最后一段。
            uri.lastPathSegment ?: return null
        }
        val colon = documentId.indexOf(':')
        if (colon <= 0) return null
        val kind = documentId.substring(0, colon)
        val id = documentId.substring(colon + 1).toLongOrNull()?.takeIf { it > 0 } ?: return null
        val collection = when (kind) {
            "image", "images" -> COLLECTION_IMAGES
            "video", "videos" -> COLLECTION_VIDEO
            else -> return null
        }
        return MediaItemParts(MediaStore.VOLUME_EXTERNAL, collection, id)
    }

    /**
     * picker URI → MediaStore 单项 URI；换不出来返回 null（这条会被剔除）。
     *
     * getMediaUri 需要读媒体权限，拿不到时退回「用末尾 id 按声明类型拼」，
     * 拼错集合的情况由 [probeExistence] 的交叉确认兜住。
     */
    private fun resolvePickerUri(uri: Uri, declaredVideo: Boolean): Uri? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val converted = MediaStore.getMediaUri(this, uri)
                if (converted != null) {
                    Log.i("AlbumMediaStore", "picker URI 转换成功: $uri -> $converted")
                    return converted
                }
            } catch (e: Exception) {
                Log.w("AlbumMediaStore", "getMediaUri 失败: $uri", e)
            }
        }
        val id = uri.lastPathSegment?.toLongOrNull()?.takeIf { it > 0 } ?: run {
            Log.w("AlbumMediaStore", "picker URI 里没有可用的媒体 id: $uri")
            return null
        }
        val collection = if (declaredVideo) COLLECTION_VIDEO else COLLECTION_IMAGES
        val built =
            ContentUris.withAppendedId(collectionUri(MediaStore.VOLUME_EXTERNAL, collection), id)
        Log.i("AlbumMediaStore", "用媒体 id 拼出 URI: $uri -> $built")
        return built
    }

    /**
     * 解析 content://media/<volume>/<images|video>/<id>。
     * 别的形态（picker、缺 id、audio/file 集合、别的 authority）一律返回 null：
     * 系统不认，送进 createDeleteRequest 会让整批抛 IllegalArgumentException。
     */
    private fun mediaItemParts(uri: Uri): MediaItemParts? {
        if (uri.scheme != "content" || uri.authority != MEDIA_AUTHORITY) return null
        val segments = uri.pathSegments
        if (segments.size != 4 || segments[2] != "media") return null
        val collection = segments[1]
        if (collection != COLLECTION_IMAGES && collection != COLLECTION_VIDEO) return null
        val id = segments[3].toLongOrNull()?.takeIf { it > 0 } ?: return null
        return MediaItemParts(segments[0], collection, id)
    }

    private fun collectionUri(volume: String, collection: String): Uri =
        Uri.Builder()
            .scheme("content")
            .authority(MEDIA_AUTHORITY)
            .appendPath(volume)
            .appendPath(collection)
            .appendPath("media")
            .build()

    private fun isPickerUri(uri: Uri): Boolean {
        val segments = uri.pathSegments
        return segments.isNotEmpty() && segments[0] == "picker"
    }

    /**
     * 有些系统选择器不把原图 URI 交出来，而是给一份**去掉定位信息的副本**：
     * 小米 HyperOS 的相册选择器就是这样（隐私保护），返回的是它自己 FileProvider
     * 缓存里的 `cache/<时间戳>.jpg`。副本上没有媒体 id，但拍摄时间和像素尺寸还在，
     * 于是按「EXIF 拍摄时间 + 宽高」回查 MediaStore：同一台手机拍的同一张照片这两项
     * 对得上，命中唯一一条就换回标准单项 URI。
     *
     * 只在 [resolveDeleteUris]（后台线程）里启用；没读权限时查询为空，按没找到处理。
     */
    private fun matchPickedMedia(uri: Uri, claimed: MutableSet<Long>? = null): MediaItemParts? {
        if (uri.scheme != "content") return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                BitmapFactory.decodeStream(input, null, bounds)
            }
        } catch (e: Exception) {
            Log.i("AlbumMediaStore", "读取副本尺寸失败: $uri", e)
            return null
        }
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) return null
        val takenAt = readExifTakenAt(uri) ?: return null
        // EXIF 只精确到秒，MediaStore 的 datetaken 与它可能有几秒偏差。
        val window = 15_000L
        val projection = arrayOf(MediaStore.MediaColumns._ID, "datetaken", MediaStore.MediaColumns.SIZE)
        val selection = "datetaken BETWEEN ? AND ? AND width = ? AND height = ?"
        val args = arrayOf(
            (takenAt - window).toString(),
            (takenAt + window).toString(),
            width.toString(),
            height.toString()
        )
        val cursor = try {
            contentResolver.query(
                collectionUri(MediaStore.VOLUME_EXTERNAL, COLLECTION_IMAGES),
                projection,
                selection,
                args,
                "datetaken ASC"
            )
        } catch (e: Exception) {
            Log.i("AlbumMediaStore", "按拍摄时间回查失败: $uri", e)
            return null
        }
        val candidates = ArrayList<MatchCandidate>()
        cursor?.use {
            val idIndex = it.getColumnIndex(MediaStore.MediaColumns._ID)
            val sizeIndex = it.getColumnIndex(MediaStore.MediaColumns.SIZE)
            while (it.moveToNext() && idIndex >= 0) {
                val id = it.getLong(idIndex)
                if (claimed?.contains(id) == true) continue
                val size = if (sizeIndex >= 0) it.getLong(sizeIndex) else 0L
                candidates.add(MatchCandidate(id, size))
            }
        }
        if (candidates.isEmpty()) {
            Log.i("AlbumMediaStore", "没有找到拍摄时间/尺寸一致的原图: $uri")
            return null
        }
        // 连拍里同一秒可能有好几张同尺寸的照片：选择器只是把副本的 GPS EXIF
        // 去掉，文件大小只差几百字节，按「尺寸最接近副本」挑最稳。
        val copySize = querySize(uri) ?: 0L
        val chosen = if (copySize > 0 && candidates.size > 1) {
            candidates.minByOrNull { abs(it.size - copySize) }!!
        } else {
            candidates.first()
        }
        if (candidates.size > 1) {
            Log.i(
                "AlbumMediaStore",
                "副本匹配到 ${candidates.size} 条候选，选 id=${chosen.id}" +
                    "（副本 $copySize B，候选 ${chosen.size} B）"
            )
        }
        claimed?.add(chosen.id)
        return MediaItemParts(MediaStore.VOLUME_EXTERNAL, COLLECTION_IMAGES, chosen.id)
    }

    /** 副本的文件大小：去掉 GPS EXIF 后只比原图小一点，用来在多条候选里挑。 */
    private fun querySize(uri: Uri): Long? {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
                if (it.moveToFirst()) {
                    val index = it.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0 && !it.isNull(index)) return it.getLong(index)
                }
            }
        } catch (_: Exception) {
            // 换一种方式再取
        }
        return try {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length }?.takeIf { it > 0 }
        } catch (_: Exception) {
            null
        }
    }

    /** 读副本的 EXIF 拍摄时间（DateTimeOriginal 优先，退化到 DateTime）。 */
    private fun readExifTakenAt(uri: Uri): Long? {
        val exif = try {
            contentResolver.openInputStream(uri)?.use { ExifInterface(it) }
        } catch (e: Exception) {
            Log.i("AlbumMediaStore", "读取副本 EXIF 失败: $uri", e)
            null
        } ?: return null
        val raw = exif.getAttribute("DateTimeOriginal")
            ?: exif.getAttribute("DateTime")
            ?: return null
        val offset = exif.getAttribute("OffsetTimeOriginal")
        return parseExifDate(raw, offset)
    }

    private fun parseExifDate(value: String, offset: String?): Long? {
        val zone = when {
            offset.isNullOrBlank() -> TimeZone.getDefault()
            else -> TimeZone.getTimeZone("GMT$offset")
        }
        return try {
            SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).apply {
                timeZone = zone
            }.parse(value)?.time
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 按 id 查一次库，确认这条还在不在。
     *
     * 关键取舍：空结果只有在「我们确实有读权限」时才算「不存在」。没有读权限时
     * scoped storage 会把看不见的条目直接过滤掉，回来的同样是空表；把那种空表当成
     * 不存在会把用户的照片全部剔除、删除功能直接失效。所以没有读权限时返回 UNKNOWN，
     * 让系统确认框做最终判定——删除本身不需要读权限，确认弹窗就是授权。
     */
    private fun probeExistence(uri: Uri, isVideo: Boolean): Existence {
        val cursor = try {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
        } catch (e: Exception) {
            Log.i("AlbumMediaStore", "核对条目是否存在失败，按未知处理: $uri", e)
            return Existence.UNKNOWN
        }
        if (cursor == null) return Existence.UNKNOWN
        cursor.use {
            if (it.moveToFirst()) return Existence.PRESENT
        }
        return if (hasMediaReadPermission(isVideo)) Existence.MISSING else Existence.UNKNOWN
    }

    private fun hasMediaReadPermission(isVideo: Boolean): Boolean {
        val permission = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ->
                Manifest.permission.READ_EXTERNAL_STORAGE
            isVideo -> Manifest.permission.READ_MEDIA_VIDEO
            else -> Manifest.permission.READ_MEDIA_IMAGES
        }
        return ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    // ---- AI 帮写：把本地图片压成 1024px 的 JPEG ----

    private fun registerImageEncoder(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "album/image_encoder")
            .setMethodCallHandler { call, result ->
                if (call.method != "encodeJpeg") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val maxEdge = call.argument<Int>("maxEdge") ?: 1024
                val quality = call.argument<Int>("quality") ?: 80
                if (path.isNullOrBlank()) {
                    result.error("bad_args", "缺少图片路径", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val bytes = compressToJpeg(path, maxEdge, quality)
                        runOnUiThread {
                            if (bytes == null) {
                                result.error("encode_failed", "无法读取图片", null)
                            } else {
                                result.success(bytes)
                            }
                        }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("encode_failed", e.message, null) }
                    }
                }.start()
            }
    }

    /** 先按 2 的幂采样解码，再缩到长边 maxEdge，最后压成 JPEG。 */
    private fun compressToJpeg(path: String, maxEdge: Int, quality: Int): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxEdge) {
            sample *= 2
        }
        var bitmap = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sample }
        ) ?: return null
        val scale = maxEdge.toFloat() / max(bitmap.width, bitmap.height)
        if (scale < 1f) {
            val scaled = Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).roundToInt().coerceAtLeast(1),
                (bitmap.height * scale).roundToInt().coerceAtLeast(1),
                true
            )
            if (scaled !== bitmap) bitmap.recycle()
            bitmap = scaled
        }
        val out = ByteArrayOutputStream()
        val ok = bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
        bitmap.recycle()
        return if (ok) out.toByteArray() else null
    }

    // ---- 补丁生效：重启进程 ----

    /**
     * 补丁在 Application.attachBaseContext 里注入，跑着的进程换不掉，所以
     * 「重启 App」必须是「旧进程先死、新进程再起」：直接在原进程里 startActivity
     * 只会新建一个 Activity，新实例跟旧进程同生共死，旧进程一退它也一起没了。
     * 这里把启动 Intent 交给 AlarmManager（setAlarmClock，见
     * [scheduleAlarmClockRelaunch]），进程退出之后再由系统拉起新进程。
     */
    private fun registerAppControl(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "album/app")
            .setMethodCallHandler { call, result ->
                if (call.method != "restart") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                restartApp(result)
            }
    }

    private fun restartApp(result: MethodChannel.Result) {
        val intent = launchIntent()
        if (intent == null) {
            // 拿不到启动 Intent 时不在这里退出：交回 Dart 兜底。
            result.error("no_launch_intent", "系统没有返回启动 Intent", null)
            return
        }

        // 通道只能回执一次，所以先把调度做完，再决定回什么。
        // 首选 setAlarmClock()：普通闹钟的 PendingIntent 在 Android 10+ 的后台
        // 启动 Activity（BAL）限制下会被系统丢掉，闹钟类的才豁免。
        val scheduled = try {
            scheduleAlarmClockRelaunch(intent)
            true
        } catch (e: Exception) {
            Log.w("AlbumApp", "setAlarmClock 调度失败，退回普通闹钟", e)
            false
        }

        if (scheduled) {
            result.success(true)
        } else {
            // 降级：个别 ROM 会限制 setAlarmClock（安全异常 / 不支持闹钟类闹钟），
            // 退回普通闹钟——它在 BAL 下大概率被拦，但成本为零，判定宽松时仍能拉起。
            // 同时把失败告诉 Dart，让它在原生退出没生效时 SystemNavigator.pop() 兜底。
            val fellBack = try {
                schedulePlainAlarmRelaunch(intent)
                true
            } catch (e: Exception) {
                Log.w("AlbumApp", "普通闹钟也调度失败，退回直接拉起", e)
                false
            }
            if (!fellBack) {
                // 最后的旧做法：新实例大概率跟着进程一起结束，用户掉回桌面后重开也能生效。
                try {
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.w("AlbumApp", "直接拉起也失败", e)
                }
            }
            result.error("restart_failed", "无法调度闹钟重启，请手动重开", null)
        }
        // 先把回执交出去，再结束自己；闹钟在 EXIT_DELAY_MS 之后触发。
        Handler(Looper.getMainLooper()).postDelayed({ exitProcess(0) }, EXIT_DELAY_MS)
    }

    /** 取启动 Intent 并补上「清掉旧任务栈、新开任务」的 flag，拿不到返回 null。 */
    private fun launchIntent(): Intent? {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.setPackage(packageName)
        return intent
    }

    /**
     * 重启用的 PendingIntent。
     *
     * FLAG_CANCEL_CURRENT：请求码固定、启动 Intent 每次都由系统重新给，所以
     * 系统里很可能还留着上一次调度（比如上一版被 BAL 拦下的那次）注册的
     * PendingIntent。CANCEL_CURRENT 先取消旧的再建新的，保证这次闹钟拿到的
     * 一定是本次 Intent（带 NEW_TASK / CLEAR_TOP），不会复用旧 Intent 里的
     * 过期状态。代价是每次调用都会产生一个新对象，所以调用点必须只建一次、
     * 同一个对象同时交给 operation 和 showIntent；建两次会互相取消。
     * FLAG_IMMUTABLE：targetSdk 31+ 要求显式声明可变性，我们不需要接收方
     * 改写 Intent，取不可变最安全（也满足 Android 14 的隐式 Intent 限制）。
     */
    private fun relaunchPendingIntent(intent: Intent): PendingIntent = PendingIntent.getActivity(
        this,
        RELAUNCH_REQUEST_CODE,
        intent,
        PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    /**
     * 用 [AlarmManager.setAlarmClock] 在进程退出之后再拉起启动 Intent。
     *
     * 为什么必须是它：Android 10+ 禁止应用在后台启动 Activity（BAL）。普通
     * AlarmManager.set() 的 PendingIntent 到点时属于「后台发送」，系统直接把
     * 启动请求丢掉——真机上的现象就是旧进程退出、新页面起不来。setAlarmClock()
     * 是闹钟类应用专用的豁免路径：系统把它当成用户可见的闹钟（带状态栏图标、
     * 不受 Doze/待机批量影响），其 PendingIntent 不受 BAL 拦截。
     *
     * 副作用：状态栏会短暂出现一个闹钟图标（触发后由系统移除），点它也能回到 App。
     * 代价可接受：一次重启只亮几百毫秒。
     *
     * 时间用墙钟：setAlarmClock 只接受 RTC 触发时间，不能传 elapsedRealtime()。
     * 误差只来自系统时间本身（用户手动改时间时才会偏），triggerAtMillis 仍在
     * 秒级以内，不会被批量延后。
     */
    private fun scheduleAlarmClockRelaunch(intent: Intent) {
        // 同一个 PendingIntent 同时当 operation 和 showIntent：
        // operation 到点负责拉起新进程，showIntent 供用户点闹钟图标时回到 App。
        val operation = relaunchPendingIntent(intent)
        val alarms = getSystemService(AlarmManager::class.java)
            ?: throw IllegalStateException("AlarmManager 不可用")
        alarms.setAlarmClock(
            AlarmManager.AlarmClockInfo(
                System.currentTimeMillis() + RELAUNCH_WALL_CLOCK_DELAY_MS,
                operation
            ),
            operation
        )
    }

    /**
     * 降级方案：普通（非精确）闹钟。
     *
     * 两条取舍都保留自上一版：BAL 下它大概率拉不起 Activity，排在这是给判定
     * 宽松的 ROM / 用户恰好在前台时留后路；用 set() 而不是
     * setExactAndAllowWhileIdle()，是因为精确闹钟在 Android 12+ 需要
     * SCHEDULE_EXACT_ALARM（Android 14 起默认不授予），为重启这几百毫秒去申请
     * 一个敏感权限不划算。真被延后也不影响正确性，补丁一定会在新进程的
     * Application.attachBaseContext 里装载。
     */
    private fun schedulePlainAlarmRelaunch(intent: Intent) {
        val pending = relaunchPendingIntent(intent)
        val alarms = getSystemService(AlarmManager::class.java)
            ?: throw IllegalStateException("AlarmManager 不可用")
        // ELAPSED_REALTIME 配 elapsedRealtime()：单调时钟，不受用户改系统时间影响。
        alarms.set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + RELAUNCH_DELAY_MS,
            pending
        )
    }

    // ---- 「记住密码」的本地加密：AndroidKeyStore 里不可导出的 AES/GCM 密钥 ----

    private fun registerSecureStore(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureStoreChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "encrypt" -> result.success(encryptValue(call.argument<String>("value") ?: ""))
                        "decrypt" -> result.success(decryptValue(call.argument<String>("value") ?: ""))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.w("AlbumSecureStore", "加解密失败", e)
                    result.error("secure_store_error", e.message, null)
                }
            }
    }

    private fun keyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun getOrCreateKey(): SecretKey {
        val store = keyStore()
        (store.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    /** 返回 base64(iv长度 + iv + 密文)，空字符串表示不支持。 */
    private fun encryptValue(value: String): String? {
        if (value.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val packed = ByteBuffer.allocate(1 + iv.size + encrypted.size)
            .put(iv.size.toByte())
            .put(iv)
            .put(encrypted)
            .array()
        return Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    private fun decryptValue(value: String): String? {
        if (value.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val packed = Base64.decode(value, Base64.NO_WRAP)
        if (packed.size < 3) return null
        val ivLength = packed[0].toInt() and 0xFF
        require(ivLength in 1 until packed.size) { "密文格式不正确" }
        val iv = packed.copyOfRange(1, 1 + ivLength)
        val cipherText = packed.copyOfRange(1 + ivLength, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(cipherText), Charsets.UTF_8)
    }
}
