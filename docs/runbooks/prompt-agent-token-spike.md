# prompt-agent-token-spike runbook

**Class:** Create work  **Severity:** 3  **Owner / backup:** from the alert payload

## 1. Trigger and impact
Model token usage for the prompt agent exceeded the cost threshold in the window. Not an outage by itself, but heavy token use can lead to `rate_limit_exceeded` failures on a shared model deployment.

## 2. Confirm
1. Workbook "Prompt Agent - operations", panel 6: tokens by version and model.
2. Compare with request volume (panel 2). More traffic explains more tokens; flat traffic with more tokens means more tokens per request.

## 3. Diagnose
1. Find the largest `chat` spans: `AppDependencies | where Name startswith "chat " | extend t = tolong(Properties["gen_ai.usage.input_tokens"]) + tolong(Properties["gen_ai.usage.output_tokens"]) | top 10 by t desc`.
2. Read that trace. Large tool results (for example documentation search output) inflate input tokens.
3. Check whether a new version changed instructions, tools or the model (panel 3).

## 4. Remediate
Open a work item. Options: tighten instructions or tool result size, set limits, or raise the deployment's capacity (approval required).

## 5. Verify
Tokens per request in panel 6 return to the expected range on new traffic.

## 6. Escalate and close
Notify the service owner and the model deployment owner. Learning loop: is the threshold tied to a real budget or quota?
