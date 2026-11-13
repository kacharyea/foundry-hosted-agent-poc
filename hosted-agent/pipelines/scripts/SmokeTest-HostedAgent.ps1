[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $ProjectEndpoint,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName
)

$ErrorActionPreference = 'Stop'
$token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a Foundry token from the Azure service connection.'
}
$headers = @{ Authorization = "Bearer $token" }
$endpoint = "$($ProjectEndpoint.TrimEnd('/'))/agents/$AgentName/endpoint/protocols/openai/responses?api-version=v1"
$request = @{ input = 'Show user 1 details and incomplete tasks. Name every tool used.'; stream = $false; store = $false } | ConvertTo-Json
$response = Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Post `
    -ContentType 'application/json' -Body $request -TimeoutSec 180

if ($response.status -ne 'completed') { throw "Agent response status was '$($response.status)'." }
$calls = @($response.output | Where-Object type -eq 'function_call' | Select-Object -ExpandProperty name)
foreach ($required in @('get_user_details', 'get_user_tasks')) {
    if ($calls -notcontains $required) { throw "Required tool '$required' was not called. Calls: $($calls -join ', ')" }
}
$text = @(($response.output | Where-Object type -eq 'message').content |
    Where-Object type -eq 'output_text' | Select-Object -ExpandProperty text)
if (-not ($text -join '').Trim()) { throw 'Agent returned no output text.' }
Write-Host "Smoke test passed. Tools: $($calls -join ', ')"
Write-Host "Response ID: $($response.id)"
