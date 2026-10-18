package com.nk.live_tv

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "live_tv/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Whether the app runs on Android TV / Google TV.
                    "isTv" -> {
                        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    // Lets the user pick VLC, MX Player or any other video app.
                    "openExternal" -> {
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(Uri.parse(call.argument<String>("url")), "video/*")
                        val apps = packageManager.queryIntentActivities(intent, 0)
                        if (apps.isEmpty()) {
                            result.success(false)
                        } else {
                            startActivity(Intent.createChooser(intent, "Open with"))
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
