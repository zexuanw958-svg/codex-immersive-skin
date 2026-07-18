#requires -Version 5.1

[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Arguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:ScriptDir 'common-windows.ps1')
. (Join-Path $script:ScriptDir 'lifecycle-windows.ps1')
$script:StateRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_STATE_ROOT' `
  -DefaultPath (Join-Path $env:LOCALAPPDATA 'CodexImmersiveSkin')
$script:InstallRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_INSTALL_ROOT' `
  -DefaultPath (Join-Path $env:USERPROFILE '.codex\codex-immersive-skin')
$script:StatePath = Join-Path $script:StateRoot 'state.json'
$script:ThemeBackupPath = Join-Path $script:StateRoot 'theme-backup.json'
$script:ThemeDir = Join-Path $script:StateRoot 'theme'
$script:ConfigPath = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_CONFIG_PATH' `
  -DefaultPath (Join-Path $env:USERPROFILE '.codex\config.toml')
$script:Injector = Join-Path $script:ScriptDir 'injector.mjs'

function Read-RestoreOptions {
  param([string[]]$Values)
  $result = [ordered]@{
    Port = 9341
    PortExplicit = $false
    RestoreBaseTheme = $false
    RestartCodex = $false
    Uninstall = $false
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
            $parsed -lt 1024 -or $parsed -gt 65535) { throw '端口值无效。' }
        $result.Port = $parsed
        $result.PortExplicit = $true
      }
      '--restore-base-theme' { $result.RestoreBaseTheme = $true }
      '--restart-codex' { $result.RestartCodex = $true }
      '--uninstall' { $result.Uninstall = $true }
      default { throw "未知恢复参数：$value" }
    }
  }
  [pscustomobject]$result
}

function Test-VerifiedCodexMainIdentity {
  param($Identity, $PackageInfo)

  if (-not (Test-CodexWindowsPathEqual -First $Identity.Path -Second $PackageInfo.AppExecutable) -or
      -not [string]::Equals([string]$Identity.PackageFullName, [string]$PackageInfo.PackageFullName, [StringComparison]::Ordinal) -or
      [int]$Identity.PackageOrigin -ne 3) { return $false }
  $argv = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine($Identity.CommandLine))
  if ($argv.Count -lt 1 -or
      -not (Test-CodexWindowsPathEqual -First $argv[0] -Second $PackageInfo.AppExecutable) -or
      @($argv | Where-Object { ([string]$_).StartsWith('--type=') }).Count -gt 0) { return $false }
  return $true
}

function Test-CodexRemoteDebugMainIdentity {
  param($Identity)
  $argv = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine($Identity.CommandLine))
  return @($argv | Where-Object {
    ([string]$_).StartsWith('--remote-debugging-', [StringComparison]::OrdinalIgnoreCase)
  }).Count -gt 0
}

function Get-VerifiedCodexMainProcesses {
  param($PackageInfo)
  $result = @()
  foreach ($process in @(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue)) {
    try {
      $identity = Get-CodexWindowsProcessIdentity -ProcessId $process.Id
      if (-not (Test-VerifiedCodexMainIdentity -Identity $identity -PackageInfo $PackageInfo)) { continue }
      $result += [pscustomobject]@{ Process = $process; Identity = $identity }
    } catch { }
  }
  $result
}

function Stop-VerifiedCodex {
  param($PackageInfo)
  $mains = @(Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo)
  $originals = @{}
  foreach ($entry in $mains) {
    $fresh = Get-CodexWindowsProcessIdentity -ProcessId $entry.Process.Id
    if (-not (Test-VerifiedCodexMainIdentity -Identity $fresh -PackageInfo $PackageInfo) -or
        $fresh.StartTimeUtc -ne $entry.Identity.StartTimeUtc) {
      throw 'Codex 进程身份在温和关闭前发生变化。'
    }
    $originals[[int]$entry.Process.Id] = $entry.Identity
    [void](Request-CodexWindowsVerifiedMainWindowClose -Identity $fresh)
  }
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  do {
    Start-Sleep -Milliseconds 250
    $remaining = @(Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo)
  } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
  foreach ($entry in $remaining) {
    if (-not $originals.ContainsKey([int]$entry.Process.Id)) {
      throw '关闭期间出现新的 Codex 主进程，已拒绝强制终止。'
    }
    $originalIdentity = $originals[[int]$entry.Process.Id]
    $fresh = Get-CodexWindowsProcessIdentity -ProcessId $entry.Process.Id
    if (-not (Test-VerifiedCodexMainIdentity -Identity $fresh -PackageInfo $PackageInfo) -or
        $fresh.StartTimeUtc -ne $originalIdentity.StartTimeUtc) {
      throw 'Codex 进程身份在关闭前发生变化，已拒绝终止。'
    }
    Stop-CodexWindowsVerifiedProcess -Identity $fresh -TimeoutMs 6000
  }
  Start-Sleep -Milliseconds 500
  if (@(Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo).Count -gt 0) {
    throw '经过身份验证的 Codex 主进程仍未退出。'
  }
}

function Start-CodexNormally {
  param($PackageInfo)
  $explorer = Join-Path $env:SystemRoot 'explorer.exe'
  $existing = @(Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo)
  if ($existing.Count -gt 0) {
    if (@($existing | Where-Object { Test-CodexRemoteDebugMainIdentity -Identity $_.Identity }).Count -gt 0) {
      throw '仍检测到带远程调试参数的 Codex，已拒绝把它当作正常启动。'
    }
    return
  }
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    Start-Process -FilePath $explorer -ArgumentList ('shell:AppsFolder\' + $PackageInfo.AppUserModelId)
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
      $mains = @(Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo)
      if (@($mains | Where-Object { Test-CodexRemoteDebugMainIdentity -Identity $_.Identity }).Count -gt 0) {
        throw 'AppsFolder 启动后仍出现远程调试参数，正常恢复已停止。'
      }
      if ($mains.Count -gt 0) { return }
      Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
  }
  throw 'Windows 未能通过已验证的 AppsFolder 身份正常启动 Codex。'
}

function Stop-RecordedInjector {
  param($State, $RuntimeInfo)
  if ($null -eq $State) { return }
  $process = Get-Process -Id ([int]$State.injectorPid) -ErrorAction SilentlyContinue
  if ($null -eq $process) { return }
  $expectedInjector = Resolve-CodexWindowsRecordedInjectorPath -State $State `
    -CurrentInjectorPath $script:Injector -InstallRoot $script:InstallRoot
  if (-not (Test-CodexWindowsRecordedInjector -State $State -RuntimeInfo $RuntimeInfo `
      -ExpectedInjectorPath $expectedInjector)) {
    throw '已记录的注入器身份不匹配；为避免误停其他进程，恢复已停止且状态被保留。'
  }
  $identity = Get-CodexWindowsProcessIdentity -ProcessId ([int]$State.injectorPid)
  if ($identity.StartTimeUtc -ne [string]$State.injectorStartedAt -or
      -not (Test-CodexWindowsPathEqual -First $identity.Path -Second $RuntimeInfo.NodePath)) {
    throw '注入器身份在终止前发生变化；恢复已停止且状态被保留。'
  }
  Stop-CodexWindowsVerifiedProcess -Identity $identity -TimeoutMs 6000
}

function Remove-OwnedDesktopLaunchers {
  param([switch]$ValidateOnly)
  $desktop = [Environment]::GetFolderPath('DesktopDirectory')
  $launchers = @(
    [pscustomobject]@{ Name = 'Codex Immersive Skin.lnk'; Script = 'start-dream-skin-windows.ps1'; Extra = @('--prompt-restart') },
    [pscustomobject]@{ Name = 'Codex Immersive Skin - Customize.lnk'; Script = 'customize-theme-windows.ps1'; Extra = @() },
    [pscustomobject]@{ Name = 'Codex Immersive Skin - Verify.lnk'; Script = 'verify-dream-skin-windows.ps1'; Extra = @() },
    [pscustomobject]@{ Name = 'Codex Immersive Skin - Restore.lnk'; Script = 'restore-dream-skin-windows.ps1'; Extra = @('--restore-base-theme', '--restart-codex') }
  )
  $shell = New-Object -ComObject WScript.Shell
  $expectedPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $ownedPaths = New-Object Collections.ArrayList
  foreach ($launcher in $launchers) {
    $path = Join-Path $desktop $launcher.Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $shortcut = $shell.CreateShortcut($path)
    if ($shortcut.Description -ne 'CodexImmersiveSkin launcher') {
      throw "拒绝删除不属于本项目的桌面文件：$($launcher.Name)"
    }
    $argv = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine('powershell.exe ' + $shortcut.Arguments))
    $expectedScript = Join-Path $script:ScriptDir $launcher.Script
    $installedScript = Join-Path (Join-Path $script:InstallRoot 'scripts') $launcher.Script
    $scriptIdentityValid = (Test-CodexWindowsPathEqual -First $argv[7] -Second $expectedScript) -or
      ((Test-CodexWindowsPathEqual -First $argv[7] -Second $installedScript) -and
        (Test-CodexWindowsOwnedInstallRoot -Root $script:InstallRoot))
    $baseValid = $argv.Count -eq (8 + $launcher.Extra.Count) -and
      $argv[1] -eq '-NoLogo' -and $argv[2] -eq '-NoProfile' -and $argv[3] -eq '-STA' -and
      $argv[4] -eq '-ExecutionPolicy' -and $argv[5] -eq 'RemoteSigned' -and $argv[6] -eq '-File'
    $tailValid = $baseValid
    if ($baseValid) {
      for ($index = 0; $index -lt $launcher.Extra.Count; $index++) {
        if ($argv[8 + $index] -ne $launcher.Extra[$index]) { $tailValid = $false; break }
      }
    }
    if (-not $baseValid -or -not $tailValid -or
        -not (Test-CodexWindowsPathEqual -First $shortcut.TargetPath -Second $expectedPowerShell) -or
        -not $scriptIdentityValid) {
      throw "拒绝删除身份不匹配的桌面快捷方式：$($launcher.Name)"
    }
    [void]$ownedPaths.Add($path)
  }
  foreach ($path in $ownedPaths) {
    if (-not $ValidateOnly) { Remove-Item -LiteralPath $path -Force }
  }
}

$options = Read-RestoreOptions -Values @(ConvertTo-CodexWindowsRemainingArguments -Values $Arguments)
$operationLock = Open-CodexWindowsOperationLock -StateRoot $script:StateRoot
try {
Assert-CodexWindowsStateRoot -Path $script:StateRoot
$runtime = Initialize-WindowsRuntime
$package = $runtime.PackageInfo
$state = Read-CodexWindowsState -Path $script:StatePath
if (-not $options.PortExplicit -and $null -ne $state) { $options.Port = [int]$state.port }

$codexRunning = @(Get-VerifiedCodexMainProcesses -PackageInfo $package).Count -gt 0
$debugReady = Test-CodexWindowsCdpEndpoint -Port $options.Port -PackageInfo $package

if ($codexRunning -and -not $options.RestartCodex) {
  throw 'Codex 仍在运行；为关闭 CDP 并避免配置写入竞争，恢复需要 --restart-codex。'
}

if ($null -ne $state -and
    $null -ne (Get-Process -Id ([int]$state.injectorPid) -ErrorAction SilentlyContinue)) {
  $expectedRecordedInjector = Resolve-CodexWindowsRecordedInjectorPath -State $state `
    -CurrentInjectorPath $script:Injector -InstallRoot $script:InstallRoot
  if (-not (Test-CodexWindowsRecordedInjector -State $state -RuntimeInfo $runtime `
      -ExpectedInjectorPath $expectedRecordedInjector)) {
    throw '已记录的注入器身份不匹配；恢复在触碰进程前停止。'
  }
}

if ($options.RestoreBaseTheme) {
  $validateResult = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments @(
    (Join-Path $script:ScriptDir 'theme-config.mjs'), 'restore',
    $script:ConfigPath, $script:ThemeBackupPath, '--validate-only'
  )
  if ($validateResult.ExitCode -ne 0) { throw 'Codex 基础主题恢复材料未通过只读校验。' }
}
if ($options.Uninstall) { [void](Remove-OwnedDesktopLaunchers -ValidateOnly) }

Stop-RecordedInjector -State $state -RuntimeInfo $runtime

$debugReady = Test-CodexWindowsCdpEndpoint -Port $options.Port -PackageInfo $package
if ($debugReady) {
  $removeResult = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments @(
    $script:Injector, '--remove', '--port', [string]$options.Port,
    '--theme-dir', $script:ThemeDir, '--timeout-ms', '8000'
  )
  if ($removeResult.ExitCode -ne 0) {
    throw '实时主题未能安全移除并验证；恢复已停止。'
  }
}

$currentMains = @(Get-VerifiedCodexMainProcesses -PackageInfo $package)
if ($currentMains.Count -gt 0) {
  if (-not $options.RestartCodex) {
    throw '恢复期间出现 Codex 主进程；需要 --restart-codex 才能继续。'
  }
  Stop-VerifiedCodex -PackageInfo $package
}
if (@(Get-VerifiedCodexMainProcesses -PackageInfo $package).Count -gt 0) {
  throw 'Codex 在配置恢复前仍在运行；已停止写入配置。'
}

if ($options.RestoreBaseTheme) {
  if (@(Get-VerifiedCodexMainProcesses -PackageInfo $package).Count -gt 0) {
    throw 'Codex 在配置恢复前重新出现；已停止写入配置。'
  }
  $configResult = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments @(
    (Join-Path $script:ScriptDir 'theme-config.mjs'), 'restore',
    $script:ConfigPath, $script:ThemeBackupPath, '--keep-backup'
  )
  if ($configResult.ExitCode -ne 0) { throw 'Codex 基础主题配置恢复失败。' }
}

if ($options.RestartCodex) {
  $newMains = @(Get-VerifiedCodexMainProcesses -PackageInfo $package)
  if ($newMains.Count -gt 0) {
    Stop-VerifiedCodex -PackageInfo $package
  }
  if (@(Get-VerifiedCodexMainProcesses -PackageInfo $package).Count -gt 0) {
    throw 'Codex 在正常恢复启动前重新出现；恢复材料已保留。'
  }
  Start-CodexNormally -PackageInfo $package
}

if (Test-Path -LiteralPath $script:StatePath) { Remove-Item -LiteralPath $script:StatePath -Force }
if ($options.Uninstall) { Remove-OwnedDesktopLaunchers }
if ($options.RestoreBaseTheme -and (Test-Path -LiteralPath $script:ThemeBackupPath -PathType Leaf)) {
  Remove-Item -LiteralPath $script:ThemeBackupPath -Force
}
if ($options.RestoreBaseTheme) {
  Write-Host 'Codex Immersive Skin 已完整移除，基础主题配置已恢复。'
} else {
  Write-Host '实时主题与注入器已移除；基础主题配置未改动。'
}
}
finally {
  Close-CodexWindowsOperationLock -Lock $operationLock
}
