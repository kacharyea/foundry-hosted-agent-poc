# Hosted Agent application

This folder is the application deployment unit for the .NET 10 Microsoft Foundry Hosted Agent.

- `src/FoundryHostedAgent`: Agent Framework host, REST tools, MCP adapter, Dockerfile, telemetry.
- `src/ConsoleAppClient`: Independent Entra-authenticated client.
- `tests`: Deterministic unit tests.
- `scripts`: Local and observability helpers.
- `pipelines`: Application/container CI/CD and deployment helpers.
- `azure.yaml`: Foundry Hosted Agent manifest.

The root `azure-pipelines.yml` extends `hosted-agent/pipelines/pipeline.yml`. Infrastructure and
workload RBAC are intentionally separate under `../infrastructure`.

Run from the repository root:

```powershell
dotnet restore .\hosted-agent\FoundryHostedAgentPoc.slnx
dotnet build .\hosted-agent\FoundryHostedAgentPoc.slnx -c Release --no-restore
dotnet test .\hosted-agent\FoundryHostedAgentPoc.slnx -c Release --no-build --no-restore
```
