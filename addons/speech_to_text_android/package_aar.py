#!/usr/bin/env python3
"""Pack the already-compiled SpeechToText classes into debug and release AARs.

Gradle's extract*Annotations task downloads lint jars from dl.google.com, which
has been returning HTTP 502. The Kotlin compile already succeeded, so this
builds the AAR zip Godot's export plugin expects.
"""
import os
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PLUGIN = ROOT / "android" / "plugin"
CLASSES = PLUGIN / "build" / "tmp" / "kotlin-classes" / "debug"
MANIFEST = PLUGIN / "src" / "main" / "AndroidManifest.xml"
BIN = ROOT / "bin"
SDK = Path.home() / "Library" / "Android" / "sdk"
AAPT2 = SDK / "build-tools" / "35.0.1" / "aapt2"
ANDROID_JAR = SDK / "platforms" / "android-35" / "android.jar"


def main() -> None:
    class_file = CLASSES / "com" / "loquiquest" / "speechtotext" / "SpeechToTextPlugin.class"
    if not class_file.is_file():
        raise SystemExit(f"Missing compiled plugin class: {class_file}")
    if not AAPT2.is_file():
        raise SystemExit(f"Missing aapt2: {AAPT2}")

    work = ROOT / "android" / "aar-pack"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    static_lib = work / "static.apk"
    subprocess.run(
        [
            str(AAPT2),
            "link",
            "--static-lib",
            "-I",
            str(ANDROID_JAR),
            "--manifest",
            str(MANIFEST),
            "-o",
            str(static_lib),
            "--min-sdk-version",
            "24",
            "--target-sdk-version",
            "35",
        ],
        check=True,
    )
    unpacked = work / "unpacked"
    unpacked.mkdir()
    with zipfile.ZipFile(static_lib) as zf:
        zf.extractall(unpacked)

    classes_jar = work / "classes.jar"
    with zipfile.ZipFile(classes_jar, "w") as jar:
        for path in CLASSES.rglob("*"):
            if path.is_file():
                jar.write(path, path.relative_to(CLASSES).as_posix())

    meta = work / "META-INF" / "com" / "android" / "build" / "gradle"
    meta.mkdir(parents=True)
    (meta / "aar-metadata.properties").write_text(
        "\n".join(
            [
                "aarFormatVersion=1.0",
                "aarMetadataVersion=1.0",
                "minCompileSdk=35",
                "minCompileSdkExtension=0",
                "minAndroidGradlePluginVersion=8.0.0",
                "coreLibraryDesugaringEnabled=false",
                "stableAidl=false",
                "",
            ]
        )
    )

    BIN.mkdir(parents=True, exist_ok=True)
    for name in ("SpeechToText-debug.aar", "SpeechToText-release.aar"):
        out = BIN / name
        if out.exists():
            out.unlink()
        with zipfile.ZipFile(out, "w") as aar:
            manifest = unpacked / "AndroidManifest.xml"
            aar.write(manifest, "AndroidManifest.xml")
            r_txt = unpacked / "R.txt"
            if r_txt.is_file():
                aar.write(r_txt, "R.txt")
            aar.write(classes_jar, "classes.jar")
            aar.write(meta / "aar-metadata.properties", "META-INF/com/android/build/gradle/aar-metadata.properties")
        print(f"Wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
