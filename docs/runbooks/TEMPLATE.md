# <Alert name> runbook

**Class:** Page | Create work | Visualize  **Severity:** n  **Owner / backup:** from the alert payload

## 1. Trigger and impact
What fired, which customer or business outcome is affected, and what it is *not* (expected conditions excluded).

## 2. Confirm
Fast checks that separate a real incident from noise. State the decision: declare, or close as false positive.

## 3. Diagnose
Ordered pivots: service, version, time range, then OperationId or conversation ID. Include the exact queries or workbook panels.

## 4. Remediate
Safe actions in order of least risk. Mark which need approval. Include rollback and a stop condition.

## 5. Verify
Evidence that health and the agent outcome have recovered, not just that the alert cleared.

## 6. Escalate and close
Who to engage and when. Evidence pack contents, decision and approver, follow-up owner and due date, learning-loop question.
