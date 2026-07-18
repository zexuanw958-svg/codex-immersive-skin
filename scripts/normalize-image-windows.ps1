[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$InputPath,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$OutputPath,

  [ValidateRange(1, 4096)]
  [int]$MaxDimension = 64,

  [ValidateSet('Bmp', 'Jpeg')]
  [string]$Format = 'Bmp',

  [ValidateRange(1, 100)]
  [int]$Quality = 84
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$source = $null
$bitmap = $null
$graphics = $null
$encoderParameters = $null
$qualityParameter = $null

try {
  $inputFullPath = [System.IO.Path]::GetFullPath($InputPath)
  $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
  if (-not [System.IO.File]::Exists($inputFullPath)) {
    throw "Input image does not exist: $inputFullPath"
  }
  if ([System.StringComparer]::OrdinalIgnoreCase.Equals($inputFullPath, $outputFullPath)) {
    throw 'InputPath and OutputPath must be different files.'
  }

  $outputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
  if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    throw 'OutputPath must include a parent directory.'
  }
  [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

  $source = [System.Drawing.Image]::FromFile($inputFullPath, $true)
  if ($source.Width -lt 1 -or $source.Height -lt 1) {
    throw 'Input image has invalid dimensions.'
  }

  $largestDimension = [Math]::Max($source.Width, $source.Height)
  $scale = [Math]::Min(1.0, [double]$MaxDimension / $largestDimension)
  $targetWidth = [Math]::Max(1, [int][Math]::Round($source.Width * $scale))
  $targetHeight = [Math]::Max(1, [int][Math]::Round($source.Height * $scale))

  $pixelFormat = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
  $bitmap = [System.Drawing.Bitmap]::new($targetWidth, $targetHeight, $pixelFormat)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([System.Drawing.Color]::White)
  $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $destination = [System.Drawing.Rectangle]::new(0, 0, $targetWidth, $targetHeight)
  $graphics.DrawImage(
    $source,
    $destination,
    0,
    0,
    $source.Width,
    $source.Height,
    [System.Drawing.GraphicsUnit]::Pixel
  )
  $graphics.Dispose()
  $graphics = $null

  if ($Format -eq 'Bmp') {
    $bitmap.Save($outputFullPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
  }
  else {
    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
      Where-Object { $_.MimeType -eq 'image/jpeg' } |
      Select-Object -First 1
    if ($null -eq $jpegCodec) {
      throw 'The Windows JPEG encoder is unavailable.'
    }
    $encoderParameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
    $qualityParameter = [System.Drawing.Imaging.EncoderParameter]::new(
      [System.Drawing.Imaging.Encoder]::Quality,
      [long]$Quality
    )
    $encoderParameters.Param[0] = $qualityParameter
    $bitmap.Save($outputFullPath, $jpegCodec, $encoderParameters)
  }
  $output = [System.IO.FileInfo]::new($outputFullPath)
  if (-not $output.Exists -or $output.Length -lt 54) {
    throw 'System.Drawing did not produce a valid BMP file.'
  }
}
finally {
  if ($null -ne $qualityParameter) { $qualityParameter.Dispose() }
  if ($null -ne $encoderParameters) { $encoderParameters.Dispose() }
  if ($null -ne $graphics) { $graphics.Dispose() }
  if ($null -ne $bitmap) { $bitmap.Dispose() }
  if ($null -ne $source) { $source.Dispose() }
}
