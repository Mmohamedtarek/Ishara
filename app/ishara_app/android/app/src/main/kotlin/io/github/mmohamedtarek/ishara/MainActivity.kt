package io.github.mmohamedtarek.ishara

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Emergency contacts (Q-T4 phase 1): the system's own phone picker.
        // It grants access to the one picked number only: no contacts
        // permission. WhatsApp: installed or not (package visibility).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ishara/contacts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPhone" -> {
                        if (pickResult != null) {
                            result.error("busy", "a pick is open", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(
                            Intent.ACTION_PICK,
                            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                        )
                        try {
                            pickResult = result
                            startActivityForResult(intent, PICK_PHONE)
                        } catch (e: ActivityNotFoundException) {
                            pickResult = null
                            result.success(null)
                        }
                    }
                    "hasWhatsApp" -> result.success(
                        listOf("com.whatsapp", "com.whatsapp.w4b").any { installed(it) },
                    )
                    else -> result.notImplemented()
                }
            }
        // Talk keeps the screen on while it is visible (S7-5); no package needed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ishara/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installed(name: String): Boolean = try {
        packageManager.getPackageInfo(name, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    @Deprecated("FlutterActivity still delivers results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_PHONE) return
        val result = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val cols = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        try {
            contentResolver.query(uri, cols, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    result.success(mapOf("name" to c.getString(0), "number" to c.getString(1)))
                    return
                }
            }
            result.success(null)
        } catch (e: SecurityException) {
            result.success(null)
        }
    }

    companion object {
        private const val PICK_PHONE = 4107
    }
}
