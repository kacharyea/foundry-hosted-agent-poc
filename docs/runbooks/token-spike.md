# hosted-agent-token-spike runbook

**Class:** Create work  **Severity:** 3  **Owner / backup:** from the alert payload

## 1. Trigger and impact
Model token usage in the window exceeded the cost threshold. Not a customer outage; a cost and capacity signal that could also indicate looping tool calls or unusually long prompts.

## 2. Confirm
1. Workbook panel 8: tokens by version and model. Compare with normal volume in panel 2; more traffic explains more tokens.
2. Tokens up while requests are flat means more tokens per request: investigate.

## 3. Diagnose
1. Find the highest-token `chat` spans: `AppDependencies | where Name startswith "chat " | extend t = tolong(Properties["gen_ai.usage.input_tokens"]) + tolong(Properties["gen_ai.usage.output_tokens"]) | top 10 by t desc`.
2. Read that trace for repeated tool calls (retry loop) or large tool responses.
3. Check whether a new version changed instructions or the model.

## 4. Remediate
Open a work item. If a loop is burning budget, escalate for approval to roll back with the rollback script. Otherwise adjust instructions, limits, or the threshold.

## 5. Verify
Tokens per request in panel 8 return to the expected range on new traffic.

## 6. Escalate and close
Notify the service owner and cost owner. Learning loop: is the threshold tied to a real budget, and should it scale with traffic?
