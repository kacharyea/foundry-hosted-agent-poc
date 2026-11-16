# hosted-agent-sustained-latency runbook

**Class:** Page  **Severity:** 2  **Owner / backup:** from the alert payload

## 1. Trigger and impact
p95 `POST /responses` latency is above the threshold with enough samples in the window. Users wait too long or time out. Average latency is deliberately not used; the alert needs both a percentile and a minimum volume.

## 2. Confirm
1. Workbook panel 3 (p95 by version) and panel 2 (request volume).
2. Compare with panel 7: cold starts are slower by design. A spike confined to `cold` start type after idle time is expected, not an incident.
3. Declare if warm requests are slow or the elevated p95 persists across several windows.

## 3. Diagnose
1. Panel 7: is time in infrastructure setup, readiness, or container response?
2. Panel 5 and 6: which tool or model call has a high p95 or failures?
3. Panel 9: is an external dependency (for example Microsoft Learn MCP) slow?
4. Panel 4: did latency step up when a new version appeared?
5. Panel 10: take a slow `OperationId` and read its timeline to find the longest span.

## 4. Remediate
- Slow external dependency: no rollback; note it, consider timeouts or retries, escalate to the dependency owner.
- Regression tied to a version: preview and, with approval, run `Rollback-HostedAgent.ps1` (see failed-invocations runbook).
- Model slowness: check model deployment capacity and quota; coordinate before changing deployments.

## 5. Verify
p95 in panel 3 back under threshold for two consecutive windows on warm traffic; alert resolved.

## 6. Escalate and close
Escalate to the service owner if unresolved after 30 minutes. Collect the evidence pack. Learning loop: was the threshold right for warm versus cold traffic?
