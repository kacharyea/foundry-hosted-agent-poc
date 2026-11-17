<#
.SYNOPSIS
Checks that the Hosted Agent operations demo is ready, and optionally warms up the dashboard with normal traffic.

.DESCRIPTION
Read-only checks (nothing is changed): Azure login, routed agent version and its recent health, recent telemetry,
the alert rules, the action group, and the operations workbook. With warm-up enabled (default 3), it also sends
normal requests so the dashboard has fresh data. Prints PASS / WARN / FAIL per check and a summary.
Run it 30 or more minutes before the session because telemetry takes a few minutes to appear.

.EXAMPLE
.\Prepare-Demo.ps1 -ProjectEndpoint https://<account>.services.ai.azure.com/api/projects/<project> `
  -AgentName foundry-hosted-integration-poc -ResourceGroup <rg> -WorkspaceName <workspace>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $ProjectEndpoint,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ResourceGroup,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WorkspaceName,
    [string] $ActionGroupName = 'ag-hosted-agent-ops',
    [string] $AlertPrefix = 'hosted-agent-',
    [ValidateRange(0, 20)] [int] $WarmupRequests = 3
)

$ErrorActionPreference = 'Stop'
$project = $ProjectEndpoint.TrimEnd('/')
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string] $Status, [string] $Check, [string] $Detail) {
    $results.Add([pscustomobject]@{ Status = $Status; Check = $Check; Detail = $Detail })
    $color = switch ($Status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } default { 'Red' } }
    Write-Host ("[{0}] {1} - {2}" -f $Status, $Check, $Detail) -ForegroundColor $color
}

function Get-Token([string] $Resource) {
    $t = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($t)) { return $null }
    return $t
}

Write-Host "`n=== Demo readiness ===" -ForegroundColor Cyan

# 1. Login
$subscription = az account show --query id -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $subscription) {
    Add-Result 'FAIL' 'Azure login' "Not signed in. Run 'az login' and try again."
    return
}
Add-Result 'PASS' 'Azure login' "Subscription $subscription"

$foundryToken = Get-Token 'https://ai.azure.com'
$logToken = Get-Token 'https://api.loganalytics.io'
if (-not $foundryToken -or -not $logToken) {
    Add-Result 'FAIL' 'Tokens' 'Could not get Foundry or Log Analytics tokens. Sign in again.'
    return
}
$foundryHeaders = @{ Authorization = "Bearer $foundryToken" }

# 2. Routed version
$routed = $null
try {
    $agent = Invoke-RestMethod -Uri "$project/agents/${AgentName}?api-version=v1" -Headers $foundryHeaders
    $rules = @($agent.agent_endpoint.version_selector.version_selection_rules)
    $routed = [string]$rules[0].agent_version
    $details = Invoke-RestMethod -Uri "$project/agents/$AgentName/versions/${routed}?api-version=v1" -Headers $foundryHeaders
    $status = if ($details.status -eq 'active') { 'PASS' } else { 'FAIL' }
    Add-Result $status 'Routed version' "v$routed receives $($rules[0].traffic_percentage)% (status $($details.status)). Note this as the version to roll back to after the fault demo."
    if ($rules.Count -gt 1) { Add-Result 'WARN' 'Routing' 'Multiple routing rules are configured; the rollback script will replace them with one rule.' }
} catch {
    Add-Result 'FAIL' 'Routed version' "Could not read the agent: $($_.Exception.Message)"
}

# 3. Warm-up traffic
if ($WarmupRequests -gt 0 -and $routed) {
    $endpoint = "$project/agents/$AgentName/endpoint/protocols/openai/responses?api-version=v1"
    $body = @{ input = 'Show user 1 details and incomplete tasks. Name every tool used.'; stream = $false; store = $false } | ConvertTo-Json
    $ok = 0
    for ($i = 1; $i -le $WarmupRequests; $i++) {
        try {
            $r = Invoke-RestMethod -Uri $endpoint -Headers $foundryHeaders -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
            if ($r.status -eq 'completed') { $ok++ }
        } catch { Write-Host "  warm-up request $i failed: $($_.Exception.Message)" -ForegroundColor DarkYellow }
    }
    $status = if ($ok -eq $WarmupRequests) { 'PASS' } elseif ($ok -gt 0) { 'WARN' } else { 'FAIL' }
    Add-Result $status 'Warm-up traffic' "$ok of $WarmupRequests requests completed. Telemetry appears in a few minutes."
}

# 4. Telemetry
try {
    $workspaceId = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $WorkspaceName --query customerId -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $workspaceId) { throw "workspace '$WorkspaceName' not found" }
    $query = @"
AppRequests
| where AppRoleName == "agentsv2" and Name == "invoke_agent"
| where tostring(Properties["gen_ai.agent.name"]) == "$AgentName"
| extend Ver = tostring(Properties["gen_ai.agent.version"])
| summarize Requests = count(), Failures = countif(Success == false), Last = max(TimeGenerated) by Ver
"@
    $body = @{ query = $query; timespan = 'P1D' } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri "https://api.loganalytics.io/v1/workspaces/$workspaceId/query" -Method Post -Headers @{ Authorization = "Bearer $logToken" } -ContentType 'application/json' -Body $body
    $rows = @($res.tables[0].rows)
    if ($rows.Count -eq 0) {
        Add-Result 'WARN' 'Telemetry (24h)' 'No invoke_agent rows yet. Wait a few minutes after warm-up, then rerun without warm-up.'
    } else {
        $total = ($rows | ForEach-Object { [int]$_[1] } | Measure-Object -Sum).Sum
        Add-Result 'PASS' 'Telemetry (24h)' "$total invoke_agent rows across $($rows.Count) version(s)."
        $cur = $rows | Where-Object { [string]$_[0] -eq $routed } | Select-Object -First 1
        if ($cur) {
            $pct = if ([int]$cur[1] -gt 0) { [math]::Round(100.0 * [int]$cur[2] / [int]$cur[1], 1) } else { 0 }
            $status = if ($pct -le 5) { 'PASS' } else { 'FAIL' }
            Add-Result $status 'Routed version health' "v$routed failure rate $pct% over 24h ($($cur[1]) requests)."
        } else {
            Add-Result 'WARN' 'Routed version health' "No telemetry for v$routed in the last 24h yet."
        }
    }
} catch {
    Add-Result 'FAIL' 'Telemetry' $_.Exception.Message
}

# 5. Alert rules, action group, workbook (az rest keeps '&' out of the command line)
$arm = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$ResourceGroup/providers/Microsoft.Insights"
try {
    $ruleList = (az rest --method get --url "$arm/scheduledQueryRules" --url-parameters api-version=2023-12-01 -o json | ConvertFrom-Json).value |
        Where-Object { $_.name -like "$AlertPrefix*" }
    $enabled = @($ruleList | Where-Object { $_.properties.enabled })
    $withGroup = @($enabled | Where-Object { @($_.properties.actions.actionGroups).Count -gt 0 })
    if ($enabled.Count -eq 0) { Add-Result 'FAIL' 'Alert rules' "No enabled rules named '$AlertPrefix*'. Deploy infrastructure/monitoring.bicep." }
    else {
        $status = if ($withGroup.Count -eq $enabled.Count) { 'PASS' } else { 'WARN' }
        Add-Result $status 'Alert rules' "$($enabled.Count) enabled, $($withGroup.Count) with an action group: $((($enabled | ForEach-Object { $_.name -replace "^$AlertPrefix", '' }) -join ', '))"
        $freq = ($enabled | ForEach-Object { "$($_.properties.evaluationFrequency)/$($_.properties.windowSize)" } | Sort-Object -Unique) -join ', '
        Add-Result 'PASS' 'Alert timing' "Evaluation frequency / window: $freq (use PT1M / PT5M for a faster live demo)."
    }
} catch { Add-Result 'FAIL' 'Alert rules' $_.Exception.Message }

try {
    $ag = az rest --method get --url "$arm/actionGroups/$ActionGroupName" --url-parameters api-version=2023-01-01 -o json | ConvertFrom-Json
    $emails = @($ag.properties.emailReceivers)
    $status = if ($ag.properties.enabled -and $emails.Count -gt 0) { 'PASS' } else { 'FAIL' }
    Add-Result $status 'Action group' "$ActionGroupName enabled=$($ag.properties.enabled), $($emails.Count) email receiver(s). Send a test notification from the portal to confirm delivery."
} catch { Add-Result 'FAIL' 'Action group' "Could not read '$ActionGroupName'." }

try {
    $wbs = (az rest --method get --url "$arm/workbooks" --url-parameters api-version=2022-04-01 category=workbook -o json | ConvertFrom-Json).value |
        Where-Object { $_.properties.displayName -like 'Hosted Agent*' }
    if ($wbs) { Add-Result 'PASS' 'Workbook' "$(@($wbs).Count) found: $((@($wbs) | ForEach-Object { $_.properties.displayName }) -join ', '). Preview it in the portal." }
    else { Add-Result 'FAIL' 'Workbook' "No 'Hosted Agent' workbook found in $ResourceGroup." }
} catch { Add-Result 'FAIL' 'Workbook' $_.Exception.Message }

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$fail = @($results | Where-Object Status -eq 'FAIL').Count
$warn = @($results | Where-Object Status -eq 'WARN').Count
Write-Host "PASS: $(@($results | Where-Object Status -eq 'PASS').Count)  WARN: $warn  FAIL: $fail" -ForegroundColor $(if ($fail) { 'Red' } elseif ($warn) { 'Yellow' } else { 'Green' })
Write-Host 'Manual items this script cannot check: preview the workbook, send a test notification, confirm Copilot Observability Agent access.' -ForegroundColor Yellow
if ($routed) { Write-Host "Reset target after the fault demo: version $routed." -ForegroundColor Yellow }
if ($fail) { exit 1 }
