<#
.SYNOPSIS
Deterministic evaluation of a Hosted Agent against a labeled dataset (no LLM judge).

.DESCRIPTION
Implements the "hard gate" criteria from the evaluation workshop:
  - Tool selection accuracy: the set of tools the agent called must equal expected_tools, plus any allowed_tools.
  - Required text (must_contain) and forbidden text (must_not_contain), case-insensitive.
A row passes only when the response completed and every check passes. Rows that error out (for example a rate
limit that survives retries) are reported as UNSCORED, never as passes.
The run targets the version currently routed on the agent endpoint; the routed version is recorded in the output.
Writes <OutputRoot>/<timestamp>/results.csv, results.json, and summary.md. Uses the current Azure CLI login.

.EXAMPLE
.\Invoke-DeterministicEval.ps1 -ProjectEndpoint https://<account>.services.ai.azure.com/api/projects/<project> `
  -AgentName foundry-hosted-integration-poc -DatasetPath ..\datasets\v1\smoke.jsonl
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $ProjectEndpoint,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName,
    [Parameter(Mandatory)] [string[]] $DatasetPath,
    [string] $OutputRoot = (Join-Path (Get-Location) 'evaluation-results'),
    [ValidateRange(0, 120)] [int] $DelaySeconds = 4,
    [ValidateRange(0, 8)] [int] $MaxRetries = 4
)

$ErrorActionPreference = 'Stop'
$project = $ProjectEndpoint.TrimEnd('/')
$token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw "Unable to acquire a token. Run 'az login'." }
$headers = @{ Authorization = "Bearer $token" }

$agent = Invoke-RestMethod -Uri "$project/agents/${AgentName}?api-version=v1" -Headers $headers
$routed = ((@($agent.agent_endpoint.version_selector.version_selection_rules) | ForEach-Object { "$($_.agent_version)@$($_.traffic_percentage)%" }) -join ', ')
Write-Host "Agent $AgentName routed to: $routed" -ForegroundColor Cyan

$rows = foreach ($path in $DatasetPath) {
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        if ($line.Trim()) { $line | ConvertFrom-Json }
    }
}
$rows = @($rows)
if ($rows.Count -eq 0) { throw 'No dataset rows were loaded.' }
Write-Host "Loaded $($rows.Count) rows from $($DatasetPath.Count) file(s)."

$endpoint = "$project/agents/$AgentName/endpoint/protocols/openai/responses?api-version=v1"

function Invoke-Agent([string] $Query) {
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        try {
            $body = @{ input = $Query; stream = $false; store = $false } | ConvertTo-Json
            return Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
        } catch {
            $message = "$($_.ErrorDetails.Message)"
            if ($message -match 'rate_limit' -and $attempt -lt $MaxRetries) {
                $wait = [math]::Min(90, 15 * [math]::Pow(2, $attempt))
                Write-Host "    rate limited; waiting $wait s (retry $($attempt + 1) of $MaxRetries)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds $wait
                continue
            }
            throw ($message -replace '\s+', ' ')
        }
    }
}

$results = foreach ($row in $rows) {
    Write-Host "[$($row.id)] $($row.query)"
    $called = @(); $text = ''; $status = ''; $error = ''
    try {
        $r = Invoke-Agent $row.query
        $status = [string]$r.status
        $called = @($r.output | Where-Object type -eq 'function_call' | Select-Object -ExpandProperty name | Sort-Object -Unique)
        $text = (@(($r.output | Where-Object type -eq 'message').content | Where-Object type -eq 'output_text' | Select-Object -ExpandProperty text) -join "`n")
    } catch { $error = [string]$_ }

    $expected = @($row.expected_tools); $allowed = @($row.allowed_tools)
    $missing = @($expected | Where-Object { $called -notcontains $_ })
    $extra = @($called | Where-Object { ($expected -notcontains $_) -and ($allowed -notcontains $_) })
    $toolPass = ($missing.Count -eq 0 -and $extra.Count -eq 0)
    $missingText = @(@($row.must_contain) | Where-Object { $_ -and $text -notmatch [regex]::Escape($_) })
    $forbiddenText = @(@($row.must_not_contain) | Where-Object { $_ -and $text -match [regex]::Escape($_) })
    $scored = (-not $error) -and $status -eq 'completed'
    $pass = $scored -and $toolPass -and $missingText.Count -eq 0 -and $forbiddenText.Count -eq 0
    $verdict = if (-not $scored) { 'UNSCORED' } elseif ($pass) { 'PASS' } else { 'FAIL' }
    $color = switch ($verdict) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("    {0}  tools called: [{1}]  expected: [{2}]" -f $verdict, ($called -join ','), ($expected -join ',')) -ForegroundColor $color

    [pscustomobject]@{
        Id = $row.id; Tier = $row.tier; Verdict = $verdict; ToolSelectionPass = $(if ($scored) { $toolPass } else { $null })
        Called = ($called -join ';'); Expected = ($expected -join ';'); MissingTools = ($missing -join ';'); ExtraTools = ($extra -join ';')
        MissingText = ($missingText -join ';'); ForbiddenText = ($forbiddenText -join ';')
        Status = $status; Error = $error; FailureCategory = $row.failure_category; Source = $row.source
        Query = $row.query; Response = ($text -replace '\s+', ' ')
    }
    if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
}
$results = @($results)

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$out = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Path $out -Force | Out-Null
$results | Export-Csv -Path (Join-Path $out 'results.csv') -Encoding UTF8
$results | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $out 'results.json') -Encoding utf8

$scoredRows = @($results | Where-Object Verdict -ne 'UNSCORED')
$toolRows = @($scoredRows | Where-Object { $null -ne $_.ToolSelectionPass })
$toolAccuracy = if ($toolRows.Count) { [math]::Round(100.0 * @($toolRows | Where-Object ToolSelectionPass).Count / $toolRows.Count, 1) } else { 0 }
$passRate = if ($scoredRows.Count) { [math]::Round(100.0 * @($scoredRows | Where-Object Verdict -eq 'PASS').Count / $scoredRows.Count, 1) } else { 0 }
$gate = if ($toolRows.Count -gt 0 -and $toolAccuracy -eq 100) { 'PASS' } else { 'FAIL' }
$unscored = @($results | Where-Object Verdict -eq 'UNSCORED').Count

$tierTable = ($results | Group-Object Tier | ForEach-Object {
    "| $($_.Name) | $($_.Count) | $(@($_.Group | Where-Object Verdict -eq 'PASS').Count) | $(@($_.Group | Where-Object Verdict -eq 'FAIL').Count) | $(@($_.Group | Where-Object Verdict -eq 'UNSCORED').Count) |" }) -join "`n"
$failed = ($results | Where-Object Verdict -ne 'PASS' | ForEach-Object { "- ``$($_.Id)`` $($_.Verdict): tools [$($_.Called)] vs expected [$($_.Expected)]; missing text [$($_.MissingText)]; forbidden text [$($_.ForbiddenText)] $($_.Error)" }) -join "`n"

@"
# Deterministic evaluation summary

| Field | Value |
|---|---|
| Run (UTC) | $((Get-Date).ToUniversalTime().ToString('s'))Z |
| Agent | $AgentName |
| Routed version(s) | $routed |
| Rows | $($results.Count) (unscored: $unscored) |
| Overall pass rate (scored rows) | $passRate% |
| Tool selection accuracy | $toolAccuracy% |
| Hard gate (tool selection = 100%) | **$gate** |

| Tier | Rows | Pass | Fail | Unscored |
|---|---|---|---|---|
$tierTable

## Rows to review (item-level, do not rely on the average)
$(if ($failed) { $failed } else { '- none' })

Unscored rows hit an error (for example a rate limit) and are not counted as passes. Classify each failure as: agent failure, ambiguous ground truth, evaluator disagreement, or environment/configuration issue.
"@ | Out-File -FilePath (Join-Path $out 'summary.md') -Encoding utf8

Write-Host "`nTool selection accuracy: $toolAccuracy%   Pass rate: $passRate%   Hard gate: $gate   Unscored: $unscored" -ForegroundColor $(if ($gate -eq 'PASS') { 'Green' } else { 'Red' })
Write-Host "Results written to: $out"
