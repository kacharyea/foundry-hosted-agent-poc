# hosted-agent-tool-errors runbook

**Class:** Create work  **Severity:** 3  **Owner / backup:** from the alert payload

## 1. Trigger and impact
Repeated unexpected tool failures (`tool.*` spans with `Success == false`). The agent may answer without data or with an apology. Expected controlled errors `invalid_user_id` and `invalid_query` are excluded because they are correct handling of bad input.

## 2. Confirm
1. Workbook panel 6: look at the **Unexpected** column per tool; panel 5 classification should read `Investigate`.
2. If only one tool fails, scope to that tool. If all tools fail at once, suspect configuration or the shared backend (see dependency-failures).

## 3. Diagnose
1. Group by `error.type` and tool in panel 5/6, and by version in panel 4 for a change correlation.
2. Take an `OperationId` and read the tool span and its exception in Logs.
3. Check the version's environment variables (for example the tool endpoint) against the previous healthy version.

## 4. Remediate
Create a work item with the evidence. If a recent version caused it and users are impacted, escalate to Page severity and follow the failed-invocations rollback steps (approval required). Otherwise fix forward in the next release.

## 5. Verify
Unexpected failures in panel 6 return to zero on new traffic; smoke test passes.

## 6. Escalate and close
Assign the work item to the service owner with a due date and attach the evidence pack. Learning loop: should this error type become an expected exclusion, or did it need a code fix?
