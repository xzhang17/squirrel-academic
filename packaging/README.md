# Building the macOS installer

On a build Mac with Python 3 and the Apple Command Line Tools, use the original nightly package from the v1.1.0 release. The script verifies its checksum, adds the saved smart-spacing executable, and builds the macOS installer.

```sh
python3 packaging/build-installer.py \
  "$HOME/Downloads/Squirrel-nightly-2026-10-30-d220b92.pkg" \
  "$HOME/Downloads/Squirrel-Academic-v1.2.0-macOS-arm64.pkg"
```

The build checks the original installer, native executable, Rime engine and indicator hashes. It verifies the app’s signature again after unpacking the final product so the detached signature on the rime-install script is covered. The installer sets up the signed-in account using the existing profile installer. It runs account setup, dictionary deployment, menu indicator installation and Simplified input-source registration with that user’s identity.

The distributed v1.2.0 prerelease is unsigned. The included app uses a local ad hoc signature. The release notes describe first-open approval and the possible first-login activation step.
