# prompt-agent-failed-invocations runbook

**Class:** Page  **Severity:** 1  **Owner / backup:** from the alert payload

## 1. Trigger and impact
The Foundry platform recorded a failed `invoke_agent` for the prompt agent (ResultCode 500 with an `error.type`). Users get an error instead of an answer. A prompt agent has no container, so failures come from the model, a tool, or the platform, not from a container start.

## 2. Confirm
1. Open the workbook "Prompt Agent - operations": panel 1 (failure %) and panel 4 (failures by error type).
2. Declare if failures are repeated on the currently routed version. One failure on an old version is noise.
3. Read `error.type` first. It usually names the cause.

## 3. Diagnose
1. Panel 4: group by `error.type`. For example `rate_limit_exceeded` means the model deployment ran out of tokens per minute.
2. Panel 7: copy an `OperationId`, then in Logs: `AppDependencies | where OperationId == "<id>"` to see the `invoke_agent`, `chat` and `execute_tool` spans in order.
3. Panel 5: did a tool fail first? A tool that returns a very large result can also exhaust model tokens.
4. Panel 3: did failures begin when a new version first appeared?
5. If the cause is `rate_limit_exceeded`, check who else uses the same model deployment (other agents and apps share its quota).

## 4. Remediate
- **Rate limit:** reduce load or wait, then ask the model owner to raise the deployment capacity. Changing capacity needs approval.
- **Bad version:** a prompt agent version holds the model, instructions and tools. Route traffic back to the last known-good version (approval required). Check the version's settings against the previous one first.
- **Tool failure:** see the prompt-agent-tool-failures runbook.
- Stop condition: if the previous version also fails, stop and escalate to the platform contact.

## 5. Verify
Panel 1 shows failure % back to 0 on new requests, and a test question returns an answer.

## 6. Escalate and close
Escalate to the service owner immediately for a Sev 1, and to the model deployment owner for quota problems. Record the timeline, the cause, the action and approver, and the follow-up owner. Learning loop: should this agent have its own deployment or a quota alert?
