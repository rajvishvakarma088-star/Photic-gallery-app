package com.example.photicgallery

import android.app.RecoverableSecurityException
import android.app.WallpaperManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val screenSecureChannel = "com.example.photicgallery/screen_security"
    private val wallpaperChannel    = "com.photicgallery/wallpaper"
    private val renameChannel       = "com.photicgallery/rename"

    companion object {
        private const val RENAME_REQUEST_CODE = 1001
    }

    private var pendingRenameResult : MethodChannel.Result? = null
    private var pendingRenameUri    : Uri? = null
    private var pendingRenameName   : String? = null

    // ── Build the correct MediaStore URI from asset ID + type ──────────────────
    // assetType: 1 = image, 2 = video, 3 = audio
    private fun mediaStoreUri(assetId: Long, assetType: Int): Uri {
        val base = when (assetType) {
            2    -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            3    -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        return ContentUris.withAppendedId(base, assetId)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Screen security ───────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenSecureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSecure"  -> { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE);  result.success(null) }
                    "disableSecure" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                    else            -> result.notImplemented()
                }
            }

        // ── Rename ────────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, renameChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "renameFile") { result.notImplemented(); return@setMethodCallHandler }

                val assetIdStr = call.argument<String>("assetId")
                val assetType  = call.argument<Int>("assetType") ?: 1
                val newName    = call.argument<String>("newName")

                if (assetIdStr == null || newName == null) {
                    result.error("INVALID_ARGS", "assetId and newName are required", null)
                    return@setMethodCallHandler
                }

                val assetId = assetIdStr.toLongOrNull()
                if (assetId == null) {
                    result.error("INVALID_ID", "assetId is not a valid number: $assetIdStr", null)
                    return@setMethodCallHandler
                }

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        // Android 10+ — use the typed MediaStore URI directly (no DATA query)
                        val itemUri = mediaStoreUri(assetId, assetType)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            // Android 11+ — createWriteRequest shows system dialog
                            @Suppress("NewApi")
                            val writeRequest = MediaStore.createWriteRequest(
                                contentResolver, listOf(itemUri)
                            )
                            pendingRenameResult = result
                            pendingRenameUri    = itemUri
                            pendingRenameName   = newName
                            startIntentSenderForResult(
                                writeRequest.intentSender,
                                RENAME_REQUEST_CODE, null, 0, 0, 0
                            )
                        } else {
                            // Android 10 — try direct update; catch permission exception
                            doRename(itemUri, newName, result)
                        }
                    } else {
                        // Android 9 and below — look up the file path and rename directly
                        val base   = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        val cursor = contentResolver.query(
                            ContentUris.withAppendedId(base, assetId),
                            arrayOf(MediaStore.MediaColumns.DATA), null, null, null
                        )
                        if (cursor != null && cursor.moveToFirst()) {
                            val filePath = cursor.getString(0)
                            cursor.close()
                            val src = java.io.File(filePath)
                            val dst = java.io.File(src.parentFile, newName)
                            if (src.renameTo(dst)) result.success(null)
                            else result.error("RENAME_FAILED", "File.renameTo() returned false", null)
                        } else {
                            cursor?.close()
                            result.error("NOT_FOUND", "Could not resolve path for asset $assetId", null)
                        }
                    }
                } catch (e: Exception) {
                    result.error("RENAME_ERROR", e.localizedMessage ?: e.toString(), null)
                }
            }

        // ── Wallpaper ─────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wallpaperChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "setWallpaperWithIntent") {
                    val assetIdStr = call.argument<String>("assetId")
                    val assetType  = call.argument<Int>("assetType") ?: 1
                    
                    if (assetIdStr == null) {
                        result.error("INVALID_ARGS", "assetId is required", null)
                        return@setMethodCallHandler
                    }
                    val assetId = assetIdStr.toLongOrNull() ?: return@setMethodCallHandler result.error("INVALID", "Invalid ID", null)
                    
                    try {
                        val itemUri = mediaStoreUri(assetId, assetType)
                        val intent = Intent(Intent.ACTION_ATTACH_DATA).apply {
                            addCategory(Intent.CATEGORY_DEFAULT)
                            setDataAndType(itemUri, "image/*")
                            putExtra("mimeType", "image/*")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(intent, "Set as"))
                        result.success(null)
                    } catch(e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                    return@setMethodCallHandler
                }

                if (call.method != "setWallpaper") { result.notImplemented(); return@setMethodCallHandler }

                val path  = call.argument<String>("path")
                val which = call.argument<Int>("which") ?: 3

                if (path == null) { result.error("INVALID_PATH", "No file path provided", null); return@setMethodCallHandler }

                try {
                    val bitmap = BitmapFactory.decodeFile(path)
                    if (bitmap == null) {
                        result.error("DECODE_FAILED", "Could not decode image at: $path", null)
                        return@setMethodCallHandler
                    }
                    val wm = WallpaperManager.getInstance(applicationContext)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val flag = when (which) {
                            1    -> WallpaperManager.FLAG_SYSTEM
                            2    -> WallpaperManager.FLAG_LOCK
                            else -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                        }
                        wm.setBitmap(bitmap, null, true, flag)
                    } else {
                        wm.setBitmap(bitmap)
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("WALLPAPER_ERROR", e.localizedMessage ?: e.toString(), null)
                }
            }
    }

    // ── Helper: attempt the ContentResolver update (catches Android 10 exception) ──
    private fun doRename(itemUri: Uri, newName: String, result: MethodChannel.Result) {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, newName)
        }
        try {
            val updated = contentResolver.update(itemUri, values, null, null)
            if (updated > 0) result.success(null)
            else result.error("RENAME_FAILED", "MediaStore returned 0 updated rows", null)
        } catch (rse: RecoverableSecurityException) {
            // Android 10: need the user to explicitly grant write access
            pendingRenameResult = result
            pendingRenameUri    = itemUri
            pendingRenameName   = newName
            startIntentSenderForResult(
                rse.userAction.actionIntent.intentSender,
                RENAME_REQUEST_CODE, null, 0, 0, 0
            )
        }
    }

    // ── Activity result — fires after the system permission dialog ─────────────
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != RENAME_REQUEST_CODE) return

        val res  = pendingRenameResult
        val uri  = pendingRenameUri
        val name = pendingRenameName

        pendingRenameResult = null
        pendingRenameUri    = null
        pendingRenameName   = null

        if (res == null) return

        if (resultCode != RESULT_OK || uri == null || name == null) {
            res.error("PERMISSION_DENIED", "User denied modification access", null)
            return
        }

        // Permission granted — retry the rename
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
        }
        try {
            val updated = contentResolver.update(uri, values, null, null)
            if (updated > 0) res.success(null)
            else res.error("RENAME_FAILED", "Update returned 0 rows after permission granted", null)
        } catch (e: Exception) {
            res.error("RENAME_FAILED", e.localizedMessage ?: e.toString(), null)
        }
    }
}
