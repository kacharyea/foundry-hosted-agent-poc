# Hosted Agent evaluation (Session 3)

Evaluates the Hosted Agent against labeled datasets. Criteria, dataset tiers, evaluator selection, and a failure-cluster template follow the Session 3 workflow: **Define, Build, Select, Run and improve**.

All data is synthetic. Nothing here runs unless you start it.

## Layout

| Path | Purpose |
|---|---|
| `datasets/v1/*.jsonl` | Four tiers: smoke (5), regression (8), challenge (7), holdout (5) |
| `scripts/Invoke-DeterministicEval.ps1` | Hard gates: tool selection, required text, forbidden text. No LLM judge. |
| `src/evaluate_agent.py` | Foundry batch evaluation with LLM-judge evaluators, pinned to an agent version |
| `requirements.txt` | `azure-ai-projects>=2.8.0`, `azure-identity` |

Result files are written to `evaluation-results/` (gitignored).

## 1. Criteria and gates

| Criterion | Signal | Pass threshold | Gate |
|---|---|---|---|
| Tool selection accuracy | The tools called equal `expected_tools` (plus `allowed_tools`) | 100% on labeled cases | **Hard, blocks release** |
| Required content | Every `must_contain` string is in the answer (for example a controlled error code) | All present | Hard |
| Forbidden claims | No `must_not_contain` string (for example "has been deleted") | None present | Hard |
| Intent resolution | The agent addresses the user's goal | 4 of 5 or better (judge) | Soft, drives improvement |
| Task adherence | The agent follows its instructions and constraints | Judge pass | Soft |

Thresholds are workshop examples. Calibrate them to your use case and risk.

## 2. Dataset tiers

| Tier | Rows | Use |
|---|---|---|
| `smoke` | 5 | Run first, always. Confirms access, quota, and the dataset schema. |
| `regression` | 8 | Session 2 incident cohorts (v11 `rest_unavailable`, `rate_limit_exceeded`, expected `invalid_user_id` errors). Grows with every incident. |
| `challenge` | 7 | Write requests, prompt extraction, data exfiltration, ambiguous and off-topic input. Use while hardening. |
| `holdout` | 5 | Pre-release gate only. **Never run it during development.** |

Fields: `id`, `query`, `ground_truth`, `expected_tools`, `allowed_tools`, `must_contain`, `must_not_contain`, `tier`, `source`, `failure_category`.
Versioning rule: never overwrite a submitted dataset. Add `v2/` for changes. Each Foundry upload gets its own dataset version.

## 3. Evaluator selection (record this with every run)

| Criterion type | Method | Why |
|---|---|---|
| Tool selection, required and forbidden text | Deterministic script | Machine-checkable; no model variance; auditable |
| Intent resolution, task adherence | Built-in LLM judge (Foundry) | Semantic quality; scales; report URL |
| Safety boundary (writes, prompt extraction) | Deterministic checks plus human sign-off | Zero tolerance; judge scores alone are not enough |
| Ambiguous ground truth | Human review | Avoid forcing pass or fail on an unclear case |

## 4. Run order

```powershell
az login
# Deterministic gates (targets the version currently routed)
.\evaluation\scripts\Invoke-DeterministicEval.ps1 -ProjectEndpoint <endpoint> -AgentName foundry-hosted-integration-poc `
  -DatasetPath .\evaluation\datasets\v1\smoke.jsonl

# Judge evaluators (pins an agent version; needs a judge model deployment)
pip install -r evaluation/requirements.txt
$env:FOUNDRY_PROJECT_ENDPOINT = '<endpoint>'; $env:FOUNDRY_MODEL_NAME = '<chat-deployment>'
python evaluation/src/evaluate_agent.py --agent-version 10 --tier smoke
```

1. Smoke first. Confirm completed status and the Foundry report URL.
2. Item-level review: for each row record the query, the score, the reason, and whether you agree. An average hides failures.
3. Then regression and challenge. Run holdout only for a release decision.
4. Cluster failures: agent failure, ambiguous ground truth, evaluator disagreement, environment or configuration issue.
5. Record any critical-error violation as release blocking before closing the run.

## 5. Failure clusters and improvements (template)

| Cluster | Rows | Category | Action | Owner | Verification | Due |
|---|---|---|---|---|---|---|
| | | | | | | |

## Capacity and rate limits

A batch evaluation calls the model for the agent and again for each judge, so it uses far more tokens than a chat. The agent and the judge share a deployment unless you set a different judge model. If you see `rate_limit_exceeded`, raise the deployment capacity, run fewer rows, or use a separate judge deployment. The deterministic script retries with backoff and reports rows it could not score as `UNSCORED`, never as passes.

## Notes and limits

- The deterministic script follows the **routed** version. To compare versions, route traffic to each version in turn, or use the Foundry script, which can pin a version.
- Target-based evaluation works with agents on the responses or invocations protocol in synchronous, non-streaming mode.
- `evaluate_agent.py` ran against a live project: the dataset upload, evaluation, and run worked. It has not yet produced judge scores (see the next two points).
- **Reasoning items break the agent evaluators.** If the judges are given the full output (`--response-from items`), a reasoning model such as `gpt-5-mini` returns `reasoning` items and every row errors with "Invalid content type 'TextReasoningContent'". The default is now `--response-from text` (final answer only). The judges then do not see tool calls, which the deterministic script checks instead.
- **The person running the evaluation needs permission to call the judge model.** The judge runs as the signed-in user. Without the data action `Microsoft.CognitiveServices/accounts/OpenAI/deployments/chat/completions/action` on the Foundry account, every row errors with `401 PermissionDenied`. Control-plane roles such as Owner or Contributor do not grant it. A role such as Cognitive Services OpenAI User at the account scope does. Role changes can take several minutes to apply.
- Rows the judge could not score are reported as `ERROR`, never as pass or fail.
- Uploading a dataset file needs storage on the Foundry project. If the upload fails, add `--inline` to send the rows directly (this path is untested).
- Rubric evaluators, risk and safety evaluators, and some other features have regional limits. Check the Microsoft Learn evaluation pages for your region.
