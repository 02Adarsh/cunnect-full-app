package com.cunnect.cunnect_food

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val APK_NAME = "CUnnect-update.apk"

    // ⭐ v63: cunnect:// deep link (password reset from email)
    private var pendingLink: String? = null
    private var linkChannel: MethodChannel? = null

    // ⭐ v52: App-wide screenshot / screen-recording block.
    // FLAG_SECURE makes every screen in the app impossible to capture
    // (screenshots come out blocked, screen recorders show black, and
    // the app preview is hidden in the recents switcher).
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        // ⭐ v63: app launched from a cunnect:// link (cold start)
        intent?.dataString?.let { if (it.startsWith("cunnect://")) pendingLink = it }
    }

    // ⭐ v63: app was already running and a cunnect:// link arrived
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val url = intent.dataString ?: return
        if (url.startsWith("cunnect://")) {
            pendingLink = url
            linkChannel?.invokeMethod("onLink", url)
        }
    }

    // ⭐ Android 14+ reports every screenshot ATTEMPT — we show the
    // custom CUnnect message on top of the OS block.
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
        // ⭐ v63: deep-link channel — Flutter pulls the launch link and
        // listens for links that arrive while the app is running.
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
                result.success(downloadApk(url))
            } else {
                result.notImplemented()
            }
        }
    }

    // ⭐ In-app APK download — browser/GitHub user ko kabhi nahi dikhta
    private fun downloadApk(url: String): Boolean {
        if (url.isEmpty()) return false
        return try {
            removeOldApk()
            val dm = getSystemService(android.app.DownloadManager::class.java)
            val req = android.app.DownloadManager.Request(android.net.Uri.parse(url))
                .setMimeType("application/vnd.android.package-archive")
                .setTitle("CUnnect Update")
                .setDescription("Downloading latest version")
                .setNotificationVisibility(
                    android.app.DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(
                    android.os.Environment.DIRECTORY_DOWNLOADS, APK_NAME)
            dm.enqueue(req)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun removeOldApk() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= 29) {
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
                val f = java.io.File(
                    android.os.Environment.getExternalStoragePublicDirectory(
                        android.os.Environment.DIRECTORY_DOWNLOADS), APK_NAME)
                if (f.exists()) f.delete()
            } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    // ⭐ OEM autostart / battery settings kholo — instant notifications ke liye
    private fun openAutostart(): Boolean {
        val intents = listOf(
            // Xiaomi / Redmi / POCO
            Intent().setComponent(ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            // Oppo / OnePlus / Realme
            Intent().setComponent(ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity")),
            Intent().setComponent(ComponentName(
                "com.oplus.safecenter",
                "com.oplus.safecenter.startupapp.StartupAppListActivity")),
            // Vivo
            Intent().setComponent(ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
            // Huawei
            Intent().setComponent(ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupapp.StartupAppControlActivity")),
            // fallback: app details
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .apply {
                    data = android.net.Uri.parse("package:$packageName")
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
