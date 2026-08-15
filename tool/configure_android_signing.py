from pathlib import Path


def configure_kotlin(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "telegramMediaPlayerSigningConfigured" in text:
        return
    imports = """
import java.io.FileInputStream
import java.util.Properties

""".lstrip()
    properties = """
// telegramMediaPlayerSigningConfigured
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

""".lstrip()
    text = imports + text
    plugin_end = _find_plugins_block_end(text)
    if plugin_end == -1:
        text = properties + text
    else:
        text = text[:plugin_end] + "\n" + properties + text[plugin_end:]
    signing = """
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

""".rstrip()
    text = text.replace("    buildTypes {", signing + "\n    buildTypes {", 1)
    text = text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    path.write_text(text, encoding="utf-8")


def _find_plugins_block_end(text: str) -> int:
    start = text.find("plugins {")
    if start == -1:
        return -1
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    return -1


def main() -> None:
    kotlin = Path("android/app/build.gradle.kts")
    if kotlin.exists():
        configure_kotlin(kotlin)
        return
    raise SystemExit("android/app/build.gradle.kts was not found after flutter create")


if __name__ == "__main__":
    main()
