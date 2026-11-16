# hosted-agent-dependency-failures runbook

**Class:** Create work  **Severity:** 3  **Owner / backup:** from the alert payload

## 1. Trigger and impact
Repeated failures calling an external HTTP dependency (for example the REST data source or the Microsoft Learn MCP server). Foundry platform probes (`*.services.ai.azure.com`, agent365, login) and benign Learn MCP HTTP 405 rows are excluded.

## 2. Confirm
1. Workbook panel 9: which `Target` has a high failure %?
2. Check the dependency's public status. A single target with all failures is a dependency problem; a wrong hostname suggests a configuration problem.

## 3. Diagnose
1. In Logs, filter `AppDependencies` by the target and read `ResultCode` and `Data`.
2. Correlate with panel 4: did failures begin at a version's first-seen time? If so compare the version's endpoint environment variables.
3. Check tool-errors; failures usually appear in both.

## 4. Remediate
Configuration fault from a new version: use the rollback script with approval (see failed-invocations). Third-party outage: no rollback; record, communicate, and wait or add resilience. Open a work item either way.

## 5. Verify
Panel 9 failure % for the target returns to normal on new traffic.

## 6. Escalate and close
Escalate to the dependency owner or vendor for outages. Attach the evidence pack to the work item. Learning loop: does this dependency need a timeout, retry, or fallback?
