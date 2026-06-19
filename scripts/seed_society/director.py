"""Ollama 'director': improvises the cast + plot, constrained to schema.py.

The plot is genuinely model-driven (it decides who does what, in what order),
but everything passes through normalize_plan so only executable events survive.
If the model fails, we fall back to a deterministic skeleton with the same
vocabulary and (separately) lazily generate all human-readable text at
execution time.
"""

from __future__ import annotations

import json

import schema
from ollama import Ollama

_CAST_SYSTEM = (
    "You are a creative writer designing a small, believable online community for "
    "a mutual-aid / favor-coordination app called Tentura, where people post "
    "'beacons' (requests for help or initiatives) and help each other. "
    "Invent a diverse cast of people with distinct voices and motivations."
)

_PLOT_SYSTEM = (
    "You are the director of an unfolding story in a mutual-aid app. You decide "
    "the sequence of actions among the cast. You may ONLY use the allowed event "
    "types. Build a coherent arc over a few weeks: people invite each other, "
    "create beacons (initiatives/requests), forward them to the right people, "
    "offer help, chat, raise asks/promises/blockers, run a poll, then close some "
    "beacons and have participants evaluate each other."
)


def _vocab_doc() -> str:
    lines = ["Allowed event types (JSON objects in an `events` array, in order):"]
    descriptions = {
        "invite": "person `from` invites person `to` to connect",
        "vote": "person `from` gives trust to `to` (optional amount -1|0|1)",
        "create_beacon": "person `by` creates a beacon with symbolic id `beacon` (e.g. \"b:garden\")",
        "forward": "person `from` forwards `beacon` to person `to`",
        "offer_help": "person `by` offers help on `beacon`",
        "chat": "person `by` posts a message in the room of `beacon`",
        "poll": "person `by` starts a poll in `beacon`",
        "ask": "person `from` asks person `to` for something on `beacon`",
        "promise": "person `from` promises person `to` something on `beacon`",
        "blocker": "person `by` flags a blocker on `beacon`",
        "close": "the author closes `beacon` (opens evaluation)",
        "evaluate": "participants of `beacon` evaluate each other (after close)",
    }
    for t, flds in schema.EVENT_TYPES.items():
        lines.append(f"- {t}: fields {flds}; {descriptions[t]}. Add a short `hint` topic string.")
    lines.append(
        "\nRules: reference people by their `handle`; reference a beacon by the same "
        "`beacon` id used in its create_beacon; never reference a beacon before it is "
        "created; only `evaluate` a beacon after it is `close`d."
    )
    return "\n".join(lines)


class Director:
    def __init__(self, ollama: Ollama):
        self.ollama = ollama

    def make_cast(self, n_users: int) -> list[dict]:
        user = (
            f"Design exactly {n_users} members. Return a JSON array; each item: "
            '{"display_name": str, "handle": str (lowercase a-z0-9_), "role": str '
            '(their imagined role/archetype), "bio": short str, "goals": short str}. '
            "Make them varied in age, background, and motivation."
        )
        raw = self.ollama.chat_json(_CAST_SYSTEM, user, num_predict=2400, retries=2)
        return schema.normalize_cast(raw, n_users)

    def make_plot(self, cast: list[dict]) -> tuple[list[dict], bool]:
        """Return (events, used_fallback)."""
        roster = "\n".join(
            f"- {p['handle']} — {p['display_name']} ({p['role']}): "
            f"{p['bio']} Goals: {p['goals']}"
            for p in cast
        )
        user = (
            f"Cast (use these exact handles):\n{roster}\n\n"
            f"{_vocab_doc()}\n\n"
            "Write the story as a chronological list of 25-40 events. Return JSON: "
            '{"events": [ {"type": ...}, ... ]}. Keep each event compact (short '
            "hints). Make it feel real: a couple of beacons should attract several "
            "helpers, generate back-and-forth chat and coordination, and at least one "
            "beacon should be closed and evaluated. Everyone should connect to at "
            "least one other person early on."
        )
        raw = self.ollama.chat_json(_PLOT_SYSTEM, user, num_predict=8000)
        events = []
        if isinstance(raw, dict):
            events = schema.normalize_plan(cast, raw.get("events"))
        elif isinstance(raw, list):
            events = schema.normalize_plan(cast, raw)

        # Require a viable plot: enough events AND at least one closed+evaluated beacon.
        has_eval = any(e["type"] == "evaluate" for e in events)
        if len(events) < 12 or not has_eval:
            return schema.ensure_evaluable(cast, schema.fallback_plan(cast)), True

        # Backfill missing event types from the fallback so the demo exercises
        # the whole API surface, without discarding the model's plot.
        gaps = schema.coverage_gaps(events)
        if gaps:
            for fe in schema.fallback_plan(cast):
                if fe["type"] in gaps:
                    events.append(fe)
                    gaps.discard(fe["type"])
            events = schema.normalize_plan(cast, events)
        events = schema.ensure_evaluable(cast, events)
        return events, False
