param(
    [string]$AssetArchive = (Join-Path $PSScriptRoot "Krodin-Windows.zip"),
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
    $OutputArchive = Join-Path $PSScriptRoot ("Krodin-Windows-" + $version + ".zip")
}

$root = (Resolve-Path $PSScriptRoot).Path
# Existing asset seeds predate the Krodin name.
if (-not $PSBoundParameters.ContainsKey("AssetArchive") -and -not (Test-Path -LiteralPath $AssetArchive -PathType Leaf)) {
    $legacyArchive = Join-Path $root "KrunkNative-Windows.zip"
    if (Test-Path -LiteralPath $legacyArchive -PathType Leaf) { $AssetArchive = $legacyArchive }
}
$assetArchive = (Resolve-Path $AssetArchive).Path
$stage = Join-Path ([IO.Path]::GetTempPath()) ("Krodin-package-" + [guid]::NewGuid().ToString("N"))

try {
    if (-not $SkipBuild) {
        & cmd.exe /c (Join-Path $root "build.bat") all
        if ($LASTEXITCODE -ne 0) {
            throw "The binary build failed with exit code $LASTEXITCODE."
        }
    }

    $clientBinary = Join-Path $root "bin\krodin_client.exe"
    $serverBinary = Join-Path $root "bin\krodin_server.exe"
    foreach ($required in @($clientBinary, $serverBinary)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing binary: $required"
        }
    }

    New-Item -ItemType Directory -Path $stage | Out-Null
    Expand-Archive -LiteralPath $assetArchive -DestinationPath $stage
    foreach ($name in @("krunknative_client.exe", "krunknative_server.exe")) {
        $legacyBinary = Join-Path $stage $name
        if (Test-Path -LiteralPath $legacyBinary -PathType Leaf) { Remove-Item -LiteralPath $legacyBinary }
    }

    $copies = @{
        $clientBinary = (Join-Path $stage "krodin_client.exe")
        $serverBinary = (Join-Path $stage "krodin_server.exe")
        (Join-Path $root "assets\config\game.toml") = (Join-Path $stage "assets\config\game.toml")
        (Join-Path $root "assets\config\sound-assets.txt") = (Join-Path $stage "assets\config\sound-assets.txt")
        (Join-Path $root "assets\shaders\basic.frag") = (Join-Path $stage "assets\shaders\basic.frag")
        (Join-Path $root "assets\textures\objective_4.png") = (Join-Path $stage "assets\textures\objective_4.png")
        (Join-Path $root "assets\textures\objective_5.png") = (Join-Path $stage "assets\textures\objective_5.png")
    }

    # Refresh the full map catalog instead of retaining old maps in the seed.
    foreach ($map in Get-ChildItem -LiteralPath (Join-Path $root "assets\maps") -Filter "*.json" -File) {
        $copies[$map.FullName] = Join-Path $stage (Join-Path "assets\maps" $map.Name)
    }
    $obsoleteSandstorm = Join-Path $stage "assets\maps\sandstorm.json"
    if (Test-Path -LiteralPath $obsoleteSandstorm -PathType Leaf) { Remove-Item -LiteralPath $obsoleteSandstorm }

    # Replace every supported default weapon from the installed modern pack;
    # the archive seed may contain an older generation of these same filenames.
    $weaponAssets = Get-Content -LiteralPath (Join-Path $root "assets\config\weapon-assets.txt")
    foreach ($asset in $weaponAssets) {
        $asset = $asset.Trim()
        if (-not $asset -or $asset.StartsWith("#")) { continue }
        $relative = Join-Path "assets" $asset
        $copies[(Join-Path $root $relative)] = Join-Path $stage $relative
    }

    # Hosted map art is absent from mod.zip and older seed archives.
    foreach ($asset in Get-Content -LiteralPath (Join-Path $root "assets\config\map-assets.txt")) {
        $asset = $asset.Trim()
        if (-not $asset -or $asset.StartsWith("#")) { continue }
        $relative = Join-Path "assets" $asset
        $copies[(Join-Path $root $relative)] = Join-Path $stage $relative
    }

    foreach ($asset in Get-Content -LiteralPath (Join-Path $root "assets\config\sound-assets.txt")) {
        $asset = $asset.Trim()
        if (-not $asset -or $asset.StartsWith("#")) { continue }
        $relative = Join-Path "assets" $asset
        $copies[(Join-Path $root $relative)] = Join-Path $stage $relative
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
