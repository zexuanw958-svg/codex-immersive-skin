#requires -Version 5.1

[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Arguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = [IO.Path]::GetFullPath((Join-Path $script:ScriptDir '..'))
. (Join-Path $script:ScriptDir 'common-windows.ps1')
. (Join-Path $script:ScriptDir 'lifecycle-windows.ps1')

$script:StateRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_STATE_ROOT' `
  -DefaultPath (Join-Path $env:LOCALAPPDATA 'CodexImmersiveSkin')
$script:InstallRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_INSTALL_ROOT' `
  -DefaultPath (Join-Path $env:USERPROFILE '.codex\codex-immersive-skin')
$script:StatePath = Join-Path $script:StateRoot 'state.json'
$script:PreferredPortPath = Join-Path $script:StateRoot 'preferred-port'
$script:ThemeBackupPath = Join-Path $script:StateRoot 'theme-backup.json'
$script:ThemeDir = Join-Path $script:StateRoot 'theme'
$script:ConfigPath = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_CONFIG_PATH' `
  -DefaultPath (Join-Path $env:USERPROFILE '.codex\config.toml')
$script:Injector = Join-Path $script:ScriptDir 'injector.mjs'
$script:InjectorLog = Join-Path $script:StateRoot 'injector.log'
$script:InjectorErrorLog = Join-Path $script:StateRoot 'injector-error.log'
$script:StartErrorLog = Join-Path $script:StateRoot 'start-error.log'
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Read-StartOptions {
  param([string[]]$Values)

  $result = [ordered]@{
    Port = 9341
    PortExplicit = $false
    RestartExisting = $false
    PromptRestart = $false
    ForegroundInjector = $false
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
        $result.PortExplicit = $true
      }
      '--restart-existing' { $result.RestartExisting = $true }
      '--prompt-restart' { $result.PromptRestart = $true }
      '--foreground-injector' { $result.ForegroundInjector = $true }
      default { throw "未知启动参数：$value" }
    }
  }
  [pscustomobject]$result
}

function Invoke-Node {
  param($RuntimeInfo, [string[]]$NodeArguments, [switch]$Capture, [switch]$StreamOutput)

  $result = Invoke-CodexWindowsNode -RuntimeInfo $RuntimeInfo -Arguments $NodeArguments -StreamOutput:$StreamOutput
  if ($result.ExitCode -ne 0) { throw "Node 子进程失败，退出码 $($result.ExitCode)。" }
  if ($Capture) { return ($result.Output -join "`n") }
  foreach ($line in @($result.Output)) { Write-Output $line }
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
  param([Parameter(Mandatory = $true)]$PackageInfo)

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
  param(
    [Parameter(Mandatory = $true)]$PackageInfo,
    [switch]$AllowForce
  )

  $mains = @(Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo)
  if ($mains.Count -eq 0) { return }
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
  if ($remaining.Count -eq 0) { return }
  if (-not $AllowForce) { throw 'Codex 未在 15 秒内退出；强制关闭需要明确授权。' }
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

function Confirm-CodexRestart {
  Add-Type -AssemblyName System.Windows.Forms
  $choice = [Windows.Forms.MessageBox]::Show(
    'Codex 需要重启一次才能启用 Immersive Skin。是否现在重启并应用？',
    'Codex Immersive Skin',
    [Windows.Forms.MessageBoxButtons]::YesNo,
    [Windows.Forms.MessageBoxIcon]::Question,
    [Windows.Forms.MessageBoxDefaultButton]::Button2
  )
  return $choice -eq [Windows.Forms.DialogResult]::Yes
}

function Select-AvailablePort {
  param([int]$Preferred)
  $last = [Math]::Min(65535, $Preferred + 100)
  for ($candidate = $Preferred; $candidate -le $last; $candidate++) {
    if (Test-CodexWindowsPortAvailable -Port $candidate) { return $candidate }
  }
  throw "端口 $Preferred 到 $last 均不可用。"
}

function Test-VerifiedCdpEndpoint {
  param([int]$Port, $PackageInfo)
  Test-CodexWindowsCdpEndpoint -Port $Port -PackageInfo $PackageInfo
}

function Start-CodexWithCdp {
  param([int]$Port, $PackageInfo)
  $arguments = @(
    '--remote-debugging-address=127.0.0.1',
    "--remote-debugging-port=$Port"
  )
  $process = Start-Process -FilePath $PackageInfo.AppExecutable -ArgumentList $arguments -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  do {
    try {
      $identity = Get-CodexWindowsProcessIdentity -ProcessId $process.Id
      if ((Test-VerifiedCodexMainIdentity -Identity $identity -PackageInfo $PackageInfo) -and
          (Test-CodexDebugIdentityForPort -Identity $identity -Port $Port)) {
        return [pscustomobject]@{ Process = $process; Identity = $identity }
      }
    } catch { }
    if ($process.HasExited) { break }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)
  try {
    if (-not $process.HasExited) {
      $process.Kill()
      if (-not $process.WaitForExit(6000) -or -not $process.HasExited) {
        throw '本事务启动的 Codex 原始进程句柄未能确认退出。'
      }
    }
  } catch {
    $script:TransactionCodexCleanupUnconfirmed = $true
    throw "本事务启动的 Codex 身份检查失败，且原始进程未确认退出：$($_.Exception.Message)"
  }
  throw '本事务启动的 Codex 未能建立可验证的调试进程身份。'
}

function Test-CodexDebugIdentityForPort {
  param($Identity, [int]$Port)
  $argv = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine($Identity.CommandLine))
  return @($argv | Where-Object {
    [string]$_ -eq '--remote-debugging-address=127.0.0.1'
  }).Count -eq 1 -and @($argv | Where-Object {
    [string]$_ -eq "--remote-debugging-port=$Port"
  }).Count -eq 1
}

function Wait-VerifiedCdpEndpoint {
  param([int]$Port, $PackageInfo, $LaunchedIdentity, [int]$TimeoutSeconds = 35)
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    try {
      $fresh = Get-CodexWindowsProcessIdentity -ProcessId ([int]$LaunchedIdentity.ProcessId)
      if ($fresh.StartTimeUtc -ne [string]$LaunchedIdentity.StartTimeUtc -or
          $fresh.CommandLine -ne [string]$LaunchedIdentity.CommandLine -or
          -not (Test-VerifiedCodexMainIdentity -Identity $fresh -PackageInfo $PackageInfo) -or
          -not (Test-CodexDebugIdentityForPort -Identity $fresh -Port $Port)) {
        return $false
      }
      if (Test-VerifiedCdpEndpoint -Port $Port -PackageInfo $PackageInfo) { return $true }
    } catch { return $false }
    Start-Sleep -Milliseconds 400
  } while ([DateTime]::UtcNow -lt $deadline)
  return $false
}

function Stop-TransactionCodex {
  param($Identity, $PackageInfo)
  if ($null -eq $Identity) { return $true }
  $process = Get-Process -Id ([int]$Identity.ProcessId) -ErrorAction SilentlyContinue
  if ($null -eq $process) { return $true }
  try {
    $fresh = Get-CodexWindowsProcessIdentity -ProcessId ([int]$Identity.ProcessId)
    if ($fresh.StartTimeUtc -ne [string]$Identity.StartTimeUtc -or
        $fresh.CommandLine -ne [string]$Identity.CommandLine -or
        -not (Test-VerifiedCodexMainIdentity -Identity $fresh -PackageInfo $PackageInfo)) {
      return $true
    }
    Stop-CodexWindowsVerifiedProcess -Identity $fresh -TimeoutMs 6000
    return $true
  } catch {
    return $false
  }
}

function Stop-RecordedInjector {
  param($RuntimeInfo)

  $state = Read-CodexWindowsState -Path $script:StatePath
  if ($null -eq $state) { return }
  $process = Get-Process -Id ([int]$state.injectorPid) -ErrorAction SilentlyContinue
  if ($null -eq $process) {
    Remove-Item -LiteralPath $script:StatePath -Force
    return
  }
  $expectedInjector = Resolve-CodexWindowsRecordedInjectorPath -State $state `
    -CurrentInjectorPath $script:Injector -InstallRoot $script:InstallRoot
  if (-not (Test-CodexWindowsRecordedInjector -State $state -RuntimeInfo $RuntimeInfo `
      -ExpectedInjectorPath $expectedInjector)) {
    throw '已记录的注入器身份不匹配；为避免误停其他进程，状态已保留。'
  }
  $identity = Get-CodexWindowsProcessIdentity -ProcessId ([int]$state.injectorPid)
  if ($identity.StartTimeUtc -ne [string]$state.injectorStartedAt -or
      -not (Test-CodexWindowsPathEqual -First $identity.Path -Second $RuntimeInfo.NodePath)) {
    throw '注入器身份在终止前发生变化；状态已保留。'
  }
  Stop-CodexWindowsVerifiedProcess -Identity $identity -TimeoutMs 6000
  Remove-Item -LiteralPath $script:StatePath -Force
}

function Quote-WindowsArgument {
  param([string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Test-NewInjectorIdentity {
  param($Identity, $RuntimeInfo, [int]$Port)
  if ($null -eq $Identity -or
      -not (Test-CodexWindowsPathEqual -First $Identity.Path -Second $RuntimeInfo.NodePath)) { return $false }
  $argv = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine($Identity.CommandLine))
  return $argv.Count -eq 7 -and
    (Test-CodexWindowsPathEqual -First $argv[0] -Second $RuntimeInfo.NodePath) -and
    (Test-CodexWindowsPathEqual -First $argv[1] -Second $script:Injector) -and
    $argv[2] -eq '--watch' -and $argv[3] -eq '--port' -and $argv[4] -eq [string]$Port -and
    $argv[5] -eq '--theme-dir' -and
    (Test-CodexWindowsPathEqual -First $argv[6] -Second $script:ThemeDir)
}

function Write-EmergencyInjectorState {
  param($Process, [int]$Port, $RuntimeInfo)
  $startedAt = $Process.StartTime.ToUniversalTime().ToString('o')
  $state = [ordered]@{
    schemaVersion = 5
    platform = 'win32-' + [string]$RuntimeInfo.Architecture
    skinVersion = ([IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'VERSION'))).Trim()
    port = $Port
    injectorPid = [int]$Process.Id
    injectorStartedAt = $startedAt
    injectorPath = $script:Injector
    nodePath = [string]$RuntimeInfo.NodePath
    nodeSha256 = [string]$RuntimeInfo.NodeSha256
    nodeVersion = [string]$RuntimeInfo.NodeVersion
    projectRoot = $script:ProjectRoot
    themeDir = $script:ThemeDir
    recoveryRequired = $true
    createdAt = [DateTime]::UtcNow.ToString('o')
  }
  $temporary = $script:StatePath + '.' + $PID + '.recovery.tmp'
  [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 5) + "`n", $script:Utf8NoBom)
  Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
}

function Start-InjectorDaemon {
  param([int]$Port, $RuntimeInfo)

  foreach ($log in @($script:InjectorLog, $script:InjectorErrorLog)) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
  }
  $argumentValues = @(
    $script:Injector, '--watch', '--port', [string]$Port, '--theme-dir', $script:ThemeDir
  )
  $argumentLine = ($argumentValues | ForEach-Object { Quote-WindowsArgument ([string]$_) }) -join ' '
  $runtimeLock = Open-CodexWindowsRuntimeLock -RuntimeInfo $RuntimeInfo
  $process = $null
  $identity = $null
  try {
    $process = Start-Process -FilePath $RuntimeInfo.NodePath -ArgumentList $argumentLine -PassThru `
      -WindowStyle Hidden -RedirectStandardOutput $script:InjectorLog -RedirectStandardError $script:InjectorErrorLog
    Start-Sleep -Milliseconds 150
    if ($null -eq (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
      throw '注入器在身份检查前提前退出。'
    }
    $identity = Get-CodexWindowsProcessIdentity -ProcessId $process.Id
    if (-not (Test-NewInjectorIdentity -Identity $identity -RuntimeInfo $RuntimeInfo -Port $Port)) {
      throw '新注入器的进程身份或参数不匹配。'
    }
    [pscustomobject]@{ Process = $process; Identity = $identity }
  } catch {
    $originalError = $_
    $cleanupError = $null
    if ($null -ne $process) {
      try {
        if (-not $process.HasExited) {
          $process.Kill()
          if (-not $process.WaitForExit(6000) -or -not $process.HasExited) {
            throw '注入器原始进程句柄未能确认退出。'
          }
        }
      } catch { $cleanupError = $_ }
      if ($null -ne $cleanupError) {
        try {
          Write-EmergencyInjectorState -Process $process -Port $Port -RuntimeInfo $RuntimeInfo
          $script:EmergencyInjectorStateWritten = $true
        } catch {
          throw "注入器身份检查失败，原始进程句柄清理也失败，且无法写入恢复状态：$($_.Exception.Message)"
        }
      }
    }
    if ($null -ne $cleanupError) {
      throw "注入器身份检查失败；原始进程未确认退出，恢复状态已保留：$($originalError.Exception.Message)"
    }
    throw $originalError
  } finally {
    $runtimeLock.Dispose()
  }
}

function Write-ImmersiveState {
  param(
    [int]$Port,
    $InjectorIdentity,
    $RuntimeInfo,
    $PackageInfo
  )

  $state = [ordered]@{
    schemaVersion = 5
    platform = 'win32-' + [string]$RuntimeInfo.Architecture
    skinVersion = ([IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'VERSION'))).Trim()
    port = $Port
    injectorPid = [int]$InjectorIdentity.ProcessId
    injectorStartedAt = [string]$InjectorIdentity.StartTimeUtc
    injectorPath = $script:Injector
    nodePath = [string]$RuntimeInfo.NodePath
    nodeSha256 = [string]$RuntimeInfo.NodeSha256
    nodeVersion = [string]$RuntimeInfo.NodeVersion
    codexExe = [string]$PackageInfo.AppExecutable
    codexPackageFullName = [string]$PackageInfo.PackageFullName
    projectRoot = $script:ProjectRoot
    themeDir = $script:ThemeDir
    createdAt = [DateTime]::UtcNow.ToString('o')
  }
  $temporary = $script:StatePath + '.' + $PID + '.tmp'
  [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 5) + "`n", $script:Utf8NoBom)
  Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
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

function Restore-ConfigSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$SnapshotPath,
    [Parameter(Mandatory = $true)][string]$SnapshotHash,
    [Parameter(Mandatory = $true)][string]$ExpectedCurrentHash
  )
  if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $SnapshotPath).Hash -ne $SnapshotHash) {
    throw '启动事务配置快照缺失或哈希不匹配。'
  }
  if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash -ne $ExpectedCurrentHash) {
    throw 'Codex 配置在启动事务期间被其他程序修改；已拒绝覆盖并保留恢复材料。'
  }
  $temporary = Join-Path (Split-Path -Parent $script:ConfigPath) `
    ('.config.toml.codex-immersive-rollback.' + $PID + '.' + [Guid]::NewGuid().ToString('N'))
  try {
    Copy-Item -LiteralPath $SnapshotPath -Destination $temporary -Force
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash -ne $SnapshotHash) {
      throw '启动事务配置临时恢复文件哈希不匹配。'
    }
    [IO.File]::Replace($temporary, $script:ConfigPath, $null)
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash -ne $SnapshotHash) {
      throw '启动事务配置恢复后的哈希不匹配。'
    }
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  }
}

$options = Read-StartOptions -Values @(ConvertTo-CodexWindowsRemainingArguments -Values $Arguments)
$operationLock = Open-CodexWindowsOperationLock -StateRoot $script:StateRoot
try {
Assert-CodexWindowsStateRoot -Path $script:StateRoot -Create
if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
  throw '未找到 Codex 配置。请先正常启动 Codex 至少一次。'
}
$runtime = Initialize-WindowsRuntime
$package = $runtime.PackageInfo

if (-not $options.PortExplicit) {
  $savedState = Read-CodexWindowsState -Path $script:StatePath
  if ($null -ne $savedState) { $options.Port = [int]$savedState.port }
  elseif (Test-Path -LiteralPath $script:PreferredPortPath -PathType Leaf) {
    $text = ([IO.File]::ReadAllText($script:PreferredPortPath)).Trim()
    $savedPort = 0
    if ([int]::TryParse($text, [ref]$savedPort) -and $savedPort -ge 1024 -and $savedPort -le 65535) {
      $options.Port = $savedPort
    }
  }
}

$debugReady = Test-VerifiedCdpEndpoint -Port $options.Port -PackageInfo $package
$codexRunning = @(Get-VerifiedCodexMainProcesses -PackageInfo $package).Count -gt 0
if ($codexRunning) {
  if ($options.PromptRestart -and -not $options.RestartExisting) {
    if (-not (Confirm-CodexRestart)) { throw '用户取消了 Codex 重启。' }
    $options.RestartExisting = $true
  }
  if (-not $options.RestartExisting) {
    throw 'Codex 正在运行；为避免配置写入竞争，请关闭 Codex 或传入 --restart-existing。'
  }
}

$payloadText = Invoke-Node -RuntimeInfo $runtime -NodeArguments @(
  $script:Injector, '--check-payload', '--theme-dir', $script:ThemeDir
) -Capture
$payload = $payloadText | ConvertFrom-Json
$appearance = if ($payload.appearance -eq 'light') { 'light' } else { 'dark' }
$configRollback = Join-Path $script:StateRoot ('config-before-start.' + $PID + '.' + [Guid]::NewGuid().ToString('N'))
$configRollbackReady = $false
$configRollbackHash = ''
$configInstalledHash = ''
$backupPreexisted = Test-Path -LiteralPath $script:ThemeBackupPath -PathType Leaf
$newInjector = $null
$newInjectorIdentity = $null
$newStateWritten = $false
$codexRecoveryRequired = $codexRunning
$launchedWithCdp = $false
$launchedCodexIdentity = $null
$foregroundInjectorRan = $false
$preexistingDebugSessionTouched = $false
$preserveConfigRollback = $false
$startCommitted = $false
$script:EmergencyInjectorStateWritten = $false
$script:TransactionCodexCleanupUnconfirmed = $false

try {
  $recordedBeforeStop = Read-CodexWindowsState -Path $script:StatePath
  if ($null -ne $recordedBeforeStop -and
      $null -ne (Get-Process -Id ([int]$recordedBeforeStop.injectorPid) -ErrorAction SilentlyContinue)) {
    $expectedRecordedInjector = Resolve-CodexWindowsRecordedInjectorPath -State $recordedBeforeStop `
      -CurrentInjectorPath $script:Injector -InstallRoot $script:InstallRoot
    if (-not (Test-CodexWindowsRecordedInjector -State $recordedBeforeStop -RuntimeInfo $runtime `
        -ExpectedInjectorPath $expectedRecordedInjector)) {
      throw '已记录的注入器身份不匹配；启动未触碰现有实时主题。'
    }
  }
  $preexistingDebugSessionTouched = $debugReady
  Stop-RecordedInjector -RuntimeInfo $runtime
  if ($codexRunning) {
    Stop-VerifiedCodex -PackageInfo $package -AllowForce
    $debugReady = $false
  }
  if (@(Get-VerifiedCodexMainProcesses -PackageInfo $package).Count -gt 0) {
    throw 'Codex 在配置事务开始前重新出现；已停止写入配置。'
  }

  Copy-Item -LiteralPath $script:ConfigPath -Destination $configRollback -Force
  $configRollbackHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $configRollback).Hash
  $configRollbackReady = $true
  [void](Invoke-Node -RuntimeInfo $runtime -NodeArguments @(
    (Join-Path $script:ScriptDir 'theme-config.mjs'), 'install',
    $script:ConfigPath, $script:ThemeBackupPath, '--appearance', $appearance,
    '--expected-config-sha256', $configRollbackHash
  ) -Capture)
  $configInstalledHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash

  if (-not $debugReady) {
    $options.Port = Select-AvailablePort -Preferred $options.Port
    $launchedCodex = Start-CodexWithCdp -Port $options.Port -PackageInfo $package
    $launchedCodexIdentity = $launchedCodex.Identity
    $launchedWithCdp = $true
    if (-not (Wait-VerifiedCdpEndpoint -Port $options.Port -PackageInfo $package `
        -LaunchedIdentity $launchedCodexIdentity)) {
      throw "Codex 未在 35 秒内开放经过验证的本机 CDP 端口 $($options.Port)。"
    }
    $unexpectedMains = @(Get-VerifiedCodexMainProcesses -PackageInfo $package | Where-Object {
      [int]$_.Identity.ProcessId -ne [int]$launchedCodexIdentity.ProcessId
    })
    if ($unexpectedMains.Count -gt 0) {
      throw '启动事务期间出现了额外的 Codex 主进程；已停止提交。'
    }
  }
  if ($options.ForegroundInjector) {
    [IO.File]::WriteAllText($script:PreferredPortPath, ([string]$options.Port) + "`n", $script:Utf8NoBom)
    $foregroundInjectorRan = $true
    Invoke-Node -RuntimeInfo $runtime -NodeArguments @(
      $script:Injector, '--watch', '--port', [string]$options.Port, '--theme-dir', $script:ThemeDir
    ) -StreamOutput
    $startCommitted = $true
    try { Remove-Item -LiteralPath $configRollback -Force }
    catch { Write-Warning '前台注入器已正常退出，但启动事务备份未能清理。' }
    return
  }

  $newInjectorResult = Start-InjectorDaemon -Port $options.Port -RuntimeInfo $runtime
  $newInjector = $newInjectorResult.Process
  $newInjectorIdentity = $newInjectorResult.Identity
  Start-Sleep -Milliseconds 650
  if ($null -eq (Get-Process -Id $newInjector.Id -ErrorAction SilentlyContinue)) {
    throw '注入器在启动阶段提前退出。'
  }
  Write-ImmersiveState -Port $options.Port -InjectorIdentity $newInjectorIdentity -RuntimeInfo $runtime -PackageInfo $package
  $newStateWritten = $true

  Invoke-Node -RuntimeInfo $runtime -NodeArguments @(
    $script:Injector, '--verify', '--port', [string]$options.Port,
    '--theme-dir', $script:ThemeDir, '--timeout-ms', '30000'
  )
  [IO.File]::WriteAllText($script:PreferredPortPath, ([string]$options.Port) + "`n", $script:Utf8NoBom)
  $startCommitted = $true
  try { Remove-Item -LiteralPath $configRollback -Force }
  catch { Write-Warning '主题已生效，但启动事务备份未能清理。' }
  Write-Host "Codex Immersive Skin 已在本机端口 $($options.Port) 生效。"
}
catch {
  $originalError = $_
  $rollbackErrors = New-Object Collections.ArrayList
  $newInjectorStopped = $null -eq $newInjectorIdentity -and -not $script:EmergencyInjectorStateWritten
  if ($script:EmergencyInjectorStateWritten) {
    [void]$rollbackErrors.Add('注入器未确认退出；可重试恢复状态已保留')
  }
  if ($null -ne $newInjectorIdentity) {
    try {
      $freshInjector = Get-CodexWindowsProcessIdentity -ProcessId ([int]$newInjectorIdentity.ProcessId)
      if ((Test-NewInjectorIdentity -Identity $freshInjector -RuntimeInfo $runtime -Port $options.Port) -and
          $freshInjector.StartTimeUtc -eq $newInjectorIdentity.StartTimeUtc -and
          $freshInjector.CommandLine -eq $newInjectorIdentity.CommandLine) {
        Stop-CodexWindowsVerifiedProcess -Identity $freshInjector -TimeoutMs 6000
        $newInjectorStopped = $true
      } else {
        throw '新注入器身份发生变化。'
      }
    } catch { [void]$rollbackErrors.Add('新注入器停止失败') }
  }
  if ($preexistingDebugSessionTouched -and -not $launchedWithCdp -and $debugReady) {
    try {
      if (-not (Test-VerifiedCdpEndpoint -Port $options.Port -PackageInfo $package)) {
        throw 'CDP 身份已变化。'
      }
      Invoke-Node -RuntimeInfo $runtime -NodeArguments @(
        $script:Injector, '--remove', '--port', [string]$options.Port,
        '--theme-dir', $script:ThemeDir, '--timeout-ms', '8000'
      )
    } catch { [void]$rollbackErrors.Add('实时主题移除失败') }
  }
  if ($newStateWritten -and $newInjectorStopped -and (Test-Path -LiteralPath $script:StatePath)) {
    try { Remove-Item -LiteralPath $script:StatePath -Force }
    catch { [void]$rollbackErrors.Add('新状态清理失败') }
  } elseif ($newStateWritten -and -not $newInjectorStopped) {
    [void]$rollbackErrors.Add('新状态因注入器未确认退出而被保留')
  }

  $transactionCodexStopped = -not $script:TransactionCodexCleanupUnconfirmed
  if ($null -ne $launchedCodexIdentity) {
    $transactionCodexStopped = Stop-TransactionCodex -Identity $launchedCodexIdentity -PackageInfo $package
    if (-not $transactionCodexStopped) {
      [void]$rollbackErrors.Add('本事务启动的调试 Codex 未确认退出')
    }
  } elseif ($script:TransactionCodexCleanupUnconfirmed) {
    [void]$rollbackErrors.Add('本事务启动的 Codex 身份建立失败且未确认退出')
  }

  $remainingMains = @(Get-VerifiedCodexMainProcesses -PackageInfo $package)
  $configRestored = -not $configRollbackReady
  if ($configRollbackReady -and -not $transactionCodexStopped) {
    $preserveConfigRollback = $true
    [void]$rollbackErrors.Add('调试 Codex 未退出，配置快照未覆盖当前文件')
  } elseif ($configRollbackReady -and $remainingMains.Count -gt 0) {
    $preserveConfigRollback = $true
    [void]$rollbackErrors.Add('检测到非本事务 Codex，配置快照未覆盖当前文件')
  } elseif ($configRollbackReady -and (Test-Path -LiteralPath $configRollback -PathType Leaf)) {
    try {
      $currentConfigHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash
      if ($currentConfigHash -eq $configRollbackHash) {
        $configRestored = $true
      } elseif ([string]::IsNullOrWhiteSpace($configInstalledHash)) {
        throw '启动失败前未能记录本事务配置哈希；已拒绝覆盖。'
      } else {
        Restore-ConfigSnapshot -SnapshotPath $configRollback -SnapshotHash $configRollbackHash `
          -ExpectedCurrentHash $configInstalledHash
        $configRestored = $true
      }
    } catch {
      $preserveConfigRollback = $true
      [void]$rollbackErrors.Add("配置恢复失败：$($_.Exception.Message)")
    }
  } elseif ($configRollbackReady) {
    $preserveConfigRollback = $true
    [void]$rollbackErrors.Add('启动事务配置快照缺失')
  }
  if ($configRestored -and -not $backupPreexisted -and (Test-Path -LiteralPath $script:ThemeBackupPath)) {
    try { Remove-Item -LiteralPath $script:ThemeBackupPath -Force }
    catch { [void]$rollbackErrors.Add('主题配置备份清理失败') }
  }
  $remainingMains = @(Get-VerifiedCodexMainProcesses -PackageInfo $package)
  if (($launchedWithCdp -or $codexRecoveryRequired) -and $configRestored -and
      $transactionCodexStopped -and $newInjectorStopped -and $remainingMains.Count -eq 0) {
    try { Start-CodexNormally -PackageInfo $package }
    catch { [void]$rollbackErrors.Add('Codex 正常启动恢复失败') }
  } elseif (($launchedWithCdp -or $codexRecoveryRequired) -and -not $configRestored) {
    [void]$rollbackErrors.Add('配置未恢复，Codex 保持停止以避免继续写入')
  }
  try {
    Assert-CodexWindowsStateRoot -Path $script:StateRoot
    [IO.File]::AppendAllText(
      $script:StartErrorLog,
      ([DateTime]::UtcNow.ToString('o') + ' ' + $originalError.Exception.Message +
        $(if ($rollbackErrors.Count -gt 0) { ' | rollback: ' + ($rollbackErrors -join ', ') } else { '' }) + "`n"),
      $script:Utf8NoBom
    )
  } catch { [void]$rollbackErrors.Add('错误日志写入失败') }
  foreach ($rollbackError in $rollbackErrors) {
    Write-Warning "启动回滚警告：$rollbackError。恢复材料已尽量保留。"
  }
  throw $originalError
}
finally {
  if (-not $startCommitted -and -not $preserveConfigRollback -and (Test-Path -LiteralPath $configRollback)) {
    try { Remove-Item -LiteralPath $configRollback -Force }
    catch { Write-Warning '启动事务备份未能清理；已保留供手动恢复。' }
  }
}
}
finally {
  Close-CodexWindowsOperationLock -Lock $operationLock
}
