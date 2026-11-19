# prompt-agent-tool-failures runbook

**Class:** Create work  **Severity:** 3  **Owner / backup:** from the alert payload

## 1. Trigger and impact
Repeated failed `execute_tool` spans for the prompt agent, for example the Microsoft Learn MCP tool. The agent may answer without documentation or report that the tool failed.

## 2. Confirm
1. Workbook "Prompt Agent - operations", panel 5: failures and p95 per tool.
2. If only one tool fails, scope to it. If all fail at once, suspect the platform or the network.

## 3. Diagnose
1. Panel 7: copy an `OperationId` and read the `execute_tool` span and its parent `invoke_agent` in Logs.
2. Check whether the tool's server is reachable and whether failures started with a new version (panel 3).
3. Check the tool's public status for third-party servers.

## 4. Remediate
Open a work item with the evidence. If users are affected and a recent version caused it, escalate to Page severity and follow the failed-invocations runbook (approval required). Otherwise fix forward.

## 5. Verify
Panel 5 shows the tool's failure % back to normal on new requests.

## 6. Escalate and close
Assign the work item with a due date. Learning loop: does the agent need an instruction for tool failures, or a fallback?
