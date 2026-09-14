package com.parametromanila

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.parametromanila/app_identity",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getGoogleApiIdentity") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                result.success(
                    mapOf(
                        "packageName" to packageName,
                        "certificateSha1" to signingCertificateSha1(),
                    ),
                )
            } catch (error: Exception) {
                result.error("identity_unavailable", error.message, null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun signingCertificateSha1(): String {
        val signatures =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager
                    .getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo
                    ?.apkContentsSigners
            } else {
                packageManager
                    .getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                    .signatures
            }
        val certificate = requireNotNull(signatures?.firstOrNull())
        return MessageDigest
            .getInstance("SHA-1")
            .digest(certificate.toByteArray())
            .joinToString("") { byte -> "%02X".format(byte.toInt() and 0xFF) }
    }
}
