package com.solarqibla.solar_qibla

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val ORIENTATION_EVENTS = "solar_qibla/orientation"
        const val ORIENTATION_CONTROL = "solar_qibla/control"
        const val PREFS_NAME = "solar_qibla_prefs"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = OrientationStreamHandler(applicationContext)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ORIENTATION_EVENTS)
            .setStreamHandler(handler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ORIENTATION_CONTROL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // يزوّد طبقة المستشعرات بالموقع لتحسب الانحراف المغناطيسي.
                    "setLocation" -> {
                        val latitude = call.argument<Double>("latitude")
                        val longitude = call.argument<Double>("longitude")
                        if (latitude == null || longitude == null) {
                            result.error(
                                "BAD_ARGS",
                                "يلزم تمرير latitude و longitude.",
                                null,
                            )
                        } else {
                            handler.setLocation(
                                latitude,
                                longitude,
                                call.argument<Double>("altitude") ?: 0.0,
                            )
                            result.success(null)
                        }
                    }

                    // تخزين محلي بسيط عبر SharedPreferences.
                    // نستعمله بدل حزمة تخزين إضافية: قناة المنصّة قائمة أصلًا،
                    // والحاجة محصورة في حفظ آخر موقع وإعدادات قليلة.
                    "readString" -> {
                        val key = call.argument<String>("key")
                        if (key == null) {
                            result.error("BAD_ARGS", "يلزم تمرير key.", null)
                        } else {
                            result.success(prefs().getString(key, null))
                        }
                    }

                    "writeString" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key == null) {
                            result.error("BAD_ARGS", "يلزم تمرير key.", null)
                        } else {
                            prefs().edit().apply {
                                if (value == null) remove(key) else putString(key, value)
                            }.apply()
                            result.success(null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun prefs() =
        applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
