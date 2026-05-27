param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectDir
)

$mainCpp = Join-Path $ProjectDir "windows\runner\main.cpp"
if (-not (Test-Path $mainCpp)) {
  Write-Error "windows runner main.cpp not found at: $mainCpp"
  exit 1
}

$content = Get-Content -Raw $mainCpp

# Patch only if the marker is missing (idempotent).
$marker = "// FUNTARGET_WINDOW_DEFAULTS"
if ($content -like "*$marker*") {
  Write-Host "Windows runner already patched."
  exit 0
}

# We patch the template-created `Win32Window::Size size(...)` line when present.
# Flutter templates may change across versions, so we try multiple patterns.

$replacement = @"
$marker
  // Set a desktop-friendly default size that matches the FunTarget stage aspect.
  // Design: 1024x768 with a vertical squash factor (0.7) in-game.
  Win32Window::Size size(1400, 820);
"@

# 1) Exact match (historical template): Win32Window::Size size(1280, 720);
$patched = $content -replace "Win32Window::Size size\\(\\s*1280\\s*,\\s*720\\s*\\);", $replacement

if ($patched -eq $content) {
  # 2) Generic match: Win32Window::Size size(<any>, <any>);
  $patternAny = "Win32Window::Size size\\(\\s*\\d+\\s*,\\s*\\d+\\s*\\);"
  $patched = [System.Text.RegularExpressions.Regex]::Replace($content, $patternAny, $replacement, 1)
}

if ($patched -eq $content) {
  Write-Warning "Could not patch default size line (template mismatch). Leaving main.cpp unchanged."
  exit 0
}

Set-Content -Path $mainCpp -Value $patched -NoNewline
Write-Host "Patched Windows runner: $mainCpp"
