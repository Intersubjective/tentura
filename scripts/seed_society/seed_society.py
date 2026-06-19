#!/usr/bin/env python3
"""Ollama-driven fake-society seeder for the LOCAL Tentura server.

Generates a small toy society — users who invite each other, create/forward
beacons, coordinate, chat, close beacons and evaluate each other — by driving
the real GraphQL API, then backdates the rows so it reads as a story unfolding
over the past few weeks. For UI/UX testing and demos only.

    python3 scripts/seed_society/seed_society.py --dry-run
    python3 scripts/seed_society/seed_society.py --users 7

See README.md for setup (venv + deps + local stack).
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from config import Config
from director import Director
from executor import Executor
from ollama import Ollama


def parse_args(argv):
    p = argparse.ArgumentParser(description="Seed a fake Tentura society via local Ollama + API.")
    p.add_argument("--users", type=int, default=7, help="number of personas (default 7)")
    p.add_argument("--beacons", type=int, default=0, help="hint for beacon count (0=director decides)")
    p.add_argument("--days", type=int, default=21, help="timeline span in days (default 21)")
    p.add_argument("--seed", type=int, default=None, help="RNG seed for reproducibility")
    p.add_argument("--no-backdate", action="store_true", help="skip Postgres timestamp rewrite")
    p.add_argument("--dry-run", action="store_true", help="print validated plan; no API/DB writes")
    p.add_argument("--graphql-url", default=None)
    p.add_argument("--ollama-url", default=None)
    p.add_argument("--model", default=None)
    p.add_argument("--out", default=None, help="output dir for seeds.json/plan.json")
    p.add_argument("--allow-remote", action="store_true", help="permit non-local GraphQL host (dangerous)")
    return p.parse_args(argv)


def assign_timestamps(events: list[dict], days: int):
    """Spread events monotonically across [now-days, now-1d]; return users_ts."""
    end = datetime.now(timezone.utc) - timedelta(days=1)
    start = end - timedelta(days=max(1, days - 1))
    span = (end - start).total_seconds()
    n = len(events)
    rng = random.Random(12345)
    last = start
    for i, ev in enumerate(events):
        frac = (i + 1) / (n + 1)
        base = start + timedelta(seconds=span * frac)
        jitter = timedelta(seconds=rng.uniform(-span / (n + 1) / 2, span / (n + 1) / 2))
        ts = base + jitter
        if ts <= last:
            ts = last + timedelta(seconds=1)
        last = ts
        ev["ts"] = ts.isoformat()
    return (start - timedelta(days=1)).isoformat()


def main(argv) -> int:
    args = parse_args(argv)
    cfg = Config.from_env_and_args(args)

    if not cfg.graphql_is_local and not args.allow_remote:
        print(f"REFUSING: GraphQL host is not local: {cfg.graphql_url}\n"
              "This tool writes test data + rewrites timestamps. Use --allow-remote "
              "only if you really mean it.", file=sys.stderr)
        return 2

    rng = random.Random(cfg.rng_seed)
    ollama = Ollama(cfg.ollama_url, cfg.model)
    director = Director(ollama)

    print(f"• Directing a society of {cfg.users} via {cfg.model} ...")
    cast = director.make_cast(cfg.users)
    events, used_fallback = director.make_plot(cast)
    users_ts = assign_timestamps(events, cfg.days)
    print(f"• Cast: {len(cast)} personas; plot: {len(events)} events"
          f"{' (fallback skeleton)' if used_fallback else ''}")

    if args.dry_run:
        print(json.dumps({"cast": cast, "events": events}, indent=2, ensure_ascii=False))
        return 0

    ex = Executor(cfg, ollama, rng)
    print("• Creating users ...")
    ex.create_users(cast, users_ts)
    print(f"• Executing {len(events)} events against {cfg.graphql_url} ...")
    for i, ev in enumerate(events, 1):
        ex.run_event(ev)
        if i % 10 == 0:
            print(f"    ... {i}/{len(events)}")

    if cfg.backdate:
        print("• Backdating timestamps in Postgres ...")
        try:
            from backdate import apply_backdate
            stats = apply_backdate(cfg, ex.audit)
            print(f"    updated {stats['updated']} rows ({stats['skipped']} skipped)")
        except Exception as e:
            print(f"    ! backdating failed: {e}")

    print("• Rebuilding trust / MeritRank ...")
    if not ex.rebuild_trust():
        print("    ! trustForceRefreshAll not permitted; skipped")

    # Outputs
    out = cfg.out_dir
    out.mkdir(parents=True, exist_ok=True)
    seeds = [
        {
            "handle": p["handle"],
            "display_name": p["display_name"],
            "role": p.get("role", ""),
            "subject": p.get("subject"),
            "seed": p.get("seed"),
        }
        for p in cast if p.get("seed")
    ]
    (out / "seeds.json").write_text(json.dumps(seeds, indent=2, ensure_ascii=False))
    (out / "plan.json").write_text(json.dumps({"cast": cast, "events": events}, indent=2, ensure_ascii=False))

    print("\n=== Summary ===")
    for k in ("users", "connections", "votes", "beacons", "forwards", "help_offers",
              "messages", "polls", "asks", "promises", "blockers", "closures", "evaluations"):
        print(f"  {k:13s}: {ex.counts.get(k, 0)}")
    print(f"\nSeeds (paste a seed into the app to log in as that persona): {out / 'seeds.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
