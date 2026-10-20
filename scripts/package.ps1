# builds the zip for mod.io, main.lua and plugin.json have to sit at the root
# only the runtime files go in, tests docs and editor stuff are left out
#
# run with: powershell -ExecutionPolicy Bypass -File scripts/package.ps1
#
# not using Compress-Archive, on windows powershell 5.1 it writes paths with backslashes
# which linux/android/ios can treat as part of the file name

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "plugin.json") -Raw | ConvertFrom-Json

if ($manifest.contactEmailAddress -like "*example.com") {
    throw "Set a real contactEmailAddress in plugin.json before packaging."
}

$dist = Join-Path $root "dist"
$archive = Join-Path $dist ("monster-lookup-" + $manifest.version + ".zip")
New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $archive) { Remove-Item $archive -Force }

$files = @()
foreach ($item in @("main.lua", "plugin.json", "THIRD_PARTY_NOTICES.txt", "src", "resources")) {
    $files += Get-ChildItem (Join-Path $root $item) -Recurse -File
}

$zip = [System.IO.Compression.ZipFile]::Open($archive, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $name = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name) | Out-Null
    }
} finally {
    $zip.Dispose()
}

Write-Output "Created $archive ($($files.Count) files)"
