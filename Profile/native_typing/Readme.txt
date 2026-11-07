Local smart spacing for Squirrel nightly d220b92 — active

The installed app retains the same nightly revision, Rime engine, plugins,
resources and the 中 / 英 menu indicator interface. No release was downloaded.
Automatic release checking/downloading is disabled for this local build.

The menu indicator reads the current mode from the focused InputMethodKit
controller. Older windows can retain their own Rime sessions and receive
deactivation late. Only the focused controller supplies the menu-bar reply.

Controls in squirrel.custom.yaml:
  typing/smart_space: Chinese/English spacing
  typing/smart_space_digit: Chinese/number spacing
Number-aware punctuation remains in zenfire_pinyin.custom.yaml and preserves
separators in examples such as 3.14, 12:00 and 1,000.

Smart spacing inserts spaces within mixed committed text and between the
preceding character and newly typed text. Continuous typing of Chinese, English
and numbers is supported. It does not move the cursor or alter existing text
after the insertion point. Reading the preceding character depends on the
editor exposing its text-input range; unavailable ranges are left alone.
No surrounding text is logged, saved or sent online by this extension.

Bracket auto completion has been removed from the executable, configuration,
source and backup assets. Brackets follow the ordinary punctuation mappings;
the extension does not insert a closer or skip over an existing closer.
There is no cursor-control helper, synthetic key replay, timer, or Accessibility
requirement for this extension. While pinyin is pending, [ / ] retain lookup.
Existing dictionaries, local learning, ranking, symbols and shortcuts remain.

The candidate panel is initialized before settings load and lays out its text
viewport after resizing. The installer uses open -g without hiding the app.
Menu actions in the saved build have no keyboard shortcuts, so this preference
does not depend on per-account macOS overrides after reinstalling.
Focused checks cover mixed-text spacing, continuous typing, expanded editor
ranges, supplementary Chinese characters, unavailable context, preservation of
existing spaces/URLs, and ordinary single bracket insertion. Punctuation does
not trigger a surrounding-text query. The native build completes without
compiler errors or warnings.

To rebuild locally with the installed Apple Command Line Tools:
  /bin/bash "$HOME/Library/Rime/native_typing/Build.command"
Build.command uses the bundled source and headers and the matching installed
nightly frameworks. It downloads nothing, runs the focused checks, and updates
Squirrel.local and its build record only after success. It does not install.
Build.command combines the two standalone Swift files with the other nightly
sources and headers from source.zip.txt.

Source, executable and build record are included in the profile's manual backup.
To restore, install the matching nightly first and then run:
  /bin/bash "$HOME/Library/Rime/native_typing/Install.command"
The installer checks the Mac's CPU, the nightly and its engine, stages the local app,
and requests macOS administrator authentication for the system installation.
An unsuccessful file replacement restores the previous executable and signature.
It never downloads a release. The executable is for this Mac's arm64 platform.

The installer verifies the original executable in the rollback archive at
  /Library/Application Support/Squirrel Typing/Original-Squirrel.zip
Installing a different nightly requires rebuilding this extension against it.
Manual “Sync user data” remains manual.
