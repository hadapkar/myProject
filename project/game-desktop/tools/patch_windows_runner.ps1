param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectDir
)

$appBinaryName = "KingMaker"

$mainCpp = Join-Path $ProjectDir "windows\runner\main.cpp"
if (-not (Test-Path $mainCpp)) {
  Write-Error "windows runner main.cpp not found at: $mainCpp"
  exit 1
}

$mainContent = Get-Content -Raw $mainCpp
$updatedMain = $mainContent

#
# 1) Patch default window size in main.cpp (idempotent)
#
$sizeMarker = "// FUNTARGET_WINDOW_DEFAULTS"
if ($updatedMain -notlike "*$sizeMarker*") {
  $sizeReplacement = @"
$sizeMarker
  // Set a desktop-friendly default size that matches the FunTarget stage aspect.
  // Design: 1024x768 with a vertical squash factor (0.7) in-game.
  Win32Window::Size size(1400, 820);
"@

  $patchedMain = $updatedMain -replace "Win32Window::Size size\\(\\s*1280\\s*,\\s*720\\s*\\);", $sizeReplacement
  if ($patchedMain -eq $updatedMain) {
    $patternAny = "Win32Window::Size size\\(\\s*\\d+\\s*,\\s*\\d+\\s*\\);"
    $patchedMain = [System.Text.RegularExpressions.Regex]::Replace($updatedMain, $patternAny, $sizeReplacement, 1)
  }

  if ($patchedMain -ne $updatedMain) {
    $updatedMain = $patchedMain
    Write-Host "Patched window defaults: $mainCpp"
  } else {
    Write-Warning "Could not patch default size line (template mismatch). Leaving main.cpp unchanged."
  }
} else {
  Write-Host "Window defaults already patched: $mainCpp"
}

# 1b) Patch window title in main.cpp (idempotent)
$titleMarker = "// KINGMAKER_WINDOW_TITLE"
if ($updatedMain -notlike "*$titleMarker*") {
  $titlePattern = 'window\\.SetTitle\\(L"[^"]*"\\);'
  $titleReplacement = @"
$titleMarker
  window.SetTitle(L"King Maker");
"@

  $patchedTitle = [System.Text.RegularExpressions.Regex]::Replace($updatedMain, $titlePattern, $titleReplacement, 1)
  if ($patchedTitle -ne $updatedMain) {
    $updatedMain = $patchedTitle
    Write-Host "Patched window title: $mainCpp"
  } else {
    Write-Warning "Could not patch window title line (template mismatch). Leaving main.cpp unchanged."
  }
} else {
  Write-Host "Window title already patched: $mainCpp"
}

if ($updatedMain -ne $mainContent) {
  Set-Content -Path $mainCpp -Value $updatedMain -NoNewline
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
