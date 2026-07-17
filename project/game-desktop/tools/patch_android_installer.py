from pathlib import Path
import re

APP_ID = "com.kingmaker.admin"
UPDATE_CHANNEL = "kingmaker/android_update"
GAME_DISPLAY_CHANNEL = "kingmaker/game_display"

ROOT = Path.cwd()
ANDROID = ROOT / "android"
MANIFEST = ANDROID / "app/src/main/AndroidManifest.xml"
LOGO = ROOT / "assets/app/app_icon.jpg"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def patch_manifest() -> None:
    if not MANIFEST.exists():
        raise SystemExit(f"AndroidManifest.xml not found: {MANIFEST}")
    text = read(MANIFEST)

    permissions = [
        '    <uses-permission android:name="android.permission.INTERNET"/>\n',
        '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n',
        '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n',
    ]
    missing = [p for p in permissions if p.split('android:name="', 1)[1].split('"', 1)[0] not in text]
    if missing:
        lines = text.splitlines(True)
        out = []
        inserted = False
        for line in lines:
            out.append(line)
            if not inserted and "<manifest" in line:
                out.extend(missing)
                inserted = True
        if not inserted:
            raise SystemExit("Failed to insert permissions: <manifest> not found")
        text = "".join(out)

    if "android:usesCleartextTraffic" not in text:
        text, count = re.subn(
            r"(<application\b)",
            r'\1 android:usesCleartextTraffic="true"',
            text,
            count=1,
        )
        if count != 1:
            raise SystemExit("Failed to add usesCleartextTraffic: <application> not found")

    if LOGO.exists():
        app_match = re.search(r"<application\b[^>]*>", text)
        if not app_match:
            raise SystemExit("Failed to set launcher icon: <application> not found")
        app_tag = app_match.group(0)
        patched_tag = app_tag
        for attr in ("android:icon", "android:roundIcon"):
            if attr in patched_tag:
                patched_tag = re.sub(rf'{attr}="[^"]*"', f'{attr}="@drawable/kingmaker_logo"', patched_tag, count=1)
            else:
                patched_tag = patched_tag[:-1] + f' {attr}="@drawable/kingmaker_logo">'
        text = text[:app_match.start()] + patched_tag + text[app_match.end():]

    if "androidx.core.content.FileProvider" not in text:
        provider = '''
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/kingmaker_file_paths" />
        </provider>
'''
        text = text.replace("    </application>", provider + "    </application>")

    if "UpdateCompletedReceiver" not in text:
        receiver = '''
        <receiver
            android:name=".UpdateCompletedReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
'''
        text = text.replace("    </application>", receiver + "    </application>")
    write(MANIFEST, text)



def patch_launcher_logo() -> None:
    if not LOGO.exists():
        raise SystemExit(f"Logo asset not found: {LOGO}")
    target = ANDROID / "app/src/main/res/drawable/kingmaker_logo.jpg"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(LOGO.read_bytes())

def patch_file_paths() -> None:
    write(
        ANDROID / "app/src/main/res/xml/kingmaker_file_paths.xml",
        '''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="updates" path="updates/" />
    <external-files-path name="external_updates" path="Download/" />
</paths>
''',
    )


def patch_main_activity() -> None:
    candidates = list((ANDROID / "app/src/main/kotlin").glob("**/MainActivity.kt"))
    target = ANDROID / "app/src/main/kotlin/com/kingmaker/admin/MainActivity.kt"
    target.parent.mkdir(parents=True, exist_ok=True)
    for candidate in candidates:
        if candidate != target and candidate.exists():
            candidate.unlink()
    write(
        target,
        f'''package {APP_ID}

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "{UPDATE_CHANNEL}").setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "getApkPath" -> {{
                    result.success(apkFileFor(call.argument<String>("fileName")).absolutePath)
                }}
                "startApkDownload" -> {{
                    startApkDownload(call.argument<String>("url"), call.argument<String>("fileName"), result)
                }}
                "queryApkDownload" -> {{
                    queryApkDownload(call.argument<Any>("id"), result)
                }}
                "cancelApkDownload" -> {{
                    cancelApkDownload(call.argument<Any>("id"), result)
                }}
                "installApk" -> {{
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {{
                        result.error("missing_path", "APK path is required", null)
                        return@setMethodCallHandler
                    }}
                    val apkFile = File(path)
                    if (!apkFile.exists()) {{
                        result.error("missing_apk", "APK file was not downloaded", null)
                        return@setMethodCallHandler
                    }}
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {{
                        val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {{
                            data = Uri.parse("package:$packageName")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }}
                        try {{
                            startActivity(settingsIntent)
                        }} catch (ex: Exception) {{
                            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS).apply {{
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }})
                        }}
                        result.error(
                            "install_permission_required",
                            "Allow King Maker to install unknown apps, then return and tap Open installer.",
                            null
                        )
                        return@setMethodCallHandler
                    }}
                    val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apkFile)
                    val intent = Intent(Intent.ACTION_VIEW).apply {{
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }}
                    startActivity(intent)
                    result.success(true)
                }}
                else -> result.notImplemented()
            }}
        }}
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "{GAME_DISPLAY_CHANNEL}").setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "enterGameDisplay" -> {{
                    enterGameDisplay()
                    result.success(true)
                }}
                "exitGameDisplay" -> {{
                    exitGameDisplay()
                    result.success(true)
                }}
                else -> result.notImplemented()
            }}
        }}
    }}

    private fun safeFileName(requestedName: String?): String {{
        val fallback = if (requestedName.isNullOrBlank()) "KingMaker.apk" else requestedName
        return fallback.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }}

    private fun updateDir(): File {{
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: File(cacheDir, "updates")
        dir.mkdirs()
        return dir
    }}

    private fun apkFileFor(requestedName: String?): File {{
        return File(updateDir(), safeFileName(requestedName))
    }}

    private fun downloadManager(): DownloadManager {{
        return getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    }}

    private fun numericId(value: Any?): Long? {{
        return when (value) {{
            is Number -> value.toLong()
            is String -> value.toLongOrNull()
            else -> null
        }}
    }}

    private fun startApkDownload(url: String?, fileName: String?, result: MethodChannel.Result) {{
        if (url.isNullOrBlank()) {{
            result.error("missing_url", "APK URL is required", null)
            return
        }}
        val apkFile = apkFileFor(fileName)
        if (apkFile.exists()) apkFile.delete()
        val request = DownloadManager.Request(Uri.parse(url)).apply {{
            setTitle("King Maker update")
            setDescription("Downloading latest version")
            setMimeType("application/vnd.android.package-archive")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            addRequestHeader("Accept", "application/vnd.android.package-archive,*/*")
            addRequestHeader("User-Agent", "KingMaker Android Updater")
            setDestinationUri(Uri.fromFile(apkFile))
        }}
        try {{
            val id = downloadManager().enqueue(request)
            result.success(mapOf("id" to id, "path" to apkFile.absolutePath))
        }} catch (ex: Exception) {{
            result.error("download_start_failed", ex.message ?: "Download could not start", null)
        }}
    }}

    private fun queryApkDownload(rawId: Any?, result: MethodChannel.Result) {{
        val id = numericId(rawId)
        if (id == null || id <= 0L) {{
            result.error("missing_download_id", "Download id is required", null)
            return
        }}
        val cursor = downloadManager().query(DownloadManager.Query().setFilterById(id))
        if (cursor == null) {{
            result.success(mapOf("status" to "missing"))
            return
        }}
        cursor.use {{ c ->
            if (!c.moveToFirst()) {{
                result.success(mapOf("status" to "missing"))
                return
            }}
            fun intColumn(name: String): Int {{
                val index = c.getColumnIndex(name)
                return if (index >= 0) c.getInt(index) else -1
            }}
            val statusCode = intColumn(DownloadManager.COLUMN_STATUS)
            val received = intColumn(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val total = intColumn(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            val reason = intColumn(DownloadManager.COLUMN_REASON)
            val status = when (statusCode) {{
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                else -> "unknown"
            }}
            result.success(
                mapOf(
                    "status" to status,
                    "receivedBytes" to received,
                    "totalBytes" to total,
                    "reason" to reason
                )
            )
        }}
    }}

    private fun cancelApkDownload(rawId: Any?, result: MethodChannel.Result) {{
        val id = numericId(rawId)
        if (id != null && id > 0L) {{
            downloadManager().remove(id)
        }}
        result.success(true)
    }}
    private fun enterGameDisplay() {{
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {{
            window.attributes = window.attributes.apply {{
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }}
        }}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {{
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {{ controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }}
        }} else {{
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }}
    }}

    private fun exitGameDisplay() {{
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {{
            window.setDecorFitsSystemWindows(true)
            window.insetsController?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
        }} else {{
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }}
    }}
}}
''',
    )

def patch_update_completed_receiver() -> None:
    write(
        ANDROID / "app/src/main/kotlin/com/kingmaker/admin/UpdateCompletedReceiver.kt",
        f'''package {APP_ID}

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class UpdateCompletedReceiver : BroadcastReceiver() {{
    override fun onReceive(context: Context, intent: Intent?) {{
        if (intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        )
        launchIntent.putExtra("kingmaker_update_completed", true)
        try {{
            context.startActivity(launchIntent)
        }} catch (ex: Exception) {{
            Log.w("KingMakerUpdate", "Unable to reopen app after update", ex)
        }}
    }}
}}
''',
    )

def patch_gradle_dependency() -> None:
    groovy = ANDROID / "app/build.gradle"
    kts = ANDROID / "app/build.gradle.kts"
    if groovy.exists():
        text = read(groovy)
        dep = '    implementation "androidx.core:core-ktx:1.13.1"'
        if "androidx.core:core-ktx" not in text:
            if "dependencies {" in text:
                text = text.replace("dependencies {", "dependencies {\n" + dep, 1)
            else:
                text += "\ndependencies {\n" + dep + "\n}\n"
            write(groovy, text)
        return
    if kts.exists():
        text = read(kts)
        dep = '    implementation("androidx.core:core-ktx:1.13.1")'
        if "androidx.core:core-ktx" not in text:
            if "dependencies {" in text:
                text = text.replace("dependencies {", "dependencies {\n" + dep, 1)
            else:
                text += "\ndependencies {\n" + dep + "\n}\n"
            write(kts, text)
        return
    raise SystemExit("No Android app Gradle file found")


patch_launcher_logo()
patch_manifest()
patch_file_paths()
patch_main_activity()
patch_update_completed_receiver()
patch_gradle_dependency()
print("Android in-app APK installer and game display patched")
