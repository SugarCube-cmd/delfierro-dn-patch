$ErrorActionPreference = 'Stop'

$REPO     = "SugarCube-cmd/delfierro-dn-patch"
$RAW_BASE = "https://raw.githubusercontent.com/$REPO/main"
$GAME_DIR = Split-Path $PSScriptRoot -Parent
$GAME_EXE = Join-Path $GAME_DIR "DragonNest.exe"
$VER_FILE = Join-Path $PSScriptRoot "version.txt"
$TMP_DIR  = Join-Path $PSScriptRoot "tmp"

function Write-Status($msg, $color = "Cyan") {
    Write-Host "[Del Fierro DN] $msg" -ForegroundColor $color
}

function Invoke-DnPatch {
    param([string]$PakPath, [string]$PatchPath, [string]$TargetFile)

    $patchBytes = [System.IO.File]::ReadAllBytes($PatchPath)
    $magic = [System.Text.Encoding]::ASCII.GetString($patchBytes, 0, 4)
    if ($magic -ne 'DNPT') { throw "Invalid patch file" }

    $newCompSize   = [BitConverter]::ToUInt32($patchBytes, 4)
    $newUncompSize = [BitConverter]::ToUInt32($patchBytes, 8)
    $newData       = $patchBytes[12..($patchBytes.Length - 1)]

    $pak     = [System.IO.File]::ReadAllBytes($PakPath)
    $pakSize = $pak.Length
    $filecount   = [BitConverter]::ToUInt32($pak, 260)
    $tableOffset = [BitConverter]::ToUInt32($pak, 264)
    $entrySize   = [int](($pakSize - $tableOffset) / $filecount)

    for ($i = 0; $i -lt $filecount; $i++) {
        $base      = $tableOffset + $i * $entrySize
        $nameBytes = $pak[$base..($base + 255)]
        $nullIdx   = [Array]::IndexOf($nameBytes, [byte]0)
        if ($nullIdx -lt 0) { $nullIdx = 256 }
        $entryName = [System.Text.Encoding]::UTF8.GetString($nameBytes, 0, $nullIdx).Replace('\', '/')
        if ($entryName.ToLower() -notlike "*$($TargetFile.ToLower())*") { continue }

        $metaBase    = $base + 256
        $oldCompSize = [BitConverter]::ToUInt32($pak, $metaBase)
        $dataOffset  = [BitConverter]::ToUInt32($pak, $metaBase + 12)

        if ($newCompSize -gt $oldCompSize) { return $false }

        [Array]::Copy($newData, 0, $pak, $dataOffset, $newData.Length)
        $pad = $oldCompSize - $newCompSize
        for ($p = 0; $p -lt $pad; $p++) { $pak[$dataOffset + $newData.Length + $p] = 0 }

        $b = [BitConverter]::GetBytes([uint32]$newCompSize);   [Array]::Copy($b, 0, $pak, $metaBase,     4)
        $b = [BitConverter]::GetBytes([uint32]$newUncompSize); [Array]::Copy($b, 0, $pak, $metaBase + 4, 4)
        $b = [BitConverter]::GetBytes([uint32]$newCompSize);   [Array]::Copy($b, 0, $pak, $metaBase + 8, 4)

        [System.IO.File]::WriteAllBytes($PakPath, $pak)
        return $true
    }
    throw "File '$TargetFile' not found in pak"
}

# ── Main ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ====================================" -ForegroundColor Yellow
Write-Host "    Del Fierro Dragon Nest Launcher   " -ForegroundColor Yellow
Write-Host "  ====================================" -ForegroundColor Yellow
Write-Host ""

$localVersion = if (Test-Path $VER_FILE) { (Get-Content $VER_FILE -Raw).Trim() } else { "0.0" }
Write-Status "Local version  : $localVersion"

$skipUpdate = $false
try {
    $remoteVersion = (Invoke-WebRequest -Uri "$RAW_BASE/version.txt" -UseBasicParsing).Content.Trim()
    Write-Status "Remote version : $remoteVersion"
} catch {
    Write-Status "Could not reach update server. Starting game anyway..." "Yellow"
    $skipUpdate = $true
}

if (-not $skipUpdate -and $localVersion -ne $remoteVersion) {
    Write-Status "Update found! Applying patch $localVersion -> $remoteVersion ..." "Yellow"
    Write-Host ""

    try {
        $manifest = (Invoke-WebRequest -Uri "$RAW_BASE/manifest.json" -UseBasicParsing).Content | ConvertFrom-Json
    } catch {
        Write-Status "Failed to fetch manifest. Starting game anyway..." "Yellow"
        $manifest = $null
    }

    if ($manifest) {
        New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null
        $allOk = $true

        foreach ($patch in $manifest.patches) {
            $pakPath   = Join-Path $GAME_DIR $patch.pak
            $patchName = [System.IO.Path]::GetFileName($patch.url)
            $patchFile = Join-Path $TMP_DIR $patchName

            Write-Status "Downloading: $patchName"
            try {
                $assetApiUrl = $releaseAssets[$patchName]
                if (-not $assetApiUrl) { throw "Asset '$patchName' not found in release v$remoteVersion" }
                Invoke-WebRequest -Uri $patch.url -OutFile $patchFile -UseBasicParsing
                $kb = [math]::Round((Get-Item $patchFile).Length / 1KB, 1)
                Write-Status "  $kb KB downloaded" "Green"
            } catch {
                Write-Status "  FAILED: $_" "Red"; $allOk = $false; continue
            }

            Write-Status "  Patching $($patch.pak) ..."
            try {
                $ok = Invoke-DnPatch -PakPath $pakPath -PatchPath $patchFile -TargetFile $patch.file
                if ($ok) { Write-Status "  OK" "Green" }
                else     { Write-Status "  FAILED: patch too large for slot" "Red"; $allOk = $false }
            } catch {
                Write-Status "  ERROR: $_" "Red"; $allOk = $false
            }
        }

        Remove-Item $TMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

        if ($allOk) {
            Set-Content -Path $VER_FILE -Value $remoteVersion
            Write-Host ""
            Write-Status "Patch complete! Now on version $remoteVersion" "Green"
        } else {
            Write-Status "Some patches failed." "Yellow"
        }
    }
} elseif (-not $skipUpdate) {
    Write-Status "Game is up to date!" "Green"
}

Write-Host ""
Write-Status "Starting game..." "Cyan"
Start-Sleep 1
Start-Process $GAME_EXE -ArgumentList "/logintoken: /ip:10.255.227.166 /port:14300 /Lver:2 /use_packing /gamechanneling:0"
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$GAME_DIR\RenameWindow.ps1`""
