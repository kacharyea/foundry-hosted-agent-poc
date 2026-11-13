# Deployment guide

Deployment creates or uses cost-bearing Azure resources. Review each step before running it.

## Target reuse decision

The existing lab project can host the agent:

```text
Subscription: <subscription-id>
Resource group: <resource-group>
Foundry account: <foundry-account>
Foundry project: <foundry-project>
Model: gpt-5-mini
Project ARM ID:
/subscriptions/<subscription-id>/resourceGroups/<resource-group>/
providers/Microsoft.CognitiveServices/accounts/<foundry-account>/projects/<foundry-project>
```

Initial implementation review found:

- The signed-in developer has **Foundry User**, not **Foundry Project Manager**, at project scope.
- No ACR or Application Insights resource is present in the resource group.
- `azd` and Docker are not installed. Docker is optional because the manifest requests ACR remote build.

Deployment added:

```text
ACR: <acr-name> (Basic, admin disabled)
Image: foundry-hosted-integration-poc:20261106.3
Log Analytics: <log-analytics-workspace> (30-day retention)
Application Insights: <application-insights-name>
Foundry connections: hosted-agent-acr, hosted-agent-appinsights
Hosted Agent: foundry-hosted-integration-poc, container-backed version 6
```

## 1. Install tooling and authenticate

Install the current Foundry Dev Pack (`azd >= 1.27.1`) using the organization-approved method.

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
azd auth login
azd ext install microsoft.foundry
.\hosted-agent\scripts\Check-Prerequisites.ps1
```

## 2. Obtain deployment permission

Request **Foundry Project Manager** at the exact project scope. Do not grant it to external clients.
The role ID is `eadc314b-1a2d-4efa-be10-5d325db5065e`.

Confirm before continuing:

```powershell
$projectId = '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.CognitiveServices/accounts/<foundry-account>/projects/<foundry-project>'
$me = az ad signed-in-user show --query id -o tsv
az role assignment list --assignee $me --scope $projectId --include-inherited -o table
```

## 3. Validate and deploy support infrastructure

The Bicep deployment references the existing Foundry account/project and manages only the Hosted
Agent ACR, monitoring resources, project connections, and workload RBAC. From the repository root:

```powershell
az bicep build --file .\infrastructure\main.bicep

az deployment group validate `
  --resource-group <resource-group> `
  --template-file .\infrastructure\main.bicep `
  --parameters .\infrastructure\environments\lab.bicepparam

az deployment group what-if `
  --resource-group <resource-group> `
  --template-file .\infrastructure\main.bicep `
  --parameters .\infrastructure\environments\lab.bicepparam
```

Review the what-if and use the separately approved infrastructure pipeline for deployment. Do not
use complete mode against the shared resource group. See `infrastructure/README.md` for pipeline
identity permissions and variables.

After provisioning:

1. Verify the project managed identity has **AcrPull** on the Basic ACR. This registry currently
   uses `LegacyRegistryPermissions`.
2. Verify `hosted-agent-acr` and `hosted-agent-appinsights` under Foundry project connections.
3. Verify Application Insights is workspace-based and linked to `<log-analytics-workspace>`.

## 4. Initialize the application against the existing project

Some azd/extension versions can mishandle special characters in a workspace path. If deployment
fails while resolving the manifest, use a synchronized working copy with a simple path or use the
Foundry Toolkit deployment UI. The authoritative source remains this repository.

Run from the `hosted-agent` folder (or use a synchronized safe-path working copy):

```powershell
$projectId = '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.CognitiveServices/accounts/<foundry-account>/projects/<foundry-project>'

Set-Location .\hosted-agent
azd ai agent init --deploy-mode container -m .\azure.yaml `
  -p $projectId -d gpt-5-mini --agent-name foundry-hosted-integration-poc
```

Inspect generated environment/configuration before provisioning. Ensure it targets the existing
project and does not declare a duplicate model deployment with incompatible version or capacity.

## 5. Deploy container and hosted version

```powershell
azd deploy
azd ai agent show --output table
```

`azd` performs an ACR remote `linux/amd64` build, pushes a uniquely versioned image, creates the
Hosted Agent version, and waits for it to become active. Do not use `latest` for a manual image flow.

For this existing project, azd initially selected source-code deployment. To satisfy the explicit
ACR requirement, the image was built with `az acr build`, an ACR project connection was created,
and a container-backed version was created through the Foundry Agents API. The registry uses
`LegacyRegistryPermissions`, so **AcrPull** is the effective pull role; repository-reader applies
when ACR is configured for RBAC Registry + ABAC Repository Permissions.

## 6. Invoke and monitor

```powershell
azd ai agent invoke "Show user 1 details and incomplete tasks"
azd ai agent invoke "Use Microsoft Learn to explain managed identity"
azd ai agent monitor --follow
```

External client:

```powershell
$env:FOUNDRY_PROJECT_ENDPOINT = 'https://<foundry-account>.services.ai.azure.com/api/projects/<foundry-project>'
$env:FOUNDRY_HOSTED_AGENT_NAME = 'foundry-hosted-integration-poc'
dotnet run --project .\hosted-agent\src\ConsoleAppClient -- "Show user 1 details and use Microsoft Learn to explain managed identity"
```

Grant calling identities **Foundry Agent Consumer** (`eed3b665-ab3a-47b6-8f48-c9382fb1dad6`)
at project scope when they do not need development access.

## 7. Validate telemetry

In Application Insights, find the request by trace ID and verify:

- Hosted endpoint request and model spans.
- `tool.get_user_details`, `tool.get_user_tasks`, `tool.get_user_posts`, or
  `tool.microsoft_docs_search` spans.
- Dependency duration and controlled failure status.
- No access tokens or secrets in attributes.

## Cleanup

Do not run `azd down` against this shared project. Remove only the hosted agent versions, ACR images,
and POC-specific support resources after reviewing their resource IDs. Deleting the shared resource
group would also delete Secure Policy RAG resources.
