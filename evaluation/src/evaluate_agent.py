"""Run a Foundry batch evaluation against a Hosted Agent version.

Uses LLM-judge evaluators (Intent Resolution, Task Adherence, optionally Relevance) on a labeled dataset tier.
The deterministic hard gates (tool selection, required and forbidden text) are in
scripts/Invoke-DeterministicEval.ps1. Run both: deterministic checks block release, judge scores drive improvement.

Setup:   pip install -r evaluation/requirements.txt ; az login
Env:     FOUNDRY_PROJECT_ENDPOINT   https://<account>.services.ai.azure.com/api/projects/<project>
         FOUNDRY_MODEL_NAME         chat-completion deployment used as the judge model
Example: python evaluation/src/evaluate_agent.py --agent-name foundry-hosted-integration-poc --agent-version 10 --tier smoke
         python evaluation/src/evaluate_agent.py --tier smoke --dry-run      (no Azure calls)

Each run uploads a new dataset version. A submitted dataset is never overwritten.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

TIERS = ("smoke", "regression", "challenge", "holdout")
DATASET_ROOT = Path(__file__).resolve().parents[1] / "datasets"


def load_rows(dataset_version: str, tier: str) -> list[dict]:
    path = DATASET_ROOT / dataset_version / f"{tier}.jsonl"
    if not path.exists():
        sys.exit(f"Dataset file not found: {path}")
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    for row in rows:
        if not row.get("query"):
            sys.exit(f"Row {row.get('id')} has no query.")
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--agent-name", default="foundry-hosted-integration-poc")
    parser.add_argument("--agent-version", help="Pin an agent version. Omit to evaluate the latest version.")
    parser.add_argument("--tier", choices=TIERS, default="smoke")
    parser.add_argument("--dataset-version", default="v1")
    parser.add_argument("--include-relevance", action="store_true", help="Also score Relevance (response text mapping is untested).")
    parser.add_argument("--output-dir", default="evaluation-results")
    parser.add_argument("--poll-seconds", type=int, default=10)
    parser.add_argument("--timeout-minutes", type=int, default=30)
    parser.add_argument("--dry-run", action="store_true", help="Validate the dataset and print the plan without calling Azure.")
    parser.add_argument("--inline", action="store_true", help="Send rows inline instead of uploading a dataset file. Use if the project has no storage for uploads (untested).")
    args = parser.parse_args()

    rows = load_rows(args.dataset_version, args.tier)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
    dataset_name = f"hosted-agent-eval-{args.tier}"
    dataset_version = f"{args.dataset_version}-{stamp}"
    evaluators = ["intent_resolution", "task_adherence"] + (["relevance"] if args.include_relevance else [])
    print(f"Tier {args.tier}: {len(rows)} rows | agent {args.agent_name} version {args.agent_version or 'latest'} | evaluators {evaluators}")
    if args.dry_run:
        print(f"Dry run. Would upload dataset {dataset_name} version {dataset_version}. No Azure calls made.")
        return 0

    endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    judge_model = os.environ.get("FOUNDRY_MODEL_NAME")
    if not endpoint or not judge_model:
        sys.exit("Set FOUNDRY_PROJECT_ENDPOINT and FOUNDRY_MODEL_NAME.")

    from azure.identity import DefaultAzureCredential
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import TestingCriterionAzureAIEvaluator
    from openai.types.eval_create_params import DataSourceConfigCustom

    project_client = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())
    client = project_client.get_openai_client()

    agent = project_client.agents.get(args.agent_name)
    print(f"Found agent: {agent.name}")

    slim_rows = [{"id": r["id"], "query": r["query"], "ground_truth": r.get("ground_truth", "")} for r in rows]
    if args.inline:
        source = {"type": "file_content", "content": [{"item": row} for row in slim_rows]}
        print("Sending rows inline (no dataset upload).")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            upload = Path(tmp) / f"{args.tier}.jsonl"
            upload.write_text("\n".join(json.dumps(row) for row in slim_rows), encoding="utf-8")
            dataset = project_client.datasets.upload_file(name=dataset_name, version=dataset_version, file_path=str(upload))
        source = {"type": "file_id", "id": dataset.id}
        print(f"Uploaded dataset {dataset_name} {dataset_version}")

    mapping_items = {"query": "{{item.query}}", "response": "{{sample.output_items}}"}
    criteria = [
        TestingCriterionAzureAIEvaluator(
            type="azure_ai_evaluator",
            name=name.replace("_", " ").title(),
            evaluator_name=f"builtin.{name}",
            initialization_parameters={"model": judge_model},
            data_mapping=mapping_items if name != "relevance" else {"query": "{{item.query}}", "response": "{{sample.output_text}}"},
        )
        for name in evaluators
    ]

    evaluation = client.evals.create(
        name=f"Hosted agent {args.tier} v{args.agent_version or 'latest'} {stamp}",
        data_source_config=DataSourceConfigCustom(
            type="custom",
            item_schema={
                "type": "object",
                "properties": {"id": {"type": "string"}, "query": {"type": "string"}, "ground_truth": {"type": "string"}},
                "required": ["query"],
            },
            include_sample_schema=True,
        ),
        testing_criteria=criteria,
    )
    print(f"Evaluation created: {evaluation.id}")

    target = {"type": "azure_ai_agent", "name": args.agent_name}
    if args.agent_version:
        target["version"] = args.agent_version
    run = client.evals.runs.create(
        eval_id=evaluation.id,
        name=f"{args.tier} run {stamp}",
        data_source={
            "type": "azure_ai_target_completions",
            "source": source,
            "input_messages": {
                "type": "template",
                "template": [{"type": "message", "role": "user", "content": {"type": "input_text", "text": "{{item.query}}"}}],
            },
            "target": target,
        },
    )
    print(f"Run started: {run.id}")

    deadline = time.time() + args.timeout_minutes * 60
    while True:
        run = client.evals.runs.retrieve(run_id=run.id, eval_id=evaluation.id)
        print(f"  status: {run.status}")
        if run.status in ("completed", "failed", "canceled"):
            break
        if time.time() > deadline:
            sys.exit("Timed out waiting for the run. Check the report in the Foundry portal.")
        time.sleep(args.poll_seconds)

    print(f"\nStatus: {run.status}\nReport URL: {run.report_url}\nResult counts: {run.result_counts}")
    for item_result in run.per_testing_criteria_results or []:
        print(f"  {item_result.testing_criteria}: passed {item_result.passed}, failed {item_result.failed}")

    items = []
    expected = {r["id"]: r for r in rows}
    for item in client.evals.runs.output_items.list(run_id=run.id, eval_id=evaluation.id):
        entry = {"id": item.id, "status": getattr(item, "status", None), "results": []}
        for result in item.results or []:
            entry["results"].append({"name": result.name, "passed": result.passed, "score": result.score,
                                     "reason": getattr(result, "reason", None)})
        items.append(entry)
        print(f"  {item.id}: " + ", ".join(f"{r['name']}={'pass' if r['passed'] else 'FAIL'}({r['score']})" for r in entry["results"]))

    out_dir = Path(args.output_dir) / f"{stamp}-{args.tier}"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "foundry-results.json").write_text(
        json.dumps({"evaluation_id": evaluation.id, "run_id": run.id, "report_url": run.report_url, "agent": args.agent_name,
                    "agent_version": args.agent_version or "latest", "tier": args.tier, "dataset": ("inline" if args.inline else f"{dataset_name}:{dataset_version}"),
                    "result_counts": str(run.result_counts), "items": items}, indent=2),
        encoding="utf-8",
    )
    print(f"Saved: {out_dir / 'foundry-results.json'}")
    print("Review every item, not just the pass rate. Averages hide the important failures.")
    return 0 if run.status == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
