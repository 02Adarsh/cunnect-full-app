package com.cunnect.cunnect_food

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val APK_NAME = "CUnnect-update.apk"

    // ⭐ v63: cunnect:// deep link (password reset from email)
    private var pendingLink: String? = null
    private var linkChannel: MethodChannel? = null

    // ⭐ v85: live APK download progress → Flutter
    private var progressSink: EventChannel.EventSink? = null
    private var activeDownloadId: Long = -1L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressTicker: Runnable? = null
    private var downloadReceiver: BroadcastReceiver? = null

    // ⭐ v52: App-wide screenshot / screen-recording block.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        intent?.dataString?.let { if (it.startsWith("cunnect://")) pendingLink = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val url = intent.dataString ?: return
        if (url.startsWith("cunnect://")) {
            pendingLink = url
            linkChannel?.invokeMethod("onLink", url)
        }
    }

    private var captureCallback: Any? = null

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                val cb = ScreenCaptureCallback {
                    runOnUiThread {
                        Toast.makeText(
                            this,
                            "The screen capture has been blocked by CUnnect team",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
                registerScreenCaptureCallback(mainExecutor, cb)
                captureCallback = cb
            } catch (_: Exception) {
            }
        }
    }

    override fun onStop() {
        super.onStop()
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                (captureCallback as? ScreenCaptureCallback)?.let {
                    unregisterScreenCaptureCallback(it)
                }
                captureCallback = null
            } catch (_: Exception) {
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        linkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "cunnect/deeplink"
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "getInitialLink") {
                    result.success(pendingLink)
                    pendingLink = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "cunnect/autostart"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openAutostart") {
                result.success(openAutostart())
            } else if (call.method == "downloadApk") {
                val url = call.argument<String>("url") ?: ""
                // ⭐ v85: run off the UI thread; result fires when the
                // file is ready (or failed) so Flutter can show %.
                Thread {
                    val ok = downloadApkBlocking(url)
                    runOnUiThread { result.success(ok) }
                }.start()
            } else {
                result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger, "cunnect/apk_progress"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }
            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
    }

    private fun emitProgress(progress: Double, status: String) {
        mainHandler.post {
            try {
                progressSink?.success(
                    hashMapOf("progress" to progress, "status" to status)
                )
            } catch (_: Exception) {
            }
        }
    }

    // ⭐ v85: DownloadManager with live % + auto-open the installer.
    // Blocks the calling worker thread until the download finishes
    // (or 4 minutes pass), so Flutter's await gets a real answer.
    private fun downloadApkBlocking(url: String): Boolean {
        if (url.isEmpty()) return false
        return try {
            removeOldApk()
            val dm = getSystemService(DownloadManager::class.java) ?: return false
            val req = DownloadManager.Request(Uri.parse(url))
                .setMimeType("application/vnd.android.package-archive")
                .setTitle("CUnnect Update")
                .setDescription("Downloading latest version")
                .setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)
                .setDestinationInExternalPublicDir(
                    Environment.DIRECTORY_DOWNLOADS, APK_NAME)
            // Allow free network use — GitHub + any CDN.
            try {
                req.setAllowedNetworkTypes(
                    DownloadManager.Request.NETWORK_WIFI or
                        DownloadManager.Request.NETWORK_MOBILE)
            } catch (_: Exception) {
            }

            val done = Object()
            var success = false
            var finished = false

            // Receiver: download complete → install
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) ?: -1L
                    if (id != activeDownloadId) return
                    stopProgressTicker()
                    val uri = dm.getUriForDownloadedFile(id)
                    val local = dm.getMimeTypeForDownloadedFile(id)
                    emitProgress(1.0, "Installing…")
                    val installed = openInstaller(id, dm)
                    success = installed
                    finished = true
                    synchronized(done) { done.notifyAll() }
                }
            }
            downloadReceiver = receiver
            val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
            try {
                if (Build.VERSION.SDK_INT >= 33) {
                    registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("DEPRECATION")
                    registerReceiver(receiver, filter)
                }
            } catch (_: Exception) {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }

            activeDownloadId = dm.enqueue(req)
            emitProgress(-1.0, "Connecting…")
            startProgressTicker(dm, activeDownloadId)

            // Wait up to 4 minutes for completion.
            synchronized(done) {
                val deadline = System.currentTimeMillis() + 4L * 60L * 1000L
                while (!finished && System.currentTimeMillis() < deadline) {
                    try {
                        done.wait(500)
                    } catch (_: InterruptedException) {
                        break
                    }
                    // Also poll status in case the broadcast was missed.
                    if (!finished) {
                        val st = queryStatus(dm, activeDownloadId)
                        if (st == DownloadManager.STATUS_SUCCESSFUL) {
                            stopProgressTicker()
                            emitProgress(1.0, "Installing…")
                            success = openInstaller(activeDownloadId, dm)
                            finished = true
                        } else if (st == DownloadManager.STATUS_FAILED) {
                            stopProgressTicker()
                            emitProgress(0.0, "Download failed")
                            finished = true
                            success = false
                        }
                    }
                }
            }
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            downloadReceiver = null
            stopProgressTicker()
            success
        } catch (_: Exception) {
            stopProgressTicker()
            false
        }
    }

    private fun startProgressTicker(dm: DownloadManager, id: Long) {
        stopProgressTicker()
        progressTicker = object : Runnable {
            override fun run() {
                try {
                    val q = DownloadManager.Query().setFilterById(id)
                    val c: Cursor? = dm.query(q)
                    c?.use {
                        if (it.moveToFirst()) {
                            val soFarIdx = it.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                            val totalIdx = it.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                            val statusIdx = it.getColumnIndex(DownloadManager.COLUMN_STATUS)
                            val soFar = if (soFarIdx >= 0) it.getLong(soFarIdx) else 0L
                            val total = if (totalIdx >= 0) it.getLong(totalIdx) else -1L
                            val status = if (statusIdx >= 0) it.getInt(statusIdx) else 0
                            when (status) {
                                DownloadManager.STATUS_RUNNING -> {
                                    if (total > 0) {
                                        val p = soFar.toDouble() / total.toDouble()
                                        val mb = soFar / (1024.0 * 1024.0)
                                        val tmb = total / (1024.0 * 1024.0)
                                        emitProgress(
                                            p,
                                            String.format("%.1f / %.1f MB", mb, tmb)
                                        )
                                    } else {
                                        val mb = soFar / (1024.0 * 1024.0)
                                        emitProgress(-1.0, String.format("%.1f MB…", mb))
                                    }
                                }
                                DownloadManager.STATUS_PENDING ->
                                    emitProgress(-1.0, "Queued…")
                                DownloadManager.STATUS_PAUSED ->
                                    emitProgress(-1.0, "Paused…")
                            }
                        }
                    }
                } catch (_: Exception) {
                }
                mainHandler.postDelayed(this, 400)
            }
        }
        mainHandler.post(progressTicker!!)
    }

    private fun stopProgressTicker() {
        progressTicker?.let { mainHandler.removeCallbacks(it) }
        progressTicker = null
    }

    private fun queryStatus(dm: DownloadManager, id: Long): Int {
        return try {
            val c = dm.query(DownloadManager.Query().setFilterById(id))
            c?.use {
                if (it.moveToFirst()) {
                    val i = it.getColumnIndex(DownloadManager.COLUMN_STATUS)
                    if (i >= 0) return it.getInt(i)
                }
            }
            -1
        } catch (_: Exception) {
            -1
        }
    }

    // ⭐ Open the package installer the moment the APK lands.
    private fun openInstaller(id: Long, dm: DownloadManager): Boolean {
        return try {
            // Prefer the public Downloads file (stable across OEMs).
            val file = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS), APK_NAME)
            val uri: Uri = if (file.exists() && file.length() > 1000) {
                if (Build.VERSION.SDK_INT >= 24) {
                    FileProvider.getUriForFile(
                        this, "$packageName.fileprovider", file)
                } else {
                    @Suppress("DEPRECATION")
                    Uri.fromFile(file)
                }
            } else {
                dm.getUriForDownloadedFile(id) ?: return false
            }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            // Last resort: try the DownloadManager content URI directly.
            try {
                val uri = dm.getUriForDownloadedFile(id) ?: return false
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun removeOldApk() {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val col = android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val q = contentResolver.query(
                    col,
                    arrayOf(android.provider.MediaStore.Downloads._ID),
                    android.provider.MediaStore.Downloads.DISPLAY_NAME + "=?",
                    arrayOf(APK_NAME), null)
                q?.use {
                    while (it.moveToNext()) {
                        val id = it.getLong(0)
                        val u = android.content.ContentUris.withAppendedId(col, id)
                        try { contentResolver.delete(u, null, null) } catch (_: Exception) {}
                    }
                }
            }
            try {
                val f = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS), APK_NAME)
                if (f.exists()) f.delete()
            } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    private fun openAutostart(): Boolean {
        val intents = listOf(
            Intent().setComponent(ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            Intent().setComponent(ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity")),
            Intent().setComponent(ComponentName(
                "com.oplus.safecenter",
                "com.oplus.safecenter.startupapp.StartupAppListActivity")),
            Intent().setComponent(ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
            Intent().setComponent(ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupapp.StartupAppControlActivity")),
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .apply {
                    data = Uri.parse("package:$packageName")
                }
        )
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }
}
