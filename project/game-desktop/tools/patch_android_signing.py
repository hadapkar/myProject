from pathlib import Path
import re

ROOT = Path.cwd()
ANDROID = ROOT / "android"
KEY_PROPERTIES = ANDROID / "key.properties"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def matching_brace(text: str, open_index: int) -> int:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    raise SystemExit("Failed to find matching Gradle block brace")


def insert_after_plugins(text: str, snippet: str) -> str:
    match = re.search(r"plugins\s*\{", text)
    if not match:
        return snippet + text
    end = matching_brace(text, text.find("{", match.start()))
    return text[: end + 1] + "\n\n" + snippet + text[end + 1 :]


def insert_in_android_block(text: str, snippet: str) -> str:
    match = re.search(r"\nandroid\s*\{", text)
    if not match:
        match = re.search(r"^android\s*\{", text)
    if not match:
        raise SystemExit("android Gradle block not found")
    open_index = text.find("{", match.start())
    return text[: open_index + 1] + "\n" + snippet + text[open_index + 1 :]


def patch_kts(path: Path) -> None:
    text = read(path)
    if "val keystoreProperties =" in text and "signingConfigs.getByName(\"release\")" in text:
        print("Android release signing already configured")
        return

    imports = "import java.io.FileInputStream\nimport java.util.Properties\n\n"
    if "import java.util.Properties" not in text:
        text = imports + text
    elif "import java.io.FileInputStream" not in text:
        text = "import java.io.FileInputStream\n" + text

    props = (
        'val keystoreProperties = Properties()\n'
        'val keystorePropertiesFile = rootProject.file("key.properties")\n'
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    if "val keystoreProperties =" not in text:
        android_match = re.search(r"\nandroid\s*\{", text)
        if not android_match:
            android_match = re.search(r"^android\s*\{", text)
        if not android_match:
            raise SystemExit("android Gradle block not found")
        text = text[: android_match.start()] + "\n" + props + text[android_match.start() :]

    signing = (
        '    signingConfigs {\n'
        '        create("release") {\n'
        '            keyAlias = keystoreProperties["keyAlias"] as String\n'
        '            keyPassword = keystoreProperties["keyPassword"] as String\n'
        '            storeFile = file(keystoreProperties["storeFile"] as String)\n'
        '            storePassword = keystoreProperties["storePassword"] as String\n'
        "        }\n"
        "    }\n"
    )
    if "create(\"release\")" not in text:
        text = insert_in_android_block(text, signing)

    release_line = 'signingConfig = signingConfigs.getByName("release")'
    text = text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        release_line,
    )
    if release_line not in text:
        text, count = re.subn(
            r"(release\s*\{\s*)",
            r'\1\n            signingConfig = signingConfigs.getByName("release")\n',
            text,
            count=1,
        )
        if count != 1:
            raise SystemExit("release buildType block not found")

    write(path, text)
    print("Android Kotlin Gradle release signing configured")


def patch_groovy(path: Path) -> None:
    text = read(path)
    if "def keystoreProperties =" in text and "signingConfigs.release" in text:
        print("Android release signing already configured")
        return

    props = (
        "def keystoreProperties = new java.util.Properties()\n"
        "def keystorePropertiesFile = rootProject.file('key.properties')\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(new java.io.FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    if "def keystoreProperties =" not in text:
        text = insert_after_plugins(text, props)

    signing = (
        "    signingConfigs {\n"
        "        release {\n"
        "            keyAlias keystoreProperties['keyAlias']\n"
        "            keyPassword keystoreProperties['keyPassword']\n"
        "            storeFile file(keystoreProperties['storeFile'])\n"
        "            storePassword keystoreProperties['storePassword']\n"
        "        }\n"
        "    }\n"
    )
    if "signingConfigs {" not in text:
        text = insert_in_android_block(text, signing)

    text = text.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    text = text.replace("signingConfig = signingConfigs.debug", "signingConfig signingConfigs.release")
    if "signingConfig signingConfigs.release" not in text:
        text, count = re.subn(
            r"(release\s*\{\s*)",
            r"\1\n            signingConfig signingConfigs.release\n",
            text,
            count=1,
        )
        if count != 1:
            raise SystemExit("release buildType block not found")

    write(path, text)
    print("Android Groovy Gradle release signing configured")


if not KEY_PROPERTIES.exists():
    raise SystemExit(f"Signing properties not found: {KEY_PROPERTIES}")

kts = ANDROID / "app/build.gradle.kts"
groovy = ANDROID / "app/build.gradle"

if kts.exists():
    patch_kts(kts)
elif groovy.exists():
    patch_groovy(groovy)
else:
    raise SystemExit("No Android app Gradle file found")
