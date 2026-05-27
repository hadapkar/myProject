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
# Current Flutter templates typically contain:
#   Win32Window::Size size(1280, 720);
$patched = $content -replace "Win32Window::Size size\\(\\s*1280\\s*,\\s*720\\s*\\);",
@"
$marker
  // Set a desktop-friendly default size that matches the FunTarget stage aspect.
  // Design: 1024x768 with a vertical squash factor (0.7) in-game.
  Win32Window::Size size(1400, 820);
"@

if ($patched -eq $content) {
  # Fallback: if the exact template line didn't match, still append a note to help debugging.
  Write-Warning "Could not patch default size line (template mismatch). Leaving main.cpp unchanged."
  exit 0
}

Set-Content -Path $mainCpp -Value $patched -NoNewline
Write-Host "Patched Windows runner: $mainCpp"
