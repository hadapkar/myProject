param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectDir
)

$appBinaryName = "KingMaker"

function Set-KingMakerWindowsIcon {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectDir
  )

  $logoPath = Join-Path $ProjectDir "assets\app\app_icon.jpg"
  $iconPath = Join-Path $ProjectDir "windows\runner\resources\app_icon.ico"
  if (-not (Test-Path $logoPath)) {
    Write-Warning "Logo asset not found for Windows icon: $logoPath"
    return
  }

  $iconDir = Split-Path -Parent $iconPath
  if (-not (Test-Path $iconDir)) {
    New-Item -ItemType Directory -Path $iconDir -Force | Out-Null
  }

  Add-Type -AssemblyName System.Drawing
  $src = $null
  $bmp = $null
  $graphics = $null
  $pngStream = $null
  $fileStream = $null
  $writer = $null
  try {
    $src = [System.Drawing.Image]::FromFile($logoPath)
    $bmp = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $side = [Math]::Min($src.Width, $src.Height)
    $srcX = [int](($src.Width - $side) / 2)
    $srcY = [int](($src.Height - $side) / 2)
    $srcRect = New-Object System.Drawing.Rectangle $srcX, $srcY, $side, $side
    $destRect = New-Object System.Drawing.Rectangle 0, 0, 256, 256
    $graphics.DrawImage($src, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

    $pngStream = New-Object System.IO.MemoryStream
    $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $pngStream.ToArray()

    $fileStream = [System.IO.File]::Open($iconPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $writer = New-Object System.IO.BinaryWriter $fileStream
    $writer.Write([UInt16]0)       # reserved
    $writer.Write([UInt16]1)       # icon type
    $writer.Write([UInt16]1)       # image count
    $writer.Write([Byte]0)         # width 256
    $writer.Write([Byte]0)         # height 256
    $writer.Write([Byte]0)         # color count
    $writer.Write([Byte]0)         # reserved
    $writer.Write([UInt16]1)       # planes
    $writer.Write([UInt16]32)      # bit count
    $writer.Write([UInt32]($pngBytes.Length))
    $writer.Write([UInt32]22)      # image data offset
    $writer.Write($pngBytes)
    Write-Host "Generated Windows app icon: $iconPath"
  } finally {
    if ($writer -ne $null) { $writer.Dispose() }
    if ($fileStream -ne $null) { $fileStream.Dispose() }
    if ($pngStream -ne $null) { $pngStream.Dispose() }
    if ($graphics -ne $null) { $graphics.Dispose() }
    if ($bmp -ne $null) { $bmp.Dispose() }
    if ($src -ne $null) { $src.Dispose() }
  }
}

$mainCpp = Join-Path $ProjectDir "windows\runner\main.cpp"
if (-not (Test-Path $mainCpp)) {
  Write-Error "windows runner main.cpp not found at: $mainCpp"
  exit 1
}

$mainContent = Get-Content -Raw $mainCpp

#
# 1) Patch default window size in main.cpp (idempotent)
#
$sizeMarker = "// FUNTARGET_WINDOW_DEFAULTS"
if ($mainContent -notlike "*$sizeMarker*") {
  $sizeReplacement = @"
$sizeMarker
  // Set a desktop-friendly default size that matches the FunTarget stage aspect.
  // Design: 1024x768 with a vertical squash factor (0.7) in-game.
  Win32Window::Size size(1400, 820);
"@

  $patchedMain = $mainContent -replace "Win32Window::Size size\\(\\s*1280\\s*,\\s*720\\s*\\);", $sizeReplacement
  if ($patchedMain -eq $mainContent) {
    $patternAny = "Win32Window::Size size\\(\\s*\\d+\\s*,\\s*\\d+\\s*\\);"
    $patchedMain = [System.Text.RegularExpressions.Regex]::Replace($mainContent, $patternAny, $sizeReplacement, 1)
  }

  if ($patchedMain -ne $mainContent) {
    Set-Content -Path $mainCpp -Value $patchedMain -NoNewline
    Write-Host "Patched window defaults: $mainCpp"
  } else {
    Write-Warning "Could not patch default size line (template mismatch). Leaving main.cpp unchanged."
  }
} else {
  Write-Host "Window defaults already patched: $mainCpp"
}

# 1b) Patch window title in main.cpp (idempotent)
$titleMarker = "// KINGMAKER_WINDOW_TITLE"
if ($mainContent -notlike "*$titleMarker*") {
  $titlePattern = 'window\\.SetTitle\\(L"[^"]*"\\);'
  $titleReplacement = @"
$titleMarker
  window.SetTitle(L"King Maker");
"@

  $patchedTitle = [System.Text.RegularExpressions.Regex]::Replace($mainContent, $titlePattern, $titleReplacement, 1)
  if ($patchedTitle -ne $mainContent) {
    Set-Content -Path $mainCpp -Value $patchedTitle -NoNewline
    Write-Host "Patched window title: $mainCpp"
  } else {
    Write-Warning "Could not patch window title line (template mismatch). Leaving main.cpp unchanged."
  }
} else {
  Write-Host "Window title already patched: $mainCpp"
}

#
# 2) Patch Windows binary name (controls .exe file name)
#
function Patch-BinaryNameInCmakeFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    return $false
  }

  $cmakeContent = Get-Content -Raw $Path
  $cmakeMarker = "# KINGMAKER_BINARY_NAME"
  if ($cmakeContent -like "*$cmakeMarker*") {
    Write-Host "Binary name already patched: $Path"
    return $true
  }

  # Note: use single-quoted regex strings; PowerShell does not support backslash-escaping quotes.
  # Match either: set(BINARY_NAME "foo") or set(BINARY_NAME foo)
  $pattern = 'set\\(BINARY_NAME\\s+("?[A-Za-z0-9_\\-]+"?)\\)'
  $replacement = @"
$cmakeMarker
set(BINARY_NAME "$appBinaryName")
"@

  $patchedCmake = [System.Text.RegularExpressions.Regex]::Replace($cmakeContent, $pattern, $replacement, 1)
  if ($patchedCmake -ne $cmakeContent) {
    Set-Content -Path $Path -Value $patchedCmake -NoNewline
    Write-Host "Patched binary name: $Path"
    return $true
  }

  return $false
}

# 2) Patch Windows binary name (controls .exe file name)
$cmakeCandidates = @(
  (Join-Path $ProjectDir "windows\CMakeLists.txt"),
  (Join-Path $ProjectDir "windows\runner\CMakeLists.txt")
)

$patchedAny = $false
foreach ($cmakePath in $cmakeCandidates) {
  if (Patch-BinaryNameInCmakeFile -Path $cmakePath) {
    $patchedAny = $true
  }
}

if (-not $patchedAny) {
  Write-Warning "Could not patch BINARY_NAME in any CMakeLists.txt under windows/. The output exe may keep the default name."
}

Set-KingMakerWindowsIcon -ProjectDir $ProjectDir

#
# 3) Patch Windows version resource strings (cosmetic)
#
$runnerRc = Join-Path $ProjectDir "windows\runner\Runner.rc"
if (Test-Path $runnerRc) {
  $rc = Get-Content -Raw $runnerRc
  $rcMarker = "// KINGMAKER_RC_STRINGS"
  if ($rc -notlike "*$rcMarker*") {
    $patchedRc = $rc
    $patchedRc = [System.Text.RegularExpressions.Regex]::Replace(
      $patchedRc,
      '(VALUE\\s+"FileDescription",\\s+")[^"]*(".*\\\\0")',
      { param($m) $m.Groups[1].Value + $appBinaryName + $m.Groups[2].Value },
      1
    )
    $patchedRc = [System.Text.RegularExpressions.Regex]::Replace(
      $patchedRc,
      '(VALUE\\s+"ProductName",\\s+")[^"]*(".*\\\\0")',
      { param($m) $m.Groups[1].Value + $appBinaryName + $m.Groups[2].Value },
      1
    )
    if ($patchedRc -ne $rc) {
      # Add marker at top for idempotency (keep it a comment in RC syntax).
      $patchedRc = "$rcMarker`r`n" + $patchedRc
      Set-Content -Path $runnerRc -Value $patchedRc -NoNewline
      Write-Host "Patched version resource strings: $runnerRc"
    } else {
      Write-Warning "No matching RC strings found to patch in: $runnerRc"
    }
  } else {
    Write-Host "RC strings already patched: $runnerRc"
  }
}
