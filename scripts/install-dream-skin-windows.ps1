#requires -Version 5.1

[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Arguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:SourceRoot = [IO.Path]::GetFullPath((Join-Path $script:ScriptDir '..'))
. (Join-Path $script:ScriptDir 'common-windows.ps1')
. (Join-Path $script:ScriptDir 'lifecycle-windows.ps1')

$script:InstallRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_INSTALL_ROOT' `
  -DefaultPath (Join-Path $env:USERPROFILE '.codex\codex-immersive-skin')
$script:StateRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_STATE_ROOT' `
  -DefaultPath (Join-Path $env:LOCALAPPDATA 'CodexImmersiveSkin')
$script:ConfigPath = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_CONFIG_PATH' `
  -DefaultPath (Join-Path $env:USERPROFILE '.codex\config.toml')
$script:ThemeDir = Join-Path $script:StateRoot 'theme'
$script:InstallIdentityName = '.codex-immersive-skin-install.json'
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Read-InstallOptions {
  param([string[]]$Values)

  $result = [ordered]@{
    Port = 9341
    CreateLaunchers = $true
    LaunchAfterInstall = $true
    InPlace = $false
  }
  for ($index = 0; $index -lt $Values.Count; $index++) {
    $value = [string]$Values[$index]
    switch -CaseSensitive ($value) {
      '--port' {
        if ($index + 1 -ge $Values.Count -or ([string]$Values[$index + 1]).StartsWith('--')) {
          throw '选项 --port 需要一个端口值。'
        }
        $parsed = 0
        if (-not [int]::TryParse([string]$Values[++$index], [ref]$parsed) -or
            $parsed -lt 1024 -or $parsed -gt 65535) {
          throw '端口必须是 1024 到 65535 之间的整数。'
        }
        $result.Port = $parsed
      }
      '--no-launchers' { $result.CreateLaunchers = $false }
      '--no-launch' { $result.LaunchAfterInstall = $false }
      '--in-place' { $result.InPlace = $true }
      default { throw "未知安装参数：$value" }
    }
  }
  [pscustomobject]$result
}

function Remove-VerifiedInstallTree {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedPrefix
  )

  if (-not (Test-Path -LiteralPath $Path)) { return }
  $parent = Split-Path -Parent $script:InstallRoot
  $resolved = [IO.Path]::GetFullPath($Path)
  $leaf = Split-Path -Leaf $resolved
  if (-not (Test-CodexWindowsPathWithin -Path $resolved -Root $parent) -or
      -not $leaf.StartsWith($ExpectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-CodexWindowsPathChainNoReparse -Path $resolved -Boundary $parent) -or
      -not (Test-CodexWindowsTreeNoReparse -Path $resolved)) {
    throw '拒绝删除未通过身份检查的安装临时目录。'
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Copy-ProjectTree {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (Test-Path -LiteralPath $Destination) { throw '安装暂存目录已存在。' }
  if (-not (Test-CodexWindowsTreeNoReparse -Path $Source)) {
    throw '源项目包含重解析点，已拒绝复制。'
  }
  [void](New-Item -ItemType Directory -Path $Destination)
  $excluded = @('.git', '.DS_Store', 'release', 'runtime')
  foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
    if ($excluded -contains $item.Name) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
  if (-not (Test-CodexWindowsTreeNoReparse -Path $Destination)) {
    throw '安装暂存目录包含重解析点，已停止。'
  }
}

function Write-InstallIdentity {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$InstalledRoot
  )

  $identity = [ordered]@{
    schemaVersion = 1
    product = 'Codex Immersive Skin'
    installedRoot = [IO.Path]::GetFullPath($InstalledRoot)
    version = ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim()
  }
  [IO.File]::WriteAllText(
    (Join-Path $Root $script:InstallIdentityName),
    ($identity | ConvertTo-Json -Depth 3) + "`n",
    $script:Utf8NoBom
  )
}

function Assert-OwnedInstallTree {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$ExpectedInstalledRoot = $Root
  )

  if (-not (Test-Path -LiteralPath $Root -PathType Container) -or
      -not (Test-CodexWindowsTreeNoReparse -Path $Root)) {
    throw '现有安装目录不是可安全替换的普通目录。'
  }
  $identityPath = Join-Path $Root $script:InstallIdentityName
  if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf)) {
    throw '现有目标目录没有本项目的安装身份标记；已拒绝替换。'
  }
  try { $identity = Read-CodexWindowsUtf8Text -Path $identityPath | ConvertFrom-Json }
  catch { throw '现有安装身份标记无法解析；已拒绝替换。' }
  if ([int]$identity.schemaVersion -ne 1 -or
      [string]$identity.product -ne 'Codex Immersive Skin' -or
      -not (Test-CodexWindowsPathEqual -First ([string]$identity.installedRoot) -Second $ExpectedInstalledRoot) -or
      -not (Test-Path -LiteralPath (Join-Path $Root 'VERSION') -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $Root 'scripts\install-dream-skin-windows.ps1') -PathType Leaf)) {
    throw '现有目标目录的项目身份不匹配；已拒绝替换。'
  }
}

function Recover-InterruptedInstallTransaction {
  $parent = Split-Path -Parent $script:InstallRoot
  $prefix = (Split-Path -Leaf $script:InstallRoot) + '.previous.'
  $previousCandidates = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop | Where-Object {
    $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
  })
  foreach ($candidate in $previousCandidates) {
    if (-not (Test-CodexWindowsPathChainNoReparse -Path $candidate.FullName -Boundary $parent)) {
      throw '检测到经过重解析点的遗留安装事务目录；已停止自动恢复。'
    }
    Assert-OwnedInstallTree -Root $candidate.FullName -ExpectedInstalledRoot $script:InstallRoot
  }
  if (-not (Test-Path -LiteralPath $script:InstallRoot)) {
    if ($previousCandidates.Count -gt 1) {
      throw '检测到多个遗留旧安装，无法安全判断恢复顺序。'
    }
    if ($previousCandidates.Count -eq 1) {
      Move-Item -LiteralPath $previousCandidates[0].FullName -Destination $script:InstallRoot
      Write-Warning '已恢复上次意外中断前的安装目录。'
    }
  } elseif ($previousCandidates.Count -gt 0) {
    Write-Warning '检测到遗留的 .previous 安装目录；当前安装保持不变，待本次成功后人工核对。'
  }
}

function Get-DesktopLaunchers {
  $desktop = [Environment]::GetFolderPath('DesktopDirectory')
  if ([string]::IsNullOrWhiteSpace($desktop)) { throw '无法解析当前用户的桌面目录。' }
  @(
    [pscustomobject]@{ Name = 'Codex Immersive Skin.lnk'; Script = 'start-dream-skin-windows.ps1'; Extra = '--prompt-restart' },
    [pscustomobject]@{ Name = 'Codex Immersive Skin - Customize.lnk'; Script = 'customize-theme-windows.ps1'; Extra = '' },
    [pscustomobject]@{ Name = 'Codex Immersive Skin - Verify.lnk'; Script = 'verify-dream-skin-windows.ps1'; Extra = '' },
    [pscustomobject]@{ Name = 'Codex Immersive Skin - Restore.lnk'; Script = 'restore-dream-skin-windows.ps1'; Extra = '--restore-base-theme --restart-codex' }
  ) | ForEach-Object {
    $_ | Add-Member -MemberType NoteProperty -Name Path -Value (Join-Path $desktop $_.Name) -Force
    $_
  }
}

function Assert-OwnedOrAbsentShortcut {
  param(
    [Parameter(Mandatory = $true)]$Launcher,
    [Parameter(Mandatory = $true)][string]$ActiveRoot
  )

  if (-not (Test-Path -LiteralPath $Launcher.Path)) { return }
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($Launcher.Path)
  if ($shortcut.Description -ne 'CodexImmersiveSkin launcher') {
    throw "拒绝覆盖不属于本项目的桌面文件：$($Launcher.Name)"
  }
  $expectedPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $expectedScript = Join-Path (Join-Path $ActiveRoot 'scripts') $Launcher.Script
  $argv = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine('powershell.exe ' + $shortcut.Arguments))
  $expectedTail = @(if ([string]::IsNullOrWhiteSpace($Launcher.Extra)) { } else { $Launcher.Extra -split ' ' })
  $baseValid = $argv.Count -eq (8 + $expectedTail.Count) -and
    $argv[1] -eq '-NoLogo' -and $argv[2] -eq '-NoProfile' -and $argv[3] -eq '-STA' -and
    $argv[4] -eq '-ExecutionPolicy' -and $argv[5] -eq 'RemoteSigned' -and $argv[6] -eq '-File'
  $tailValid = $true
  for ($index = 0; $index -lt $expectedTail.Count; $index++) {
    if ($argv[8 + $index] -ne $expectedTail[$index]) { $tailValid = $false; break }
  }
  if (-not $baseValid -or -not $tailValid -or
      -not (Test-CodexWindowsPathEqual -First $shortcut.TargetPath -Second $expectedPowerShell) -or
      -not (Test-CodexWindowsPathEqual -First $argv[7] -Second $expectedScript)) {
    throw "拒绝覆盖身份不匹配的桌面快捷方式：$($Launcher.Name)"
  }
}

function Write-OwnedShortcut {
  param(
    [Parameter(Mandatory = $true)]$Launcher,
    [Parameter(Mandatory = $true)][string]$ActiveRoot,
    [Parameter(Mandatory = $true)]$PackageInfo
  )

  $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw '系统 Windows PowerShell 不存在。'
  }
  $targetScript = Join-Path (Join-Path $ActiveRoot 'scripts') $Launcher.Script
  if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) {
    throw "安装包缺少脚本：$($Launcher.Script)"
  }
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($Launcher.Path)
  $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "{0}"' -f $targetScript
  if (-not [string]::IsNullOrWhiteSpace($Launcher.Extra)) { $arguments += ' ' + $Launcher.Extra }
  $shortcut.TargetPath = $powerShell
  $shortcut.Arguments = $arguments
  $shortcut.WorkingDirectory = $ActiveRoot
  $shortcut.IconLocation = ([string]$PackageInfo.AppExecutable) + ',0'
  $shortcut.Description = 'CodexImmersiveSkin launcher'
  $shortcut.Save()
}

function Invoke-Node {
  param(
    [Parameter(Mandatory = $true)]$RuntimeInfo,
    [Parameter(Mandatory = $true)][string[]]$NodeArguments
  )
  $result = Invoke-CodexWindowsNode -RuntimeInfo $RuntimeInfo -Arguments $NodeArguments
  if ($result.ExitCode -ne 0) { throw "Node 子进程失败，退出码 $($result.ExitCode)。" }
  ($result.Output -join "`n")
}

$options = Read-InstallOptions -Values @(ConvertTo-CodexWindowsRemainingArguments -Values $Arguments)
$operationLock = Open-CodexWindowsOperationLock -StateRoot $script:StateRoot
try {
$runtime = Initialize-WindowsRuntime
$package = $runtime.PackageInfo
if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
  throw '未找到 Codex 配置。请先正常启动 Codex 至少一次，然后重试。'
}

Assert-CodexWindowsStateRoot -Path $script:StateRoot -Create
$installParent = Split-Path -Parent $script:InstallRoot
[void](New-Item -ItemType Directory -Path $installParent -Force)
$installBoundary = if ($env:CODEX_IMMERSIVE_TEST_MODE -eq '1') {
  [IO.Path]::GetFullPath($env:CODEX_IMMERSIVE_TEST_ROOT)
} else { [IO.Path]::GetFullPath($env:USERPROFILE) }
if (-not (Test-CodexWindowsPathChainNoReparse -Path $script:InstallRoot -Boundary $installBoundary)) {
  throw '安装目标路径包含或经过重解析点。'
}
Recover-InterruptedInstallTransaction

$transactionId = '{0}.{1}' -f $PID, [Guid]::NewGuid().ToString('N')
$staging = $script:InstallRoot + '.installing.' + $transactionId
$previous = $script:InstallRoot + '.previous.' + $transactionId
$failed = $script:InstallRoot + '.failed.' + $transactionId
$rollbackRoot = Join-Path $script:StateRoot ('install-rollback.' + $transactionId)
$deployed = $false
$previousExists = $false
$committed = $false
$launcherRollbackReady = $false
$launcherOriginalPresence = @{}
$launcherBackupHashes = @{}
$launcherTouched = @{}
$launcherWrittenHashes = @{}
$launchers = @(Get-DesktopLaunchers)
$activeRoot = if (-not $options.InPlace -and
    -not (Test-CodexWindowsPathEqual -First $script:SourceRoot -Second $script:InstallRoot)) {
  $script:InstallRoot
} else { $script:SourceRoot }

try {
  if (-not $options.InPlace -and
      -not (Test-CodexWindowsPathEqual -First $script:SourceRoot -Second $script:InstallRoot) -and
      (Test-Path -LiteralPath $script:InstallRoot)) {
    Assert-OwnedInstallTree -Root $script:InstallRoot
  }
  if ($options.CreateLaunchers) {
    foreach ($launcher in $launchers) {
      Assert-OwnedOrAbsentShortcut -Launcher $launcher -ActiveRoot $activeRoot
    }
  }
  [void](New-Item -ItemType Directory -Path $rollbackRoot)
  if ($options.CreateLaunchers) {
    [void](New-Item -ItemType Directory -Path (Join-Path $rollbackRoot 'launchers'))
    foreach ($launcher in $launchers) {
      $launcherOriginalPresence[$launcher.Name] = Test-Path -LiteralPath $launcher.Path -PathType Leaf
      if ($launcherOriginalPresence[$launcher.Name]) {
        $launcherBackup = Join-Path (Join-Path $rollbackRoot 'launchers') $launcher.Name
        Copy-Item -LiteralPath $launcher.Path -Destination $launcherBackup -Force
        $launcherBackupHashes[$launcher.Name] = (Get-FileHash -Algorithm SHA256 -LiteralPath $launcherBackup).Hash
      }
    }
    $launcherRollbackReady = $true
  }

  if (-not $options.InPlace -and
      -not (Test-CodexWindowsPathEqual -First $script:SourceRoot -Second $script:InstallRoot)) {
    Copy-ProjectTree -Source $script:SourceRoot -Destination $staging
    Write-InstallIdentity -Root $staging -InstalledRoot $script:InstallRoot
    Assert-OwnedInstallTree -Root $staging -ExpectedInstalledRoot $script:InstallRoot
    if (Test-Path -LiteralPath $script:InstallRoot) {
      Assert-OwnedInstallTree -Root $script:InstallRoot
      Move-Item -LiteralPath $script:InstallRoot -Destination $previous
      $previousExists = $true
    }
    Move-Item -LiteralPath $staging -Destination $script:InstallRoot
    $deployed = $true
  }

  $injector = Join-Path $activeRoot 'scripts\injector.mjs'
  $payloadText = Invoke-Node -RuntimeInfo $runtime -NodeArguments @(
    $injector, '--check-payload', '--theme-dir', $script:ThemeDir
  )
  $payload = $payloadText | ConvertFrom-Json
  if (-not $payload.pass) { throw '主题载荷检查失败。' }
  if ($options.CreateLaunchers) {
    foreach ($launcher in $launchers) {
      $originalPresent = [bool]$launcherOriginalPresence[$launcher.Name]
      if ($originalPresent) {
        if (-not (Test-Path -LiteralPath $launcher.Path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $launcher.Path).Hash -ne $launcherBackupHashes[$launcher.Name]) {
          throw "桌面快捷方式在安装期间被其他程序修改；已停止覆盖：$($launcher.Name)"
        }
        Assert-OwnedOrAbsentShortcut -Launcher $launcher -ActiveRoot $activeRoot
      } elseif (Test-Path -LiteralPath $launcher.Path) {
        throw "桌面快捷方式在安装期间由其他程序创建；已停止覆盖：$($launcher.Name)"
      }
      Write-OwnedShortcut -Launcher $launcher -ActiveRoot $activeRoot -PackageInfo $package
      $launcherTouched[$launcher.Name] = $true
      $launcherWrittenHashes[$launcher.Name] = (Get-FileHash -Algorithm SHA256 -LiteralPath $launcher.Path).Hash
    }
  }

  if ($options.LaunchAfterInstall) {
    & (Join-Path $activeRoot 'scripts\start-dream-skin-windows.ps1') '--port' ([string]$options.Port) '--prompt-restart'
  }
  else {
    [IO.File]::WriteAllText(
      (Join-Path $script:StateRoot 'preferred-port'),
      ([string]$options.Port) + "`n",
      $script:Utf8NoBom
    )
  }

  $committed = $true
  if ($previousExists) {
    try {
      Remove-VerifiedInstallTree -Path $previous -ExpectedPrefix ((Split-Path -Leaf $script:InstallRoot) + '.previous.')
    }
    catch { Write-Warning '安装已成功，但旧版本清理失败；请稍后手动检查同级的 .previous 临时目录。' }
  }
  try {
    if (-not (Test-CodexWindowsTreeNoReparse -Path $rollbackRoot)) { throw '事务备份目录包含重解析点。' }
    Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
  }
  catch { Write-Warning '安装已成功，但事务备份目录未能清理。' }
  $safeInstall = ConvertTo-CodexSafePath $activeRoot
  Write-Host "Codex Immersive Skin 已安装到 $safeInstall。"
  Write-Host '可使用桌面快捷方式进行定制、启动、验证和恢复。'
}
catch {
  $originalError = $_
  $rollbackErrors = New-Object Collections.ArrayList

  if ($deployed -and (Test-Path -LiteralPath $script:InstallRoot)) {
    try {
      Assert-OwnedInstallTree -Root $script:InstallRoot
      Move-Item -LiteralPath $script:InstallRoot -Destination $failed
    }
    catch { [void]$rollbackErrors.Add('新安装隔离失败') }
  }
  if ($previousExists -and (Test-Path -LiteralPath $previous)) {
    try {
      if (Test-Path -LiteralPath $script:InstallRoot) { throw '目标仍被占用。' }
      Assert-OwnedInstallTree -Root $previous -ExpectedInstalledRoot $script:InstallRoot
      Move-Item -LiteralPath $previous -Destination $script:InstallRoot
    }
    catch { [void]$rollbackErrors.Add('旧安装恢复失败') }
  }

  if ($launcherRollbackReady) {
    foreach ($launcher in $launchers) {
      if (-not $launcherTouched.ContainsKey($launcher.Name) -or
          -not [bool]$launcherTouched[$launcher.Name]) { continue }
      try {
        $backup = Join-Path (Join-Path $rollbackRoot 'launchers') $launcher.Name
        $originalPresent = [bool]$launcherOriginalPresence[$launcher.Name]
        if ($originalPresent) {
          if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw '原快捷方式事务备份缺失。'
          }
          if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash -ne $launcherBackupHashes[$launcher.Name]) {
            throw '原快捷方式事务备份哈希不匹配。'
          }
        }
        if (-not $launcherWrittenHashes.ContainsKey($launcher.Name)) {
          throw '本事务写入的快捷方式哈希缺失。'
        }
        if (-not (Test-Path -LiteralPath $launcher.Path -PathType Leaf)) {
          if ($originalPresent) { throw '本事务写入的快捷方式已被移除。' }
          continue
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $launcher.Path).Hash -ne
            $launcherWrittenHashes[$launcher.Name]) {
          throw '本事务写入后快捷方式又被修改；已保留当前文件和恢复材料。'
        }
        Remove-Item -LiteralPath $launcher.Path -Force
        if ($originalPresent) { Copy-Item -LiteralPath $backup -Destination $launcher.Path -Force }
      }
      catch { [void]$rollbackErrors.Add("快捷方式恢复失败：$($launcher.Name)") }
    }
  }
  if (Test-Path -LiteralPath $failed) {
    try {
      Remove-VerifiedInstallTree -Path $failed -ExpectedPrefix ((Split-Path -Leaf $script:InstallRoot) + '.failed.')
    }
    catch { [void]$rollbackErrors.Add('失败安装目录清理失败') }
  }
  if (Test-Path -LiteralPath $staging) {
    try {
      Remove-VerifiedInstallTree -Path $staging -ExpectedPrefix ((Split-Path -Leaf $script:InstallRoot) + '.installing.')
    }
    catch { [void]$rollbackErrors.Add('安装暂存目录清理失败') }
  }
  if ($rollbackErrors.Count -eq 0 -and (Test-Path -LiteralPath $rollbackRoot)) {
    try {
      if (-not (Test-CodexWindowsTreeNoReparse -Path $rollbackRoot)) { throw '事务备份目录包含重解析点。' }
      Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
    }
    catch { [void]$rollbackErrors.Add('事务备份目录清理失败') }
  }
  foreach ($rollbackError in $rollbackErrors) {
    Write-Warning "安装回滚警告：$rollbackError。恢复材料已尽量保留。"
  }
  throw $originalError
}
finally {
  if (-not $committed -and (Test-Path -LiteralPath $staging)) {
    try { Remove-VerifiedInstallTree -Path $staging -ExpectedPrefix ((Split-Path -Leaf $script:InstallRoot) + '.installing.') } catch { }
  }
}
}
finally {
  Close-CodexWindowsOperationLock -Lock $operationLock
}
