# Azure DevOps pipeline

The root [`azure-pipelines.yml`](../azure-pipelines.yml) is the stable application-pipeline entry
point. It extends
[`hosted-agent/pipelines/pipeline.yml`](../hosted-agent/pipelines/pipeline.yml), which contains the
implementation and uses helpers under
[`hosted-agent/pipelines/scripts`](../hosted-agent/pipelines/scripts).

Infrastructure has an independent pipeline at
[`infrastructure/azure-pipelines.yml`](../infrastructure/azure-pipelines.yml). Configure it as a
second Azure DevOps pipeline so infrastructure/RBAC changes have separate validation, what-if,
approval, and deployment history.

The Hosted Agent pipeline implements:

1. Branch and pull-request restore/build/test/format/package checks.
2. Immutable `linux/amd64` ACR remote build for `main` and `develop`.
3. Development Hosted Agent deployment.
4. Managed-endpoint smoke test requiring two REST tool calls.
5. Manual production validation on `main`.
6. Production deployment of the exact approved image and a second smoke test.

## Azure DevOps setup

Create an Azure Resource Manager service connection and a variable group named:

```text
foundry-hosted-agent-poc
```

Define these **nonsecret placeholders** in the group:

| Variable | Example/description |
|---|---|
| `AZURE_SERVICE_CONNECTION` | Name of the Azure DevOps ARM service connection |
| `ACR_NAME` | `<acr-name>` |
| `ACR_LOGIN_SERVER` | `<acr-name>.azurecr.io` |
| `FOUNDRY_PROJECT_ENDPOINT` | Foundry project HTTPS endpoint |
| `FOUNDRY_MODEL_DEPLOYMENT` | `gpt-5-mini` |
| `APPROVAL_NOTIFY_USERS` | Azure DevOps users/groups notified for approval |
| `PRODUCTION_APPROVERS` | Azure DevOps users/groups allowed to approve |

Credentials belong in the Azure service connection, not in variables or YAML. Prefer workload
identity federation rather than a stored client secret.

## Service connection permissions

The service-connection identity needs only the deployment permissions required by the pipeline:

- **Container Registry Tasks Contributor** or equivalent permission to queue ACR builds.
- **Foundry Project Manager** on the target Foundry project to create and route versions.
- **Foundry Agent Consumer** is sufficient for a separate invocation-only identity.
- ACR/project connection and project identity pull permissions must already exist.

Do not grant subscription Owner solely for this pipeline.

## Approval checks

The YAML includes `ManualValidation@1`. Also configure an Azure DevOps **Approvals and checks** rule
on the `foundry-hosted-agent-prod` environment. Environment checks are administered outside YAML,
so a pull request cannot remove the production gate.

Recommended production checks:

- Named security/application owner approval.
- Branch control allowing only `main`.
- Required successful development smoke test.
- Optional business-hours or change-ticket check.
- Exclusive lock to prevent overlapping promotions.

## Branch behavior

| Branch/event | Behavior |
|---|---|
| Pull request to `main`/`develop` | Build, tests, formatting, dependency check only |
| `feature/*` push | Build and checks only |
| `develop` push | Build image, deploy development, smoke test |
| `main` push | Build image, deploy/smoke development, manual approval, deploy/smoke production |

The development and production agent names are separate. Production currently targets
`foundry-hosted-integration-poc`; development targets `foundry-hosted-integration-poc-dev`.
