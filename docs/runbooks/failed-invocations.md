# hosted-agent-failed-invocations runbook

**Class:** Page  **Severity:** 1  **Owner / backup:** from the alert payload

## 1. Trigger and impact
The Foundry platform recorded a failed `invoke_agent` (for example `session_not_ready` or HTTP 500) for a version. Users receive no answer. The alert is split by `AgentVersion`, so the version that broke is named in the alert.

## 2. Confirm
1. Open the workbook, panel 1 (failure %) and panel 4 (failures per version).
2. Decide: failures on the **currently routed** version with more than one occurrence means declare. One failure on an old version no longer receiving traffic means close.
3. A version showing status `active` in Foundry is **not** proof of health; a broken version can still be `active`.

## 3. Diagnose
1. Workbook panel 10: copy an `OperationId` from a failed row.
2. In Logs: `AppRequests | where OperationId == "<id>"` then the same id in `AppDependencies` and `AppExceptions`.
3. Check panel 4 for a version that started failing right after its first-seen time (change correlation).
4. If the failure is `session_not_ready`, the container is not starting: check recent image, model deployment name, and environment variables on that version.

## 4. Remediate
1. Preview: `Rollback-HostedAgent.ps1 -ProjectEndpoint <endpoint> -AgentName <agent> -ResourceGroup <rg> -WorkspaceName <workspace> -Reason "<ticket>" -WhatIf`
2. Get service-owner approval, then run the same command without `-WhatIf`. The script chooses the newest earlier version with healthy telemetry, not merely "previous active".
3. Stop condition: if the target also fails, stop and escalate to the platform contact.

## 5. Verify
Workbook panel 1 shows failure % returning to 0 and the smoke test (run by the script) passes with both tools called. Alert auto-resolves after a clean window.

## 6. Escalate and close
Escalate to the service owner immediately for a Sev 1 and to the platform contact if more than one version fails. Run `Collect-EvidencePack.ps1`, complete `summary.md` (timeline, hypothesis, action, approver, verification), and open a follow-up for the faulty version's root cause. Learning loop: could this have been caught in the release smoke test?
