# Test scenarios and current results

Validated November 6, 2026. Local model runs used the existing Foundry project and `gpt-5-mini`.
Cloud deployment completed against container-backed Hosted Agent version 6.

| ID | Scenario | Current result | Evidence |
|---|---|---|---|
| TC-01 | Request user details | **Pass locally** | Unit route/structure test; live combined run selected `get_user_details` |
| TC-02 | Request incomplete tasks | **Pass locally** | Unit filtering test; live run returned 9 incomplete tasks for user 1 |
| TC-03 | Request user posts | **Pass locally** | Unit route/structured-result test |
| TC-04 | Ask about Azure services | **Pass locally** | Live call selected `microsoft_docs_search` and returned a Learn URL |
| TC-05 | User details and tasks | **Pass locally** | One request selected both REST tools and synthesized both results |
| TC-06 | User details and Microsoft documentation | **Pass locally** | One request selected `get_user_details` and `microsoft_docs_search` and synthesized both results |
| TC-07 | Invoke from external C# client | **Pass hosted** | Entra-authenticated `ConsoleAppClient` invoked the managed Responses endpoint successfully |
| TC-08 | REST API failure | **Pass deterministic test** | Controlled `rest_rejected`/`rest_timeout`; raw body suppressed |
| TC-09 | MCP failure | **Pass deterministic test** | Controlled `mcp_unavailable` or `mcp_timeout` |
| TC-10 | Inspect execution | **Partial pass** | Hosted session logs show version, trace ID, model/tool execution, and errors; `AppInsightsConfigured=True`, but KQL had not ingested rows at validation time |

## Automated suite

```text
Passed: 10
Failed: 0
Skipped: 0
Build warnings: 0
```

## Important observation

The first MCP implementation serialized the complete protocol result, which was too large for a
clean synthesis turn. The implementation now extracts at most five results with bounded excerpts.
The corrected live run completed and cited the official managed-identities overview.

## Hosted evidence

| Item | Observed value |
|---|---|
| Hosted Agent | `foundry-hosted-integration-poc` |
| Active container version | `10` |
| Image | `<acr-name>.azurecr.io/foundry-hosted-integration-poc:20261110.10` |
| Runtime | Foundry Hosted Agent, Responses 2.0, .NET 10 |
| REST multi-tool | `get_user_details,get_user_tasks` |
| Hosted MCP | `microsoft_docs_search` returned official managed-identity documentation |
| External client | Returned REST and MCP answers using Entra authentication |
| Example hosted trace ID | `<successful-trace-id>` |

Container session logs report `AppInsightsConfigured=True`. Workspace-native queries verify
correlated `AppRequests`, `AppDependencies`, and `AppTraces`, including custom successful and failed
tool spans. See `docs/observability-demo.md` for the exact trace IDs and timings.
