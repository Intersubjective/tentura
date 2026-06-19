"""Rewrites row timestamps in Postgres so the seeded activity reads as history.

All API calls happen "now"; this stage spreads created_at/updated_at (and the
review window's opened_at/closes_at) across the chosen window using the logical
timestamps the orchestrator assigned to each event. Refuses non-local DBs.

Timestamp columns are discovered from information_schema so we never UPDATE a
column that doesn't exist on a given table.
"""

from __future__ import annotations

from datetime import datetime, timedelta

try:
    import psycopg2
except ImportError:  # pragma: no cover - surfaced at runtime
    psycopg2 = None

# Columns we will set to the logical timestamp, if present on the table.
_TS_COLUMNS = ("created_at", "updated_at", "occurred_at")
_REVIEW_WINDOW_DAYS = 7


def _columns(cur, table: str) -> set[str]:
    cur.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_schema='public' AND table_name=%s",
        (table,),
    )
    return {r[0] for r in cur.fetchall()}


def apply_backdate(cfg, audit: list[dict]) -> dict:
    if psycopg2 is None:
        raise RuntimeError("psycopg2 not installed; cannot backdate (use --no-backdate)")
    if not cfg.pg.is_local:
        raise RuntimeError(f"Refusing to backdate non-local DB host: {cfg.pg.host}")

    stats = {"updated": 0, "skipped": 0}
    conn = psycopg2.connect(
        host=cfg.pg.host,
        port=cfg.pg.port,
        dbname=cfg.pg.dbname,
        user=cfg.pg.user,
        password=cfg.pg.password,
    )
    try:
        conn.autocommit = False
        cur = conn.cursor()
        col_cache: dict[str, set[str]] = {}

        for entry in audit:
            table = entry["table"]
            ts = entry["ts"]
            if table not in col_cache:
                col_cache[table] = _columns(cur, table)
            cols = col_cache[table]

            set_cols = [c for c in _TS_COLUMNS if c in cols]
            # Special handling for the review window's own time fields.
            if table == "beacon_review_window":
                if "opened_at" in cols:
                    set_cols.append("opened_at")

            if not set_cols:
                stats["skipped"] += 1
                continue

            assignments = ", ".join(f"{c} = %s::timestamptz" for c in set_cols)
            params: list = [ts] * len(set_cols)
            extra = ""
            if table == "beacon_review_window" and "closes_at" in cols:
                closes = (datetime.fromisoformat(ts) + timedelta(days=_REVIEW_WINDOW_DAYS)).isoformat()
                assignments += ", closes_at = %s::timestamptz"
                params.append(closes)

            if "id" in entry:
                where_sql = "id = %s"
                params.append(entry["id"])
            elif "where" in entry:
                conds, wvals = [], []
                for k, v in entry["where"].items():
                    if k in cols:
                        conds.append(f"{k} = %s")
                        wvals.append(v)
                if not conds:
                    stats["skipped"] += 1
                    continue
                where_sql = " AND ".join(conds)
                params.extend(wvals)
            else:
                stats["skipped"] += 1
                continue

            cur.execute(f"UPDATE public.{table} SET {assignments} WHERE {where_sql}", params)
            stats["updated"] += cur.rowcount

        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return stats
