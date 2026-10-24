# Local test runs: resource profile and policy

How local and agent (Alloy, Claude, Cursor) test runs are balanced on the dev
machine: fast enough to iterate, without overlapping runs exhausting RAM or
breaking each other. CI is unaffected (ephemeral runners, its own selection).

## Rules

1. **Run tests through `scripts/run_tests.sh <profile>`** (or, for anything it
   does not cover, `scripts/run_with_test_cleanup.sh`). Never a bare
   `dart test` / `flutter test`, and never a whole package without a tag
   filter: an untagged `dart test` in `packages/server` mixes `mr`, `perf` and
   ordinary suites at `-j 8`, which is how timing-sensitive tests fail.
2. **One wrapped run at a time, machine-wide.** `run_with_test_cleanup.sh`
   queues on a `flock` (`~/.cache/tentura-tests.lock`, holder in
   `tentura-tests.lock.holder`). A second run waits and logs
   `queued behind another test run (...)`; nested wrapped runs inherit the
   lock. `--no-lock` / `TENTURA_TEST_LOCK=off` only for a run you know is alone
   (the wrapper selftests use it on purpose).
3. **Tiered verification** (Alloy and by hand):

   | When | Server | Client |
   |---|---|---|
   | every iteration | `server-files <the bead's tests>`, `server-affected` | `client-files <paths>`, `client-affected` |
   | once before landing | `server-regression` | `client-gates` + `client-all` |
   | never in a routine run | `perf`, `load` suites (manual, idle machine) | `bench` with `TENTURA_ENFORCE_BENCH_BUDGET=1` |

   `server-regression` = `server-gates` + `server-unit` + `server-pg`, plus
   `server-mr` only when the change touches Field / visibility / trust /
   MeritRank code or a migration.
4. **Kernels live on disk.** With `TMPDIR` unset the wrapper uses
   `~/.cache/tentura-test-tmp`; `/tmp` is a RAM tmpfs with a user quota and a
   full pg run compiles ~14 GB of kernels.

## Profiles

| Profile | What | -j |
|---|---|---|
| `server-files <files>` | named server suites; `mr` files split into their own `-j 1` run | ≤ 4 |
| `server-affected` | server tests changed vs `HEAD` + tests importing a changed `lib/` file (direct imports only) | ≤ 4 |
| `server-unit` | `--exclude-tags pg -x toolchain` | ≤ 8 |
| `server-pg` | `--tags pg -x mr -x perf -x load`, only files carrying `pg` | ≤ 6 |
| `server-mr` | `--tags mr -x perf -x load -j 1`, only files carrying `mr` | 1 |
| `server-gates` | `check-analyze-baseline.sh` + `check-custom-lints.sh` (what the `toolchain` tests re-run) | — |
| `server-regression` | gates + unit + pg (+ mr when relevant) | — |
| `client-files`, `client-affected`, `client-all`, `client-gates` | same idea for `packages/client` | ≤ 8 |

`-j` = clamp(MemAvailable / budget, 1, cap); budgets 1.0–1.5 GB per suite.
Tag runs pass only the files that carry the tag (`scripts/ci_select_tests.py`):
`dart test --tags X` otherwise loads and compiles every suite to find them.

## Measurements (2026-10-24, idle, 16 cores / 61 GB, MemAvailable 41 GB)

| Profile | -j | Wall | Tests | Lowest MemAvailable |
|---|---|---|---|---|
| server-unit | 8 | 2.0 min | 3041 | 36.0 GB |
| server-pg | 6 | 9.4 min | 2613 | 37.5 GB |
| server-mr (preselected files) | 1 | 3.7 min | 600 | 39.5 GB |
| client-all | 8 | 9.8 min | 7914 | 34.7 GB |

Before: `dart test --tags mr --exclude-tags load -j 1` took 16–22 min (it
loaded all ~620 suites; it also ran the `perf` suites, which carry `mr`).
Memory was never the limit for a single run; overlapping runs (an Alloy check
plus an agent's own run plus a manual run) and kernels on the RAM tmpfs were.

Known load-sensitive tests (pass alone, can fail when the machine is busy):
`test/perf/*` (budgets), `beacon_readable_ids_parity_pg_test` (5× faster),
`analyzer_issue_budget_toolchain_integration_test` (now excluded from
`server-unit`; `server-gates` covers it).
