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
        when (call.method) {
            INSPECT_METHOD -> inspect(call, result)
            INSTALL_METHOD -> install(call, result)
            else -> result.notImplemented()
        }
    }

    /** קורא מה-APK את שם החבילה והגרסה, בלי להתקין. */
    @Suppress("DEPRECATION")
    private fun inspect(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val info = path?.let { activity.packageManager.getPackageArchiveInfo(it, 0) }
        if (info == null) {
            result.error("not_apk", "הקובץ אינו קובץ התקנה תקין", null)
            return
        }
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        result.success(
            mapOf(
                "packageName" to info.packageName,
                "versionCode" to code,
                "versionName" to info.versionName,
                "ownPackage" to activity.packageName,
            ),
        )
    }

    private fun install(call: MethodCall, result: MethodChannel.Result) {
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
        const val INSPECT_METHOD = "inspect"
    }
}
