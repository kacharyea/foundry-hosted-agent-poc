# Security notes

## Implemented controls

| Risk | Control |
|---|---|
| Arbitrary REST access | Fixed base URL and three hard-coded GET routes |
| Input manipulation | Integer user IDs restricted to `1..10`; MCP query restricted to `1..500` chars |
| Secret exposure | No API keys; Entra authentication; no secrets in source or manifests |
| Tool-output injection | System instructions treat all tool results as untrusted data |
| Excessive MCP context | Maximum five results and 1,200-character excerpt per result |
| Dependency hangs | REST 10-second and MCP 20-second timeouts |
| Raw upstream leakage | Controlled error codes/messages; upstream response body not returned on error |
| Unapproved MCP capability | Exact endpoint and exact `microsoft_docs_search` discovery check |
| Side effects | GET-only REST tools and read-only documentation search |
| Cross-request identity | Foundry endpoint authentication; platform-created agent identity |

## Required deployment review

- Verify outbound HTTPS policy permits only the required endpoints where egress controls are used.
- Verify the hosted agent identity has only default project/model access; grant no unrelated Azure roles.
- Grant external callers **Foundry Agent Consumer**, not project-management roles.
- Review Application Insights payload collection, retention, workspace access, and protected tables.
- Confirm ACR public/private access matches the existing Foundry project's supported registry mode.
- Confirm JSONPlaceholder is approved for the demo. It is not a Microsoft service.
- Use only the synthetic records already published by JSONPlaceholder.

## Not implemented

- Organization-specific production identity federation.
- Private networking or an outbound allowlist.
- Durable business audit storage beyond platform telemetry.
- Tool-level user delegation to downstream APIs.
- Content Safety guardrails beyond the selected model deployment defaults.
- Production SLA, distributed retry policy, circuit breaker, or disaster recovery.

These are explicit production gaps, not capabilities demonstrated by the POC.
