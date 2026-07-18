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
$script:ThemeDir = Join-Path $script:StateRoot 'theme'
$script:ThemeIdentityName = '.codex-immersive-theme.json'
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Read-CustomizeOptions {
  param([string[]]$Values)
  $result = [ordered]@{
    Image = ''
    Name = ''
    Tagline = ''
    Quote = ''
    Accent = ''
    Secondary = ''
    Highlight = ''
    Appearance = ''
    ApplyNow = $true
    ResetDemo = $false
  }
  $valueOptions = @('--image', '--name', '--tagline', '--quote', '--accent', '--secondary', '--highlight', '--appearance')
  for ($index = 0; $index -lt $Values.Count; $index++) {
    $value = [string]$Values[$index]
    if ($valueOptions -contains $value) {
      if ($index + 1 -ge $Values.Count -or ([string]$Values[$index + 1]).StartsWith('--')) {
        throw "选项 $value 需要一个非空值。"
      }
      $optionValue = [string]$Values[++$index]
      switch ($value) {
        '--image' { $result.Image = $optionValue }
        '--name' { $result.Name = $optionValue }
        '--tagline' { $result.Tagline = $optionValue }
        '--quote' { $result.Quote = $optionValue }
        '--accent' { $result.Accent = $optionValue }
        '--secondary' { $result.Secondary = $optionValue }
        '--highlight' { $result.Highlight = $optionValue }
        '--appearance' { $result.Appearance = $optionValue }
      }
      continue
    }
    switch -CaseSensitive ($value) {
      '--no-apply' { $result.ApplyNow = $false }
      '--reset-demo' { $result.ResetDemo = $true }
      default { throw "未知定制参数：$value" }
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($result.Appearance) -and
      $result.Appearance -notin @('light', 'dark')) {
    throw '--appearance 只能是 light 或 dark。'
  }
  foreach ($name in @('Accent', 'Secondary', 'Highlight')) {
    $color = [string]$result[$name]
    if (-not [string]::IsNullOrWhiteSpace($color) -and $color -notmatch '^#[0-9a-fA-F]{6}$') {
      throw "--$($name.ToLowerInvariant()) 必须是六位十六进制颜色。"
    }
  }
  [pscustomobject]$result
}

function Select-LocalImage {
  Add-Type -AssemblyName PresentationFramework
  $dialog = New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title = '选择一张主题图片（建议横向、宽度 2000px 以上）'
  $dialog.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff|所有文件|*.*'
  $dialog.Multiselect = $false
  if ($dialog.ShowDialog() -ne $true) { throw '已取消图片选择。' }
  $dialog.FileName
}

function Read-ThemeName {
  Add-Type -AssemblyName Microsoft.VisualBasic
  $value = [Microsoft.VisualBasic.Interaction]::InputBox(
    '给这套主题起个名字',
    'Codex Immersive Skin',
    '我的 Codex 主题'
  )
  if ([string]::IsNullOrWhiteSpace($value)) { throw '已取消主题设置。' }
  $value
}

function Remove-VerifiedThemeTransactionDirectory {
  param([string]$Path, [string]$Prefix)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $resolved = [IO.Path]::GetFullPath($Path)
  $leaf = Split-Path -Leaf $resolved
  if (-not (Test-CodexWindowsPathWithin -Path $resolved -Root $script:StateRoot) -or
      -not $leaf.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-CodexWindowsPathChainNoReparse -Path $resolved -Boundary $script:StateRoot) -or
      -not (Test-CodexWindowsTreeNoReparse -Path $resolved)) {
    throw '拒绝删除未通过身份检查的主题事务目录。'
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Write-ThemeIdentity {
  param([Parameter(Mandatory = $true)][string]$Root)
  $identity = [ordered]@{ schemaVersion = 1; product = 'Codex Immersive Skin theme' }
  [IO.File]::WriteAllText(
    (Join-Path $Root $script:ThemeIdentityName),
    ($identity | ConvertTo-Json -Depth 3) + "`n",
    $script:Utf8NoBom)
}

function Assert-OwnedThemeTree {
  param([Parameter(Mandatory = $true)][string]$Root)
  if (-not (Test-Path -LiteralPath $Root -PathType Container) -or
      -not (Test-CodexWindowsPathChainNoReparse -Path $Root -Boundary $script:StateRoot) -or
      -not (Test-CodexWindowsTreeNoReparse -Path $Root)) {
    throw '现有主题目录不是可安全替换的普通目录。'
  }
  $identityPath = Join-Path $Root $script:ThemeIdentityName
  $themePath = Join-Path $Root 'theme.json'
  if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    throw '现有主题目录缺少本项目的身份文件；已拒绝替换。'
  }
  try {
    $identity = Read-CodexWindowsUtf8Text -Path $identityPath | ConvertFrom-Json
    $theme = Read-CodexWindowsUtf8Text -Path $themePath | ConvertFrom-Json
  } catch { throw '现有主题目录的身份或主题元数据无法解析。' }
  if ([int]$identity.schemaVersion -ne 1 -or
      [string]$identity.product -ne 'Codex Immersive Skin theme' -or
      [int]$theme.schemaVersion -ne 1 -or
      [string]$theme.brandSubtitle -ne 'CODEX IMMERSIVE SKIN') {
    throw '现有主题目录身份不匹配；已拒绝替换。'
  }
}

function Recover-InterruptedThemeTransaction {
  $prefix = 'theme.previous.'
  $previousCandidates = @(Get-ChildItem -LiteralPath $script:StateRoot -Directory -Force -ErrorAction Stop | Where-Object {
    $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
  })
  foreach ($candidate in $previousCandidates) { Assert-OwnedThemeTree -Root $candidate.FullName }
  if (-not (Test-Path -LiteralPath $script:ThemeDir)) {
    if ($previousCandidates.Count -gt 1) {
      throw '检测到多个遗留旧主题，无法安全判断恢复顺序。'
    }
    if ($previousCandidates.Count -eq 1) {
      Move-Item -LiteralPath $previousCandidates[0].FullName -Destination $script:ThemeDir
      Write-Warning '已恢复上次意外中断前的主题目录。'
    }
  } elseif ($previousCandidates.Count -gt 0) {
    Write-Warning '检测到遗留的 theme.previous 目录；当前主题保持不变，待本次成功后人工核对。'
  }
}

$options = Read-CustomizeOptions -Values @(ConvertTo-CodexWindowsRemainingArguments -Values $Arguments)
$operationLock = Open-CodexWindowsOperationLock -StateRoot $script:StateRoot
try {
$runtime = Initialize-WindowsRuntime
Assert-CodexWindowsStateRoot -Path $script:StateRoot -Create
Recover-InterruptedThemeTransaction
$transactionId = '{0}.{1}' -f $PID, [Guid]::NewGuid().ToString('N')
$staging = Join-Path $script:StateRoot ('theme.staging.' + $transactionId)
$previous = Join-Path $script:StateRoot ('theme.previous.' + $transactionId)
$failed = Join-Path $script:StateRoot ('theme.failed.' + $transactionId)
$previousExists = $false
$themeSwapped = $false
$committed = $false

try {
  if ($options.ResetDemo) {
    if (Test-Path -LiteralPath $script:ThemeDir) {
      Assert-OwnedThemeTree -Root $script:ThemeDir
      Move-Item -LiteralPath $script:ThemeDir -Destination $previous
      $previousExists = $true
    }
    $themeSwapped = $true
  }
  else {
    if ([string]::IsNullOrWhiteSpace($options.Image)) { $options.Image = Select-LocalImage }
    $sourceImage = [IO.Path]::GetFullPath($options.Image)
    if (-not (Test-Path -LiteralPath $sourceImage -PathType Leaf)) { throw '所选图片不存在。' }
    $sourceLength = (Get-Item -LiteralPath $sourceImage).Length
    if ($sourceLength -gt 52428800) { throw '所选图片超过 50 MB，请选择更小的文件。' }
    if ([string]::IsNullOrWhiteSpace($options.Name)) { $options.Name = Read-ThemeName }
    if ([string]::IsNullOrWhiteSpace($options.Tagline)) {
      $options.Tagline = '把喜欢的画面变成可交互的 Codex 工作台。'
    }
    if ([string]::IsNullOrWhiteSpace($options.Quote)) { $options.Quote = 'MAKE SOMETHING WONDERFUL' }

    [void](New-Item -ItemType Directory -Path $staging)
    $imageName = 'background-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N') + '.jpg'
    $prepared = Join-Path $staging $imageName
    & (Join-Path $script:ScriptDir 'normalize-image-windows.ps1') `
      -InputPath $sourceImage -OutputPath $prepared -MaxDimension 3200 -Format Jpeg -Quality 84
    if (-not (Test-Path -LiteralPath $prepared -PathType Leaf)) {
      throw 'Windows 无法转换所选图片。请使用 PNG、JPEG、BMP、GIF 或 TIFF。'
    }
    $preparedLength = (Get-Item -LiteralPath $prepared).Length
    if ($preparedLength -lt 1 -or $preparedLength -gt 16777216) {
      throw '处理后的图片为空或超过 16 MB。'
    }

    $styleArguments = @(
      (Join-Path $script:ScriptDir 'analyze-image.mjs'),
      '--image', $prepared, '--format', 'tsv'
    )
    foreach ($mapping in @(
      @('--appearance', 'Appearance'),
      @('--accent', 'Accent'),
      @('--secondary', 'Secondary'),
      @('--highlight', 'Highlight')
    )) {
      $explicit = [string]$options.($mapping[1])
      if (-not [string]::IsNullOrWhiteSpace($explicit)) { $styleArguments += @($mapping[0], $explicit) }
    }
    $analysisError = Join-Path $staging 'analysis-warning.txt'
    $analysisResult = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments $styleArguments `
      -StandardErrorPath $analysisError
    $styleLines = @($analysisResult.Output)
    $analysisExit = $analysisResult.ExitCode
    if (Test-Path -LiteralPath $analysisError -PathType Leaf) {
      $warning = [IO.File]::ReadAllText($analysisError)
      if (-not [string]::IsNullOrWhiteSpace($warning)) { [Console]::Error.Write($warning) }
      Remove-Item -LiteralPath $analysisError -Force
    }
    if ($analysisExit -ne 0) { throw '自动主题取色进程启动失败。' }
    $fields = (($styleLines -join "`n").Trim()) -split "`t"
    if ($fields.Count -ne 4 -or $fields[0] -notin @('light', 'dark') -or
        $fields[1] -notmatch '^#[0-9a-f]{6}$' -or
        $fields[2] -notmatch '^#[0-9a-f]{6}$' -or
        $fields[3] -notmatch '^#[0-9a-f]{6}$') {
      throw '自动主题取色返回了无效结果。'
    }

    $writeResult = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments @(
      (Join-Path $script:ScriptDir 'write-theme.mjs'), 'custom',
      '--output-dir', $staging, '--image', $imageName,
      '--name', $options.Name, '--tagline', $options.Tagline, '--quote', $options.Quote,
      '--appearance', $fields[0], '--accent', $fields[1],
      '--secondary', $fields[2], '--highlight', $fields[3]
    )
    if ($writeResult.ExitCode -ne 0) { throw '写入自定义主题失败。' }
    Write-ThemeIdentity -Root $staging
    Assert-OwnedThemeTree -Root $staging

    if (Test-Path -LiteralPath $script:ThemeDir) {
      Assert-OwnedThemeTree -Root $script:ThemeDir
      Move-Item -LiteralPath $script:ThemeDir -Destination $previous
      $previousExists = $true
    }
    Move-Item -LiteralPath $staging -Destination $script:ThemeDir
    $themeSwapped = $true
  }

  if ($options.ApplyNow) {
    & (Join-Path $script:ScriptDir 'start-dream-skin-windows.ps1') '--prompt-restart'
  }
  $committed = $true
  if ($previousExists) {
    try { Remove-VerifiedThemeTransactionDirectory -Path $previous -Prefix 'theme.previous.' }
    catch { Write-Warning '主题已提交，但旧主题事务目录未能清理。' }
  }
  Write-Host 'Codex Immersive Skin 主题已准备完成。'
}
catch {
  $originalError = $_
  $rollbackErrors = New-Object Collections.ArrayList
  if ($themeSwapped -and (Test-Path -LiteralPath $script:ThemeDir)) {
    try {
      Assert-OwnedThemeTree -Root $script:ThemeDir
      Move-Item -LiteralPath $script:ThemeDir -Destination $failed
    }
    catch { [void]$rollbackErrors.Add('新主题隔离失败') }
  }
  if ($previousExists -and (Test-Path -LiteralPath $previous)) {
    try {
      if (Test-Path -LiteralPath $script:ThemeDir) { throw '主题目标仍被占用。' }
      Assert-OwnedThemeTree -Root $previous
      Move-Item -LiteralPath $previous -Destination $script:ThemeDir
    }
    catch { [void]$rollbackErrors.Add('旧主题恢复失败') }
  }
  if (Test-Path -LiteralPath $staging) {
    try { Remove-VerifiedThemeTransactionDirectory -Path $staging -Prefix 'theme.staging.' }
    catch { [void]$rollbackErrors.Add('主题暂存目录清理失败') }
  }
  if (Test-Path -LiteralPath $failed) {
    try { Remove-VerifiedThemeTransactionDirectory -Path $failed -Prefix 'theme.failed.' }
    catch { [void]$rollbackErrors.Add('失败主题目录清理失败') }
  }
  foreach ($rollbackError in $rollbackErrors) {
    Write-Warning "主题回滚警告：$rollbackError。恢复材料已尽量保留。"
  }
  throw $originalError
}
finally {
  if (-not $committed -and (Test-Path -LiteralPath $staging)) {
    try { Remove-VerifiedThemeTransactionDirectory -Path $staging -Prefix 'theme.staging.' } catch { }
  }
}
}
finally {
  Close-CodexWindowsOperationLock -Lock $operationLock
}
