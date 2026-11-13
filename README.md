# Microsoft Foundry Hosted Agent — .NET POC

A reusable C#/.NET 10 reference implementation for a Microsoft Foundry Hosted Agent built with
Microsoft Agent Framework. It demonstrates:

- Responses 2.0 container hosting in Microsoft Foundry.
- Three read-only REST tools backed by JSONPlaceholder.
- Microsoft Learn MCP discovery and `microsoft_docs_search`.
- Entra ID authentication and managed identity.
- Native Foundry OpenTelemetry plus custom tool spans.
- Workspace-based Application Insights and Log Analytics.
- Azure Bicep for support resources, Foundry connections, and workload RBAC.
- Separate Azure DevOps pipelines for infrastructure and application delivery.

## Security and portability

This repository contains **no password, client secret, access token, certificate, or Application
Insights connection string**. Azure resource names and endpoints are examples only. Authentication
uses Azure CLI/DefaultAzureCredential locally, managed identity in Foundry, and a federated Azure
DevOps service connection in pipelines.

Never commit `.env`, `.azure`, `bin`, `obj`, Visual Studio user state, credentials, or downloaded
certificates. Review `git status` and run your organization's secret scanner before publishing.

To create a ZIP that excludes those local/generated files:

```powershell
.\tools\New-SharePackage.ps1
```

Review the archive and run your organization's approved secret scanner before distribution. When
using Git, prefer sharing committed/tracked files because `.gitignore` already excludes local state.

> GenAI message-content capture is enabled in the Hosted Agent deployment for synthetic/public POC
> data. Set `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=false` before using sensitive data.

## Architecture

```text
ConsoleAppClient
  | Entra token for https://ai.azure.com/.default
  v
Foundry managed Responses endpoint
  v
.NET 10 Hosted Agent / Microsoft Agent Framework
  |-- get_user_details -----> JSONPlaceholder
  |-- get_user_tasks -------> JSONPlaceholder
  |-- get_user_posts -------> JSONPlaceholder
  `-- microsoft_docs_search -> Microsoft Learn MCP
  |
  `--> Foundry native traces + custom tool.* spans
         |
         `--> Application Insights / Log Analytics
```

## Repository layout

```text
hosted-agent/                    Application deployment unit
  src/FoundryHostedAgent/        Agent, tools, telemetry, Dockerfile
  src/ConsoleAppClient/          Entra-authenticated client
  tests/                         Deterministic unit tests
  scripts/                       Local and observability helpers
  pipelines/                     Application pipeline and deployment scripts
  azure.yaml                     Foundry Hosted Agent manifest

infrastructure/                  Infrastructure deployment unit
  main.bicep                     Bicep composition
  modules/                       Support resources, connections, permissions
  environments/example.bicepparam
  azure-pipelines.yml            Infrastructure validation/what-if/deployment

azure-pipelines.yml              Stable application-pipeline entry point
deploy/Deploy-Solution.ps1       One-command infrastructure + agent deployment
tools/New-SharePackage.ps1       Creates a sanitized ZIP for sharing
docs/                            Architecture, security, and operations detail
```

## Prerequisites

- Azure subscription and permission to deploy resources/RBAC.
- Existing Microsoft Foundry account and project with a system-assigned identity.
- A compatible model deployment, such as `gpt-5-mini`.
- Azure CLI and an authenticated account.
- Azure Developer CLI with the Microsoft Foundry extension for `azd` workflows.
- .NET SDK version from `global.json`.
- Azure DevOps only if using the included pipelines.

Confirm local tools:

```powershell
az version
az bicep version
dotnet --version
azd version
```

## Choose a deployment method

Both methods deploy the same things in the same order: **infrastructure and permissions → container
image → Hosted Agent version → smoke test**. Complete the Prerequisites first, then pick one.

### Option A — one deployment script

1. Sign in (`az login`) and make sure you can reach the subscription.
2. Create your parameter file (see step 3 below):

   ```powershell
   Copy-Item .\infrastructure\environments\example.bicepparam .\infrastructure\environments\dev.bicepparam
   ```

3. Preview the infrastructure changes. Nothing is created in this mode:

   ```powershell
   .\deploy\Deploy-Solution.ps1 `
     -ParameterFile .\infrastructure\environments\dev.bicepparam `
     -ResourceGroup <resource-group> `
     -ModelDeployment <model-deployment-name> `
     -WhatIfOnly
   ```

4. Deploy everything:

   ```powershell
   .\deploy\Deploy-Solution.ps1 `
     -ParameterFile .\infrastructure\environments\dev.bicepparam `
     -ResourceGroup <resource-group> `
     -ModelDeployment <model-deployment-name>
   ```

Useful switches: `-SubscriptionId`, `-AgentName`, `-ImageTag`, `-SkipInfrastructure`,
`-SkipImageBuild`, `-SkipAgentDeployment`, `-SkipSmokeTest`. If PowerShell blocks scripts, start it
with `powershell.exe -ExecutionPolicy Bypass -File .\deploy\Deploy-Solution.ps1 ...`.

The script uses your current Azure CLI identity, which needs permission to deploy to the resource
group, create role assignments, build in ACR, and manage agents in the Foundry project (see
[infrastructure/README.md](infrastructure/README.md)). It is idempotent: re-running it creates a new
image tag and a new agent version and leaves existing infrastructure unchanged. Role assignments can
take a few minutes to propagate, so the script retries the agent deployment automatically.

> Run it from a folder whose path has no `&`, `^`, `%`, or `!` characters; the Azure CLI Windows
> launcher cannot pass those safely. The script stops with a clear message if it detects one.

### Option B — Azure DevOps pipelines

Use two pipelines. Run the **infrastructure pipeline first**, because the application pipeline needs
the registry and Foundry connections it creates.

1. Create an Azure Resource Manager service connection using workload identity federation, and
   grant its identity the permissions listed in [infrastructure/README.md](infrastructure/README.md).
2. Create the variable groups and environments described in
   [Azure DevOps pipelines](#azure-devops-pipelines) below.
3. Create pipeline 1 from `/infrastructure/azure-pipelines.yml` and run it. Approve the what-if.
4. Create pipeline 2 from `/azure-pipelines.yml`. `develop` deploys the development agent; `main`
   additionally requires approval before production.

### Manual step-by-step

The numbered sections below show each stage individually, which is useful for troubleshooting or
for adapting the flow to another tool.

## 1. Sign in and select your subscription

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
azd auth login
```

No credentials are stored in the repository.

## 2. Prepare a Foundry project and model

Create or select a Foundry account/project and deploy a model. Record:

```text
Subscription ID
Resource group
Foundry account name
Foundry project name
Foundry project endpoint
Model deployment name
```

The project endpoint has this form:

```text
https://<foundry-account>.services.ai.azure.com/api/projects/<foundry-project>
```

The Bicep template intentionally **references** the Foundry account/project; it does not create or
replace them or the model deployment.

## 3. Configure infrastructure parameters

Copy the example:

```powershell
Copy-Item `
  .\infrastructure\environments\example.bicepparam `
  .\infrastructure\environments\dev.bicepparam
```

Edit `dev.bicepparam` with your existing Foundry names and globally unique ACR name:

```bicep
param location = 'eastus2'
param foundryAccountName = 'my-foundry-account'
param foundryProjectName = 'my-foundry-project'
param containerRegistryName = 'myagentacr12345'
param logAnalyticsWorkspaceName = 'law-hosted-agent-dev'
param applicationInsightsName = 'appi-hosted-agent-dev'
```

Leave the role-assignment-name parameters empty for a new environment. Supply GUIDs only when
adopting existing assignments created outside this template.

The infrastructure creates or manages:

- Azure Container Registry with local admin disabled.
- Log Analytics workspace.
- Workspace-based Application Insights.
- Foundry ACR and Application Insights project connections.
- `AcrPull` for the Foundry project identity on ACR.
- `Log Analytics Data Reader` for the project identity on the workspace.

## 4. Validate and deploy infrastructure

Always review what-if before deployment:

```powershell
$resourceGroup = '<resource-group>'
$parameters = '.\infrastructure\environments\dev.bicepparam'

az bicep build --file .\infrastructure\main.bicep

az deployment group validate `
  --resource-group $resourceGroup `
  --template-file .\infrastructure\main.bicep `
  --parameters $parameters

az deployment group what-if `
  --resource-group $resourceGroup `
  --template-file .\infrastructure\main.bicep `
  --parameters $parameters

az deployment group create `
  --name hosted-agent-infra `
  --resource-group $resourceGroup `
  --template-file .\infrastructure\main.bicep `
  --parameters $parameters
```

Use incremental mode only in a shared resource group. See `infrastructure/README.md` for required
deployment-identity permissions.

## 5. Configure local application settings

Copy `hosted-agent/.env.example` to `.env` for reference, but note that PowerShell and .NET do not
automatically load this file. Set environment variables in your shell:

```powershell
$env:FOUNDRY_PROJECT_ENDPOINT = 'https://<account>.services.ai.azure.com/api/projects/<project>'
$env:AZURE_AI_MODEL_DEPLOYMENT_NAME = 'gpt-5-mini'
$env:JSONPLACEHOLDER_BASE_URL = 'https://jsonplaceholder.typicode.com/'
$env:MICROSOFT_LEARN_MCP_ENDPOINT = 'https://learn.microsoft.com/api/mcp'
$env:FOUNDRY_HOSTED_AGENT_NAME = 'foundry-hosted-integration-poc'
$env:POC_CREDENTIAL_MODE = 'azure-cli'
$env:PORT = '8088'
```

Do not put a token or connection string in `.env`.

## 6. Build and test

```powershell
dotnet restore .\hosted-agent\FoundryHostedAgentPoc.slnx
dotnet build .\hosted-agent\FoundryHostedAgentPoc.slnx -c Release --no-restore
dotnet test .\hosted-agent\FoundryHostedAgentPoc.slnx -c Release --no-build --no-restore
dotnet format .\hosted-agent\FoundryHostedAgentPoc.slnx --verify-no-changes --no-restore
```

## 7. Run locally

```powershell
dotnet run --project .\hosted-agent\src\FoundryHostedAgent -c Release
```

In a second terminal:

```powershell
.\hosted-agent\scripts\Test-LocalTools.ps1
```

## 8. Build the container

Use ACR remote build so local Docker is optional:

```powershell
$acrName = '<acr-name>'
$tag = 'dev-1'

az acr build `
  --registry $acrName `
  --image "foundry-hosted-integration-poc:$tag" `
  --file .\hosted-agent\src\FoundryHostedAgent\Dockerfile `
  --platform linux/amd64 `
  .\hosted-agent\src\FoundryHostedAgent
```

## 9. Deploy the Hosted Agent

The application pipeline is the recommended deployment path. For a manual deployment:

```powershell
.\hosted-agent\pipelines\scripts\Deploy-HostedAgent.ps1 `
  -ProjectEndpoint $env:FOUNDRY_PROJECT_ENDPOINT `
  -AgentName $env:FOUNDRY_HOSTED_AGENT_NAME `
  -ImageUri '<acr-name>.azurecr.io/foundry-hosted-integration-poc:dev-1' `
  -ModelDeployment $env:AZURE_AI_MODEL_DEPLOYMENT_NAME `
  -Release 'dev-1'
```

The script creates an immutable Hosted Agent version, waits for it to become active, then routes
100% of endpoint traffic to that version.

## 10. Invoke the deployed agent

```powershell
dotnet run --project .\hosted-agent\src\ConsoleAppClient -- `
  "Show user 1 details and incomplete tasks. Name every tool used."
```

The caller needs **Foundry Agent Consumer** at project scope, or another approved role that includes
managed-agent invocation.

## 11. Verify telemetry

Generate demo traces:

```powershell
$agentEndpoint = "$($env:FOUNDRY_PROJECT_ENDPOINT)/agents/$($env:FOUNDRY_HOSTED_AGENT_NAME)/endpoint/protocols/openai/responses?api-version=v1"

.\hosted-agent\scripts\Run-ObservabilityDemo.ps1 `
  -AgentEndpoint $agentEndpoint
```

Query the linked workspace:

```powershell
.\hosted-agent\scripts\Query-Observability.ps1 `
  -ResourceGroup '<resource-group>' `
  -WorkspaceName '<log-analytics-workspace>'
```

Native spans include `invoke_agent`, `chat`, and `execute_tool`. Custom spans use names such as
`tool.get_user_details` and the service role `foundry-hosted-integration-poc-tools`.

## Azure DevOps pipelines

### Infrastructure pipeline

Create a pipeline using:

```text
/infrastructure/azure-pipelines.yml
```

Variable group: `foundry-hosted-agent-infra`

| Variable | Description |
|---|---|
| `AZURE_SERVICE_CONNECTION` | Federated ARM service connection |
| `AZURE_RESOURCE_GROUP` | Target resource group |
| `INFRA_PARAMETER_FILE` | Example: `infrastructure/environments/dev.bicepparam` |
| `APPROVAL_NOTIFY_USERS` | Approval notifications |
| `INFRASTRUCTURE_APPROVERS` | Authorized infrastructure approvers |

### Application pipeline

Create a pipeline using the root file:

```text
/azure-pipelines.yml
```

Variable group: `foundry-hosted-agent-poc`

| Variable | Description |
|---|---|
| `AZURE_SERVICE_CONNECTION` | Federated ARM service connection |
| `ACR_NAME` | Registry name |
| `ACR_LOGIN_SERVER` | `<acr-name>.azurecr.io` |
| `FOUNDRY_PROJECT_ENDPOINT` | Foundry project endpoint |
| `FOUNDRY_MODEL_DEPLOYMENT` | Model deployment name |
| `APPROVAL_NOTIFY_USERS` | Approval notifications |
| `PRODUCTION_APPROVERS` | Authorized production approvers |

Credentials belong in the federated service connection—not YAML or variable groups. Add Azure
DevOps environment approvals/checks for production and infrastructure in addition to YAML gates.

## Sharing a resource group with other workloads

The templates deploy **incrementally** and only **reference** the Foundry account, project, and model
deployment, so they can run in a resource group that already hosts another solution (for example a
Secure Policy RAG sample) and in either order. Review these points first:

| Topic | Guidance |
|---|---|
| Resource names | Use names different from the other workload's. The example parameters use `law-hosted-agent-*`, `appi-hosted-agent-*`, and a customer-chosen ACR name, so they do not collide with typical RAG names. |
| Foundry account and project | Look them up rather than guessing: `az cognitiveservices account list -g <rg> -o table`. The deploy script verifies they exist, have a system-assigned identity, and that the model deployment exists. |
| Application Insights | Use a **separate** component. If another workload's component disables local authentication, the Hosted Agent's connection-string exporter is rejected there. |
| Project connections | The template adds `hosted-agent-acr` and `hosted-agent-appinsights` to the shared project. Foundry's Traces view for that project then uses this App Insights. Avoid adding a second default App Insights connection. |
| Model capacity | The agent uses the same model deployment as the other workload, so they share its token quota. Check capacity before demos or load. |
| Network restrictions | If the Foundry account restricts outbound access, confirm the agent can reach `jsonplaceholder.typicode.com` and `learn.microsoft.com`, or point the tools at approved endpoints. |
| Teardown | Never delete the resource group to remove this solution; it would delete the other workload too. Delete only the agent versions, the ACR, the monitoring resources, the two project connections, and the two role assignments. Do not run Bicep in **Complete** mode against a shared group. |
| Agent names | Use a unique `-AgentName`; agent names are unique per Foundry project. |

## Tool examples

```text
Show user 1 details and incomplete tasks. Name every tool used.
Show the posts written by user 1 and name the tool used.
Use Microsoft Learn to explain managed identity and include a Learn URL.
Get details for user 99 and report the controlled error code.
```

## Additional documentation

- `docs/architecture.md`
- `docs/security.md`
- `docs/deployment.md`
- `docs/pipeline.md`
- `docs/observability-demo.md`

This POC uses public synthetic data and is not production-ready without an organizational security,
privacy, networking, reliability, and cost review.
