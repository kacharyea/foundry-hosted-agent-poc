# hosted-agent-no-traffic runbook

**Class:** Create work  **Severity:** 3  **Owner / backup:** from the alert payload

This alert is opt-in (`enableNoTrafficAlert`). Enable it only for agents with steady traffic; an idle demo agent would alert constantly.

## 1. Trigger and impact
No `invoke_agent` requests were recorded in the window. Either users have stopped reaching the agent, or telemetry has stopped.

## 2. Confirm
1. Is this a normal quiet period (night, weekend, planned maintenance)? If so, close, and consider a maintenance window.
2. Run the smoke test: `hosted-agent/pipelines/scripts/SmokeTest-HostedAgent.ps1`. If it succeeds and appears in telemetry within a few minutes, the agent and telemetry work.

## 3. Diagnose
1. Check the endpoint routing (`Rollback-HostedAgent.ps1 -WhatIf` prints the routed version) and caller changes such as a broken client, expired credentials, or network changes.
2. If the smoke test succeeds but nothing appears, check Application Insights ingestion and the workspace connection.

## 4. Remediate
Fix the caller or telemetry path. No rollback unless the routed version is broken.

## 5. Verify
Requests appear in workbook panel 2.

## 6. Escalate and close
Engage the calling team or platform contact. Learning loop: should the alert use a traffic-aware baseline instead of a fixed zero?
