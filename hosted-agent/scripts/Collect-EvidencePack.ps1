<#
.SYNOPSIS
Collects an incident evidence pack from Application Insights / Log Analytics for a Hosted Agent.

.DESCRIPTION
Produces the artifacts a runbook asks for before closing or handing off an incident: symptom by version,
failed invocations, hotspots, tool errors, version rollout markers, representative trace timelines, and a
GenAI attribute inventory. Everything is read-only. Output goes to <OutputRoot>/<timestamp>/ as CSV plus a
summary.md with sections to complete (actions, approvals, verification, follow-up). Output contains
telemetry only; review it before sharing because content capture may include prompts for synthetic runs.

.EXAMPLE
.\Collect-EvidencePack.ps1 -ResourceGroup <rg> -WorkspaceName <workspace> -WindowMinutes 120
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ResourceGroup,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WorkspaceName,
    [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName = 'foundry-hosted-integration-poc',
    [ValidateRange(5, 20160)] [int] $WindowMinutes = 60,
    [ValidatePattern('^[a-fA-F0-9]{32}$')] [string] $TraceId,
    [ValidateRange(1, 10)] [int] $MaxTraces = 3,
    [string] $ProjectEndpoint,
    [string] $DashboardUrl,
    [string] $OutputRoot = (Join-Path (Get-Location) 'evidence')
)

$ErrorActionPreference = 'Stop'

function Get-AccessToken([string] $Resource) {
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw "Unable to acquire a token for $Resource. Run 'az login'." }
    return $token
}

$workspaceId = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $WorkspaceName --query customerId -o tsv
if ($LASTEXITCODE -ne 0 -or -not $workspaceId) { throw "Could not resolve workspace '$WorkspaceName'." }
$logHeaders = @{ Authorization = "Bearer $(Get-AccessToken 'https://api.loganalytics.io')" }

function Invoke-Kql([string] $Query) {
    $body = @{ query = $Query; timespan = "PT${WindowMinutes}M" } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "https://api.loganalytics.io/v1/workspaces/$workspaceId/query" -Method Post -Headers $logHeaders -ContentType 'application/json' -Body $body
    $table = $result.tables[0]
    $names = @($table.columns.name)
    foreach ($row in $table.rows) {
        $item = [ordered]@{}
        for ($i = 0; $i -lt $names.Count; $i++) { $item[$names[$i]] = $row[$i] }
        [pscustomobject]$item
    }
}

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$out = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Path $out -Force | Out-Null

$platform = @"
AppRequests
| where AppRoleName == "agentsv2" and Name == "invoke_agent"
| where tostring(Properties["gen_ai.agent.name"]) == "$AgentName"
| extend Ver = tostring(Properties["gen_ai.agent.version"])
"@

$queries = [ordered]@{
    '01-symptom-by-version' = @"
$platform
| summarize Requests = count(), Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0) by bin(TimeGenerated, 5m), Version = Ver
| extend FailureRatePct = round(100.0 * Failures / Requests, 2)
| order by TimeGenerated asc
"@
    '02-failed-invocations' = @"
$platform
| where Success == false
| project TimeGenerated, OperationId, Version = Ver, ResultCode, DurationMs = round(DurationMs, 0), ConversationId = tostring(Properties["gen_ai.conversation.id"])
| order by TimeGenerated desc
| take 100
"@
    '03-dependency-hotspots' = @"
AppDependencies
| where AppRoleName in ("$AgentName", "$AgentName-tools")
| summarize Calls = count(), Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0) by AppRoleName, DependencyType, Target, Name
| extend FailureRatePct = round(100.0 * Failures / Calls, 2)
| top 25 by Failures desc
"@
    '04-tool-errors' = @"
AppDependencies
| where AppRoleName == "$AgentName-tools" and Name startswith "tool." and Success == false
| project TimeGenerated, OperationId, Tool = tostring(Properties["gen_ai.tool.name"]), ErrorType = tostring(Properties["error.type"]), Version = AppVersion, DurationMs = round(DurationMs, 0)
| order by TimeGenerated desc
| take 100
"@
    '05-version-rollout-markers' = @"
$platform
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated), Requests = count(), Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0) by Version = Ver
| order by FirstSeen desc
"@
    '07-genai-attribute-inventory' = @"
union withsource = TableName isfuzzy = true AppRequests, AppDependencies, AppTraces
| where AppRoleName in ("agentsv2", "$AgentName", "$AgentName-tools")
| mv-expand Attribute = bag_keys(Properties)
| where tostring(Attribute) startswith "gen_ai."
| summarize Rows = count() by TableName, Attribute = tostring(Attribute)
| order by TableName asc, Rows desc
"@
}

$counts = [ordered]@{}
foreach ($name in $queries.Keys) {
    Write-Host "Collecting $name ..."
    $rows = @(Invoke-Kql $queries[$name])
    $counts[$name] = $rows.Count
    if ($rows.Count) { $rows | Export-Csv -Path (Join-Path $out "$name.csv") -NoTypeInformation -Encoding UTF8 }
    else { '' | Out-File -FilePath (Join-Path $out "$name.empty.txt") -Encoding utf8 }
}

# Representative traces: the supplied one, otherwise the most recent failed invocations.
$traceIds = @()
if ($TraceId) { $traceIds = @($TraceId.ToLowerInvariant()) }
else {
    $failed = @(Invoke-Kql "$platform | where Success == false | summarize Last = max(TimeGenerated) by OperationId | top $MaxTraces by Last desc")
    $traceIds = @($failed | ForEach-Object { $_.OperationId })
}
foreach ($id in $traceIds) {
    Write-Host "Collecting trace $id ..."
    $timeline = @"
union isfuzzy = true
  (AppRequests | project TimeGenerated, OperationId, ParentId, SpanId = Id, Kind = "request", Name, Success, DurationMs, ResultCode, AppRoleName, AppVersion),
  (AppDependencies | project TimeGenerated, OperationId, ParentId, SpanId = Id, Kind = "dependency", Name, Success, DurationMs, ResultCode, AppRoleName, AppVersion),
  (AppExceptions | project TimeGenerated, OperationId, ParentId, SpanId = "", Kind = "exception", Name = OuterMessage, Success = false, DurationMs = real(null), ResultCode = ProblemId, AppRoleName, AppVersion)
| where OperationId == "$id"
| order by TimeGenerated asc
"@
    $rows = @(Invoke-Kql $timeline)
    if ($rows.Count) { $rows | Export-Csv -Path (Join-Path $out "06-trace-$id.csv") -NoTypeInformation -Encoding UTF8 }
}

$routed = 'not queried (pass -ProjectEndpoint to record it)'
if ($ProjectEndpoint) {
    $headers = @{ Authorization = "Bearer $(Get-AccessToken 'https://ai.azure.com')" }
    $agent = Invoke-RestMethod -Uri "$($ProjectEndpoint.TrimEnd('/'))/agents/${AgentName}?api-version=v1" -Headers $headers
    $routed = ((@($agent.agent_endpoint.version_selector.version_selection_rules) | ForEach-Object { "$($_.agent_version) @ $($_.traffic_percentage)%" }) -join ', ')
}

$summary = @"
# Incident evidence pack

| Field | Value |
|---|---|
| Collected (UTC) | $((Get-Date).ToUniversalTime().ToString('s'))Z |
| Agent | $AgentName |
| Window | last $WindowMinutes minutes |
| Currently routed version | $routed |
| Workspace | $WorkspaceName |
$(if ($DashboardUrl) { "| Dashboard | $DashboardUrl |" })

## Collected artifacts

$(($counts.Keys | ForEach-Object { "- ``$_`` - $($counts[$_]) rows" }) -join "`n")
$(($traceIds | ForEach-Object { "- ``06-trace-$_.csv`` - representative trace timeline" }) -join "`n")

## Representative trace IDs

$(if ($traceIds) { ($traceIds | ForEach-Object { "- $_" }) -join "`n" } else { '- none in window' })

## Complete before closing (manual)

- **Incident timeline:**
- **Alert / issue link:**
- **Hypothesis and ruling-out evidence:**
- **Actions taken and approver:**
- **Verification (health and agent outcome recovered):**
- **Follow-up owner and due date:**
"@
$summary | Out-File -FilePath (Join-Path $out 'summary.md') -Encoding utf8

Write-Host "`nEvidence pack written to: $out" -ForegroundColor Green
