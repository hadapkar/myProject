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

#
# 2) Patch Windows binary name (controls .exe file name)
#
$windowsCmake = Join-Path $ProjectDir "windows\CMakeLists.txt"
if (Test-Path $windowsCmake) {
  $cmakeContent = Get-Content -Raw $windowsCmake
  $cmakeMarker = "# KINGMAKER_BINARY_NAME"
  if ($cmakeContent -notlike "*$cmakeMarker*") {
    # Note: use single-quoted regex strings; PowerShell does not support backslash-escaping quotes.
    $pattern = 'set\\(BINARY_NAME\\s+"[^"]+"\\)'
    $replacement = @"
$cmakeMarker
set(BINARY_NAME "$appBinaryName")
"@
    $patchedCmake = [System.Text.RegularExpressions.Regex]::Replace($cmakeContent, $pattern, $replacement, 1)
    if ($patchedCmake -ne $cmakeContent) {
      Set-Content -Path $windowsCmake -Value $patchedCmake -NoNewline
      Write-Host "Patched binary name: $windowsCmake"
    } else {
      Write-Warning "Could not patch BINARY_NAME in: $windowsCmake"
    }
  } else {
    Write-Host "Binary name already patched: $windowsCmake"
  }
} else {
  Write-Warning "windows/CMakeLists.txt not found; skipping binary name patch."
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
