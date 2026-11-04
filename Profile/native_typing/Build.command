#!/bin/bash
# Rebuild the matching local nightly without downloads or installation.
set -euo pipefail
cd -- "$(dirname -- "$0")"
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile
import hashlib, json, os, plistlib, shutil, subprocess, tempfile

assets = Path.cwd()
app = Path('/Library/Input Methods/Squirrel.app')
base = json.loads((assets/'nightly-base.txt').read_text())
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'im.rime.inputmethod.Squirrel'
assert info['CFBundleVersion'] == base['bundle_version'], 'A different Squirrel nightly is installed.'
assert info.get('AcademicTypingBase') == base['revision'] or hashlib.sha256((app/'Contents/MacOS/Squirrel').read_bytes()).hexdigest() == base['original_sha256'], 'The installed nightly does not match this source.'
frameworks = app/'Contents/Frameworks'
assert hashlib.sha256((frameworks/'librime.1.dylib').read_bytes()).hexdigest() == base['librime_sha256'], 'The Rime engine has changed.'

with tempfile.TemporaryDirectory(prefix='squirrel-local-build-', dir='/private/tmp') as folder:
    work = Path(folder)
    with ZipFile(assets/'source.zip.txt') as archive:
        for name in archive.namelist():
            path = Path(name)
            assert not path.is_absolute() and '..' not in path.parts, 'Invalid source archive path.'
        archive.extractall(work)
    for name in ['TextInsertion.swift', 'IMKTypingClient.swift']:
        shutil.copy2(assets/name, work/'sources'/name)

    sparkle = work/'Frameworks/Sparkle.framework'
    shutil.copytree(frameworks/'Sparkle.framework', sparkle, symlinks=True)
    version = sparkle/'Versions/Current'
    headers, modules = version/'Headers', version/'Modules'
    headers.mkdir(exist_ok=True)
    modules.mkdir(exist_ok=True)
    for header in (work/'SparkleHeaders').glob('*.h'):
        shutil.copy2(header, headers/header.name)
    (modules/'module.modulemap').write_text('framework module Sparkle {\n umbrella header "Sparkle.h"\n export *\n module * { export * }\n}\n')
    for name in ['Headers', 'Modules']:
        if not (sparkle/name).exists():
            (sparkle/name).symlink_to('Versions/Current/'+name)

    compiler = Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip())
    sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
    common = ['xcrun', 'swiftc', '-target', 'arm64-apple-macos13.0', '-module-cache-path', str(work/'module-cache')]
    # This CLT version duplicates Swift's module map in its SDK. Hide only the
    # duplicate compiler-side map for this build; never edit the developer tools.
    duplicate = compiler.parent.parent/'include/swift/module.modulemap'
    if duplicate.exists():
        empty = work/'empty.modulemap'
        empty.write_text('')
        overlay = work/'compiler-overlay.json'
        overlay.write_text(json.dumps({'version': 0, 'roots': [
            {'type': 'file', 'name': str(duplicate), 'external-contents': str(empty)}]}))
        common += ['-vfsoverlay', str(overlay)]

    tests = common + [str(work/'sources'/name) for name in ['TextInsertion.swift', 'IMKTypingClient.swift']]
    subprocess.run(tests + [str(work/'tests/SpacingTests.swift'), '-o', str(work/'spacing-tests')], check=True)
    subprocess.run([str(work/'spacing-tests')], check=True)
    command = common + ['-O', '-whole-module-optimization', '-swift-version', '5',
        '-enable-bare-slash-regex', '-module-name', 'Squirrel', '-I', str(work/'headers'),
        '-Xcc', '-I'+str(sdk/'System/Library/Frameworks/Tk.framework/Headers'),
        '-import-objc-header', str(work/'sources/Squirrel-Bridging-Header.h'),
        '-F', str(work/'Frameworks'), '-L', str(frameworks), '-lrime.1', '-framework', 'Sparkle',
        '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks']
    command += [str(p) for p in sorted((work/'sources').glob('*.swift'))]
    subprocess.run(command + ['-o', str(work/'Squirrel')], check=True)
    base['modified_sha256'] = hashlib.sha256((work/'Squirrel').read_bytes()).hexdigest()
    # Publish only after both the focused tests and the full build pass.
    shutil.copy2(work/'Squirrel', assets/'Squirrel.local.new')
    os.replace(assets/'Squirrel.local.new', assets/'Squirrel.local')
    (assets/'nightly-base.txt.new').write_text(json.dumps(base, indent=2)+'\n')
    os.replace(assets/'nightly-base.txt.new', assets/'nightly-base.txt')
print('Built and checked local nightly '+base['revision']+'. Run Install.command to apply it.')
PY
