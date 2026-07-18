# Codex Immersive Skin Windows Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Codex Immersive Skin 增加与 macOS 对等、可恢复且经过 Windows 真机验证的安装、定制、启动、验证和恢复链路。

**Architecture:** 保留现有跨平台的主题载荷、DOM 注入器和 TOML 配置逻辑，以独立 PowerShell 层实现 Windows 应用发现、Store 包身份校验、进程/端口校验、后台注入器管理、图片转换和桌面快捷方式。根目录提供五个 `.cmd` 双击入口，入口仅以当前 PowerShell 进程的 `RemoteSigned` 执行对应 `.ps1`，并尊重更严格的 MachinePolicy/UserPolicy；不修改 `app.asar`、MSIX 包或持久化执行策略。

**Tech Stack:** Windows PowerShell 5.1、Node.js 22+、Microsoft Store/MSIX、Electron CDP、System.Drawing、Node test runner、Git。

---

## File map

- Create `Install Codex Immersive Skin.cmd`: 双击安装入口。
- Create `Customize Codex Immersive Skin.cmd`: 双击定制入口。
- Create `Verify Codex Immersive Skin.cmd`: 双击验证入口。
- Create `Restore Codex Immersive Skin.cmd`: 双击恢复入口。
- Create `Start Codex Immersive Skin.cmd`: 双击启动/重新应用入口。
- Create `scripts/common-windows.ps1`: Windows 路径、Store 包、Node、进程、端口、状态、日志与安全校验公共层。
- Create `scripts/normalize-image-windows.ps1`: 使用 `System.Drawing` 做 64 px BMP 归一化与 3200 px JPEG 准备。
- Create `scripts/install-dream-skin-windows.ps1`: 事务式安装、配置备份及桌面快捷方式。
- Create `scripts/customize-theme-windows.ps1`: 图片选择、自动取色、逐项覆盖与主题写入。
- Create `scripts/start-dream-skin-windows.ps1`: 授权式重启、CDP 启动、注入器守护与状态提交。
- Create `scripts/verify-dream-skin-windows.ps1`: 经进程身份核验的 CDP 验证和截图。
- Create `scripts/restore-dream-skin-windows.ps1`: 经 PID 身份核验的注入器停止、DOM 清理、配置恢复和正常重启。
- Create `scripts/doctor-windows.ps1`: Windows 环境、载荷与可选实时会话诊断。
- Create `scripts/run-tests.mjs`: 根据平台选择 macOS 或 Windows 测试运行器。
- Create `tests/run-tests-windows.ps1`: PowerShell/JavaScript 语法、载荷、主题、配置和安全回归测试。
- Create `tests/windows-support.test.mjs`: Windows 入口、图片归一化、参数覆盖和源代码安全约束测试。
- Create `docs/windows/README.md`: Windows 安装、定制、验证、恢复和避坑说明。
- Create `docs/windows/适配报告.md`: 环境、证据、差异、未验证事项和发布建议。
- Create `docs/windows/观众部署提示词.md`: Windows 版谨慎部署向导提示词。
- Modify `scripts/analyze-image.mjs`: 保持 CLI 不变，按平台选择 `sips` 或 PowerShell 归一化器。
- Modify `scripts/theme-config.mjs`: 备份元数据记录真实平台。
- Modify `scripts/write-theme.mjs`: 用规范化真实路径保护内置 demo，避免 Windows 大小写绕过。
- Modify `tests/auto-palette.test.mjs`: 用跨平台 BMP 样本替代只适用于 `sips` 的 SVG 集成假设。
- Modify `tests/adaptive-theme.test.mjs`: 增加 Windows 启动器和动态端口契约。
- Modify `package.json`: `npm test` 走跨平台 Node 分发器。
- Modify `scripts/build-release.sh`: 将 Windows 文件纳入发布 ZIP。
- Modify `README.md`: 新增 Windows 使用章节，不改既有归属与非官方声明。
- Modify `SKILL.md`: 增加 Windows 兼容性和 Windows 入口说明。

## Task 1: Freeze the Windows environment contract

**Files:**
- Create: `docs/windows/适配报告.md`

- [ ] **Step 1: Record only non-private environment facts**

  写入以下已验证信息，路径一律使用环境变量或包内相对路径：

  ```text
  Windows 11 家庭版中文版 10.0.26200（64 位）
  Windows PowerShell 5.1.26100.8655
  全局 Node.js v22.16.0；Codex 可执行运行时 Node.js v24.14.0
  Codex MSIX：OpenAI.Codex 26.715.2305.0，SignatureKind=Store，Status=Ok
  主程序相对路径：app\ChatGPT.exe
  配置：%USERPROFILE%\.codex\config.toml（存在）
  包内 Node：存在且签名有效，但从 WindowsApps 包目录直接执行被拒绝
  Codex 运行时 Node：%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\<runtime-id>\bin\node.exe
  运行时 Node 与 Store 包内副本 SHA-256 一致、Authenticode=Valid、签发者 OpenJS Foundation、架构 x64
  ```

- [ ] **Step 2: State the implementation consequence**

  报告中明确记录：Windows 版优先使用 Codex 首次启动后解压到 `%LOCALAPPDATA%` 的自身 Node 运行时，不依赖全局 Node。脚本必须把候选运行时与 Store 包内只读副本做 SHA-256 一致性校验，并校验版本 22+、架构及有效 OpenJS Authenticode 签名；不复制、不重分发 Node。

- [ ] **Step 3: Verify privacy**

  Run: `rg -n "C:\\Users\\|Users/|AppData\\Local\\Packages" docs/windows`

  Expected: 无真实个人路径命中。

## Task 2: Add a cross-platform image normalization seam

**Files:**
- Create: `scripts/normalize-image-windows.ps1`
- Modify: `scripts/analyze-image.mjs`
- Modify: `tests/auto-palette.test.mjs`
- Test: `tests/windows-support.test.mjs`

- [ ] **Step 1: Write failing Windows normalization tests**

  测试必须生成 24 位 BMP 像素数据，不把图片提交到仓库；调用真实 analyzer 后断言非 fallback、浅深色判断正确、显式字段逐项覆盖：

  ```js
  test("Windows normalization analyzes a generated BMP without fallback", async () => {
    const source = path.join(temp, "source.bmp");
    await fs.writeFile(source, create24BitBmp([[{ red: 244, green: 241, blue: 234 }]]));
    const result = spawnSync(process.execPath, [analyzer, "--image", source, "--format", "json"], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).fallback, false);
    assert.equal(JSON.parse(result.stdout).appearance, "light");
  });
  ```

- [ ] **Step 2: Run the test and capture the current failure**

  Run: `node --test tests/windows-support.test.mjs`

  Expected: FAIL because `analyze-image.mjs` still invokes `/usr/bin/sips` and returns `fallback: true`.

- [ ] **Step 3: Implement the PowerShell image normalizer**

  `normalize-image-windows.ps1` accepts mandatory `-InputPath`, `-OutputPath`, `-Format Bmp|Jpeg`, `-MaxDimension`, and optional `-Quality`. It must load with `System.Drawing.Image::FromFile`, calculate a no-upscale aspect-preserving size, draw into a 24-bit RGB bitmap, save BMP directly or JPEG with the requested encoder quality, and dispose Image/Bitmap/Graphics in `finally` blocks.

- [ ] **Step 4: Route analyzer normalization by platform**

  `resolveImageStyle()` keeps its public signature and CLI unchanged. Use `/usr/bin/sips` on `darwin`; on `win32`, execute:

  ```js
  await execFile("powershell.exe", [
    "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
    "-File", path.join(here, "normalize-image-windows.ps1"),
    "-InputPath", imagePath, "-OutputPath", normalizedBmp,
    "-Format", "Bmp", "-MaxDimension", "64",
  ], { encoding: "utf8", windowsHide: true });
  ```

- [ ] **Step 5: Run palette tests**

  Run: `node --test tests/auto-palette.test.mjs tests/windows-support.test.mjs`

  Expected: 自动取色、fallback、部分覆盖和完整覆盖全部 PASS。

- [ ] **Step 6: Commit**

  ```powershell
  git add scripts/analyze-image.mjs scripts/normalize-image-windows.ps1 tests/auto-palette.test.mjs tests/windows-support.test.mjs
  git commit -m "feat: add Windows image normalization"
  ```

## Task 3: Build the Windows security and runtime foundation

**Files:**
- Create: `scripts/common-windows.ps1`
- Create: `scripts/doctor-windows.ps1`
- Test: `tests/windows-support.test.mjs`

- [ ] **Step 1: Write source-contract tests**

  断言公共层包含并实际使用：`Get-AppxPackage -Name OpenAI.Codex`、`SignatureKind`、`PublisherId`、`Get-AuthenticodeSignature`、Node 主版本 22、`Get-NetTCPConnection`、父进程追溯、loopback WebSocket 校验、PID/启动时间/Node 路径/注入器路径/命令行五重校验；断言不存在对 `app.asar` 的写入。

- [ ] **Step 2: Run and observe failure**

  Run: `node --test tests/windows-support.test.mjs`

  Expected: FAIL because `scripts/common-windows.ps1` does not exist.

- [ ] **Step 3: Implement immutable runtime discovery**

  公共层固定以下运行时契约：

  ```powershell
  $script:InstallRoot = Join-Path $env:USERPROFILE '.codex\codex-immersive-skin'
  $script:StateRoot = Join-Path $env:LOCALAPPDATA 'CodexImmersiveSkin'
  $script:ConfigPath = Join-Path $env:USERPROFILE '.codex\config.toml'
  $script:ExpectedPackageName = 'OpenAI.Codex'
  $script:ExpectedPublisherId = '2p2nqsd0c76g0'
  $script:ExpectedMainRelativePath = 'app\ChatGPT.exe'
  ```

  `Initialize-WindowsRuntime` 每次运行重新发现包，要求 `Status=Ok`、`SignatureKind=Store`、PublisherId 匹配、manifest 的 Application Id/Executable 匹配且主程序存在。随后在 `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\*\bin\node.exe` 中只接受 SHA-256 与包内 `app\resources\cua_node\bin\node.exe` 完全一致的唯一候选，并要求主版本至少 22、`process.arch` 与包架构兼容、签名状态 Valid 且证书主题包含 `OpenJS Foundation`；不回退到 PATH 中的 Node。

- [ ] **Step 4: Implement process and CDP identity checks**

  只把可执行路径严格等于发现到的 `app\ChatGPT.exe` 的根进程识别为主进程；子进程最多向上追溯 32 层。端口必须由主进程或合法后代监听，`/json/version` 的 WebSocket 协议必须是 `ws:`，主机只能是 `127.0.0.1`、`localhost` 或 `[::1]`，端口必须完全相同。

- [ ] **Step 5: Implement atomic state and verified stop**

  状态 schema 记录 `platform`、`skinVersion`、`port`、`injectorPid`、`injectorStartedAt`、`injectorPath`、`nodePath`、`codexExe`、`codexPackageFullName`、`codexPid`、`projectRoot`、`themeDir`。停止注入器前逐项比对 PID、启动时间、Node 路径、脚本路径和命令行；任一不符就保留状态并停止恢复流程。

- [ ] **Step 6: Run doctor without touching live Codex state**

  Run: `powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File scripts\doctor-windows.ps1`

  Expected: JSON 中 `pass=true`、`live=false` 或当前真实 live 值、`modifiesAppAsar=false`，且不输出真实用户名。

- [ ] **Step 7: Commit**

  ```powershell
  git add scripts/common-windows.ps1 scripts/doctor-windows.ps1 tests/windows-support.test.mjs
  git commit -m "feat: validate Windows Codex runtime"
  ```

## Task 4: Add transactional install and five user entrypoints

**Files:**
- Create: `Install Codex Immersive Skin.cmd`
- Create: `Customize Codex Immersive Skin.cmd`
- Create: `Verify Codex Immersive Skin.cmd`
- Create: `Restore Codex Immersive Skin.cmd`
- Create: `Start Codex Immersive Skin.cmd`
- Create: `scripts/install-dream-skin-windows.ps1`
- Test: `tests/windows-support.test.mjs`

- [ ] **Step 1: Write failing entrypoint and rollback tests**

  断言五个 `.cmd` 都使用 `%~dp0` 定位仓库、`-NoProfile`、`-STA`、当前进程 `-ExecutionPolicy RemoteSigned`、对应 `.ps1`、透传 `%*`，失败时保留退出码；断言不存在持久化 `Set-ExecutionPolicy` 或 `Bypass`。安装测试使用临时 `USERPROFILE`/`LOCALAPPDATA` 覆盖，验证已有安装和已有桌面文件不会被无条件覆盖；另用 CRLF TOML 做 install/restore 字节级 round trip，先复现当前实现残留裸 LF 的失败。

- [ ] **Step 2: Implement root launchers**

  每个 `.cmd` 使用同一模式，示例安装入口：

  ```bat
  @echo off
  setlocal
  powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0scripts\install-dream-skin-windows.ps1" %*
  set "CODEX_IMMERSIVE_EXIT=%ERRORLEVEL%"
  if not "%CODEX_IMMERSIVE_EXIT%"=="0" pause
  exit /b %CODEX_IMMERSIVE_EXIT%
  ```

- [ ] **Step 3: Implement transactional deployment**

  安装器把完整项目复制到 `%USERPROFILE%\.codex\codex-immersive-skin.installing.<pid>`，排除 `.git`、`release`、运行状态和日志；已有安装先移动为 `.previous.<pid>`。新安装验证失败时恢复 previous，成功后才删除 previous。

- [ ] **Step 4: Back up only the two base-theme keys**

  调用现有 `theme-config.mjs install`，仅备份/修改 `appearanceTheme` 和 `appearanceDarkCodeThemeId`。修改 `theme-config.mjs` 让 `platform` 写入 `process.platform`，并从原文件检测 `\r\n` 或 `\n` 后把同一换行符用于新增/替换行，保证 CRLF 与 LF 输入都能字节级恢复；恢复仍要求 configPath/schema 匹配。

- [ ] **Step 5: Protect the bundled demo with canonical path identity**

  在 `write-theme.mjs reset-demo` 删除前，对目标目录和内置 `assets` 使用 `fs.realpath()`；Windows 上再以不区分大小写的规范化路径比较。两者相同必须拒绝，即使调用者把 `assets` 写成不同大小写。测试断言内置图片和 `theme.json` 始终存在。

- [ ] **Step 6: Create four installed Desktop shortcuts**

  通过 `WScript.Shell.CreateShortcut()` 创建启动、定制、验证、恢复 `.lnk`；TargetPath 为系统 `powershell.exe`，Arguments 固定 `-NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File` 加已安装脚本。若目标文件存在且不是本项目创建的快捷方式，安装必须失败并回滚。

- [ ] **Step 7: Run isolated install tests**

  Run: `node --test tests/windows-support.test.mjs`

  Expected: 五入口、事务部署、快捷方式身份与选择性配置备份测试 PASS。

- [ ] **Step 8: Commit**

  ```powershell
  git add "*.cmd" scripts/install-dream-skin-windows.ps1 scripts/theme-config.mjs scripts/write-theme.mjs tests/windows-support.test.mjs
  git commit -m "feat: add transactional Windows installer"
  ```

## Task 5: Implement start, verify and restore

**Files:**
- Create: `scripts/start-dream-skin-windows.ps1`
- Create: `scripts/verify-dream-skin-windows.ps1`
- Create: `scripts/restore-dream-skin-windows.ps1`
- Test: `tests/windows-support.test.mjs`

- [ ] **Step 1: Write failing lifecycle contract tests**

  断言 Start 在 Codex 已运行但没有经核验 CDP 时必须满足以下之一：收到 `--restart-existing`，或 `--prompt-restart` 得到用户确认；否则退出。断言 Restore 在状态身份不匹配时不停止进程、不删状态、不改配置。

- [ ] **Step 2: Implement authorized Codex restart**

  `--prompt-restart` 使用 Windows Forms Yes/No 对话框；只有 Yes 才将 `restartExisting=true`。关闭时先对经路径核验的根进程调用 `CloseMainWindow()` 并等待 15 秒，仍未退出且已有显式授权时才 `Stop-Process`；不按名称批量杀进程。

- [ ] **Step 3: Launch Codex with loopback CDP**

  选择 9341 至 9441 的第一个空闲端口，使用隐藏 PowerShell 启动器直接运行已发现的 `app\ChatGPT.exe` 并只传：

  ```text
  --remote-debugging-address=127.0.0.1
  --remote-debugging-port=<selected-port>
  ```

  最多等待 35 秒，且只有端口所有者和 `/json/version` 同时通过身份核验才继续。

- [ ] **Step 4: Start and verify the injector daemon**

  使用 `Start-Process -WindowStyle Hidden -PassThru` 启动签名有效的 Node：`injector.mjs --watch --port <port> --theme-dir <dir>`，分别重定向 stdout/stderr。记录启动时间后运行一次 `injector.mjs --verify`；失败则停止刚启动且身份仍匹配的注入器、删除未提交状态并恢复 start 前配置。

- [ ] **Step 5: Implement Verify**

  Verify 先核验状态端口属于 Codex，再执行现有 `injector.mjs --verify`，可选 `--reload` 和 `--screenshot`。桌面入口默认把截图存到用户桌面并用 `Invoke-Item` 打开。

- [ ] **Step 6: Implement Restore**

  Restore 顺序固定：核验并停止记录的注入器；如果 CDP 仍可信则执行 `--remove` 并验证；恢复 TOML 两键；需要重启时只关闭已核验的 Codex 包进程，然后通过 `shell:AppsFolder\<PackageFamilyName>!App` 正常启动；最后才删除状态。`--uninstall` 仅删除本项目创建且目标身份匹配的四个快捷方式。

- [ ] **Step 7: Run lifecycle source and isolated tests**

  Run: `node --test tests/windows-support.test.mjs tests/adaptive-theme.test.mjs`

  Expected: 所有静态契约和不触碰真实 Codex 的隔离测试 PASS。

- [ ] **Step 8: Commit**

  ```powershell
  git add scripts/start-dream-skin-windows.ps1 scripts/verify-dream-skin-windows.ps1 scripts/restore-dream-skin-windows.ps1 tests
  git commit -m "feat: add verified Windows lifecycle"
  ```

## Task 6: Implement Windows customization and override behavior

**Files:**
- Create: `scripts/customize-theme-windows.ps1`
- Test: `tests/windows-support.test.mjs`

- [ ] **Step 1: Write failing customization integration tests**

  用测试代码生成浅色和深色 BMP，分别运行 `--no-apply`；检查 `theme.json` 的 appearance 和三色来自图片。再传单个 `--accent #123456`，断言只有 accent 被覆盖，其他字段仍与图片派生值一致。传损坏图片时断言中文 warning 只出现一次并使用默认值。

- [ ] **Step 2: Implement GNU-style option parsing**

  手动解析并严格接受 `--image`、`--name`、`--tagline`、`--quote`、`--accent`、`--secondary`、`--highlight`、`--appearance`、`--no-apply`、`--reset-demo`；值选项后缺值或紧跟另一个 `--` 选项时立即中文报错，不创建主题目录或状态。

- [ ] **Step 3: Implement local image selection and preparation**

  未给 `--image` 时使用 `Microsoft.Win32.OpenFileDialog`，只返回本地选择结果，不把图片内容交给模型。源文件限制 50 MB；调用 `normalize-image-windows.ps1` 输出最长边 3200 px、质量 84 的 JPEG；输出限制 16 MB。

- [ ] **Step 4: Preserve analyzer override semantics**

  始终把准备后的图片传给 `analyze-image.mjs --format tsv`；用户显式提供的字段才追加到 analyzer 参数。严格验证 TSV 恰好四项，再调用 `write-theme.mjs custom`。分析器无法读图时允许其中文警告与默认值；分析器进程本身启动失败或返回结构错误则事务回滚。

- [ ] **Step 5: Apply only after theme commit**

  主题 JSON 成功写入后才删除旧 `background-*`；未指定 `--no-apply` 时调用 Start 的 `--prompt-restart`。任何失败都删除本次临时/准备图片并保留之前主题。

- [ ] **Step 6: Run customization tests**

  Run: `node --test tests/windows-support.test.mjs tests/auto-palette.test.mjs`

  Expected: 自动浅色、自动深色、全覆盖、单项覆盖、fallback 和失败清理全部 PASS。

- [ ] **Step 7: Commit**

  ```powershell
  git add scripts/customize-theme-windows.ps1 tests
  git commit -m "feat: customize themes on Windows"
  ```

## Task 7: Add a first-class Windows test and release path

**Files:**
- Create: `scripts/run-tests.mjs`
- Create: `tests/run-tests-windows.ps1`
- Modify: `package.json`
- Modify: `scripts/build-release.sh`
- Modify: `SKILL.md`

- [ ] **Step 1: Implement platform test dispatch**

  `scripts/run-tests.mjs` 使用 `spawnSync`；Windows 执行 `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File tests/run-tests-windows.ps1`，其他平台执行 `/bin/bash tests/run-tests.sh`，并原样继承 stdio/退出码。

- [ ] **Step 2: Implement Windows full static suite**

  Windows runner先用 PowerShell 发现并验证 Codex 可执行运行时 Node，再依次执行：PowerShell AST 解析全部 `.ps1`；运行时 Node `--check` 全部 `.mjs/.js`；扫描禁止 `app.asar` 写入；`injector --check-payload`；Node tests；临时自定义主题写入/删除；LF 与 CRLF TOML 深色/浅色安装/恢复 exact round trip；内置 demo 大小写路径保护；`doctor-windows.ps1`。

- [ ] **Step 3: Update package scripts**

  ```json
  {
    "scripts": {
      "test": "node ./scripts/run-tests.mjs",
      "doctor:macos": "./scripts/doctor-macos.sh",
      "doctor:windows": "powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/doctor-windows.ps1"
    }
  }
  ```

- [ ] **Step 4: Include all Windows files in the release manifest**

  将五个 `.cmd`、六个 Windows 生命周期脚本、normalizer、doctor、test runner、Windows tests 和 `docs/windows` 加入 `build-release.sh` 的 FILES 数组；保留现有凭据/元数据文件名扫描。

- [ ] **Step 5: Run full static verification**

  Run: `npm test`

  Expected: `PASS: Windows syntax, payload, palette, custom-theme, config round-trip, runtime identity, and doctor checks.`

- [ ] **Step 6: Commit**

  ```powershell
  git add package.json scripts/run-tests.mjs scripts/build-release.sh tests/run-tests-windows.ps1 SKILL.md
  git commit -m "test: add Windows release checks"
  ```

## Task 8: Execute the real-machine lifecycle

**Files:**
- Update: `docs/windows/适配报告.md`
- Runtime output only: `%LOCALAPPDATA%\CodexImmersiveSkin\verification\`

- [ ] **Step 1: Obtain explicit restart authorization**

  在关闭当前 Codex 前向用户明确说明：下一步会关闭并重启正在使用的 Codex Desktop，以加入仅绑定 `127.0.0.1` 的 CDP 参数；未经确认不执行。

- [ ] **Step 2: Generate a local non-IP test image**

  使用 `System.Drawing` 在临时目录生成纯色/渐变 JPEG，不添加到仓库；记录尺寸、文件字节数和 SHA-256，不在报告中写真实个人路径。

- [ ] **Step 3: Clean install**

  Run: `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File scripts\install-dream-skin-windows.ps1 --no-launch`

  Evidence: 安装目录存在、四个项目快捷方式存在且目标匹配、TOML 备份存在、doctor pass。

- [ ] **Step 4: Automatic palette customization**

  Run: installed `customize-theme-windows.ps1 --image <generated-image> --name "Windows 自动取色测试" --no-apply`

  Evidence: theme JSON 的 appearance/三色/fallback 状态与 analyzer 输出一致。

- [ ] **Step 5: Single-field override**

  Run: same customizer with `--accent #123456 --no-apply`.

  Evidence: accent 精确为 `#123456`，secondary/highlight 仍由同一图片派生。

- [ ] **Step 6: Start and live verify**

  Run Start with `--restart-existing`; then Verify with `--reload --screenshot <verification.png>`.

  Evidence: verified loopback listener belongs to Codex；JSON `pass=true`；截图存在；手动确认侧栏、输入、按钮和链接可用。

- [ ] **Step 7: Restore and confirm**

  Run Restore with `--restore-base-theme --restart-codex`.

  Evidence: injector identity-checked and stopped；DOM skin removed or session closed；TOML 恢复 exact original；端口不再监听；Codex 正常启动。

- [ ] **Step 8: Reinstall**

  再次运行安装和 Start，证明重复安装可用；记录每步通过/失败与命令输出摘要。

## Task 9: Finish user documentation and delivery report

**Files:**
- Modify: `README.md`
- Create: `docs/windows/README.md`
- Create: `docs/windows/观众部署提示词.md`
- Finalize: `docs/windows/适配报告.md`

- [ ] **Step 1: Add the README Windows section**

  只新增 Windows 准备、五入口、SmartScreen/当前进程执行策略、安装/定制/验证/恢复和“Codex 至少启动过一次以准备自身 Node 运行时”的前提；不改顶部非官方声明、MIT 上游归属、创意参考和素材免责声明。

- [ ] **Step 2: Write the Windows guide**

  明确 Store/MSIX 安装形态、`%USERPROFILE%`/`%LOCALAPPDATA%` 通用位置、完整仓库要求、右键“以 PowerShell 运行”与 `.cmd` 双击方式、核验 ZIP 哈希后仅对该 ZIP 解除锁定、当前进程 RemoteSigned、恢复和端口风险。绝不建议修改 Machine/User 级执行策略或关闭 SmartScreen。

- [ ] **Step 3: Write the viewer deployment prompt**

  保留 macOS 参考提示词的谨慎向导、先读文档、三句归属、不看用户图片、只用现有入口、保留 Restore、逐步确认和不做侵权/官方背书保证；将 Gatekeeper/`.command`/Finder 全部替换为 SmartScreen/PowerShell/Windows 文件选择器与五个 Windows 入口。

- [ ] **Step 4: Complete the report**

  报告包含环境、每个真机步骤的结果与证据、macOS/Windows 差异表、所有实测坑与最小范围解法、未验证事项、是否可发给观众的结论。失败或未执行步骤只能写“失败”或“未验证”，不能写推测性通过。

- [ ] **Step 5: Verify legal, privacy and safety language**

  Run:

  ```powershell
  rg -n "原创|官方项目|首发|绝对不侵权|免费商用|关闭 SmartScreen|Set-ExecutionPolicy.+(LocalMachine|CurrentUser)|C:\\Users\\" README.md docs/windows
  git diff --exit-code -- LICENSE NOTICE.md
  ```

  Expected: 禁止性措辞无不当命中；LICENSE 与 NOTICE.md 零改动。

- [ ] **Step 6: Run final verification**

  Run: `npm test`

  Run: `git diff --check`

  Run: `git status --short --branch`

  Expected: 全部测试 PASS、无 whitespace error、分支为 `windows-support`。

- [ ] **Step 7: Commit documentation**

  ```powershell
  git add README.md docs/windows SKILL.md
  git commit -m "docs: publish Windows setup and validation report"
  ```

- [ ] **Step 8: Push or package without force**

  先运行 `git push -u origin windows-support`。如果权限或登录失败，不重试强推；创建本地 `git bundle` 与工作树 ZIP，报告其工作区相对位置和 SHA-256。

## Self-review

- Spec coverage: 五入口、自动/部分覆盖、真实路径、SmartScreen/执行策略、完整真机顺序、报告、观众提示词、分支纪律、协议/归属、素材、隐私和恢复均有对应任务。
- Placeholder scan: 文档没有 `TBD`、`TODO` 或“稍后实现”步骤。
- Type/option consistency: 对外选项统一为 GNU 长选项；PowerShell 入口手动解析并转交 Node；端口、状态和主题目录字段在 Start/Verify/Restore 中一致。
- Safety: 所有进程停止都先做身份校验；所有安全策略放宽仅限新启动的 PowerShell 进程；不修改 MSIX、`app.asar`、LICENSE 或 NOTICE。
