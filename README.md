<div align="center">

# ✨ Codex Immersive Skin

**把自己的图片，变成 macOS / Windows Codex Desktop 的沉浸式主题。**

主页独立横幅 · 任务页低干扰背景 · 磨砂内容层 · 浅色 / 深色自适应 · 一键验证与恢复

[![Platform: macOS](https://img.shields.io/badge/platform-macOS-111827?style=flat-square&logo=apple&logoColor=white)](#-macos-使用前准备)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-2563eb?style=flat-square&logo=windows11&logoColor=white)](#windows)
[![License: MIT](https://img.shields.io/badge/license-MIT-2563eb?style=flat-square)](LICENSE)
[![Theme: Light / Dark](https://img.shields.io/badge/theme-light%20%2F%20dark-8b5cf6?style=flat-square)](#-换成自己的图片)
[![Tests: Passing](https://img.shields.io/badge/tests-passing-16a34a?style=flat-square)](#-自检与恢复)
[![Restore: Reversible](https://img.shields.io/badge/restore-reversible-f59e0b?style=flat-square)](#-自检与恢复)

<sub>🎬 作者抖音：<strong>@泽轩604</strong>（App 内搜索即达）</sub>

<sub>⭐ 项目免费开源、持续维护——觉得好用，右上角点个 Star 就是对作者最大的支持</sub>

<sub><a href="#-30-秒理解">✨ 特点</a> · <a href="#-快速开始">🚀 macOS 安装</a> · <a href="#windows">🪟 Windows</a> · <a href="#-换成自己的图片">🖼️ 自定义</a> · <a href="#security">🛡️ 安全</a> · <a href="#-常见问题">❓ FAQ</a> · <a href="#-english-summary">English</a></sub>

</div>

> ⚠️ **非官方项目：** 本项目不是 OpenAI 发布的项目，与 OpenAI 不存在合作、授权或背书关系。项目基于 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的 MIT 版本修改，编辑器引擎与注入框架并非作者从零开发；创意参考 [HeiGeAi/codex-miku-theme](https://github.com/HeiGeAi/codex-miku-theme) 以及公众号「黑哥Ai」。

## ✨ 30 秒理解

| 能力 | 你会得到什么 |
| --- | --- |
| 沉浸式布局 | 不只替换横幅，主页、侧栏、任务区和输入区共同形成连续视觉。 |
| 原生组件适配 | 保留 Codex 自带的按钮、输入框、菜单和项目选择器，只调整与主题匹配的颜色。 |
| 浅色 / 深色 | 主题配置支持 `light` 与 `dark`，仓库各附一套中性示例。 |
| 持久重注入 | 刷新、切换任务或渲染器重建后，常驻注入器会重新读取并应用当前主题。 |
| 验证与恢复 | 自动测试覆盖脚本语法、主题载荷、配置备份/恢复、浅/深色适配、刷新重注入与签名运行时检查；桌面入口可执行真实 CDP 自检或完整恢复。 |

## 🖼️ 两套内置主题

以下是仓库内真实使用的**背景预览**，不是 Codex UI 截图。

<table>
  <tr>
    <td align="center"><img src="assets/morning-mist.png" alt="晨雾浅色主题背景预览" width="100%"></td>
    <td align="center"><img src="examples/warm-sand/background.png" alt="暖沙深色主题背景预览" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>晨雾 · Light</strong></td>
    <td align="center"><strong>暖沙 · Dark</strong></td>
  </tr>
</table>

两张示例图都是由仓库内 SVG 源文件生成的原创抽象渐变背景，来源和哈希记录见 [`references/asset-provenance.md`](references/asset-provenance.md)。

## 💻 macOS 使用前准备

- macOS；
- 已安装 Codex Desktop，并至少正常启动过一次；
- 完整下载本仓库，不要只复制 CSS 或图片；
- 首次应用主题时，允许 Codex 在确认后重启一次。

项目复用 Codex 自带且经过签名校验的 Node.js，不要求另外安装全局 Node.js，也不会修改 `Codex.app`、`app.asar` 或代码签名。

## 🚀 快速开始

### 方法一：下载 ZIP 后双击

1. 在 GitHub 的 **Code → Download ZIP** 下载并解压。
2. 双击 `Install Codex Immersive Skin.command`。
3. 安装完成后，桌面会出现启动、定制、验证和恢复四个入口。
4. 双击 `Codex Immersive Skin - Customize.command`，在 Finder 选择自己的图片并输入主题名。
5. 以后从 `Codex Immersive Skin.command` 启动或重新应用主题。

如果 macOS 首次拦截 `.command` 文件，可在 Finder 中右键该文件，选择“打开”，再确认一次。

### 方法二：Git 克隆

```bash
git clone https://github.com/zexuanw958-svg/codex-immersive-skin.git
cd codex-immersive-skin
open "Install Codex Immersive Skin.command"
```

安装目录为 `~/.codex/codex-immersive-skin`，用户主题、状态和日志位于 `~/Library/Application Support/CodexImmersiveSkin`。

<a id="windows"></a>

## 🪟 Windows 使用

当前 Windows 路径适用于 Microsoft Store/MSIX 形态的 Codex。已经自动化检查的环境是 Windows 11 x64 与 Windows PowerShell 5.1；完整真机状态、准确 Codex 版本和未验证范围见 [`docs/windows/适配报告.md`](docs/windows/适配报告.md)。Windows 10、Windows on ARM 和非 Store 安装形态不能从现有结果推定为已支持。

### 准备与安全

- 从 Microsoft Store 安装 Codex，并至少正常启动一次，让 Codex 准备位于 `%LOCALAPPDATA%` 的自身 Node.js 运行时；
- 下载完整仓库或可信 ZIP，不需要管理员权限，也不依赖全局 Node.js/npm；
- 若下载标记阻止文件，只在确认来源并核对发布方提供的哈希后，对该可信 ZIP 在“属性”中解除锁定，再重新解压；
- 不要关闭 SmartScreen，不要修改用户级或机器级执行策略。`.cmd` 只给新建 PowerShell 进程使用 `RemoteSigned`，不会运行 `Set-ExecutionPolicy`；组织策略仍阻止时应停止并联系管理员。

### 安装与五个入口

双击 `Install Codex Immersive Skin.cmd`。默认安装位置是 `%USERPROFILE%\.codex\codex-immersive-skin`，主题和状态位于 `%LOCALAPPDATA%\CodexImmersiveSkin`。安装器使用事务目录部署；配置备份与两项基础主题设置只在 Start 获得重启授权并关闭正在运行的 Codex 后进入事务。如果 Codex 正在运行，会在重启前询问。

仓库提供五个入口：

- `Install Codex Immersive Skin.cmd`：事务安装并创建桌面入口；
- `Customize Codex Immersive Skin.cmd`：本地选图、自动取色或显式覆盖；
- `Start Codex Immersive Skin.cmd`：启动或重新应用主题；
- `Verify Codex Immersive Skin.cmd`：验证真实 renderer，可刷新；取得用户明确同意后可选截图；
- `Restore Codex Immersive Skin.cmd`：移除主题；配合公开参数恢复基础配色并正常重启。

安装后桌面会出现 Start、Customize、Verify、Restore 四个快捷方式。Install 保留为仓库内的一次性入口。

### Windows 定制示例

不传四项外观参数时全部自动生成：

```powershell
& ".\Customize Codex Immersive Skin.cmd" --image "<本地图片路径>" --name "我的 Windows 主题"
```

只覆盖 `accent`，其他项目仍从同一图片派生：

```powershell
& ".\Customize Codex Immersive Skin.cmd" --image "<本地图片路径>" --name "单色覆盖" --accent "#123456"
```

完全显式控制：

```powershell
& ".\Customize Codex Immersive Skin.cmd" `
  --image "<本地图片路径>" --name "全显式主题" `
  --appearance dark --accent "#123456" `
  --secondary "#4f7890" --highlight "#8b5a83"
```

图片只在本机用 `System.Drawing` 处理，不交给模型。无法分析颜色时使用默认配色并警告；无法转换图片时保留原主题并退出。

### Windows 验证与恢复

桌面 Verify 默认检查侧栏、输入区、编辑区最小宽度、滚动宽度、输入控件边界、主页横幅、建议卡、项目选择器、页面溢出和装饰层点击穿透，并把 JSON 结果写入本地状态目录，不截图。只有用户对当前非敏感任务明确同意后，才应从命令行追加截图参数；截图不要提交仓库或上传给模型。自动通过后仍应亲自点击侧栏、输入框、按钮和链接。

桌面 Restore 会执行完整恢复。仓库根入口的等效命令是：

```powershell
& ".\Restore Codex Immersive Skin.cmd"
```

Windows 不修改 MSIX、`app.asar` 或签名；CDP 只绑定 `127.0.0.1`，但没有额外认证。不用主题时通过 Restore 关闭调试会话。完整安装、安全边界、故障处理和参数说明见 [`docs/windows/README.md`](docs/windows/README.md)。

Windows 安装前只读检查与维护者全量测试：

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned `
  -File ".\scripts\doctor-windows.ps1"
npm.cmd test
```

普通安装只要求 doctor 通过；`npm.cmd test` 是仓库维护者检查，不是主题运行依赖。

## 🎨 换成自己的图片

最省事的方法是双击桌面的定制入口。图片可以是自己拍摄、自己绘制或已获得授权的素材；也可以用豆包、GPT 等工具生成一张新的抽象图或风景图。横向图片效果通常更好，建议宽度 2000 px 以上、左侧保留较安静的区域。

不填写 `--accent`、`--secondary`、`--highlight` 和 `--appearance` 时，脚本会在本机从图片自动提取三种强调色并判断浅色 / 深色；只填写其中一部分时，明确填写的值优先，其余项目继续自动生成。整个过程不需要模型看图。

需要手动覆盖自动结果时，命令行方式支持显式指定主题名、浅深色和三种强调色：

```bash
~/.codex/codex-immersive-skin/scripts/customize-theme-macos.sh \
  --image "/path/to/your-image.png" \
  --name "我的主题" \
  --appearance light \
  --accent "#2e6874" \
  --secondary "#5d7f92" \
  --highlight "#8a7190"
```

`--appearance` 只能是 `light` 或 `dark`。原图不能超过 50 MB；脚本会使用 macOS 自带工具转成最长边不超过 3200 px 的 JPEG，并把处理后的文件限制在 16 MB 内。

恢复仓库自带的“晨雾”示例：

```bash
~/.codex/codex-immersive-skin/scripts/customize-theme-macos.sh --reset-demo
```

第二套深色示例“暖沙”位于 `examples/warm-sand/`。下面的命令会先备份当前自定义主题，再复制“暖沙”并重新应用：

```bash
THEME_DIR="$HOME/Library/Application Support/CodexImmersiveSkin/theme"
if [ -e "$THEME_DIR" ]; then
  mv "$THEME_DIR" "$THEME_DIR.backup-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$THEME_DIR"
cp ~/.codex/codex-immersive-skin/examples/warm-sand/{theme.json,background.png} "$THEME_DIR/"
~/.codex/codex-immersive-skin/scripts/start-dream-skin-macos.sh --prompt-restart
```

## 🧰 桌面入口

- `Codex Immersive Skin.command`：启动或重新应用主题；
- `Codex Immersive Skin - Customize.command`：重新选图并应用；
- `Codex Immersive Skin - Verify.command`：执行真实 CDP 自检并保存验证截图；
- `Codex Immersive Skin - Restore.command`：移除主题、恢复 Codex 的基础配色并正常启动。

## ✅ macOS 自检与恢复

在仓库目录运行静态测试：

```bash
./tests/run-tests.sh
```

测试脚本会自动寻找 Codex 自带且已签名的 Node.js 22 或更新版本；运行工具本身不依赖全局 Node.js 或 npm。

检查已启动的真实主题：

```bash
~/.codex/codex-immersive-skin/scripts/doctor-macos.sh --require-live
~/.codex/codex-immersive-skin/scripts/verify-dream-skin-macos.sh \
  --reload \
  --screenshot "$HOME/Desktop/Codex Immersive Skin Verification.png"
```

验证器会检查原生侧栏、输入栏与编辑区布局、主页横幅、建议卡、存在时的项目选择器、横向溢出以及装饰层是否拦截点击。输入栏虽然存在但宽度塌缩、内部溢出或控件越界时，Verify 会判定失败。要彻底移除主题，可运行桌面的 Restore 入口；恢复脚本会停止经过身份核验的注入器，并恢复安装前备份的基础主题设置。

<a id="security"></a>

## 🛡️ 工作原理与安全边界

- 动态查找 Bundle ID 为 `com.openai.codex` 的 Codex 应用；
- 校验应用及其 Node.js 的代码签名、Team ID、CPU 架构和 Node.js 版本；
- 通过用户级 `launchd` 启动应用，只在 `127.0.0.1` 打开 CDP；
- 只接受由 Codex 主进程或合法子进程持有的监听端口；
- 只向包含预期原生结构的 `app://` 页面注入；
- 通过常驻注入器处理刷新、路由切换和渲染器重建；
- 恢复时核对 PID、启动时间、Node 路径和注入器路径，避免误停其他进程。

CDP 是仅限本机但没有额外认证的调试接口。主题运行期间，不要执行来源不明的本地程序；不用主题时可通过 Restore 入口关闭当前主题会话和调试端口。

当前版本面向已验证范围内的 macOS，以及 Windows 适配报告所列的 Store/MSIX 包身份、运行时和静态/隔离测试范围；Windows 真机生命周期是否完成，以适配报告中的逐项记录为准。Codex 升级后如果移除或改变已验证运行时、包身份或关键页面结构，项目会停止并要求更新适配，不会盲目写入应用包。仓库保留部分上游的 `dream-skin` 内部文件名、CSS 类名和脚本名，以降低对已验证运行时的破坏；对外项目名与安装目录使用 `Codex Immersive Skin`。

## ❓ 常见问题

### macOS 提示无法打开 `.command` 怎么办？

这是 Gatekeeper 对下载脚本的常见提示。在 Finder 中右键对应的 `.command` 文件，选择“打开”，再确认一次。

### 安装时提示 `The injector launchd job did not start` 怎么办？

`v1.0.0` 在部分 macOS 上存在 `launchd` 启动时序竞态，已在 `v1.0.1` 修复。请重新从本仓库下载最新 ZIP 并再次运行安装器；如果使用 Git 克隆，先执行 `git pull` 再重试。

### 新建对话页的输入栏变成很窄的长条怎么办？

`v1.0.1` 及更早版本中，一条横向自动外边距规则可能把原生 flex 输入栏压缩到最小内容宽度，已在 `v1.0.2` 修复。请重新下载最新 ZIP 并再次运行安装器；更新后 Verify 也会主动拒绝这类输入栏塌缩。

### 支持 Windows 或 Linux 吗？

Windows 支持仅限 [Windows 指南](docs/windows/README.md)与[适配报告](docs/windows/适配报告.md)列出的 Store/MSIX、系统、架构和 Codex 版本范围；其他 Windows 环境属于未验证。Linux 目前不支持。

### 会修改 Codex 应用包吗？

不会。项目不修改 `Codex.app`、Windows MSIX、`app.asar` 或代码签名，而是在校验运行环境后，向符合预期结构的本机 `app://` 页面应用运行时主题。

### 可以完整恢复吗？

可以。macOS 双击桌面的 `Codex Immersive Skin - Restore.command`；Windows 双击安装器创建的 Restore 快捷方式。恢复脚本会停止经过身份核验的注入器、恢复安装前备份的基础主题设置，并关闭当前主题会话和调试端口。

## 🙏 来源与致谢

- [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin)：本项目的 MIT 上游代码来源，提供编辑器引擎与注入框架基础。
- [HeiGeAi/codex-miku-theme](https://github.com/HeiGeAi/codex-miku-theme) 与公众号「黑哥Ai」：本项目的创意参考。

感谢上述项目与创作者的公开分享。

## 📄 许可证、素材与免责声明

软件代码按仓库中的 [MIT License](LICENSE) 分发，并原样保留上游 [NOTICE](NOTICE.md)。本仓库不包含第三方角色、作品截图或品牌素材。

本项目不是 OpenAI 发布的项目，与 OpenAI 不存在合作、授权或背书关系。MIT 软件许可证不替代商标许可，也不自动授予任何第三方图片、角色或其他素材的使用权。用户添加图片时，请只使用自己拥有或已经获得授权的素材，并自行判断具体使用场景所需的权利。

<a id="-english-summary"></a>

## English Summary

**Codex Immersive Skin** turns a user-selected image into an immersive theme for Codex Desktop on macOS, with a Store-checked Windows adaptation whose current live-test scope is recorded separately in the Windows report. It provides separate home and task backgrounds, native-component color adaptation, `light` / `dark` modes, and persistent reinjection after refreshes, route changes, or renderer rebuilds.

The project validates Codex and its own Node.js runtime before use: macOS checks code signing and Team ID, while Windows checks Store/MSIX identity, package content, Authenticode, architecture, and a package-matching runtime hash. It opens CDP only on `127.0.0.1`, checks the listening process identity, and does **not** modify `Codex.app`, the Windows MSIX, `app.asar`, or the app's code signature. Desktop shortcuts cover launch/reapply, theme customization, live verification, and complete restoration.

For the quickest start, choose **Code → Download ZIP** and extract the archive. On macOS, double-click `Install Codex Immersive Skin.command`; if Gatekeeper blocks it, right-click in Finder, choose **Open**, and confirm once. On Windows, first launch the Store/MSIX Codex app once, then double-click `Install Codex Immersive Skin.cmd`. If Windows marks a trusted ZIP as downloaded, verify its source/hash and unblock only that ZIP; do not disable SmartScreen or lower machine/user execution policy. See the [Windows guide](docs/windows/README.md).

This project is based on the MIT-licensed [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin), with creative inspiration from [HeiGeAi/codex-miku-theme](https://github.com/HeiGeAi/codex-miku-theme) and the 「黑哥Ai」 WeChat Official Account. See the repository [MIT License](LICENSE) and retained [NOTICE](NOTICE.md).

This is an independent project, not published, sponsored, authorized, or endorsed by OpenAI.
