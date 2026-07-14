from pathlib import Path
import re

APP_ID = "com.kingmaker.admin"
UPDATE_CHANNEL = "kingmaker/android_update"
GAME_DISPLAY_CHANNEL = "kingmaker/game_display"

ROOT = Path.cwd()
ANDROID = ROOT / "android"
MANIFEST = ANDROID / "app/src/main/AndroidManifest.xml"


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

    write(MANIFEST, text)


def patch_file_paths() -> None:
    write(
        ANDROID / "app/src/main/res/xml/kingmaker_file_paths.xml",
        '''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="updates" path="updates/" />
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

import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Build
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
                    val updateDir = File(cacheDir, "updates")
                    updateDir.mkdirs()
                    result.success(File(updateDir, "KingMaker.apk").absolutePath)
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


patch_manifest()
patch_file_paths()
patch_main_activity()
patch_gradle_dependency()
print("Android in-app APK installer and game display patched")
