#requires -Version 5.1

[CmdletBinding()]
param(
  [switch]$RequireLive,
  [string]$StatePath = (Join-Path $env:LOCALAPPDATA "CodexImmersiveSkin\state.json")
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common-windows.ps1")

try {
  $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..") -ErrorAction Stop).Path
  $injector = Join-Path $PSScriptRoot "injector.mjs"
  $installRoot = Resolve-CodexWindowsScopedPath -EnvironmentName 'CODEX_IMMERSIVE_INSTALL_ROOT' `
    -DefaultPath (Join-Path $env:USERPROFILE '.codex\codex-immersive-skin')
  $requiredFiles = @(
    $injector,
    (Join-Path $projectRoot "assets\dream-skin.css"),
    (Join-Path $projectRoot "assets\renderer-inject.js"),
    (Join-Path $projectRoot "assets\theme.json")
  )
  foreach ($required in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "A required project file is missing: $(ConvertTo-CodexSafePath $required)"
    }
  }

  $package = Get-CodexWindowsPackage
  $runtime = Resolve-CodexWindowsRuntime -PackageInfo $package
  $configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Codex config was not found at $(ConvertTo-CodexSafePath $configPath)."
  }

  $statePresent = Test-Path -LiteralPath $StatePath -PathType Leaf
  $state = Read-CodexWindowsState -Path $StatePath
  $themeDirectory = Join-Path $projectRoot "assets"
  if ($null -ne $state -and $state.PSObject.Properties.Name -contains "themeDir" -and
      (Test-Path -LiteralPath ([string]$state.themeDir) -PathType Container)) {
    $themeDirectory = [string]$state.themeDir
  }

  $runtimeLock = Open-CodexWindowsRuntimeLock -RuntimeInfo $runtime
  try {
    $payloadOutput = @(& $runtime.NodePath $injector --check-payload --theme-dir $themeDirectory 2>&1)
    if ($LASTEXITCODE -ne 0) {
      throw "The Windows injector payload check failed: $($payloadOutput -join ' ')"
    }
  } finally {
    $runtimeLock.Dispose()
  }
  $payload = ($payloadOutput -join [Environment]::NewLine) | ConvertFrom-Json
  if (-not $payload.pass) { throw "The Windows injector payload did not pass validation." }

  $injectorIdentityValid = $false
  $cdpVerified = $false
  $port = $null
  if ($null -ne $state) {
    $port = [int]$state.port
    $expectedInjector = Resolve-CodexWindowsRecordedInjectorPath -State $state `
      -CurrentInjectorPath $injector -InstallRoot $installRoot
    $injectorIdentityValid = Test-CodexWindowsRecordedInjector -State $state -RuntimeInfo $runtime `
      -ExpectedInjectorPath $expectedInjector
    $cdpVerified = Test-CodexWindowsCdpEndpoint -Port $port -PackageInfo $package
  }
  $live = $injectorIdentityValid -and $cdpVerified
  if ($RequireLive -and -not $live) {
    throw "No verified live Windows Immersive Skin session is active."
  }

  $platform = Get-CodexWindowsRuntimePlatform -RuntimeInfo $runtime
  $version = (Read-CodexWindowsUtf8Text -Path (Join-Path $projectRoot "VERSION")).Trim()

  [pscustomobject]@{
    pass = $true
    product = "Codex Immersive Skin"
    version = $version
    platform = $platform
    package = [pscustomobject]@{
      name = $package.Name
      version = $package.Version
      familyName = $package.PackageFamilyName
      appUserModelId = $package.AppUserModelId
      signatureValid = $package.SignatureValid
      signatureKind = $package.SignatureKind
      blockMapValidated = $package.BlockMapValidated
      installLocation = ConvertTo-CodexSafePath $package.InstallLocation
      appExecutable = ConvertTo-CodexSafePath $package.AppExecutable
    }
    runtime = [pscustomobject]@{
      nodeVersion = $runtime.NodeVersion
      architecture = $runtime.Architecture
      nodeSha256 = $runtime.NodeSha256
      nodeMatchesPackage = $runtime.NodeMatchesPackage
      signatureValid = $runtime.SignatureValid
      nodePath = ConvertTo-CodexSafePath $runtime.NodePath
    }
    configExists = $true
    statePresent = [bool]$statePresent
    statePath = ConvertTo-CodexSafePath $StatePath
    injectorIdentityValid = [bool]$injectorIdentityValid
    cdpVerified = [bool]$cdpVerified
    live = [bool]$live
    port = $port
    modifiesAppAsar = $false
    theme = [pscustomobject]@{
      id = $payload.themeId
      name = $payload.themeName
      appearance = $payload.appearance
      imageBytes = $payload.imageBytes
      payloadBytes = $payload.payloadBytes
    }
  } | ConvertTo-Json -Depth 6
} catch {
  $message = ConvertTo-CodexSafePath ([string]$_.Exception.Message)
  Write-Error "Codex Immersive Skin: $message"
  exit 1
}
