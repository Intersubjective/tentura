# seed_society — Ollama-driven fake activity generator

Generates a small, believable "toy society" of Tentura users and their activity
(invites, beacons, forwards, help offers, room chat, asks/promises/blockers,
polls, beacon closures, peer evaluations) by driving the **local** server's
GraphQL API. Local **Ollama** acts as the story "director" and writes all the
human-readable text. After execution it **backdates** the rows in Postgres so the
activity reads as a story unfolding over the past few weeks.

For UI/UX testing and demos only. It refuses to run against a non-local server.

## Prerequisites

1. Local stack up:
   ```bash
   docker compose up -d
   ./scripts/run-server-local.sh        # GraphQL on http://localhost:2080/api/v2/graphql
   ```
   Local `.env` should have `NEED_INVITE=false` (default).
2. Ollama serving the model:
   ```bash
   curl -s localhost:11434/api/tags | grep qwopus-glm-18b
   ```
3. Python deps (one-time venv):
   ```bash
   python3 -m venv scripts/seed_society/.venv
   scripts/seed_society/.venv/bin/pip install -r scripts/seed_society/requirements.txt
   ```

## Usage

```bash
VENV=scripts/seed_society/.venv/bin/python

# 1. Inspect the validated plan (no writes):
$VENV scripts/seed_society/seed_society.py --dry-run

# 2. Real run (default ~7 users):
$VENV scripts/seed_society/seed_society.py --users 7
```

Useful flags: `--users N`, `--days N` (timeline span), `--seed N` (reproducible
RNG), `--no-backdate`, `--graphql-url`, `--ollama-url`, `--model`, `--out DIR`.

## Outputs

Written to `packages/server/.local/seed_society/` by default:

- `seeds.json` — one entry per persona with its **device seed**. Paste a seed
  into the app's seed login to browse the data as that persona.
- `plan.json` — the cast and the executed event timeline.

## How it works

- **director.py** asks Ollama for a cast and a chronological plot, constrained to
  the event vocabulary in **schema.py**. `normalize_plan` repairs/drops anything
  unexecutable; if the model fails, a deterministic skeleton (same vocabulary) is
  used so a run never fails.
- **api_client.py** does device-seed Ed25519 auth (PyNaCl) and GraphQL transport.
- **executor.py** dispatches events to mutations, enforces participation gating
  (forward → offer help → admit before posting), lazily generates text, and
  records an audit log. Evaluations are driven by the server's visibility graph
  (`evaluationParticipants`), not guessed.
- **backdate.py** rewrites `created_at`/`updated_at` (and the review window's
  `opened_at`/`closes_at`) from the audit log.

## Cleanup

All persona handles are prefixed with `seed_`, so seeded users are easy to find
and purge from the dev DB.
