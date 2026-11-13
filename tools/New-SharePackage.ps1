[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path $PWD 'FoundryHostedAgentPoc-share.zip')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$staging = Join-Path ([IO.Path]::GetTempPath()) "FoundryHostedAgentPoc-share-$([guid]::NewGuid().ToString('N'))"
$excludedDirectories = @('.git', '.azure', '.vs', '.vscode', 'bin', 'obj', 'TestResults')
$excludedNames = @('.env', 'deployment.local.json')
$excludedExtensions = @('.user', '.suo', '.pfx', '.pem', '.key')

try {
    New-Item -ItemType Directory -Path $staging | Out-Null
    $files = Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart([char[]]'\/')
        $segments = $relative -split '[\\/]'
        -not ($segments | Where-Object { $_ -in $excludedDirectories }) -and
        $_.Name -notin $excludedNames -and
        $_.Extension -notin $excludedExtensions -and
        $_.Name -notlike '*.local.bicepparam' -and
        $_.Name -ne (Split-Path -Leaf $OutputPath)
    }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart([char[]]'\/')
        $destination = Join-Path $staging $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }

    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputPath -CompressionLevel Optimal
    Write-Host "Created sanitized share package: $OutputPath" -ForegroundColor Green
    Write-Host "Review the archive and run your organization's secret scanner before distribution."
}
finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
