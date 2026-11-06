# Building 学术拼音 v1.3.0

Requirements: Apple Silicon Mac, Python 3.8 or newer, and Apple Command Line Tools.

Use the retained original Squirrel nightly `d220b92` installer (also available in release v1.1.0). Do not substitute a stable release. Download `wanxiang-lts-zh-hans.gram` from release v1.3.0 into `Profile/`; the builder verifies `Model.sha256`.

```sh
python3 packaging/build-installer.py \
  "$HOME/Downloads/Squirrel-nightly-2026-10-30-d220b92.pkg" \
  "$HOME/Downloads/Squirrel-Academic-v1.3.0-macOS-arm64.pkg"
```

The builder verifies the original installer, native executable, Rime engine, model and indicator hashes. It packages the complete offline model, public dictionaries, scripts and customized app. Personal phrases, learned words and ranking records are excluded. The app is verified again after unpacking the final product, including the detached signature on `rime-install`.

Installation runs dictionary deployment, mode-indicator setup and Simplified input-source registration as the signed-in desktop user. Existing private data and sync settings are preserved. Changed configuration files are saved before replacement. Existing `academic_pinyin` learning is migrated only if `zenfire_pinyin.userdb` is absent; the original database stays intact.

The package is unsigned; the included app uses a local ad hoc signature. The release notes distinguish isolated deployment tests from fresh-Mac GUI activation, which cannot be confirmed by a package build alone.
