# Squirrel Academic Config · 学术拼音

A Simplified Chinese profile for the official **Squirrel** input method on macOS. It combines academic and everyday dictionaries, fuzzy pinyin, English candidates in Chinese mode, a seven-candidate MacGreen skin, and a clickable menu-bar indicator. Recognition and candidate ranking run on the Mac. The published files are a static configuration snapshot.

| Try it | Behavior |
|---|---|
| `hamidunl`, `mint`, `mdjz` | 哈密顿量, 明天, 密度矩阵 |
| `taisi`, `bochi` | 态矢, 驳斥. The s/sh and c/ch families stay separate. |
| `wosou` | 握手, with 🤝 behind the Chinese candidates |
| `[` / `]` | Open extended lookup using the pinyin already typed / return to the ordinary list |
| `-` / `=` | Previous / next candidate page. With no composition, `=` inserts an ordinary equals sign. |
| Tab / Shift+Tab | Move forward / backward one pinyin syllable |
| Ctrl+P / Ctrl+U | Pin an eligible highlighted word / remove its pin |
| Shift | Switch Chinese/English. During composition, commit the literal letters. |

New typing sessions start in English. The indicator shows an outlined A for English and the Squirrel badge for Chinese. Left- or right-click it for Deploy, Sync, Settings and Logs. The final menu item links to the official nightly release.

## Download and install

1. Install the official **Squirrel** input method on macOS if you do not already have it. [Official Squirrel releases](https://github.com/rime/squirrel/releases)
2. Download the **Squirrel-Academic-Config** ZIP under **Assets** on the release page and unzip it. [Download the latest release](https://github.com/xzhang17/squirrel-academic-config/releases/latest)
3. Open **Install.command**, read the installation summary and enter `y` to continue. You can also run `./Install.command` from Terminal in the unzipped folder. The installer runs as your normal Mac user. It offers the clickable indicator separately on compatible nightly builds.
4. Choose **Squirrel → Deploy** (重新部署). Switch to Chinese with Shift, then try `mdjz` for 密度矩阵.

On an existing installation the academic schema and MacGreen skin become active. The installer keeps your private phrases, learning data, sync settings and other files outside the release. It saves copies of every differing file it replaces under `~/Library/Squirrel-Academic-Previous-…`, including any dictionaries with matching filenames. An existing word-preference file is also backed up because redeployment can prune pins for words absent from the new dictionaries. The path is printed during installation. To revert, copy those files back to `~/Library/Rime` at the same relative paths and redeploy. `Added-files.txt` lists the files that were introduced. A new installation uses `~/Squirrel-Backup/sync`; an existing installation retains its sync destination.

## Manual installation or a separate staged profile

1. Install the official Squirrel input method. This profile was tested with the 2026-10-30 nightly at commit `d220b92`, whose installer SHA-256 is `7eb907e3aafb62741e4871ec63c7ba3cf25669fff9777d792a5a9f0b1aded984`. The upstream nightly link moves as new builds are released. If restoring from a personal Squirrel backup, use the matching package in its `installers` folder. [Official releases](https://github.com/rime/squirrel/releases) · [Tested revision](https://github.com/rime/squirrel/commit/d220b92ae7d0c916f4cce50df42d9a136668ea52)
2. Clone or download this repository. In Terminal, run the following from the repository root. It prints the path to a new staged profile under your Library. It preserves any active Rime profile.

   ```sh
   /bin/bash ./Prepare-profile.command
   ```

3. With Squirrel stopped, move the staged folder to `~/Library/Rime`. Keep an existing Rime folder separately so you can revert or recover your own phrases and preferences. If Squirrel is your only keyboard, you can have an administrator swap the folders while you are signed out. Enable **Squirrel – Simplified** in System Settings → Keyboard → Text Input, select it and choose **Deploy**.
4. To use the SVG indicator, run the following from the repository root. It installs the helper for the signed-in user, sets it to start at login, and hides Squirrel’s built-in text label. If the separate Apple Input menu is also visible, its setting is under Keyboard → Text Input → Edit.

   ```sh
   /bin/bash ./Mode-Indicator/Restore.command
   ```

5. Select **Sync user data** in the indicator or Squirrel menu. The staged profile configures a fresh device ID and a local sync destination under `~/Squirrel-Backup/sync`. Keep the `Mode-Indicator` folder alongside `sync` for an offline indicator restore. If your backup already contains it, keep that verified copy.

## What is shared

The `Profile` directory contains the academic and daily dictionaries, the two additional personal term lists approved for sharing, the shared shortcuts, fuzzy-pinyin and ranking rules, and the skin. The large Ice dictionaries are used by extended lookup. `Mode-Indicator` contains the helper app ZIP, checksums, SVGs, source, and restore command. Third-party data notices are under `notices`.

**Private reference shortcuts and learned preferences stay local.** Preparing a profile creates an empty `custom_phrase.txt` and `academic_preferences.txt`. Sync data, logs, device IDs, and compiled caches are excluded from Git. A personal Squirrel backup can restore private entries that this public profile omits.

## Edit and back up

Edit the plain dictionary or shortcut files, then redeploy. After editing nested resources under `~/Library/Rime`, refresh the archive used by Squirrel’s native backup, then select **Sync user data**.

```sh
/bin/bash "$HOME/Library/Rime/academic_profile.txt" prepare
```

Squirrel Sync writes to your local backup. To publish later changes, copy just the intended shareable files to a clone of this repository, review the Git diff, commit, and push.
