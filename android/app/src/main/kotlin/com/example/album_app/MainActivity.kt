package com.example.album_app

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 使用 Android 系统 Photo Picker，同时在拿到 URI 后请求原始文件。
 * 普通 image_picker 会复制照片；带位置信息的照片会被系统脱敏，小米
 * Motion Photo 的内嵌视频也可能随之丢失。这里申请 ACCESS_MEDIA_LOCATION
 * 并调用 setRequireOriginal()，尽量保留原始字节。
 */
class MainActivity : FlutterFragmentActivity() {
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

    // 删除原图需要用户在系统弹窗里确认（Android 11+）。
    private var pendingDeleteResult: MethodChannel.Result? = null
    // 这一次交给系统的张数，以及这批图片视频总共要删的张数。
    private var pendingDeleteRequested = 0
    private var pendingDeleteTotal = 0
    // 留着给 Dart 侧显示，方便没有 adb 时也能知道系统为什么拒绝。
    private var lastDeleteError: String? = null
    private val deleteLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        val callback = pendingDeleteResult
        val requested = pendingDeleteRequested
        val total = pendingDeleteTotal
        pendingDeleteResult = null
        pendingDeleteRequested = 0
        pendingDeleteTotal = 0
        if (callback == null) return@registerForActivityResult
        val approved = result.resultCode == Activity.RESULT_OK
        val deleted = if (approved) requested else 0
        callback.success(
            mapOf(
                "deleted" to deleted,
                "failed" to total - deleted,
                "error" to if (approved) null else "用户取消了系统确认"
            )
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerSecureStore(flutterEngine)
        registerImageEncoder(flutterEngine)
        registerMediaStore(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickMultiple") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
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
                    else -> result.notImplemented()
                }
            }
    }

    /** 优先用系统确认弹窗删除；API < 30 或拿不到 MediaStore URI 时直接删。 */
    private fun deleteMedia(items: List<Map<String, Any>>, result: MethodChannel.Result) {
        if (items.isEmpty()) {
            result.success(mapOf("deleted" to 0, "failed" to 0))
            return
        }
        lastDeleteError = null
        val picked = ArrayList<Pair<Uri, Boolean>>()
        for (item in items) {
            val raw = item["uri"] as? String ?: continue
            val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: continue
            picked.add(uri to (item["video"] == true))
        }
        if (picked.isEmpty()) {
            result.success(
                mapOf("deleted" to 0, "failed" to items.size, "error" to "无法识别相册地址")
            )
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 不同厂商对 picker URI 的支持差别很大（小米尤其严格），
            // 按“转换后的批量 / 原始批量 / 逐条”依次尝试，哪一档能被系统接住就用哪一档。
            val converted = picked.mapNotNull { (uri, isVideo) ->
                runCatching { resolveDeletableUri(uri, isVideo) }.getOrNull()
                    ?.takeIf { it != uri }
            }
            val originals = picked.map { it.first }
            val batches = ArrayList<List<Uri>>()
            if (converted.isNotEmpty()) batches.add(converted)
            batches.add(originals)
            for (uri in converted.distinct()) batches.add(listOf(uri))
            for (uri in originals.distinct()) batches.add(listOf(uri))
            val tried = HashSet<String>()
            for (batch in batches) {
                if (batch.isEmpty()) continue
                if (!tried.add(batch.joinToString("|") { it.toString() })) continue
                val sender = try {
                    MediaStore.createDeleteRequest(contentResolver, batch).intentSender
                } catch (e: Exception) {
                    recordDeleteError(e)
                    Log.w("AlbumMediaStore", "createDeleteRequest 被拒（${batch.size} 项）", e)
                    continue
                }
                pendingDeleteResult = result
                pendingDeleteRequested = batch.size
                pendingDeleteTotal = originals.size
                try {
                    deleteLauncher.launch(IntentSenderRequest.Builder(sender).build())
                    return
                } catch (e: Exception) {
                    pendingDeleteResult = null
                    pendingDeleteRequested = 0
                    pendingDeleteTotal = 0
                    recordDeleteError(e)
                    Log.w("AlbumMediaStore", "无法弹出系统删除确认框", e)
                }
            }
        }
        var deleted = 0
        for ((uri, _) in picked) {
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
                "failed" to picked.size - deleted,
                "error" to lastDeleteError
            )
        )
    }

    private fun recordDeleteError(e: Exception) {
        if (lastDeleteError != null) return
        val message = e.message?.take(120)
        lastDeleteError = if (message.isNullOrBlank()) e.javaClass.simpleName
        else "${e.javaClass.simpleName}: $message"
    }

    /**
     * Photo Picker 返回的是 content://media/picker/0/.../media/<id>，
     * MediaStore 的删除接口只认 content://media/external/... 这类 URI，必须转换：
     * 1) Android 13+ 用 MediaStore.getMediaUri（需要读媒体权限，拿不到就走下一步）
     * 2) 用末尾的媒体 id 直接拼出 images/video 的 MediaStore URI
     */
    private fun resolveDeletableUri(uri: Uri, isVideo: Boolean): Uri {
        if (!isPickerUri(uri)) return uri
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
        val id = uri.lastPathSegment?.toLongOrNull()
        if (id != null) {
            val base = if (isVideo) {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val fallback = ContentUris.withAppendedId(base, id)
            Log.i("AlbumMediaStore", "使用媒体 id 拼出 URI: $uri -> $fallback")
            return fallback
        }
        Log.w("AlbumMediaStore", "无法识别 picker URI: $uri")
        return uri
    }

    private fun isPickerUri(uri: Uri): Boolean {
        val segments = uri.pathSegments
        return segments.isNotEmpty() && segments[0] == "picker"
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
