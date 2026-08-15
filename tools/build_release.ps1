param(
    [string]$Version = "",
    [string]$InnoCompiler = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not $Version) {
    $versionContent = Get-Content "secure_tiles\__init__.py" -Raw
    $versionMatch = [regex]::Match($versionContent, '__version__\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
    if (-not $versionMatch.Success) { throw "Could not read the application version." }
    $Version = $versionMatch.Groups[1].Value
}

$portableName = "Secure-Tiles-Portable-v$Version"
$portablePath = Join-Path $projectRoot "dist\$portableName.exe"
$installerPath = Join-Path $projectRoot "dist\Secure-Tiles-Setup-v$Version.exe"
$versionParts = $Version.Split('.')
if ($versionParts.Count -ne 3 -or @($versionParts | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) {
    throw "Version must contain three numeric parts."
}
$versionTuple = "($($versionParts[0]), $($versionParts[1]), $($versionParts[2]), 0)"
$generatedVersionFile = Join-Path $projectRoot "build\version_info-$Version.txt"
New-Item -ItemType Directory -Force (Split-Path -Parent $generatedVersionFile) | Out-Null
$versionInfo = Get-Content "packaging\version_info.txt" -Raw
$versionInfo = $versionInfo -replace 'filevers=\([^)]*\)', "filevers=$versionTuple"
$versionInfo = $versionInfo -replace 'prodvers=\([^)]*\)', "prodvers=$versionTuple"
$versionInfo = $versionInfo -replace "StringStruct\(u'FileVersion', u'[^']*'\)", "StringStruct(u'FileVersion', u'$Version')"
$versionInfo = $versionInfo -replace "StringStruct\(u'OriginalFilename', u'[^']*'\)", "StringStruct(u'OriginalFilename', u'$portableName.exe')"
$versionInfo = $versionInfo -replace "StringStruct\(u'ProductVersion', u'[^']*'\)", "StringStruct(u'ProductVersion', u'$Version')"
Set-Content -LiteralPath $generatedVersionFile -Value $versionInfo -Encoding UTF8

python -m PyInstaller --noconfirm --clean --onefile --windowed `
    --name $portableName `
    --icon "assets\secure_tiles.ico" `
    --version-file $generatedVersionFile `
    --add-data "secure_tiles\qml;secure_tiles\qml" `
    --add-data "assets;assets" `
    --hidden-import relay_server `
    --hidden-import _cffi_backend `
    "main.py"
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed." }

if (-not $InnoCompiler) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    $InnoCompiler = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $InnoCompiler -or -not (Test-Path $InnoCompiler)) {
    throw "Inno Setup 6 was not found. Install it or pass -InnoCompiler."
}

& $InnoCompiler "/DMyAppVersion=$Version" "/DBuildRoot=$projectRoot" "packaging\secure-tiles.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed." }

foreach ($artifact in @($portablePath, $installerPath)) {
    if (-not (Test-Path $artifact)) { throw "Missing release artifact: $artifact" }
    $item = Get-Item $artifact
    $hash = Get-FileHash $artifact -Algorithm SHA256
    [pscustomobject]@{ Name = $item.Name; Bytes = $item.Length; SHA256 = $hash.Hash }
}
