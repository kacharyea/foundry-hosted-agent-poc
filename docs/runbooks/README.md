# Hosted Agent runbooks

Each alert carries a `runbook` link in its context payload. Every runbook follows the same six sections so a
responder always knows where to look: **1 Trigger and impact, 2 Confirm, 3 Diagnose, 4 Remediate, 5 Verify, 6 Escalate and close.**

> Ownership, escalation paths, and thresholds below are **draft examples**. Replace them with your organization's
> on-call, severity, and approval policy before relying on them.

| Alert | Class | Severity | Runbook |
|---|---|---|---|
| `hosted-agent-failed-invocations` | Page | 1 | [failed-invocations](failed-invocations.md) |
| `hosted-agent-sustained-latency` | Page | 2 | [sustained-latency](sustained-latency.md) |
| `hosted-agent-tool-errors` | Create work | 3 | [tool-errors](tool-errors.md) |
| `hosted-agent-dependency-failures` | Create work | 3 | [dependency-failures](dependency-failures.md) |
| `hosted-agent-token-spike` | Create work | 3 | [token-spike](token-spike.md) |
| `hosted-agent-no-traffic` (opt-in) | Create work | 3 | [no-traffic](no-traffic.md) |

Page only for customer-impacting symptoms. Trends and cost become work items, not pages.

## Tools used by the runbooks

| Need | Tool |
|---|---|
| Health, version, hotspots | Workbook "Hosted Agent - operations" |
| Collect evidence | `hosted-agent/scripts/Collect-EvidencePack.ps1` |
| Roll back a version | `hosted-agent/scripts/Rollback-HostedAgent.ps1` (supports `-WhatIf`; requires confirmation) |
| Reproduce a fault for a drill | `hosted-agent/scripts/Start-DemoFault.ps1` (non-production only) |

Rollback is a human decision. Always run with `-WhatIf` first, record the approver, then run it for real.

## Draft ownership and escalation (replace)

| Role | Responsibility |
|---|---|
| Primary on-call (owner on the alert) | Acknowledge, confirm, diagnose, remediate |
| Backup owner (on the alert) | Takes over after 15 minutes without acknowledgement |
| Service owner | Approves rollback and risk-bearing changes; owns follow-up |
| Platform/Foundry contact | Engaged when the cause is the platform (for example repeated `session_not_ready` across versions) |

## Learning loop

After every Page and every repeated Create-work alert, answer: was the alert actionable, was it early enough,
did the runbook work, which threshold or exclusion should change? Record the result as a follow-up work item.

Maintenance: planned work can suppress notifications with the `maintenanceWindowStart` and `maintenanceWindowEnd`
parameters of `infrastructure/monitoring.bicep`; alert records are still kept.
