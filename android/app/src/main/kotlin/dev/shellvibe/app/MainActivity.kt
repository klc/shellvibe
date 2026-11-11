package dev.shellvibe.app

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
    }
}
