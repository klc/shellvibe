package dev.shellvibe.app

import android.content.ClipData
import android.content.ClipboardManager
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FLAG_SECURE keeps the window out of screenshots, screen recordings
        // and the recent-apps thumbnail. Dart turns it on while a master
        // password guards the vault (see ShellVibeApp).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.shellvibe.app/secure_window",
        ).setMethodCallHandler { call, result ->
            if (call.method != "setSecure") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (call.arguments == true) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            result.success(null)
        }
        // Secrets copied with the "sensitive" mark: Android 13+ masks them in
        // the copy preview and keyboards' clipboard suggestions. Dart falls
        // back to a plain copy if this fails.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.shellvibe.app/clipboard",
        ).setMethodCallHandler { call, result ->
            val text = call.arguments as? String
            if (call.method != "copySensitive" || text == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val clip = ClipData.newPlainText("", text)
                clip.description.extras = PersistableBundle().apply {
                    // The extra's key; ClipDescription.EXTRA_IS_SENSITIVE
                    // names it from API 33 on, older versions ignore it.
                    putBoolean("android.content.extra.IS_SENSITIVE", true)
                }
                getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                result.success(null)
            } catch (e: Exception) {
                result.error("copy_failed", e.message, null)
            }
        }
    }
}
