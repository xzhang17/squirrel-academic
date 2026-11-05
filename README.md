# Squirrel Academic Config · 学术拼音

A Simplified Chinese profile and locally customized **Squirrel nightly d220b92** for macOS. This snapshot includes the current dictionaries, Lua scripts, configuration, smart-spacing source and executable, and the clickable Chinese/English menu-bar indicator.

The custom executable is **arm64 (Apple silicon), macOS 13 or later**, with local extension version **1.2** and Rime **1.17.0**. It retains the special nightly's mode-notification interface used by the indicator. It was built locally; no stable release was substituted.

## Current behavior

| Input or feature | Behavior |
|---|---|
| `hamidunl`, `mint`, `mdjz` | 哈密顿量, 明天, 密度矩阵 |
| Local Chinese learning | Learns Chinese phrases up to eight characters. A deliberate choice promotes a phrase to second place, then first after another deliberate choice. |
| Smart spacing | Adds spaces at supported Chinese/English and Chinese/number boundaries. |
| Number punctuation | Keeps ASCII separators in values such as `3.14`, `12:00`, and `1,000`. |
| `[` / `]` during composition | Open extended lookup / return to the ordinary candidate list. |
| `-` / `=` during composition | Previous / next seven-candidate page. |
| Shift alone | Switch Chinese/English; new typing sessions start in English. |
| Tab | Move forward one pinyin syllable. |
| Chinese-mode punctuation | `[` and `]` insert 【 and 】; shifted `{`, `}`, and `|` insert those ASCII symbols directly. |
| `riqi`, `xinqi`, `alpha`, `du` | Current date, weekday, Greek-letter and degree-symbol suggestions. |

Full-width mode and special modifier-key shortcuts are disabled. Brackets insert individually; automatic bracket completion is absent. Smart spacing does not move the cursor or require Accessibility. It uses text context exposed by the editor and leaves unavailable context alone. English candidates keep their existing ranking rules.

The optional indicator shows an outlined A for English and a Squirrel badge for Chinese. Either mouse button opens its configuration menu. The candidate window remains a single row with ordinary paging.

## Release downloads

The `v1.1.1` profile keeps one ordinary space between the number and the candidate and uses a thin space before an optional annotation. [Download v1.1.1](https://github.com/xzhang17/squirrel-academic-config/releases/tag/v1.1.1)

- The profile ZIP contains the dictionaries, scripts, local executable, rebuild source, profile installer and mode indicator. [Download the profile](https://github.com/xzhang17/squirrel-academic-config/releases/download/v1.1.1/Squirrel-Academic-Config-v1.1.1-macOS.zip)
- The custom app ZIP contains the installed arm64 nightly with its matching engine, plugins and resources. [Download the custom app](https://github.com/xzhang17/squirrel-academic-config/releases/download/v1.1.0/Squirrel-Custom-d220b92-smart-spacing-1.2-arm64.zip)
- Use the original d220b92 installer for a fresh installation. [Download the matching nightly installer](https://github.com/xzhang17/squirrel-academic-config/releases/download/v1.1.0/Squirrel-nightly-2026-10-30-d220b92.pkg)
- Checksums are available for each download. [Profile checksum](https://github.com/xzhang17/squirrel-academic-config/releases/download/v1.1.1/SHA256SUMS) · [App and installer checksums](https://github.com/xzhang17/squirrel-academic-config/releases/download/v1.1.0/SHA256SUMS)

The full app ZIP is an offline copy of the customized bundle. The installation steps below use the matching original installer plus the saved customization, so no replacement nightly needs to be downloaded. Upstream background release checking is disabled in the custom build.

## Install or restore the customized setup

1. On a Mac without the matching nightly, install the included `Squirrel-nightly-2026-10-30-d220b92.pkg` with macOS administrator authorization. The upstream nightly link moves; use this saved package for the build in this release.
2. Unzip **Squirrel-Academic-Config-v1.1.1-macOS.zip**, open **Install.command**, and enter `y` to install the profile for your account. It offers the menu-bar indicator separately. Existing private phrases, learned data and sync settings are preserved; differing managed files are copied to a `~/Library/Squirrel-Academic-Previous-…` folder.
3. Apply the saved custom executable to the matching installed nightly:

   ```sh
   /bin/bash "$HOME/Library/Rime/native_typing/Install.command"
   ```

   Complete the macOS administrator prompt. The script checks the nightly and engine, installs the saved executable, verifies the bundle, and restarts Squirrel. It downloads nothing. Python 3 and Apple's command-line tools are needed for this script; rebuilding additionally needs the Swift compiler.
4. Choose **Squirrel – Simplified** in macOS input settings and **Deploy** in Squirrel's menu. New sessions start in English; tap Shift for Chinese. Try `mdjz`, mixed Chinese/English text, and ordinary bracket insertion.
5. If the indicator was not installed in step 2, run `Mode-Indicator/Restore.command` from the unzipped release. Either mouse button opens its menu.

The untouched original app is retained locally at `/Library/Application Support/Squirrel Typing/Original-Squirrel.zip`. A different Squirrel nightly requires rebuilding the customization against matching sources and libraries.

## Prepare a separate profile

To stage a fresh profile without changing an active input method:

```sh
/bin/bash ./Prepare-profile.command
```

The command prints a new `Rime-restored.…` directory under your Library. With Squirrel stopped, keep any existing `~/Library/Rime` separately and move the staged profile into its place. The staged profile has a fresh device ID and a manual sync destination under `~/Squirrel-Backup/sync`. Installing a profile alone does not modify the Squirrel app; use the custom installation step above for smart spacing.

## What is shared

`Profile` contains the academic, everyday and approved personal term dictionaries, shared shortcuts, current Lua modules, configuration, and `native_typing` source/executable. `Mode-Indicator` contains its app archive, SVG artwork, source and restore helper. Third-party notices remain under `notices` and in the source archive.

**Private reference phrases and learned typing data are excluded from this public repository and its release downloads.** Profile preparation creates empty `custom_phrase.txt` and `academic_preferences.txt` files. Live user databases, exported learning records, account/device identifiers, sync settings, logs and compiled profile caches are excluded. Restore personal learning from your separate private backup.

## Edit, rebuild and back up manually

After changing profile configuration or dictionaries, choose **Deploy**. After changing nested resources, prepare the archive before selecting **Sync user data**:

```sh
/bin/bash "$HOME/Library/Rime/academic_profile.txt" prepare
```

To rebuild the local executable from the retained source against the installed matching nightly:

```sh
/bin/bash "$HOME/Library/Rime/native_typing/Build.command"
```

The build command runs its spacing checks and updates the saved executable only after success. It does not install. Backups and future GitHub updates remain manual.
