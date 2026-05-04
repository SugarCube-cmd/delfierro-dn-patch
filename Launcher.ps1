$ErrorActionPreference = 'Stop'

$REPO      = "SugarCube-cmd/delfierro-dn-patch"
$RAW_BASE  = "https://raw.githubusercontent.com/$REPO/main"
$GAME_DIR  = Split-Path $PSScriptRoot -Parent
$GAME_EXE  = Join-Path $GAME_DIR "DragonNest.exe"
$VER_FILE  = Join-Path $PSScriptRoot "version.txt"

function Write-Status($msg, $color = "Cyan") {
    Write-Host "[Del Fierro DN] $msg" -ForegroundColor $color
}

Write-Host ""
Write-Host "  ====================================" -ForegroundColor Yellow
Write-Host "    Del Fierro Dragon Nest Launcher   " -ForegroundColor Yellow
Write-Host "  ====================================" -ForegroundColor Yellow
Write-Host ""

# Read local version
$localVersion = "0.0"
if (Test-Path $VER_FILE) {
    $localVersion = (Get-Content $VER_FILE -Raw).Trim()
}
Write-Status "Local version  : $localVersion"

# Fetch remote version
try {
    $remoteVersion = (Invoke-WebRequest -Uri "$RAW_BASE/version.txt" -UseBasicParsing).Content.Trim()
    Write-Status "Remote version : $remoteVersion"
} catch {
    Write-Status "Could not reach update server. Starting game anyway..." "Yellow"
    Start-Sleep 2
    Start-Process $GAME_EXE -ArgumentList "/logintoken: /ip:10.255.227.166 /port:14300 /Lver:2 /use_packing /gamechanneling:0"
    exit
}

# Check if update needed
if ($localVersion -eq $remoteVersion) {
    Write-Status "Game is up to date!" "Green"
} else {
    Write-Status "Update found! Downloading patch $localVersion -> $remoteVersion ..." "Yellow"
    Write-Host ""

    # Fetch manifest
    $manifest = (Invoke-WebRequest -Uri "$RAW_BASE/manifest.json" -UseBasicParsing).Content | ConvertFrom-Json

    foreach ($file in $manifest.files) {
        $destPath = Join-Path $GAME_DIR $file.path
        $destDir  = Split-Path $destPath -Parent

        Write-Status "Downloading: $($file.path)"

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        $tmp = "$destPath.tmp"
        try {
            Invoke-WebRequest -Uri $file.url -OutFile $tmp -UseBasicParsing
            Move-Item -Path $tmp -Destination $destPath -Force
            Write-Status "  OK: $($file.path)" "Green"
        } catch {
            Write-Status "  FAILED: $($file.path) - $_" "Red"
            if (Test-Path $tmp) { Remove-Item $tmp -Force }
        }
    }

    # Save new version
    Set-Content -Path $VER_FILE -Value $remoteVersion
    Write-Host ""
    Write-Status "Patch complete! Version is now $remoteVersion" "Green"
}

Write-Host ""
Write-Status "Starting game..." "Cyan"
Start-Sleep 1

Start-Process $GAME_EXE -ArgumentList "/logintoken: /ip:10.255.227.166 /port:14300 /Lver:2 /use_packing /gamechanneling:0"
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$GAME_DIR\RenameWindow.ps1`""
