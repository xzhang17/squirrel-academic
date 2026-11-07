#!/usr/bin/env python3
"""Build the macOS installer from the retained original nightly and the public profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
from tempfile import TemporaryDirectory

PACKAGE_ID = "com.github.xzhang17.squirrel-academic"
VERSION = "1.3.1"
NIGHTLY_PKG_SHA256 = "7eb907e3aafb62741e4871ec63c7ba3cf25669fff9777d792a5a9f0b1aded984"
HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def copy_public_setup(setup):
    source = REPO / "Profile"
    manifest = (source / "zenfire_profile_files.txt").read_text().splitlines()
    private = {"zenfire_preferences.txt", "custom_phrase.txt"}
    files = [line for line in manifest if line and not line.startswith("#") and line not in private]
    files += ["zenfire_profile.txt", "zenfire_profile_files.txt"]
    for name in files:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or (source / path).is_symlink():
            raise ValueError(f"Unexpected profile path: {name}")
        dest = setup / "Profile" / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / path, dest)
    for name in ["Install.command", "Prepare-profile.command", "Model.sha256", "README.md"]:
        shutil.copy2(REPO / name, setup / name)
    indicator = setup / "Mode-Indicator"
    indicator.mkdir()
    for name in ["Chinese.svg", "English.svg", "SHA256SUMS", "Squirrel Mode Indicator.zip", "Restore.command"]:
        shutil.copy2(REPO / "Mode-Indicator" / name, indicator / name)
    subprocess.run(["/usr/bin/shasum", "-a", "256", "-c", "SHA256SUMS"], cwd=indicator, check=True)
    shutil.copytree(REPO / "notices", setup / "notices")
    shutil.copy2(HERE / "install-user.sh", setup / "install-user.sh")


def stage_custom_app(nightly, work, payload):
    if hashlib.sha256(nightly.read_bytes()).hexdigest() != NIGHTLY_PKG_SHA256:
        raise ValueError("Use the d220b92 original nightly package from GitHub release v1.1.0.")
    expanded = work / "nightly"
    subprocess.run(["/usr/sbin/pkgutil", "--expand-full", nightly, expanded], check=True)
    original = expanded / "Squirrel-component.pkg/Payload/Squirrel.app"
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", original], check=True)
    assets = REPO / "Profile/native_typing"
    base = json.loads((assets / "nightly-base.txt").read_text())
    app = payload / "Library/Input Methods/Squirrel.app"
    app.parent.mkdir(parents=True)
    # ditto preserves the upstream script's detached signature attributes.
    subprocess.run(["/usr/bin/ditto", original, app], check=True)
    executable = app / "Contents/MacOS/Squirrel"
    engine = app / "Contents/Frameworks/librime.1.dylib"
    saved = assets / "Squirrel.local"
    for file, expected in [(executable, base["original_sha256"]), (engine, base["librime_sha256"]),
                           (saved, base["modified_sha256"])]:
        if hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Build record mismatch: {file.name}")
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if info["CFBundleIdentifier"] != "im.rime.inputmethod.Squirrel" or info["CFBundleVersion"] != base["bundle_version"]:
        raise ValueError("The app differs from the retained nightly.")
    shutil.copyfile(saved, executable)
    info.update(AcademicTypingBase=base["revision"], AcademicTypingVersion="1.2",
                AcademicTypingFeatures=["smart_space", "smart_space_digit"],
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
                    "--entitlements", assets / "entitlements.txt", app], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], check=True)
    return executable


def build(nightly, output):
    os.umask(0o022)
    model = REPO / "Profile/wanxiang-lts-zh-hans.gram"
    expected = (REPO / "Model.sha256").read_text().split()[0]
    digest = hashlib.sha256()
    with model.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError("The Wanxiang model differs from Model.sha256.")
    with TemporaryDirectory(dir=output.parent, prefix=".squirrel-package-") as folder:
        work = Path(folder)
        payload = work / "payload"
        staged_executable = stage_custom_app(nightly, work, payload)
        setup = payload / "Library/Application Support/Squirrel Academic/Setup"
        setup.mkdir(parents=True)
        copy_public_setup(setup)
        subprocess.run(["/usr/bin/xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=13.0",
                        "-Wall", "-Wextra", "-Werror", HERE / "is-simplified-selected.c",
                        "-framework", "Carbon", "-framework", "CoreFoundation",
                        "-o", setup / "is-simplified-selected"], check=True)
        # Install at the system input-method path even if another copy exists on a mounted disk.
        components = work / "components.plist"
        components.write_bytes(plistlib.dumps([{
            "RootRelativeBundlePath": "Library/Input Methods/Squirrel.app",
            "BundleIsRelocatable": False, "BundleIsVersionChecked": False,
            "BundleHasStrictIdentifier": True, "BundleOverwriteAction": "upgrade",
        }]))
        subprocess.run(["/usr/bin/pkgbuild", "--root", payload, "--component-plist", components,
                        "--scripts", HERE / "scripts", "--ownership", "recommended",
                        "--identifier", PACKAGE_ID, "--version", VERSION, "--install-location", "/",
                        work / "SquirrelAcademic-component.pkg"], check=True)
        product = work / "product.pkg"
        subprocess.run(["/usr/bin/productbuild", "--distribution", HERE / "distribution.xml",
                        "--resources", HERE / "resources", "--package-path", work, product], check=True)
        # Validate the packaged copy too. An archive can lose the signature
        # attributes on rime-install even when the source app verifies.
        checked = work / "verified"
        subprocess.run(["/usr/sbin/pkgutil", "--expand-full", product, checked], check=True)
        installed = checked / "SquirrelAcademic-component.pkg/Payload/Library/Input Methods/Squirrel.app"
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", installed], check=True)
        if (installed / "Contents/MacOS/Squirrel").read_bytes() != staged_executable.read_bytes():
            raise ValueError("Packaged Squirrel executable differs from the verified native build.")
        os.replace(product, output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("nightly_pkg", type=Path)
    parser.add_argument("output_pkg", type=Path)
    args = parser.parse_args()
    build(args.nightly_pkg.resolve(), args.output_pkg.resolve())
