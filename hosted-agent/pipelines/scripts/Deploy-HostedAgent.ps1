[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^https://')] [string] $ProjectEndpoint,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9.-]+/[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$')] [string] $ImageUri,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ModelDeployment,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]{1,100}$')] [string] $Release,
    [int] $TimeoutMinutes = 12
)

$ErrorActionPreference = 'Stop'
$project = $ProjectEndpoint.TrimEnd('/')
$token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a Foundry token from the Azure service connection.'
}
$headers = @{ Authorization = "Bearer $token" }
$agentUri = "$project/agents/$AgentName?api-version=v1"

$definition = @{
    kind = 'hosted'
    cpu = '0.5'
    memory = '1Gi'
    container_configuration = @{ image = $ImageUri }
    protocol_versions = @(@{ protocol = 'responses'; version = '2.0.0' })
    environment_variables = @{
        AZURE_AI_MODEL_DEPLOYMENT_NAME = $ModelDeployment
        JSONPLACEHOLDER_BASE_URL = 'https://jsonplaceholder.typicode.com/'
        MICROSOFT_LEARN_MCP_ENDPOINT = 'https://learn.microsoft.com/api/mcp'
        # Safe only for this synthetic/public-data POC. Disable for sensitive workloads.
        OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = 'true'
        POC_RELEASE = $Release
    }
}

$exists = $false
try {
    Invoke-RestMethod -Uri $agentUri -Headers $headers -Method Get | Out-Null
    $exists = $true
} catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
}

$payload = if ($exists) {
    @{ definition = $definition; description = 'Read-only C# Hosted Agent with REST and Microsoft Learn MCP tools.' }
} else {
    @{ name = $AgentName; definition = $definition; description = 'Read-only C# Hosted Agent with REST and Microsoft Learn MCP tools.' }
}
$createUri = if ($exists) { "$project/agents/$AgentName/versions?api-version=v1" } else { "$project/agents?api-version=v1" }
$created = Invoke-RestMethod -Uri $createUri -Headers $headers -Method Post `
    -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 12)
$version = [string]$created.version
if ([string]::IsNullOrWhiteSpace($version)) { throw 'Foundry did not return an agent version.' }
Write-Host "Created $AgentName version $version from $ImageUri"

$deadline = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
do {
    Start-Sleep -Seconds 10
    $details = Invoke-RestMethod -Uri "$project/agents/$AgentName/versions/$version?api-version=v1" -Headers $headers
    Write-Host "Provisioning status: $($details.status)"
    if ($details.status -eq 'failed') { throw "Hosted Agent provisioning failed: $($details.error.code) - $($details.error.message)" }
} while ($details.status -ne 'active' -and [DateTimeOffset]::UtcNow -lt $deadline)
if ($details.status -ne 'active') { throw "Timed out waiting for $AgentName version $version." }

$route = @{ agent_endpoint = @{ version_selector = @{ version_selection_rules = @(@{
    type = 'FixedRatio'; agent_version = $version; traffic_percentage = 100
}) }; protocol_configuration = @{ responses = @{} } } } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri $agentUri -Headers $headers -Method Patch `
    -ContentType 'application/merge-patch+json' -Body $route | Out-Null

Write-Host "Activated $AgentName version $version"
Write-Host "##vso[task.setvariable variable=DeployedAgentVersion]$version"
Write-Host "##vso[task.setvariable variable=DeployedAgentEndpoint]$project/agents/$AgentName/endpoint/protocols/openai/responses?api-version=v1"
