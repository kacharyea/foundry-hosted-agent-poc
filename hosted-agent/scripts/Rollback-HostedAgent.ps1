<#
.SYNOPSIS
Routes a Foundry Hosted Agent endpoint back to a known-good version.

.DESCRIPTION
Runbook action for "remediate": validate the target, show the plan, ask for confirmation, change the
endpoint routing, and verify. A Hosted Agent version can report status 'active' even when its container
fails at session start (for example session_not_ready), so this script does NOT trust version status.
When -TargetVersion is omitted it selects the newest version below the current one that has successful
invoke_agent telemetry and a failure rate within -MaxFailurePercent over -LookbackDays.

Supports -WhatIf. Uses the current Azure CLI identity (Foundry Project Manager is required to change routing).

.EXAMPLE
.\Rollback-HostedAgent.ps1 -ProjectEndpoint https://<account>.services.ai.azure.com/api/projects/<project> `
  -AgentName foundry-hosted-integration-poc -ResourceGroup <rg> -WorkspaceName <workspace> -WhatIf

.EXAMPLE
.\Rollback-HostedAgent.ps1 -ProjectEndpoint <endpoint> -AgentName <agent> -TargetVersion 9 -Reason 'INC-1234 tool timeouts'
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $ProjectEndpoint,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName,
    [ValidatePattern('^\d+$')] [string] $TargetVersion,
    [string] $ResourceGroup,
    [string] $WorkspaceName,
    [ValidatePattern('^\d+$')] [string] $FromVersion,
    [ValidateRange(1, 90)] [int] $LookbackDays = 14,
    [ValidateRange(0, 100)] [double] $MaxFailurePercent = 5,
    [string] $Reason = 'unspecified',
    [switch] $SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
$project = $ProjectEndpoint.TrimEnd('/')

function Get-AccessToken([string] $Resource) {
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw "Unable to acquire a token for $Resource. Run 'az login'." }
    return $token
}

$foundryHeaders = @{ Authorization = "Bearer $(Get-AccessToken 'https://ai.azure.com')" }
$agentUri = "$project/agents/${AgentName}?api-version=v1"

Write-Host "`n=== Validate: current routing ===" -ForegroundColor Cyan
$agent = Invoke-RestMethod -Uri $agentUri -Headers $foundryHeaders -Method Get
$rules = @($agent.agent_endpoint.version_selector.version_selection_rules)
if ($rules.Count -eq 0) { throw 'The endpoint has no routing rules; nothing to roll back.' }
if ($rules.Count -gt 1) { Write-Warning 'Multiple routing rules are configured; this script replaces them with a single 100% rule.' }
$routed = [string]$rules[0].agent_version
$current = if ($FromVersion) { $FromVersion } else { $routed }
Write-Host "Routed version: $routed$(if ($FromVersion) { " (evaluating rollback from $FromVersion)" })"

if (-not $TargetVersion) {
    if (-not $ResourceGroup -or -not $WorkspaceName) {
        throw 'Provide -TargetVersion, or -ResourceGroup and -WorkspaceName so the last known-good version can be chosen from telemetry.'
    }
    Write-Host "`n=== Select last known-good version from telemetry ($LookbackDays days) ===" -ForegroundColor Cyan
    $workspaceId = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $WorkspaceName --query customerId -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $workspaceId) { throw "Could not resolve workspace '$WorkspaceName'." }
    $logHeaders = @{ Authorization = "Bearer $(Get-AccessToken 'https://api.loganalytics.io')" }
    $query = @"
AppRequests
| where AppRoleName == "agentsv2" and Name == "invoke_agent"
| where tostring(Properties["gen_ai.agent.name"]) == "$AgentName"
| extend Ver = tostring(Properties["gen_ai.agent.version"])
| where isnotempty(Ver)
| summarize Requests = count(), Failures = countif(Success == false), LastSeen = max(TimeGenerated) by Ver
"@
    $body = @{ query = $query; timespan = "P${LookbackDays}D" } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "https://api.loganalytics.io/v1/workspaces/$workspaceId/query" -Method Post -Headers $logHeaders -ContentType 'application/json' -Body $body
    $table = $result.tables[0]
    $versions = foreach ($row in $table.rows) {
        $requests = [int]$row[1]; $failures = [int]$row[2]
        [pscustomobject]@{
            Version = [int]$row[0]; Requests = $requests; Failures = $failures
            FailurePct = if ($requests -gt 0) { [math]::Round(100.0 * $failures / $requests, 1) } else { 100 }
            LastSeen = $row[3]
        }
    }
    $versions | Sort-Object Version -Descending | Format-Table -AutoSize | Out-String | Write-Host
    $candidate = $versions | Where-Object { $_.Version -lt [int]$current -and $_.Requests -gt 0 -and $_.FailurePct -le $MaxFailurePercent } |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $candidate) { throw "No version below $current has successful telemetry within $MaxFailurePercent% failures. Choose -TargetVersion explicitly." }
    $TargetVersion = [string]$candidate.Version
    Write-Host "Selected version $TargetVersion ($($candidate.Requests) requests, $($candidate.FailurePct)% failures). Versions with failures or no traffic were skipped even if their status is 'active'."
}

if ($TargetVersion -eq $routed) { throw "Version $TargetVersion is already the routed version." }

$targetDetails = Invoke-RestMethod -Uri "$project/agents/$AgentName/versions/${TargetVersion}?api-version=v1" -Headers $foundryHeaders -Method Get
if ($targetDetails.status -ne 'active') { throw "Target version $TargetVersion has status '$($targetDetails.status)', not 'active'." }
$image = $targetDetails.definition.container_configuration.image

Write-Host "`n=== Plan ===" -ForegroundColor Cyan
[pscustomobject]@{
    Agent = $AgentName; From = $routed; To = $TargetVersion; Image = $image
    Reason = $Reason; RequestedAtUtc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
} | Format-List | Out-String | Write-Host

if ($PSCmdlet.ShouldProcess("$AgentName endpoint", "route 100% of traffic from version $routed to version $TargetVersion")) {
    Write-Host '=== Remediate: change routing ===' -ForegroundColor Cyan
    $route = @{ agent_endpoint = @{
        version_selector = @{ version_selection_rules = @(@{ type = 'FixedRatio'; agent_version = $TargetVersion; traffic_percentage = 100 }) }
        protocol_configuration = @{ responses = @{} }
    } } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $agentUri -Headers $foundryHeaders -Method Patch -ContentType 'application/merge-patch+json' -Body $route | Out-Null

    $after = Invoke-RestMethod -Uri $agentUri -Headers $foundryHeaders -Method Get
    $now = [string]@($after.agent_endpoint.version_selector.version_selection_rules)[0].agent_version
    if ($now -ne $TargetVersion) { throw "Routing verification failed: endpoint reports version $now." }
    Write-Host "Routing verified: version $now receives 100% of traffic." -ForegroundColor Green

    if (-not $SkipSmokeTest) {
        Write-Host "`n=== Verify: smoke test ===" -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot '..\pipelines\scripts\SmokeTest-HostedAgent.ps1') -ProjectEndpoint $project -AgentName $AgentName
    }

    Write-Host "`nNext: confirm recovery on the Hosted Agent operations workbook (failure rate and p95), then run Collect-EvidencePack.ps1 and record the decision, approver, and follow-up owner." -ForegroundColor Yellow
}
