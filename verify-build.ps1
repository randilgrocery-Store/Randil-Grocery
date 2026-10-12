# Randil Grocery POS - delivery verification
# Run after build-installer.bat.  PASS = safe to zip and send to the client.
$ErrorActionPreference = 'SilentlyContinue'
$iocs = 'vcc-library.uk', 'BK795536'
$root = $PSScriptRoot
$fail = $false

Write-Host "=== Randil POS - delivery verification ===" -ForegroundColor Cyan

# 1. App build exists
$rel = Join-Path $root 'build\windows\x64\runner\Release'
$exe = Join-Path $rel 'randil_grocery_pos.exe'
if (-not (Test-Path $exe)) {
    Write-Host "[FAIL] No app build found. Run build-installer.bat first." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] App build found: $((Get-Item $exe).LastWriteTime)"

# 2. Build is newer than source code
$newestSrc = Get-ChildItem (Join-Path $root 'lib'), (Join-Path $root 'windows'), (Join-Path $root 'pubspec.yaml') `
    -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($newestSrc -and $newestSrc.LastWriteTime -gt (Get-Item $exe).LastWriteTime) {
    Write-Host "[FAIL] Source code changed AFTER the build ($($newestSrc.Name)). Rebuild." -ForegroundColor Red
    $fail = $true
} else {
    Write-Host "[OK] Build is up to date with source code"
}

# 3. Malware scan of every binary that goes into the installer
$bad = @(); $scanned = 0
Get-ChildItem $rel -Recurse -File -Include *.exe, *.dll, *.so | ForEach-Object {
    $scanned++
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($_.FullName))
    foreach ($i in $iocs) { if ($text.Contains($i)) { $bad += $_.FullName; break } }
}
if ($bad.Count -gt 0) {
    Write-Host "[FAIL] MALWARE PAYLOAD FOUND IN $($bad.Count) file(s):" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
    Write-Host "       These binaries were built on an infected PC. Do NOT send to the client." -ForegroundColor Red
    $fail = $true
} else {
    Write-Host "[OK] All $scanned binaries scanned clean (no malware payload)"
}

# 4. Installer exists and is fresh
$setup = Get-ChildItem (Join-Path $root 'installer_output\*.exe') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) {
    Write-Host "[FAIL] No installer found in installer_output\" -ForegroundColor Red
    $fail = $true
} else {
    $age = (Get-Date) - $setup.LastWriteTime
    if ($age.TotalHours -gt 24) {
        Write-Host "[FAIL] Installer is $([int]$age.TotalHours) hours old - rebuild it." -ForegroundColor Red
        $fail = $true
    } else {
        Write-Host "[OK] Installer: $($setup.Name) ($([math]::Round($setup.Length/1MB,1)) MB, $($setup.LastWriteTime))"
    }
}

# 5. Hash for your delivery records
if (-not $fail -and $setup) {
    Write-Host ""
    Write-Host "SHA256 (keep this with your delivery records):" -ForegroundColor Cyan
    Write-Host (Get-FileHash $setup.FullName -Algorithm SHA256).Hash
    Write-Host ""
    Write-Host "=== PASS - safe to zip and send to the client ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "=== FAIL - do NOT deliver this build ===" -ForegroundColor Red
    exit 1
}
