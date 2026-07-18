#requires -Version 5.1

Set-StrictMode -Version 2.0

function Assert-CodexWindowsStateRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Create
  )

  if ($Create) { [void](New-Item -ItemType Directory -Path $Path -Force) }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw 'The Codex Immersive Skin state directory does not exist.'
  }
  $boundary = if ($env:CODEX_IMMERSIVE_TEST_MODE -eq '1' -and
      -not [string]::IsNullOrWhiteSpace($env:CODEX_IMMERSIVE_TEST_ROOT)) {
    [IO.Path]::GetFullPath($env:CODEX_IMMERSIVE_TEST_ROOT)
  } else {
    [IO.Path]::GetFullPath($env:LOCALAPPDATA)
  }
  if (-not (Test-CodexWindowsPathChainNoReparse -Path $Path -Boundary $boundary) -or
      -not (Test-CodexWindowsTreeNoReparse -Path $Path)) {
    throw 'The Codex Immersive Skin state directory contains or traverses a reparse point.'
  }
}
