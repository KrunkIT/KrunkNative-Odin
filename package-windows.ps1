param(
    [string]$AssetArchive = (Join-Path $PSScriptRoot "KrunkNative-Windows.zip"),
    [string]$OutputArchive = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$versionFile = Join-Path $PSScriptRoot "VERSION"
if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "Missing version file: $versionFile"
}
$version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
if ([string]::IsNullOrEmpty($version)) {
    throw "Version file is empty: $versionFile"
}
if ([string]::IsNullOrEmpty($OutputArchive)) {
    $OutputArchive = Join-Path $PSScriptRoot ("KrunkNative-Windows-" + $version + ".zip")
}

$root = (Resolve-Path $PSScriptRoot).Path
$assetArchive = (Resolve-Path $AssetArchive).Path
$stage = Join-Path ([IO.Path]::GetTempPath()) ("KrunkNative-package-" + [guid]::NewGuid().ToString("N"))

try {
    if (-not $SkipBuild) {
        & cmd.exe /c (Join-Path $root "build.bat") all
        if ($LASTEXITCODE -ne 0) {
            throw "The binary build failed with exit code $LASTEXITCODE."
        }
    }

    $clientBinary = Join-Path $root "bin\krunknative_client.exe"
    $serverBinary = Join-Path $root "bin\krunknative_server.exe"
    foreach ($required in @($clientBinary, $serverBinary)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing binary: $required"
        }
    }

    New-Item -ItemType Directory -Path $stage | Out-Null
    Expand-Archive -LiteralPath $assetArchive -DestinationPath $stage

    $copies = @{
        $clientBinary = (Join-Path $stage "krunknative_client.exe")
        $serverBinary = (Join-Path $stage "krunknative_server.exe")
        (Join-Path $root "assets\config\game.toml") = (Join-Path $stage "assets\config\game.toml")
        (Join-Path $root "assets\models\weapons\weapon_15.obj") = (Join-Path $stage "assets\models\weapons\weapon_15.obj")
        (Join-Path $root "assets\textures\weapons\weapon_15.png") = (Join-Path $stage "assets\textures\weapons\weapon_15.png")
    }

    foreach ($source in $copies.Keys) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Missing package input: $source"
        }

        $destination = $copies[$source]
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    if (Test-Path -LiteralPath $OutputArchive) {
        Remove-Item -LiteralPath $OutputArchive -Force
    }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $OutputArchive -CompressionLevel Optimal
    Write-Host "Created $OutputArchive"
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
