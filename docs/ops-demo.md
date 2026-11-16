# Operations demo: dashboard, alert, runbook, rollback

Audience: on-call and service owners. Total time about 30 minutes. Do the **preparation** at least 30 minutes
ahead because telemetry ingestion and alert evaluation take 5 to 10 minutes.

## Preparation (non-production environment only)

1. Deploy monitoring (see the root README). For a live demo, set `alertEvaluationFrequency = 'PT1M'` and
   `alertWindowSize = 'PT5M'` in your local parameter file.
2. Open the **Hosted Agent - operations** workbook and confirm tiles show healthy traffic. Send a few normal
   requests with `SmokeTest-HostedAgent.ps1` if empty.
3. Note the currently routed version (the rollback script prints it with `-WhatIf`).
4. Confirm the action group sends mail (portal: action group, Test action group).
5. Rehearse `ModelDeployment` once before using it live; `ToolEndpoint` is the dependable fault.

## Flow

| Step | Action | What to say |
|---|---|---|
| 1. Healthy baseline | Workbook panels 1 to 4 | Decision rail: declare, scope, pivot, act. Version markers show what changed. |
| 2. Inject fault | `Start-DemoFault.ps1 -Fault ToolEndpoint ...` (confirm the prompt) | A bad release goes out. Nothing in the app changed; only an endpoint setting. |
| 3. Detect | Workbook panels 4, 5, 6 and 9 | New version appears, tool and dependency failures rise. Expected `invalid_*` errors are excluded. |
| 4. Alert | Alert email or Alerts blade | Response contract: owner, runbook link, severity class, split by version. Create-work alerts do not page. |
| 5. Triage | Open the runbook from the alert | Same six sections for every alert. Confirm, diagnose with an `OperationId`. |
| 6. Evidence | `Collect-EvidencePack.ps1` | Evidence before action. |
| 7. Remediate | `Rollback-HostedAgent.ps1 ... -WhatIf`, then run with approval | Picks the last known-good version from telemetry, not "previous active". Human approval stays. |
| 8. Verify | Workbook panels 1 and 6; smoke test | Verify recovery, not just alert clearing. |
| 9. Learn | Runbook section 6 | Record what to change in thresholds or exclusions. |

## Optional: Azure Copilot Observability Agent

With a fired alert and access to the preview in your region, open the alert and ask Copilot to investigate.
Check availability and permissions beforehand.

## Reset

Run `Rollback-HostedAgent.ps1 -TargetVersion <original>` if the demo version is still routed. Alerts auto-resolve
after clean windows. Delete the evidence folder when done.
