# Observability demo

This POC uses the existing resources in `<resource-group>`:

```text
Application Insights: <application-insights-name>
Log Analytics:        <log-analytics-workspace>
Hosted Agent:         foundry-hosted-integration-poc
```

Agent Framework and the Foundry Responses host emit OpenTelemetry spans automatically. Active
version 10 also exports the POC's custom `FoundryHostedAgent.Tools` spans through an isolated tracer
provider and enables `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true` for synthetic demo data.
Disable that setting before using real or sensitive content.

## Generate a successful multi-tool trace

```text
Show user 1 details and incomplete tasks. Name every tool used.
```

Expected span sequence:

```text
invoke_agent
  chat/model
  execute_tool get_user_details
    HTTP GET /users/1
  execute_tool get_user_tasks
    HTTP GET /todos?userId=1
  chat/model
```

## Generate an MCP trace

```text
Use Microsoft Learn to explain managed identity in three bullets and include a Learn URL.
```

Expected tool: `microsoft_docs_search`.

## Generate a controlled error trace

```text
Get details for user 99.
```

Expected result: `invalid_user_id`; zero outbound REST calls. This demonstrates that a tool can
execute and return a controlled business/security failure even when the HTTP request itself succeeds.

## Portal walkthrough

1. In Foundry, open the agent and select **Traces**.
2. Select the most recent trace and expand `invoke_agent`, model, and `execute_tool` spans.
3. Compare span duration to find model versus tool latency.
4. Open **Monitor** or the linked Application Insights resource.
5. In Azure Portal, open `<log-analytics-workspace>` > **Logs** (or open Logs from
   `<application-insights-name>`). Use the workspace-table KQL below and paste the printed trace ID.
6. Point out the shared `OperationId`: it correlates the platform request, container request, model
   calls, Agent Framework `execute_tool`, custom `tool.*`, and outbound HTTP spans.

## KQL examples

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| where AppVersion == "10" or Name == "invoke_agent"
| project TimeGenerated, Name, ResultCode, Success, DurationMs, OperationId, AppRoleName, AppVersion
| order by TimeGenerated desc
```

```kusto
AppDependencies
| where TimeGenerated > ago(1h)
| where Name startswith "invoke_agent"
    or Name startswith "chat "
    or Name startswith "execute_tool"
    or Name startswith "tool."
    or Target in ("jsonplaceholder.typicode.com", "learn.microsoft.com")
| project TimeGenerated, Name, Target, ResultCode, Success, DurationMs,
          OperationId, ParentId, AppRoleName, AppVersion
| order by TimeGenerated asc
```

```kusto
union AppRequests, AppDependencies, AppTraces, AppExceptions
| where OperationId == "<trace-id-without-hyphens>"
| order by TimeGenerated asc
```

Controlled failures, including custom tool errors:

```kusto
union AppRequests, AppDependencies
| where TimeGenerated > ago(1h)
| where Success == false
| project TimeGenerated, Type, Name, ResultCode, DurationMs, OperationId,
          AppRoleName, Properties
| order by TimeGenerated desc
```

Use the `App*` workspace tables for this environment. The earlier CLI checks against classic
`requests`/`dependencies` aliases appeared empty even while the workspace tables were ingesting.

## Troubleshooting prompts

| Demonstration | What to inspect |
|---|---|
| Slow first request | Cold-start/platform latency versus model/tool spans |
| Two REST tools | Parallel or sequential `execute_tool` spans and dependency duration |
| Invalid user 99 | Controlled `invalid_user_id`; no HTTP dependency |
| MCP request | MCP connection, discovery, tool call, bounded result, synthesis |
| MCP endpoint failure in a nonproduction test version | `mcp_timeout` or `mcp_unavailable` and span error status |

For a successful MCP call, protocol discovery/cleanup can contain HTTP 405 rows for unsupported
GET or DELETE operations while the enclosing `execute_tool microsoft_docs_search` and
`tool.microsoft_docs_search` spans remain successful. Diagnose the enclosing span before treating
an individual MCP transport row as the user-visible outcome.

Likewise, Foundry can emit expected 404 dependency rows while probing task or state-store records
before creating them. Use the enclosing `invoke_agent`, `POST /responses`, and tool span status to
distinguish an expected existence probe from a failed user request.

Never put access tokens, secrets, customer data, or sensitive tool output into span attributes.

## Run the prepared demo

```powershell
.\hosted-agent\scripts\Run-ObservabilityDemo.ps1
.\hosted-agent\scripts\Query-Observability.ps1
```

To inspect one trace only:

```powershell
.\hosted-agent\scripts\Query-Observability.ps1 -TraceId '<32-character-trace-id>'
```

## Current deployment note

The endpoint is pinned 100% to healthy version 10. Version 8 is failed and must not receive traffic;
version 9 remains the healthy rollback. Foundry's hosting package already registers the main Azure
Monitor exporter, so do not add a second DI `UseAzureMonitor`/`UseAzureMonitorExporter`
registration. Version 10 uses a separate `TracerProvider` that listens only to
`FoundryHostedAgent.Tools`.

Verified rows on November 10, 2026:

| Scenario | Trace ID | Evidence |
|---|---|---|
| REST multi-tool | `<successful-trace-id>` | `invoke_agent` 13.3 s; `POST /responses` 10.1 s; `tool.get_user_details` 122.5 ms; `tool.get_user_tasks` 39.3 ms |
| Controlled error | `<controlled-error-trace-id>` | `tool.get_user_details` 5.5 ms; `Success=false`; `error.type=invalid_user_id`; no JSONPlaceholder request |
| Microsoft Learn MCP | `<mcp-trace-id>` | `execute_tool microsoft_docs_search` 1.46 s; `tool.microsoft_docs_search` 1.45 s; successful Learn result |
