param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\bin'))
$ErrorActionPreference = 'Stop'

# Official Microsoft package, pinned and verified before extracting redistribution files.
$version = '1.0.3650.58'
$sha256 = '911A472128C82AC8BAA0C486C23342CC9DD6E7DC50D754E676726642CA065C60'
$cache = Join-Path $PSScriptRoot 'webview2'
$archive = Join-Path $cache 'sdk.zip'
New-Item -ItemType Directory -Path $cache, $OutputDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -UseBasicParsing "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$version" -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) {
    throw "WebView2 SDK checksum mismatch. Remove tools/webview2/sdk.zip and retry."
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $files = @{
        'build/native/x64/WebView2Loader.dll' = 'WebView2Loader.dll'
        'LICENSE.txt' = 'WebView2-LICENSE.txt'
        'NOTICE.txt' = 'WebView2-NOTICE.txt'
    }
    foreach ($source in $files.Keys) {
        $entry = $zip.GetEntry($source)
        if ($null -eq $entry) { throw "Missing official SDK file: $source" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $OutputDirectory $files[$source]), $true)
    }
}
finally { $zip.Dispose() }
