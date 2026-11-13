<#
.SYNOPSIS
Deploys the Foundry Hosted Agent solution end to end from a workstation or any PowerShell host.

.DESCRIPTION
Runs the same stages as the Azure DevOps pipelines:
  1. Bicep validation, what-if, and incremental deployment of support infrastructure/RBAC.
  2. ACR remote build of the agent container image.
  3. Hosted Agent version creation and endpoint routing.
  4. Managed-endpoint smoke test.

Requires an existing Microsoft Foundry account/project and model deployment. Authentication uses the
current Azure CLI login; no credentials are stored or accepted by this script.

.EXAMPLE
.\deploy\Deploy-Solution.ps1 -ParameterFile .\infrastructure\environments\dev.bicepparam `
  -ResourceGroup rg-agent-dev -ModelDeployment gpt-5-mini -WhatIfOnly

.EXAMPLE
.\deploy\Deploy-Solution.ps1 -ParameterFile .\infrastructure\environments\dev.bicepparam `
  -ResourceGroup rg-agent-dev -ModelDeployment gpt-5-mini
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ParameterFile,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ResourceGroup,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ModelDeployment,
    [string] $SubscriptionId,
    [ValidatePattern('^[a-zA-Z0-9-]{1,63}$')] [string] $AgentName = 'foundry-hosted-integration-poc',
    [ValidatePattern('^[a-z0-9][a-z0-9._/-]{0,127}$')] [string] $ImageRepository = 'foundry-hosted-integration-poc',
    [ValidatePattern('^[a-zA-Z0-9._-]{1,100}$')] [string] $ImageTag = (Get-Date -Format 'yyyyMMddHHmmss'),
    [ValidateRange(1, 5)] [int] $AgentDeploymentAttempts = 3,
    [switch] $WhatIfOnly,
    [switch] $SkipInfrastructure,
    [switch] $SkipImageBuild,
    [switch] $SkipAgentDeployment,
    [switch] $SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($repositoryRoot -match '[&^%!]') {
    throw "The repository path '$repositoryRoot' contains a special character (& ^ % !) that the Azure CLI Windows launcher cannot pass safely. Clone or copy the repository to a simple path such as C:\src\foundry-hosted-agent and run again."
}
$templateFile = Join-Path $repositoryRoot 'infrastructure\main.bicep'
$dockerContext = Join-Path $repositoryRoot 'hosted-agent\src\FoundryHostedAgent'
$dockerFile = Join-Path $dockerContext 'Dockerfile'
$deployAgentScript = Join-Path $repositoryRoot 'hosted-agent\pipelines\scripts\Deploy-HostedAgent.ps1'
$smokeTestScript = Join-Path $repositoryRoot 'hosted-agent\pipelines\scripts\SmokeTest-HostedAgent.ps1'

function Write-Step([string] $Message) {
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Invoke-Az {
    # Simple (non-advanced) function so az switches such as -o are not bound as PowerShell parameters.
    $azArguments = @($args)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & az @azArguments 2>&1 } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) { throw "az $($azArguments -join ' ') failed.`n$($output | Out-String)" }
    return $output
}

function Get-BicepParameterValues([string] $Path) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $raw = & az bicep build-params --file $Path --stdout 2>&1 } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) { throw "Unable to compile parameter file '$Path'.`n$($raw | Out-String)" }
    $json = ($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String)
    $compiled = $json | ConvertFrom-Json
    return ($compiled.parametersJson | ConvertFrom-Json).parameters
}

Write-Step 'Checking prerequisites'
foreach ($tool in @('az')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool was not found on PATH." }
}
foreach ($path in @($templateFile, $dockerFile, $deployAgentScript, $smokeTestScript)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file was not found: $path" }
}
$ParameterFile = (Resolve-Path -LiteralPath $ParameterFile).Path

$null = Invoke-Az account show --query id -o tsv
if ($SubscriptionId) { $null = Invoke-Az account set --subscription $SubscriptionId }
$activeSubscription = (Invoke-Az account show --query id -o tsv | Out-String).Trim()
Write-Host "Subscription: $activeSubscription"
Write-Host "Resource group: $ResourceGroup"

$parameters = Get-BicepParameterValues $ParameterFile
foreach ($required in @('foundryAccountName', 'foundryProjectName', 'containerRegistryName')) {
    if (-not $parameters.$required.value) { throw "Parameter '$required' is missing from $ParameterFile." }
}
$registryName = [string]$parameters.containerRegistryName.value
$foundryAccount = [string]$parameters.foundryAccountName.value
$foundryProject = [string]$parameters.foundryProjectName.value

Write-Step 'Checking the existing Foundry account and project'
$null = Invoke-Az cognitiveservices account show --name $foundryAccount --resource-group $ResourceGroup --query name -o tsv
$projectResourceId = (Invoke-Az cognitiveservices account show --name $foundryAccount --resource-group $ResourceGroup --query id -o tsv | Out-String).Trim() + "/projects/$foundryProject"
$projectPrincipal = (Invoke-Az resource show --ids $projectResourceId --api-version 2025-06-01 --query identity.principalId -o tsv | Out-String).Trim()
if (-not $projectPrincipal) {
    throw "Foundry project '$foundryProject' has no system-assigned managed identity. Enable it before deploying."
}
Write-Host "Foundry account '$foundryAccount' and project '$foundryProject' found."
$existingDeployment = (Invoke-Az cognitiveservices account deployment list --name $foundryAccount --resource-group $ResourceGroup --query "[?name=='$ModelDeployment'].name | [0]" -o tsv | Out-String).Trim()
if (-not $existingDeployment) {
    throw "Model deployment '$ModelDeployment' was not found on '$foundryAccount'. Create it first or pass the correct -ModelDeployment."
}
Write-Host "Model deployment '$ModelDeployment' found (shared with any other workload that uses it)."
$projectEndpoint = "https://$($parameters.foundryAccountName.value).services.ai.azure.com/api/projects/$($parameters.foundryProjectName.value)"
$deploymentName = "hosted-agent-infra-$ImageTag"

if (-not $SkipInfrastructure) {
    Write-Step 'Validating infrastructure'
    $null = Invoke-Az bicep build --file $templateFile --stdout
    $null = Invoke-Az deployment group validate --name "$deploymentName-validate" --resource-group $ResourceGroup `
        --template-file $templateFile --parameters $ParameterFile

    Write-Step 'Reviewing infrastructure changes (what-if)'
    Invoke-Az deployment group what-if --name "$deploymentName-whatif" --resource-group $ResourceGroup `
        --template-file $templateFile --parameters $ParameterFile --result-format ResourceIdOnly | Write-Host

    if ($WhatIfOnly) {
        Write-Host "`nWhat-if completed. No resources were changed." -ForegroundColor Green
        return
    }

    Write-Step 'Deploying infrastructure and permissions'
    $state = (Invoke-Az deployment group create --name $deploymentName --resource-group $ResourceGroup `
        --template-file $templateFile --parameters $ParameterFile --query properties.provisioningState -o tsv | Out-String).Trim()
    if ($state -ne 'Succeeded') { throw "Infrastructure deployment ended with state '$state'." }
    Write-Host "Infrastructure deployment: $state" -ForegroundColor Green
}
elseif ($WhatIfOnly) {
    throw '-WhatIfOnly cannot be combined with -SkipInfrastructure.'
}

$loginServer = (Invoke-Az acr show --name $registryName --resource-group $ResourceGroup --query loginServer -o tsv | Out-String).Trim()
$imageUri = "$loginServer/${ImageRepository}:$ImageTag"

if (-not $SkipImageBuild) {
    Write-Step "Building container image $imageUri"
    Invoke-Az acr build --registry $registryName --image "${ImageRepository}:$ImageTag" `
        --file $dockerFile --platform linux/amd64 $dockerContext | Write-Host
}

if (-not $SkipAgentDeployment) {
    Write-Step 'Deploying Hosted Agent version'
    $deployed = $false
    for ($attempt = 1; $attempt -le $AgentDeploymentAttempts -and -not $deployed; $attempt++) {
        try {
            & $deployAgentScript -ProjectEndpoint $projectEndpoint -AgentName $AgentName -ImageUri $imageUri `
                -ModelDeployment $ModelDeployment -Release $ImageTag
            $deployed = $true
        }
        catch {
            if ($attempt -eq $AgentDeploymentAttempts) { throw }
            Write-Warning "Attempt $attempt failed: $($_.Exception.Message)"
            Write-Warning 'RBAC assignments can take several minutes to propagate. Retrying in 90 seconds.'
            Start-Sleep -Seconds 90
        }
    }
}

if (-not $SkipSmokeTest) {
    Write-Step 'Running managed-endpoint smoke test'
    & $smokeTestScript -ProjectEndpoint $projectEndpoint -AgentName $AgentName
}

Write-Step 'Deployment complete'
Write-Host "Agent endpoint: $projectEndpoint/agents/$AgentName/endpoint/protocols/openai/responses?api-version=v1"
Write-Host "Image:          $imageUri"
Write-Host "Invoke:         `$env:FOUNDRY_PROJECT_ENDPOINT='$projectEndpoint'; `$env:FOUNDRY_HOSTED_AGENT_NAME='$AgentName'"
Write-Host '                dotnet run --project .\hosted-agent\src\ConsoleAppClient'
