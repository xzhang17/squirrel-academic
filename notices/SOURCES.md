# Dictionary and artwork sources

The public product name is 学术拼音; the profile's internal ID remains `zenfire_pinyin`. Dictionaries and custom code are shared without the author's private phrases or learned data.

Academic subject terminology, selected scientist names and mixed Chinese/Latin vocabulary retain detailed attributions in [Profile/dicts/academic_dicts/Sources.txt](../Profile/dicts/academic_dicts/Sources.txt).

The generated `zenfire_chars` table combines existing Ice readings with character-frequency scores from [Rime Frost, gaboolic and contributors, commit 3ba4f1d](https://github.com/gaboolic/rime-frost/tree/3ba4f1df224823079b947ce1553441c36097b124). Upstream notices remain with the dictionaries. This profile does not replace its complete word dictionary or schema with Frost.

The unmodified `wanxiang-lts-zh-hans.gram` is from [Wanxiang LTS, amzxyz and contributors](https://github.com/amzxyz/rime-wanxiang-data/releases/tag/LTS), SHA-256 `e34500ab44626dc039a0641792ecba98ab63307646eb3d29186be56608ffe094`. The upstream data license is CC BY 4.0, included as Wanxiang-LICENSE. This binary is included inside the installer, rather than Git history or a separate release attachment. No Wanxiang training code is redistributed, and no personal model training is claimed.

The four optional Mint skins and selected name-source entries are adapted from [Mintimate/oh-my-rime, commit cb4f7dd](https://github.com/Mintimate/oh-my-rime/tree/cb4f7dda2fb74332cda0a7712ffc89ea5ded856f). MacGreen remains selected.

The profile includes adapted Rime Ice dictionaries from iDvel. Their file headers retain the dictionary sources and credits. The Ice license is included here and in the profile. [Rime Ice](https://github.com/iDvel/rime-ice)

The Chinese ranking tables adapt published word and character frequencies from Qing Cai and Marc Brysbaert, *SUBTLEX-CH: Chinese Word and Character Frequencies Based on Film Subtitles* (2010). The profile uses these counts to adjust the weights of existing dictionary readings. [Paper](https://doi.org/10.1371/journal.pone.0010729) · [Frequency tables](https://doi.org/10.1371/journal.pone.0010729.s002)

The English-word evidence uses SCOWL 2020.12.07. Its copyright and permission notices are in SCOWL-Copyright.txt and the generated evidence file. [SCOWL](https://wordlist.aspell.net/)

Emoji names and keywords use Unicode CLDR 46 Simplified Chinese data and Unicode Emoji 17.0. Unicode-LICENSE.txt contains the license. [CLDR](https://github.com/unicode-org/cldr/tree/release-46/common/annotations) · [Emoji data](https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt)

The Chinese menu-bar badge uses the Squirrel logo. The English badge is an outlined A. The indicator source and its SVG files accompany the app archive. [Squirrel](https://github.com/rime/squirrel)

## Customized native app

The custom frontend is based on Squirrel nightly commit [d220b92ae7d0c916f4cce50df42d9a136668ea52](https://github.com/rime/squirrel/commit/d220b92ae7d0c916f4cce50df42d9a136668ea52), with Rime 1.17.0. Its retained source, headers, spacing tests, Squirrel license and Sparkle license are in `Profile/native_typing/source.zip.txt` (a ZIP archive). The standalone Swift files in `native_typing` replace their archived copies during builds. `Build.command`, `Install.command`, and `nightly-base.txt` describe the local build and matching components. The release preserves the original installer and a copy of the customized app bundle.
