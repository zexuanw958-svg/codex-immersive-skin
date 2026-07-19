# Codex Immersive Skin：Windows 使用指南

> **非官方项目：** 本项目不是 OpenAI 发布的项目，与 OpenAI 不存在合作、授权或背书关系。项目基于 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的 MIT 版本修改，编辑器引擎与注入框架并非作者从零开发；创意参考 [HeiGeAi/codex-miku-theme](https://github.com/HeiGeAi/codex-miku-theme) 以及公众号「黑哥Ai」。

本指南适用于 Microsoft Store/MSIX 形态的 Codex Windows 应用。当前自动化检查环境为 Windows 11 x64、Windows PowerShell 5.1；完整真机生命周期已复测到 Store Codex `26.715.3651.0`，准确版本边界见[《Windows 适配报告》](适配报告.md)。Windows 10、Windows on ARM 和非 Store 安装形态如未在报告中列为“通过”，均属于未验证范围。

## 开始前检查

- 从 Microsoft Store 安装 Codex，并至少正常启动一次；首次启动会准备 Codex 自身位于 `%LOCALAPPDATA%` 的 Node.js 运行时。
- 下载完整仓库或可信发布 ZIP，不要只复制 `.cmd`、CSS 或图片。
- 普通使用不需要管理员权限，不需要另外安装全局 Node.js 或 npm。
- 只使用自己拥有或已经获得授权的图片。
- 首次应用主题或调试会话失效时，Codex 需要在你确认后重启一次。

## SmartScreen 与执行策略

如果 Windows 标记了下载文件：

1. 先确认 ZIP 来自本仓库或你信任的发布方；若发布页提供 SHA-256，先核对哈希。
2. 只对这个可信 ZIP 打开“属性”，勾选“解除锁定”，再重新解压。
3. 不要关闭 SmartScreen，也不要降低用户级或机器级 PowerShell 执行策略。

五个 `.cmd` 入口仅给它新建的 Windows PowerShell 进程传入 `RemoteSigned`，不会调用 `Set-ExecutionPolicy`，也不会写入用户或机器策略。如果组织的 `MachinePolicy` 或 `UserPolicy` 仍然阻止脚本，请停止操作并联系管理员，不要改成 `Bypass`。

下文所有 `.\*.cmd` 示例都要求 PowerShell 当前目录是完整仓库根目录：

```powershell
Set-Location "<完整仓库根目录>"
```

安装前先运行只读 doctor；它不会启动、停止或重启 Codex：

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned `
  -File ".\scripts\doctor-windows.ps1"
```

只有退出码为 0 且 JSON 中 `pass=true` 才继续。把 `package.version`、`platform` 与[适配报告](适配报告.md)中的已验证版本比较；不一致时按“未验证”处理。维护者可另运行 `npm.cmd test`，不要在 PowerShell 中调用可能被策略拦截的 `npm.ps1`。

## 五个入口

| 仓库入口 | 用途 |
| --- | --- |
| `Install Codex Immersive Skin.cmd` | 校验 Codex 包和自身运行时，事务安装项目并创建桌面入口；基础主题配置留到已授权的 Start 事务。 |
| `Customize Codex Immersive Skin.cmd` | 本地选图、自动取色或按明确参数覆盖颜色，然后应用主题。 |
| `Start Codex Immersive Skin.cmd` | 启动或重新应用主题；需要重启正在运行的 Codex 时先询问。 |
| `Verify Codex Immersive Skin.cmd` | 验证真实 Codex renderer，可选刷新和截图。 |
| `Restore Codex Immersive Skin.cmd` | 移除实时主题；通过公开参数可恢复基础配色并正常重启 Codex。 |

安装后桌面会创建 Start、Customize、Verify、Restore 四个快捷方式；Install 仍是仓库中的一次性入口。安装器只覆盖带有本项目身份标记的同名快捷方式，遇到其他同名桌面文件会停止并回滚。

## 安装

1. 关闭不需要保存的临时界面，但不必预先退出 Codex。
2. 双击 `Install Codex Immersive Skin.cmd`。
3. 如果 Codex 正在运行，安装器会在真正重启前显示确认框；选择“否”会停止这次应用，不会强行结束 Codex。
4. 安装完成后，从桌面 `Codex Immersive Skin` 快捷方式启动主题。

需要只安装、不启动时，可在仓库目录的 PowerShell 中运行：

```powershell
& ".\Install Codex Immersive Skin.cmd" --no-launch
```

常用位置：

| 内容 | 默认位置 |
| --- | --- |
| 已安装项目 | `%USERPROFILE%\.codex\codex-immersive-skin` |
| 用户主题、状态与日志 | `%LOCALAPPDATA%\CodexImmersiveSkin` |
| Codex 配置 | `%USERPROFILE%\.codex\config.toml` |
| Codex 自身运行时 | `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\<runtime-id>` |

`--no-launch` 只部署项目和快捷方式，不读取后回写或修改 Codex 配置。部署使用 `.installing` / `.previous` 事务目录，失败时恢复旧安装；若上次在目录换名后意外中断，只自动接回唯一且身份、结构均通过验证的 `.previous`。之后 Start 会在取得重启授权、确认 Codex 已退出后，对完整配置快照执行预期哈希/CAS，只备份并调整 `[desktop]` 下的 `appearanceTheme` 与 `appearanceDarkCodeThemeId`；其他 TOML 内容保持不变，并发修改不会被回滚覆盖。

## 定制图片与配色

最简单的方式是双击桌面 Customize 快捷方式，在 Windows 文件选择器中选择图片并输入主题名。处理全部在本机完成：源图最大 50 MB，经 `System.Drawing` 等比缩放为最长边不超过 3200 px 的 JPEG，处理后最大 16 MB。脚本不会把图片上传给模型。

不传 `--appearance`、`--accent`、`--secondary`、`--highlight` 时，四项都由图片自动生成：

```powershell
& ".\Customize Codex Immersive Skin.cmd" `
  --image "<本地图片路径>" `
  --name "我的 Windows 主题"
```

只覆盖一个颜色时，其他字段仍从同一图片派生：

```powershell
& ".\Customize Codex Immersive Skin.cmd" `
  --image "<本地图片路径>" `
  --name "单色覆盖示例" `
  --accent "#123456"
```

需要完全显式控制时，同时给出浅深色和三种颜色：

```powershell
& ".\Customize Codex Immersive Skin.cmd" `
  --image "<本地图片路径>" `
  --name "全显式示例" `
  --appearance dark `
  --accent "#123456" `
  --secondary "#4f7890" `
  --highlight "#8b5a83"
```

`--appearance` 只能是 `light` 或 `dark`，颜色必须是六位十六进制。图片可转换但无法分析时，分析器会给出中文警告并使用安全默认值；图片本身无法转换时，定制会失败并保留之前主题。调试时可加 `--no-apply` 只生成主题，不重启 Codex。

恢复内置示例：

```powershell
& ".\Customize Codex Immersive Skin.cmd" --reset-demo
```

## Start 与本机调试端口

Start 会重新发现并验证 Store/MSIX 包、Codex 自身 Node.js 和保存的状态。只要 Codex 已运行，Start 都会在修改配置前要求本次重启授权，以避免 Codex 与工具并发写配置；桌面入口会先显示 Yes/No 确认框。命令行自动化只有显式传入 `--restart-existing` 才授权本次重启。

Store 启动入口可能先返回短生命周期启动器，再把请求交给另一个 Codex 主进程。Start 不再假定 `Start-Process` 返回的 PID 就是最终主进程：它记录启动前基线、UTC 时间和一次性事务标记，只接纳唯一一个新出现、Store/MSIX 身份通过且精确携带 loopback、端口和事务标记参数的主进程。出现多个候选、参数丢失或身份变化时会失败关闭，并只按已重新核验的事务身份逐个清理。

CDP 只绑定 `127.0.0.1`，默认从端口 `9341` 开始选择可用端口。CDP 是仅限本机但没有额外认证的调试接口；主题运行期间不要执行来源不明的本地程序，不用主题时通过 Restore 关闭当前会话。

## Verify

双击桌面 Verify 快捷方式会执行真实 renderer 检查并保存 JSON，默认不截图。

不需要截图时，从仓库根目录运行：

```powershell
& ".\Verify Codex Immersive Skin.cmd" --reload
```

只有用户对当前非敏感任务明确同意保存截图时才运行；桌面可能受 OneDrive 等软件同步，截图使用完应由用户自行确认并删除：

```powershell
& ".\Verify Codex Immersive Skin.cmd" --reload --screenshot-default
```

验证器检查 renderer 身份、原生侧栏、composer 与编辑区最小宽度、client/scroll width、输入控件边界、主页横幅、建议卡、项目选择器、页面溢出和装饰层点击穿透。JSON 中的 `composerLayoutOk` 必须为 `true`，以防只看到外壳存在却漏掉新建对话输入框塌缩。结果保存在 `%LOCALAPPDATA%\CodexImmersiveSkin\last-verify.json`。脚本只有在至少找到一个 renderer 且每个 `targets[].result.pass` 都为 `true` 时才以 0 退出；其他情况按失败处理。查看结果但不打开截图：

```powershell
Get-Content -Raw "$env:LOCALAPPDATA\CodexImmersiveSkin\last-verify.json" |
  ConvertFrom-Json | ConvertTo-Json -Depth 8
```

自动检查不能替代人工确认。请实际点击侧栏、输入框、按钮和链接，并确认键盘输入正常。验证截图可能包含私人任务信息；不要把它提交到仓库，也不要要求其他人上传截图或用户图片给模型。

## Restore

桌面 Restore 快捷方式执行完整恢复：核验并停止记录的注入器、移除实时 DOM/CSS、恢复安装前保存的两项基础配色、关闭当前调试会话并正常启动 Codex。

从仓库根入口执行同等操作时使用：

```powershell
& ".\Restore Codex Immersive Skin.cmd"
```

恢复后再次运行只读 doctor。只有 `statePresent=false`、`cdpVerified=false`、`live=false` 才能记录为主题会话已关闭；如果 doctor 仍报告端口或状态，按恢复失败处理。

恢复失败时不要手动按进程名结束程序；选择性配置备份会保留到整笔恢复提交，因此应保留状态和日志后用同一 Restore 命令重试。若要彻底清理，应在这次完整恢复时运行 `& ".\Restore Codex Immersive Skin.cmd" --uninstall`，让同一事务同时删除本项目创建且身份匹配的四个桌面快捷方式；它不删除安装目录或用户主题。项目不自动删除私人主题、日志或验证截图；用户在成功 Restore 并确认不再需要再次定制后，可在文件资源管理器中自行删除前述两个精确目录及自己保存的截图，删除前再次核对路径。

Start 失败时的完整配置快照回滚使用同目录临时源和唯一 displaced 备份路径调用 PowerShell 5.1 的 `File.Replace`。每次替换前都重新检查预期哈希；只对 Windows access denied、sharing violation 和 lock violation 做有限重试。恢复后的目标与 displaced 文件都必须匹配预期哈希，验证完成后才清理 displaced 文件；并发修改或非瞬时错误不会被重试覆盖。

## 安全边界与已知限制

- 不修改、解包、重打包或重签名 MSIX，不写入 `app.asar`。
- 只接受名称、Store 签名种类、发布者、Publisher ID、manifest 入口和 BlockMap 内容链符合预期的 `OpenAI.Codex` 包。
- WindowsApps 中的包内 Node.js 不能直接执行；项目只使用 Codex 首次启动后放在 `%LOCALAPPDATA%` 的自身运行时，并校验其 SHA-256 与包内副本一致，同时核对版本、架构和 Authenticode 签名。
- 五个入口使用当前用户 SID 和状态目录哈希派生、ACL 仅允许当前用户的 `Global` 互斥锁，防止不同 Windows Session 交错修改状态。
- 只通过已经核验的同一原生句柄温和关闭或强制停止路径、PID、启动时间、命令行、包身份和来源均匹配的进程；身份不一致时保留状态并失败关闭。
- 配置、选择性备份和快捷方式写入均带事务所有权或预期哈希检查；检测到并发修改时保留恢复材料并停止，不覆盖新内容。
- Codex 自身 Node.js 的 stdout/stderr 按严格 UTF-8 解码，不依赖中文 Windows 的 OEM 代码页。
- Codex 升级如果改变包结构、运行时或关键 DOM，项目会停止并要求重新适配，不会绕过校验继续注入。
- Windows 11 x64 之外的系统、ARM64、非 Store 包以及未来 Codex 版本，应以适配报告中的实际记录为准。

## 故障排查

- **提示未找到配置：** 先正常启动 Codex 一次，再退出并重试。
- **提示未找到可用运行时：** 先让 Store 版 Codex 完成一次正常启动；不要改用 PATH 中的全局 Node.js。
- **组织策略阻止 PowerShell：** 停止并联系管理员；不要关闭 SmartScreen 或修改机器/用户执行策略。
- **Codex 正在运行但没有可信 CDP：** 使用桌面 Start 并确认重启，或先自行正常退出 Codex。
- **主题看似生效但交互异常：** 先运行 Verify；若仍异常，运行完整 Restore。
- **Codex 更新后校验失败：** 保持失败关闭，等待项目适配新版本。

## 许可证、来源与素材

软件代码按仓库中的 [MIT License](../../LICENSE) 分发，并保留上游 [NOTICE](../../NOTICE.md)。本仓库不包含第三方角色、作品截图或品牌素材。MIT 软件许可证不替代商标许可，也不自动授予任何第三方图片、角色或其他素材的使用权；用户添加图片时应自行确认所需权利。
