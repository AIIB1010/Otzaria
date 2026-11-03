package org.otzaria.otzaria

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** פותח את מתקין החבילות של Android עבור APK שהורד (עדכון עצמי). */
class ApkInstallerChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result -> onMethodCall(call, result) }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != INSTALL_METHOD) {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val file = path?.let { File(it) }
        if (file == null || !file.exists()) {
            result.error("missing_file", "קובץ העדכון לא נמצא", null)
            return
        }
        // באנדרואיד 8 ומעלה צריך לאשר "התקנת אפליקציות לא ידועות" לאפליקציה הזו.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success("needs_permission")
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.lvfileprovider",
                file,
            )
            activity.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                    ),
            )
            result.success("started")
        } catch (error: Exception) {
            result.error("install_failed", error.message, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "org.otzaria.humanware/apk_installer"
        const val INSTALL_METHOD = "install"
    }
}
