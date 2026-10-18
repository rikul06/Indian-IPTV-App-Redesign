package com.nk.live_tv

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Tells the Flutter side whether it runs on Android TV / Google TV.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "live_tv/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isTv") {
                    val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    result.success(uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                } else {
                    result.notImplemented()
                }
            }
    }
}
