[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $AgentEndpoint,
    [string] $AzdPath = "$env:LOCALAPPDATA\Programs\Azure Dev CLI\azd.exe"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $AzdPath)) { throw "azd was not found at $AzdPath" }
$azdDirectory = Split-Path -Parent $AzdPath
if (($env:PATH -split ';') -notcontains $azdDirectory) {
    $env:PATH = "$azdDirectory;$env:PATH"
}

$cases = @(
    @{ Name = 'REST multi-tool and latency'; Prompt = 'Show user 1 details and incomplete tasks. Name every tool used.' },
    @{ Name = 'Microsoft Learn MCP'; Prompt = 'Use Microsoft Learn to explain managed identity in three bullets and include a Learn URL.' },
    @{ Name = 'Controlled validation error'; Prompt = 'Get details for user 99. Report the exact controlled error code.' }
)

foreach ($case in $cases) {
    Write-Host "`n=== $($case.Name) ===" -ForegroundColor Cyan
    & $AzdPath ai agent invoke --agent-endpoint $AgentEndpoint --new-session --new-conversation $case.Prompt
    if ($LASTEXITCODE -ne 0) { throw "Observability case '$($case.Name)' failed to invoke." }
}

Write-Host "`nOpen Foundry > Agents > your agent > Traces and inspect the printed trace IDs." -ForegroundColor Green
