# 学术拼音

面向日常中文与科研写作的 macOS 鼠须管定制版。采用 Zenfire 拼音方案、雾凇词库、精选白霜字频及万象句子模型，保留模糊拼音、稳定的个人学习排序和 MacGreen 候选窗。

**[下载安装包 v1.3.0](https://github.com/xzhang17/squirrel-academic-config/releases/download/v1.3.0/Squirrel-Academic-v1.3.0-macOS-arm64.pkg)** · [发布说明与校验值](https://github.com/xzhang17/squirrel-academic-config/releases/tag/v1.3.0)

支持 **Apple Silicon（M 系列）、macOS 13 及以上**。安装包包含定制鼠须管 nightly `d220b92`、全部词典、脚本、万象模型及中英文菜单栏指示器，无需另装稳定版或逐个下载组件。Intel Mac 暂无安装包。

## 核心功能

- **日常与学术词汇兼顾。** 保留雾凇中文基础词库，采用经过本方案测试的白霜字频调整；学科词库可独立开关。科学家使用常见教材简称。
- **模糊拼音与定向读音兼容。** 支持 `z/zh`、`c/ch`、`s/sh`、`an/ang`、`en/eng`、`in/ing`、`on/ong`，以及 `geiyu → 给予` 等词级别兼容读音。
- **中英混合词直接输入。** `duolaameng` 或模糊拼音 `duolaamen` 可候选“哆啦A梦”；`deutschsuanfa` 可候选“Deutsch算法”。中文部分支持模糊拼音，Latin 部分保持精确拼写；普通中文优先。
- **本地句子模型。** 内置 Wanxiang LTS 简体模型，参与长输入的组句。模型为固定的本地文件，不联网补全，也不根据输入自动重训练；短词的个人排序另由学习层控制。
- **更稳定的学习排序。** 自动学习最多 8 个汉字的词。首次手动选词获得一次后续输入的第二位展示机会；完成该轮输入后回到按使用频率排序。此后的选择逐步累计，领先者需要被明显超过才换位，减少“哪里／那里”来回跳首位。固定短语优先，英文和中英混合词不使用这套中文频率规则。
- **中英数字智能空格。** 在编辑器提供足够上下文时，在中文与英文、数字之间补空格；数字内的小数点、时间及分组分隔符保持 ASCII。内置于定制 app，无需辅助功能光标控制。
- **常用符号快捷候选。** `riqi`、`xinqi`、`meiyuan`、`alpha`、`du` 等提供日期、星期、货币、希腊字母或单位候选；仍可按数字选词。
- **简洁候选窗与输入控制。** 默认 MacGreen 单行候选窗，附带四款可选 Mint 皮肤；Shift 单独切换中英文，`-` / `=` 翻页。拼音组合中用 `[` 进入扩展词库，`]` 返回。新会话默认英文。

全角模式、修饰键组合快捷键和括号自动补全均关闭。空闲中文输入时，`[` / `]` / `\` 输出 `【` / `】` / `、`，而 `{` / `}` / `|` 直接输出 ASCII 符号。`$` 提供 `￥`、`$`、`€`，`*` 提供 `*`、`×`。

## 安装与升级

1. 下载上方 `.pkg`，双击后按 macOS 安装向导继续。安装目标是当前登录的桌面账户。
2. 在输入菜单选择 **Squirrel – Simplified**，按 Shift 切到中文。方案显示名为 **学术拼音**；内部标识保留 `zenfire_pinyin`，避免再次更名影响学习数据。
3. 如果首次安装后输入法尚未出现，注销并重新登录，再到“系统设置 → 键盘 → 文本输入 → 编辑”添加 Squirrel – Simplified。

安装包未经过 Apple Developer ID 签名或公证；macOS 可能要求在“隐私与安全性”中允许打开。安装器会编译词典，最后一步可能稍候片刻。此版通过了打包、签名完整性和隔离配置部署检查；全新 Mac 的首次登录激活仍可能需要上述手动一步。

已有定制 `d220b92` nightly 可以直接升级。安装器保留私人短语、学习数据库和同步设置；被替换的配置文件保存到 `~/Library/Squirrel-Academic-Previous-…`。旧 `academic_pinyin` 学习数据库在没有新版数据库时迁移到 `zenfire_pinyin`，原数据库保留。其他版本的鼠须管不会被此安装器直接覆盖。

## 按需选择学科

全部学科文件都随安装包提供，默认仅启用下表中的第一组。

| 默认状态 | 学科 |
| --- | --- |
| 启用 | 物理、数学、力学、科研与写作 |
| 未启用 | 生物、化学、计算机科学、工程、地质、历史、力学扩展 |

编辑 `~/Library/Rime/dicts/academic_dicts/subjects.yaml` 中的 `true` / `false`，然后运行：

```sh
/usr/bin/ruby "$HOME/Library/Rime/dicts/rebuild_academic.rb"
```

随后在鼠须管菜单选择“重新部署”。中文学术词与对应的 `*_mixed.dict.yaml` 会一起启用，普通中文优先规则保持不变。

## 个人数据与手动备份

这个公开仓库和安装包包含共享词典、配置、脚本及定制 app，**不包含作者的私人短语、输入历史、学习频率、候选偏好、设备标识或 Dropbox 路径**。`personal_terms` 和 `word_shortcuts` 是公开的精选词汇，不是学习记录。

安装后，个人学习保存在本机 `zenfire_pinyin.userdb` 和 `zenfire_preferences.txt`。默认手动同步位置为 `~/Squirrel-Backup/sync`，每台 Mac 使用新设备标识；升级保留已有同步位置。可自行将同步位置设为 Dropbox 等受信任目录。没有自动备份计划。

更新词典或脚本后，先刷新资源归档：

```sh
/bin/bash "$HOME/Library/Rime/zenfire_profile.txt" prepare
```

然后在鼠须管菜单选择 **Sync user data／同步用户资料**。同步包含词典、配置、脚本、原生学习频率及自定义候选排序。新 Mac 的安装包是干净起点；要带回自己的学习数据，再按 `Squirrel-Recovery.txt` 恢复私人同步备份。

## 仓库结构与源码安装

| 路径 | 内容 |
| --- | --- |
| `Profile/` | 可发布的 Rime 配置模板 |
| `Profile/dicts/academic_dicts/` | 按学科划分的中文和混合词典 |
| `Profile/dicts/cn_dicts/`、`en_dicts/` | 普通中文、英文和扩展词库 |
| `Profile/lua/` | 学习排序、混合输入、扩展查询和符号候选 |
| `Profile/native_typing/` | 智能空格定制的源码、构建记录和可执行文件 |
| `Mode-Indicator/` | 菜单栏中英文指示器及源码 |
| `packaging/` | 可复现安装包的构建脚本 |
| `notices/` | 第三方来源和许可证 |

GitHub 源码 ZIP **不包含约 399 MiB 的 `.gram` 文件**。普通用户只需下载完整 `.pkg`。源码用户从本版 [Release](https://github.com/xzhang17/squirrel-academic-config/releases/tag/v1.3.0) 下载 `wanxiang-lts-zh-hans.gram` 放入 `Profile/`，用 `Model.sha256` 校验后，可运行 `Prepare-profile.command` 生成独立配置，或运行 `Install.command` 安装配置。源码安装前需已有兼容鼠须管；智能空格需要本仓库的定制 app。

安装包构建方法见 [packaging/README.md](packaging/README.md)。词典与模型来源见 [notices/SOURCES.md](notices/SOURCES.md) 和 [学科词典来源](Profile/dicts/academic_dicts/Sources.txt)。各组件保留各自许可证。
