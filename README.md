# Codex Immersive Skin

把自己的图片变成 macOS Codex Desktop 的沉浸式主题：主页有独立横幅，任务页有低干扰背景和磨砂内容层，同时保留原生侧栏、卡片、项目选择器、任务内容和输入框。

> 归属说明：本项目基于 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的 MIT 版本修改，编辑器引擎与注入框架不是本人从零开发。创意也参考了 [HeiGeAi/codex-miku-theme](https://github.com/HeiGeAi/codex-miku-theme) 以及公众号「黑哥Ai」。感谢前述项目与创作者公开分享。

## 这个版本改了什么

- **整页更沉浸**：不只换一张横幅，主页、侧栏、任务区和输入区形成一套连续视觉。
- **原生组件会跟着主题换色**：按钮、输入框、菜单和项目选择器仍是 Codex 自己的组件，只调整适配颜色，不用截图盖住界面。
- **浅色/深色可选**：主题配置支持 `light` 与 `dark`，仓库各附一套中性示例。
- **热切换更稳**：刷新、切换任务或渲染器重建后，常驻注入器会重新读取主题并应用，不会一直抱着启动时的旧配置。
- **有自动测试**：覆盖脚本语法、主题载荷、配置备份恢复、浅深色适配、刷新重注入和签名运行时检查。

## 使用前准备

- macOS；
- 已安装 Codex Desktop，并至少正常启动过一次；
- 完整下载本仓库，不要只复制 CSS 或图片；
- 首次应用主题时，允许 Codex 在确认后重启一次。

项目复用 Codex 自带且经过签名校验的 Node.js，不要求另外安装全局 Node.js，也不会修改 Codex 的 `.app`、`app.asar` 或代码签名。

## 安装

### 方法一：下载后双击

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

## 换成自己的图片

最省事的方法是双击桌面的定制入口。图片可以是自己拍摄、自己绘制或已获得授权的素材；也可以用豆包、GPT 等工具生成一张新的抽象图或风景图。横向图片效果通常更好，建议宽度 2000 px 以上、左侧保留较安静的区域。

命令行方式支持主题名、浅深色和三种强调色：

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

两张示例图都是仓库内 SVG 源文件生成的纯渐变背景，来源和哈希记录见 [`references/asset-provenance.md`](references/asset-provenance.md)。

## 桌面入口

- `Codex Immersive Skin.command`：启动或重新应用主题；
- `Codex Immersive Skin - Customize.command`：重新选图并应用；
- `Codex Immersive Skin - Verify.command`：执行真实 CDP 自检并保存验证截图；
- `Codex Immersive Skin - Restore.command`：移除主题、恢复 Codex 的基础配色并正常启动。

## 自检与恢复

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

验证器会检查原生侧栏、输入框、主页横幅、建议卡、项目选择器、横向溢出以及装饰层是否拦截点击。要彻底移除主题，可运行桌面的 Restore 入口；恢复脚本会停止经过身份核验的注入器，并恢复安装前备份的基础主题设置。

## 工作原理与安全边界

- 动态查找 Bundle ID 为 `com.openai.codex` 的 Codex 应用；
- 校验应用及其 Node.js 的代码签名、Team ID、CPU 架构和 Node.js 版本；
- 通过用户级 `launchd` 启动应用，只在 `127.0.0.1` 打开 CDP；
- 只接受由 Codex 主进程或合法子进程持有的监听端口；
- 只向包含预期原生结构的 `app://` 页面注入；
- 通过常驻注入器处理刷新、路由切换和渲染器重建；
- 恢复时核对 PID、启动时间、Node 路径和注入器路径，避免误停其他进程。

CDP 是仅限本机但没有额外认证的调试接口。主题运行期间，不要执行来源不明的本地程序；不用主题时可通过 Restore 入口关闭当前主题会话和调试端口。

## 支持范围

当前版本面向 macOS Codex Desktop。Codex 升级后如果移除内部签名 Node.js 或改变关键页面结构，项目会停止并要求更新适配，不会盲目写入应用包。仓库保留部分上游的 `dream-skin` 内部文件名、CSS 类名和脚本名，以降低对已验证运行时的破坏；对外项目名与安装目录使用 `Codex Immersive Skin`。

## 许可证、素材与免责声明

软件代码按仓库中的 [MIT License](LICENSE) 分发，并原样保留上游 [NOTICE](NOTICE.md)。本仓库不包含第三方角色、作品截图或品牌素材。

本项目不是 OpenAI 发布的项目，与 OpenAI 不存在合作、授权或背书关系。MIT 软件许可证不替代商标许可，也不自动授予任何第三方图片、角色或其他素材的使用权。用户添加图片时，请只使用自己拥有或已经获得授权的素材，并自行判断具体使用场景所需的权利。
