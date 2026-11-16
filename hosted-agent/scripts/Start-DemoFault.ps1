<#
.SYNOPSIS
Deploys a deliberately faulty Hosted Agent version and sends traffic so the demo alerts fire.

.DESCRIPTION
DEMO / NON-PRODUCTION ONLY. Creates a new agent version from the image already routed (no code change) with
one bad setting, routes 100% of traffic to it, then sends requests so alert queries have data.
  ToolEndpoint    : JSONPLACEHOLDER_BASE_URL points at an unreachable host. Tool calls fail, which should
                    fire hosted-agent-tool-errors and hosted-agent-dependency-failures (create-work alerts).
  ModelDeployment : AZURE_AI_MODEL_DEPLOYMENT_NAME names a deployment that does not exist. Invocations are
                    expected to fail, which should fire hosted-agent-failed-invocations (page). Rehearse first.
Recover with Rollback-HostedAgent.ps1. Supports -WhatIf; confirmation is required by default.

.EXAMPLE
.\Start-DemoFault.ps1 -ProjectEndpoint <endpoint> -AgentName foundry-hosted-integration-poc -Fault ToolEndpoint -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $ProjectEndpoint,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName,
    [Parameter(Mandatory)] [ValidateSet('ToolEndpoint', 'ModelDeployment')] [string] $Fault,
    [ValidateRange(1, 100)] [int] $RequestCount = 8,
    [switch] $SkipTraffic
)

$ErrorActionPreference = 'Stop'
$project = $ProjectEndpoint.TrimEnd('/')
$token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw "Unable to acquire a token. Run 'az login'." }
$headers = @{ Authorization = "Bearer $token" }

$agent = Invoke-RestMethod -Uri "$project/agents/${AgentName}?api-version=v1" -Headers $headers
$routed = [string]@($agent.agent_endpoint.version_selector.version_selection_rules)[0].agent_version
$current = Invoke-RestMethod -Uri "$project/agents/$AgentName/versions/${routed}?api-version=v1" -Headers $headers
$image = $current.definition.container_configuration.image
$model = $current.definition.environment_variables.AZURE_AI_MODEL_DEPLOYMENT_NAME
if (-not $image -or -not $model) { throw "Could not read image and model from routed version $routed." }

$badUrl = 'https://fault-injection.invalid/'
$badModel = 'fault-injection-missing-deployment'
Write-Host "Routed version: $routed (image $image, model $model)" -ForegroundColor Cyan
Write-Host "Fault: $Fault. A new version will receive 100% of traffic. Roll back with Rollback-HostedAgent.ps1 -TargetVersion $routed." -ForegroundColor Yellow

if (-not $PSCmdlet.ShouldProcess("$AgentName endpoint", "deploy faulty version ($Fault) and route 100% of traffic to it")) { return }

$deploy = Join-Path $PSScriptRoot '..\pipelines\scripts\Deploy-HostedAgent.ps1'
$release = "fault-$((Get-Date).ToString('yyyyMMdd-HHmm'))"
$params = @{
    ProjectEndpoint = $project; AgentName = $AgentName; ImageUri = $image
    ModelDeployment = $(if ($Fault -eq 'ModelDeployment') { $badModel } else { $model })
    Release = $release
}
if ($Fault -eq 'ToolEndpoint') { $params.JsonPlaceholderBaseUrl = $badUrl }
& $deploy @params

if ($SkipTraffic) { return }

$endpoint = "$project/agents/$AgentName/endpoint/protocols/openai/responses?api-version=v1"
$body = @{ input = 'Show user 1 details and incomplete tasks. Name every tool used.'; stream = $false; store = $false } | ConvertTo-Json
$ok = 0; $failed = 0
for ($i = 1; $i -le $RequestCount; $i++) {
    try {
        $r = Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
        if ($r.status -eq 'completed') { $ok++ } else { $failed++ }
    } catch { $failed++ }
    Write-Host "Request $i of ${RequestCount}: ok=$ok failed=$failed"
    Start-Sleep -Seconds 3
}
Write-Host "`nTraffic sent. Alerts evaluate every few minutes and telemetry takes a few minutes to ingest." -ForegroundColor Green
Write-Host "Watch the Hosted Agent operations workbook, then follow the matching runbook in docs/runbooks." -ForegroundColor Green
