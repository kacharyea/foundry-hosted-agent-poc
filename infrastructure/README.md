# Hosted Agent infrastructure

This folder owns the Azure support resources, Foundry project connections, and workload permissions
required by the Hosted Agent. It references—rather than creates—the Foundry account/project and
model deployment.

## Managed resources

- Azure Container Registry with local admin disabled.
- Log Analytics workspace.
- Workspace-based Application Insights component.
- Foundry project connections for ACR and Application Insights.
- `AcrPull` for the Foundry project managed identity on ACR.
- `Log Analytics Data Reader` for the project identity on the workspace.

The Basic ACR configuration uses legacy registry permissions, so `AcrPull` is intentional. Review
the role if your registry uses ABAC repository permissions.

## Configure an environment

```powershell
Copy-Item `
  .\infrastructure\environments\example.bicepparam `
  .\infrastructure\environments\dev.bicepparam
```

Edit the copied file. The ACR name must be globally unique. Leave role-assignment-name parameters
empty for new environments; provide existing assignment GUIDs only when adopting those records.

## Validate and deploy

```powershell
$resourceGroup = '<resource-group>'
$parameters = '.\infrastructure\environments\dev.bicepparam'

az bicep build --file .\infrastructure\main.bicep
az deployment group validate --resource-group $resourceGroup `
  --template-file .\infrastructure\main.bicep --parameters $parameters
az deployment group what-if --resource-group $resourceGroup `
  --template-file .\infrastructure\main.bicep --parameters $parameters
az deployment group create --name hosted-agent-infra --resource-group $resourceGroup `
  --template-file .\infrastructure\main.bicep --parameters $parameters
```

Use incremental mode in a shared resource group and review what-if before deployment.

## Pipeline

Create a separate Azure DevOps pipeline at `/infrastructure/azure-pipelines.yml` and a variable
group named `foundry-hosted-agent-infra` containing:

| Variable | Purpose |
|---|---|
| `AZURE_SERVICE_CONNECTION` | Federated Azure Resource Manager service connection |
| `AZURE_RESOURCE_GROUP` | Target resource group |
| `INFRA_PARAMETER_FILE` | Environment parameter path |
| `APPROVAL_NOTIFY_USERS` | Users/groups notified for approval |
| `INFRASTRUCTURE_APPROVERS` | Users/groups authorized to approve |

The service-connection identity requires resource-group Contributor, permission to create the two
role assignments, and Foundry Project Manager on the existing project. Bootstrap those permissions
through an authorized administrator; this template does not self-grant deployment permissions.
