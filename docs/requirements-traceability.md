# Requirements traceability

| Requirement | Implementation | Evidence/status |
|---|---|---|
| FR-01 C#/.NET 10 Hosted Agent | `hosted-agent/src/FoundryHostedAgent`, Agent Framework, Responses 2.0 | Container version 10 active in Foundry |
| FR-01 Foundry model | `AIProjectClient.AsAIAgent`, `gpt-5-mini` | Local and hosted responses passed |
| FR-01 managed invocation endpoint | Foundry managed Responses endpoint | Console client and azd invocation passed |
| FR-02 user details | `JsonPlaceholderTools.GetUserDetailsAsync` | Unit and hosted multi-tool pass |
| FR-02 tasks | `JsonPlaceholderTools.GetUserTasksAsync` | Incomplete filtering unit/hosted pass |
| FR-02 posts | `JsonPlaceholderTools.GetUserPostsAsync` | Unit and hosted invocation pass |
| FR-02 errors/timeouts | Structured `rest_*` error contracts | Deterministic tests passed |
| FR-02 multiple calls | Agent Framework local function tools | Hosted request selected details + tasks |
| FR-03 Learn MCP | `MicrosoftLearnMcpTool` | Live local and hosted MCP calls passed |
| FR-03 discovery | `ListToolsAsync`, exact-name check | Verified by successful invocation |
| FR-03 controlled failure | `mcp_timeout`, `mcp_unavailable`, `mcp_tool_missing` | Deterministic tests passed |
| FR-04 intelligent selection | Tool descriptions + agent instructions | REST, MCP, REST+REST, REST+MCP passed |
| FR-05 external client | `hosted-agent/src/ConsoleAppClient` | Entra-authenticated hosted invocation passed |
| ACR deployment | Dockerfile + ACR remote build | Image `20261110.10`, digest documented |
| Authentication | `DefaultAzureCredential`; Foundry endpoint RBAC | Hosted and client calls passed |
| Observability | AgentHost telemetry, custom ActivitySource spans, App Insights connection | End-to-end `App*` KQL evidence for requests, models, tools, latency, and errors |
| Read-only/synthetic | Three fixed GET routes; IDs 1–10; Learn search only | Code and tests |
| Documentation | README and `docs/*` | Complete |

## Acceptance summary

The functional POC is deployed and usable. All requested REST and MCP capabilities, intelligent
multi-tool selection, managed invocation, the external C# client, and end-to-end Application
Insights observability have been demonstrated. See `docs/observability-demo.md` for verified trace
IDs and workspace-native KQL.
