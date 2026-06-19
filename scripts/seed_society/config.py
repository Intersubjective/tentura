"""Configuration + .env loading for the Tentura fake-society seeder.

All defaults target the LOCAL dev stack. The seeder hard-refuses non-local
hosts (see api_client / backdate) so a misconfigured run can never write to a
real deployment.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path

# Repo root is two levels up from scripts/seed_society/.
REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_GRAPHQL_URL = "http://localhost:2080/api/v2/graphql"
DEFAULT_OLLAMA_URL = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "qwopus-glm-18b:q4_k_m"

# Persona handles are prefixed so seeded data is trivially identifiable/purgeable.
HANDLE_PREFIX = "seed_"


def load_dotenv(path: Path) -> dict[str, str]:
    """Minimal .env parser (KEY=VALUE, ignores comments/blank lines)."""
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key:
            out[key] = val
    return out


@dataclass
class PgConfig:
    host: str = "127.0.0.1"
    port: int = 5432
    dbname: str = "postgres"
    user: str = "postgres"
    password: str = "password"

    @property
    def is_local(self) -> bool:
        return self.host in {"127.0.0.1", "localhost", "::1"}


@dataclass
class Config:
    graphql_url: str = DEFAULT_GRAPHQL_URL
    ollama_url: str = DEFAULT_OLLAMA_URL
    model: str = DEFAULT_MODEL
    pg: PgConfig = field(default_factory=PgConfig)

    users: int = 7
    beacons: int = 0  # 0 => let the director decide (small default in the prompt)
    days: int = 21
    rng_seed: int | None = None
    backdate: bool = True
    out_dir: Path = REPO_ROOT / "packages" / "server" / ".local" / "seed_society"

    @property
    def graphql_is_local(self) -> bool:
        return bool(re.search(r"://(localhost|127\.0\.0\.1|\[::1\])(:|/|$)", self.graphql_url))

    @classmethod
    def from_env_and_args(cls, args) -> "Config":
        env = load_dotenv(REPO_ROOT / ".env")
        pg = PgConfig(
            host=env.get("POSTGRES_HOST", "127.0.0.1"),
            port=int(env.get("POSTGRES_PORT", "5432")),
            dbname=env.get("POSTGRES_DBNAME", "postgres"),
            user=env.get("POSTGRES_USERNAME", "postgres"),
            password=env.get("POSTGRES_PASSWORD", "password"),
        )
        cfg = cls(pg=pg)
        if args.graphql_url:
            cfg.graphql_url = args.graphql_url
        if args.ollama_url:
            cfg.ollama_url = args.ollama_url
        if args.model:
            cfg.model = args.model
        if args.users:
            cfg.users = args.users
        if args.beacons:
            cfg.beacons = args.beacons
        if args.days:
            cfg.days = args.days
        if args.seed is not None:
            cfg.rng_seed = args.seed
        if args.no_backdate:
            cfg.backdate = False
        if args.out:
            cfg.out_dir = Path(args.out)
        return cfg
