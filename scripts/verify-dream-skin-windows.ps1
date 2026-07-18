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
$script:StatePath = Join-Path $script:StateRoot 'state.json'
$script:ThemeDir = Join-Path $script:StateRoot 'theme'
$script:Injector = Join-Path $script:ScriptDir 'injector.mjs'
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Read-VerifyOptions {
  param([string[]]$Values)
  $result = [ordered]@{
    Port = 9341
    PortExplicit = $false
    Screenshot = ''
    ScreenshotDefault = $false
    OpenScreenshot = $false
    Reload = $false
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
      '--screenshot' {
        if ($index + 1 -ge $Values.Count -or ([string]$Values[$index + 1]).StartsWith('--')) {
          throw '选项 --screenshot 需要一个输出路径。'
        }
        $result.Screenshot = [IO.Path]::GetFullPath([string]$Values[++$index])
      }
      '--screenshot-default' { $result.ScreenshotDefault = $true }
      '--open-screenshot' { $result.OpenScreenshot = $true }
      '--reload' { $result.Reload = $true }
      default { throw "未知验证参数：$value" }
    }
  }
  [pscustomobject]$result
}

function Test-VerifiedCdpEndpoint {
  param([int]$Port, $PackageInfo)
  Test-CodexWindowsCdpEndpoint -Port $Port -PackageInfo $PackageInfo
}

$options = Read-VerifyOptions -Values @(ConvertTo-CodexWindowsRemainingArguments -Values $Arguments)
$operationLock = Open-CodexWindowsOperationLock -StateRoot $script:StateRoot
try {
Assert-CodexWindowsStateRoot -Path $script:StateRoot
$runtime = Initialize-WindowsRuntime
$package = $runtime.PackageInfo
$state = Read-CodexWindowsState -Path $script:StatePath
if (-not $options.PortExplicit -and $null -ne $state) { $options.Port = [int]$state.port }
if (-not (Test-VerifiedCdpEndpoint -Port $options.Port -PackageInfo $package)) {
  throw "端口 $($options.Port) 不是经过身份验证的 Codex 本机 CDP 端点。"
}

if ($options.ScreenshotDefault -and [string]::IsNullOrWhiteSpace($options.Screenshot)) {
  $desktop = [Environment]::GetFolderPath('DesktopDirectory')
  if ([string]::IsNullOrWhiteSpace($desktop)) { throw '无法解析当前用户的桌面目录。' }
  $options.Screenshot = Join-Path $desktop 'Codex Immersive Skin Verification.png'
}

$injectorArguments = @(
  $script:Injector, '--verify', '--port', [string]$options.Port,
  '--theme-dir', $script:ThemeDir, '--timeout-ms', '30000'
)
if ($options.Reload) { $injectorArguments += '--reload' }
if (-not [string]::IsNullOrWhiteSpace($options.Screenshot)) {
  $injectorArguments += @('--screenshot', $options.Screenshot)
}

$verifyResult = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments $injectorArguments
if ($verifyResult.ExitCode -ne 0) { throw "实时验证失败，退出码 $($verifyResult.ExitCode)。" }
$json = $verifyResult.Output -join "`n"
try { $result = $json | ConvertFrom-Json } catch { throw '验证器没有返回有效 JSON。' }
if (@($result.targets).Count -eq 0) { throw '验证器没有找到 Codex renderer。' }
foreach ($target in @($result.targets)) {
  if (-not $target.result.pass) { throw '至少一个 Codex renderer 未通过主题验证。' }
}

Assert-CodexWindowsStateRoot -Path $script:StateRoot
[IO.File]::WriteAllText((Join-Path $script:StateRoot 'last-verify.json'), $json + "`n", $script:Utf8NoBom)
Write-Output $json

if ($options.OpenScreenshot -and -not [string]::IsNullOrWhiteSpace($options.Screenshot)) {
  if (-not (Test-Path -LiteralPath $options.Screenshot -PathType Leaf)) {
    throw '验证截图未生成。'
  }
  Invoke-Item -LiteralPath $options.Screenshot
}
}
finally {
  Close-CodexWindowsOperationLock -Lock $operationLock
}
