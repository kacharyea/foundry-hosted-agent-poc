# Deployment results

Deployed November 6 and observability revalidated November 10, 2026.

## Reused resources

| Resource | Value |
|---|---|
| Subscription | `<subscription-id>` |
| Resource group | `<resource-group>` |
| Foundry project | `<foundry-account> / <foundry-project>` |
| Model deployment | `gpt-5-mini` |

## Added resources

| Resource | Value |
|---|---|
| ACR | `<acr-name>` — Basic, admin disabled, public endpoint enabled |
| ACR image | `foundry-hosted-integration-poc:20261110.10` |
| Image digest | `<immutable-image-digest>` |
| Log Analytics | `<log-analytics-workspace>` — 30-day retention |
| Application Insights | `<application-insights-name>` |
| Foundry ACR connection | `hosted-agent-acr` |
| Foundry App Insights connection | `hosted-agent-appinsights` |
| Hosted Agent | `foundry-hosted-integration-poc` |
| Active version | `10` — container-backed, Responses 2.0, 0.5 CPU / 1 GiB |
| Agent identity | `<agent-identity-object-id>` |

Endpoint:

```text
https://<foundry-account>.services.ai.azure.com/api/projects/<foundry-project>/
agents/foundry-hosted-integration-poc/endpoint/protocols/openai/responses?api-version=v1
```

## RBAC

- The Foundry project managed identity has **AcrPull** on the POC ACR. The registry uses
  `LegacyRegistryPermissions`, so this is the effective pull role.
- The project managed identity has **Log Analytics Data Reader** on the POC workspace.
- The developer's temporary **Foundry Project Manager** assignment was removed after deployment;
  the pre-existing **Foundry User** assignment remains.
- No direct model, Search, Storage, or APIM roles were added to the hosted agent identity.

## Validation evidence

- Version 10 status: `active`, with 100% endpoint traffic.
- Remote REST multi-tool request selected `get_user_details` and `get_user_tasks`.
- Remote post request selected `get_user_posts`.
- Remote docs request selected `microsoft_docs_search` and returned a Microsoft Learn URL.
- External C# client authenticated with Entra and invoked the managed endpoint successfully.
- Example hosted trace ID: `<successful-trace-id>`.
- Session log confirmed `IsHosted=True`, `AgentVersion=10`, managed identity, and
  `AppInsightsConfigured=True`.
- Log Analytics `AppRequests`, `AppDependencies`, and `AppTraces` contain correlated version 10
  records, including model, Agent Framework tool, custom `tool.*`, outbound HTTP, latency, and
  controlled-error spans.
- Verified controlled-error trace: `<controlled-error-trace-id>`.
- Verified Microsoft Learn MCP trace: `<mcp-trace-id>`.

Versions 2 and 3 record failed ACR pull attempts before the project ACR connection/effective
legacy pull role were configured. Version 8 failed readiness because it duplicated Foundry's Azure
Monitor exporter and must not receive traffic. Version 9 is the healthy rollback; version 10 is the
current healthy release with an isolated custom tool-span provider.
