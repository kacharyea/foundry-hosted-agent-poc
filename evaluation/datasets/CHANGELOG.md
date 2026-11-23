# Dataset change log

Never overwrite a submitted dataset. Add a new version folder and record why.

## v2 (current)

Adds `rest_unavailable` to `must_not_contain` on every row that expects real REST data (12 rows): smoke-001, smoke-002, reg-004, reg-005, reg-007, reg-008, ch-001, ch-006, ch-007, ho-001, ho-002, ho-005.

**Why:** an evaluation of the faulty Hosted Agent version (v11, REST base URL points to an address that does not exist) passed 3 rows that should have failed. smoke-002, reg-004, and reg-007 had no content assertion, so an answer that said "the tool call failed, rest_unavailable" still passed because the right tool was called. Tool selection alone does not prove the agent worked.

**Evidence (deterministic checks on the same 13 smoke and regression answers from v11):**

| Dataset | Pass rate on v11 | Pass rate on v10 (20 rows) |
|---|---|---|
| v1 | 69.2% | 100% |
| v2 | 46.2% | 100% |

v2 fails all 7 rows that need the broken REST tools on v11, keeps the 6 that should pass (Learn search, expected `invalid_user_id` errors, a greeting), and does not fail any row on the healthy v10.

## v1

First version: smoke (5), regression (8), challenge (7), holdout (5), built from the Session 1 demo and Session 2 incident cohorts.
