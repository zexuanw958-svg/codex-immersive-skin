[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $script:Utf8NoBom
$OutputEncoding = $script:Utf8NoBom

$script:TestsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = [IO.Path]::GetFullPath((Join-Path $script:TestsRoot '..'))
$script:NodePath = $null
$script:TemporaryRoot = $null
$script:LocationPushed = $false

function Get-ProjectRelativePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [IO.Path]::GetFullPath($Path)
  $rootPrefix = $script:ProjectRoot.TrimEnd([char]'\', [char]'/') + [IO.Path]::DirectorySeparatorChar
  if ($fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    return $fullPath.Substring($rootPrefix.Length)
  }
  return [IO.Path]::GetFileName($fullPath)
}

function Add-NodeCandidate {
  param(
    [AllowNull()]$Value,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.ArrayList]$Candidates
  )

  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    if (-not [string]::IsNullOrWhiteSpace($Value)) { [void]$Candidates.Add($Value) }
    return
  }
  if ($Value -is [IO.FileInfo]) {
    [void]$Candidates.Add($Value.FullName)
    return
  }

  foreach ($propertyName in @(
    'NodePath', 'Node', 'RuntimeNodePath', 'RuntimeNode',
    'CodexNodePath', 'CodexNode', 'ExecutablePath'
  )) {
    $property = $Value.PSObject.Properties[$propertyName]
    if ($null -ne $property) { Add-NodeCandidate -Value $property.Value -Candidates $Candidates }
  }
}

function Resolve-TestNode {
  $commonPath = Join-Path $script:ProjectRoot 'scripts\common-windows.ps1'
  $candidates = New-Object Collections.ArrayList

  if (Test-Path -LiteralPath $commonPath -PathType Leaf) {
    . $commonPath
    $initializer = Get-Command Initialize-WindowsRuntime -CommandType Function -ErrorAction SilentlyContinue
    if ($null -eq $initializer) {
      throw 'scripts/common-windows.ps1 must expose Initialize-WindowsRuntime.'
    }

    $runtimeResult = @(Initialize-WindowsRuntime)
    foreach ($value in $runtimeResult) { Add-NodeCandidate -Value $value -Candidates $candidates }
    foreach ($variableName in @(
      'NodePath', 'Node', 'NODE', 'RuntimeNodePath', 'RuntimeNode',
      'CodexNodePath', 'CodexNode', 'WindowsRuntime', 'Runtime'
    )) {
      $variable = Get-Variable -Name $variableName -Scope Script -ErrorAction SilentlyContinue
      if ($null -ne $variable) { Add-NodeCandidate -Value $variable.Value -Candidates $candidates }
    }
    if ($candidates.Count -eq 0) {
      throw 'Initialize-WindowsRuntime did not expose the verified Codex Node.js path.'
    }
  } else {
    $bootstrapNode = $env:CODEX_IMMERSIVE_TEST_BOOTSTRAP_NODE
    if ([string]::IsNullOrWhiteSpace($bootstrapNode)) {
      $command = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
      if ($null -ne $command) { $bootstrapNode = $command.Source }
    }
    if ([string]::IsNullOrWhiteSpace($bootstrapNode)) {
      throw 'Codex runtime discovery is not installed yet and no bootstrap Node.js was provided.'
    }
    [void]$candidates.Add($bootstrapNode)
    Write-Host 'common-windows.ps1 is not present; using the bootstrap Node.js for incomplete-tree checks.'
  }

  foreach ($candidate in $candidates) {
    try {
      $expanded = [Environment]::ExpandEnvironmentVariables([string]$candidate).Trim('"')
      $resolved = [IO.Path]::GetFullPath($expanded)
      if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        $versionOutput = @(& $resolved --version 2>$null)
        $exitCode = $LASTEXITCODE
        $version = ''
        if ($versionOutput.Count -gt 0) { $version = [string]$versionOutput[0] }
        if ($exitCode -eq 0 -and $version -match '^v([0-9]+)\.') {
          if ([int]$Matches[1] -lt 22) { throw "Node.js $version is too old; version 22 or newer is required." }
          $script:NodePath = $resolved
          Write-Host "Using Node.js $version for Windows checks."
          return
        }
      }
    } catch {
      if ($_.Exception.Message -like 'Node.js * is too old*') { throw }
    }
  }
  throw 'No usable Node.js 22+ executable was returned by Windows runtime discovery.'
}

function Invoke-NodeChecked {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  & $script:NodePath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

function Invoke-NodeCaptured {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $output = @(& $script:NodePath @Arguments)
  if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
  return ($output -join "`n")
}

function Test-PowerShellSyntax {
  $directories = @((Join-Path $script:ProjectRoot 'scripts'), (Join-Path $script:ProjectRoot 'tests'))
  $files = @(Get-ChildItem -LiteralPath $directories -Recurse -File | Where-Object {
    $_.Extension -eq '.ps1' -or $_.Extension -eq '.psm1'
  } | Sort-Object FullName)

  foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
      $file.FullName,
      [ref]$tokens,
      [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
      $detail = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
      throw "PowerShell syntax failed for $(Get-ProjectRelativePath $file.FullName): $detail"
    }
  }
  Write-Host "PASS: parsed $($files.Count) PowerShell files."
}

function Test-JavaScriptSyntax {
  $directories = @(
    (Join-Path $script:ProjectRoot 'scripts'),
    (Join-Path $script:ProjectRoot 'assets'),
    (Join-Path $script:ProjectRoot 'tests')
  )
  $files = @(Get-ChildItem -LiteralPath $directories -Recurse -File | Where-Object {
    $_.Extension -eq '.mjs' -or $_.Extension -eq '.js'
  } | Sort-Object FullName)

  foreach ($file in $files) {
    Invoke-NodeChecked -Label "JavaScript syntax check for $(Get-ProjectRelativePath $file.FullName)" `
      -Arguments @('--check', $file.FullName)
  }
  Write-Host "PASS: checked $($files.Count) JavaScript files."
}

function Test-SourceSafety {
  $scriptRoot = Join-Path $script:ProjectRoot 'scripts'
  $files = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File | Where-Object {
    $_.Extension -in @('.mjs', '.js', '.ps1', '.psm1', '.sh')
  })
  $legacyPattern = 'dream-skin-skin|DREAM_SKIN_SKIN|1\.0\.0-rc2'
  $asarMutationPattern = '(?im)^[^\r\n]*(?:writeFile(?:Sync)?|rename(?:Sync)?|copyFile(?:Sync)?|\brm\b|Remove-Item|Set-Content|Add-Content|Out-File)[^\r\n]*app\.asar|^[^\r\n]*app\.asar[^\r\n]*(?:writeFile(?:Sync)?|rename(?:Sync)?|copyFile(?:Sync)?|\brm\b|Remove-Item|Set-Content|Add-Content|Out-File)'
  $policyMutationPattern = '(?im)^\s*Set-ExecutionPolicy\b'
  $policyBypassPattern = '(?im)-ExecutionPolicy[\s''"]+Bypass\b'
  $packageMutationPattern = '(?im)^\s*(?:Add-AppxPackage|Remove-AppxPackage)\b'
  $unverifiedNameKillPattern = '(?im)(?:Stop-Process\s+-Name\s+(?:ChatGPT|Codex)\b|taskkill(?:\.exe)?[^\r\n]*/IM\s+(?:ChatGPT|Codex)\.exe)'

  foreach ($file in $files) {
    $content = [IO.File]::ReadAllText($file.FullName)
    $relative = Get-ProjectRelativePath $file.FullName
    if ($content -match $legacyPattern) { throw "Legacy release-candidate identifiers remain in $relative." }
    if ($content -match $asarMutationPattern) { throw "A runtime script may mutate app.asar: $relative." }
    if ($content -match $policyMutationPattern) { throw "A script changes persistent PowerShell execution policy: $relative." }
    if ($content -match $policyBypassPattern) { throw "A script bypasses PowerShell execution policy: $relative." }
    if ($content -match $packageMutationPattern) { throw "A script may modify the installed MSIX package: $relative." }
    if ($content -match $unverifiedNameKillPattern) { throw "A script stops Codex by process name instead of verified identity: $relative." }
  }
  Write-Host 'PASS: runtime source safety scans.'
}

function Test-Payloads {
  $injector = Join-Path $script:ProjectRoot 'scripts\injector.mjs'
  $expectedVersion = [IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'VERSION')).Trim()
  $cases = @(
    @{ Name = 'bundled'; Arguments = @($injector, '--check-payload') },
    @{ Name = 'warm-sand'; Arguments = @($injector, '--check-payload', '--theme-dir', (Join-Path $script:ProjectRoot 'examples\warm-sand')) }
  )

  foreach ($case in $cases) {
    $json = Invoke-NodeCaptured -Label "$($case.Name) payload check" -Arguments $case.Arguments
    try { $payload = $json | ConvertFrom-Json } catch { throw "$($case.Name) payload did not return valid JSON." }
    if (-not $payload.pass -or $payload.version -ne $expectedVersion -or [long]$payload.imageBytes -lt 1) {
      throw "$($case.Name) payload identity or content check failed."
    }
  }
  Write-Host 'PASS: bundled and example payloads.'
}

function Test-NodeSuites {
  $testFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'tests') -File -Filter '*.test.mjs' |
    Sort-Object Name | ForEach-Object { $_.FullName })
  if ($testFiles.Count -eq 0) { throw 'No Node.js test files were found.' }
  Invoke-NodeChecked -Label 'Node.js test suite' -Arguments (@('--test') + $testFiles)
}

function Test-ConfigRoundTrip {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Newline,
    [Parameter(Mandatory = $true)][ValidateSet('light', 'dark')][string]$Appearance
  )

  $directory = Join-Path $script:TemporaryRoot $Name
  [void](New-Item -ItemType Directory -Path $directory)
  $configPath = Join-Path $directory 'config.toml'
  $backupPath = Join-Path $directory 'theme-backup.json'
  $themeConfig = Join-Path $script:ProjectRoot 'scripts\theme-config.mjs'
  $content = (@(
    'model = "gpt-5"',
    '',
    '[desktop]',
    'appearanceTheme = "system"',
    'appearanceDarkCodeThemeId = "vscode-dark"',
    'keepMe = true'
  ) -join $Newline) + $Newline
  [IO.File]::WriteAllText($configPath, $content, $script:Utf8NoBom)
  $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($configPath))

  Invoke-NodeChecked -Label "$Name config install" -Arguments @(
    $themeConfig, 'install', $configPath, $backupPath, '--appearance', $Appearance
  )
  $installed = [IO.File]::ReadAllText($configPath)
  if ($installed -notmatch "(?m)^appearanceTheme = `"$Appearance`"\r?$") {
    throw "$Name config did not select the requested appearance."
  }
  if ($installed -notmatch '(?m)^keepMe = true\r?$') { throw "$Name config lost an unrelated value." }
  $backup = [IO.File]::ReadAllText($backupPath) | ConvertFrom-Json
  if ($backup.platform -ne 'win32') { throw "$Name backup platform must be win32." }

  Invoke-NodeChecked -Label "$Name config restore" -Arguments @($themeConfig, 'restore', $configPath, $backupPath)
  $after = [Convert]::ToBase64String([IO.File]::ReadAllBytes($configPath))
  if ($before -ne $after) { throw "$Name config restore was not byte-exact." }
  if (Test-Path -LiteralPath $backupPath) { throw "$Name config backup was not removed after restore." }
}

function Remove-VerifiedTemporaryRoot {
  if ([string]::IsNullOrWhiteSpace($script:TemporaryRoot)) { return }
  $resolved = [IO.Path]::GetFullPath($script:TemporaryRoot)
  $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]'\', [char]'/') + [IO.Path]::DirectorySeparatorChar
  $leaf = [IO.Path]::GetFileName($resolved)
  if (-not $resolved.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -or
      -not $leaf.StartsWith('codex-immersive-windows-tests-', [StringComparison]::Ordinal)) {
    throw 'Refusing to remove an unverified temporary test directory.'
  }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

$exitCode = 0
try {
  Push-Location -LiteralPath $script:ProjectRoot
  $script:LocationPushed = $true
  Test-PowerShellSyntax
  Resolve-TestNode
  Test-JavaScriptSyntax
  Test-SourceSafety
  Test-Payloads

  $script:TemporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'codex-immersive-windows-tests-' + [Guid]::NewGuid().ToString('N')
  )
  [void](New-Item -ItemType Directory -Path $script:TemporaryRoot)
  Test-ConfigRoundTrip -Name 'lf-dark' -Newline "`n" -Appearance 'dark'
  Test-ConfigRoundTrip -Name 'crlf-light' -Newline "`r`n" -Appearance 'light'
  Write-Host 'PASS: LF and CRLF config round-trips.'
  Test-NodeSuites
  Write-Host 'PASS: Windows syntax, payload, Node tests, config round-trip, and safety checks.'
} catch {
  [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
  $exitCode = 1
} finally {
  try { Remove-VerifiedTemporaryRoot } catch {
    [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
    $exitCode = 1
  }
  if ($script:LocationPushed) { Pop-Location }
}

exit $exitCode
