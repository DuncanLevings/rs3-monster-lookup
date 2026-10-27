# Build only the runtime upload; source tests and development files stay local.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$pluginRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $pluginRoot "plugin.json") -Raw | ConvertFrom-Json
$dist = Join-Path $pluginRoot "dist"
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$archivePath = Join-Path $dist ("monster-lookup-" + $manifest.version + ".zip")
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath }
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, "Create")
try {
    $files = @("main.lua", "plugin.json", "README.md", "THIRD_PARTY_NOTICES.txt") |
        ForEach-Object { Get-Item -LiteralPath (Join-Path $pluginRoot $_) }
    $files += Get-ChildItem -LiteralPath (Join-Path $pluginRoot "src") -Recurse -File
    $files += Get-ChildItem -LiteralPath (Join-Path $pluginRoot "resources") -Recurse -File
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($pluginRoot.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $relative) | Out-Null
    }
} finally { $archive.Dispose() }
Write-Output $archivePath
