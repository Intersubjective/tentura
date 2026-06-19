"""Event vocabulary + plan validation/normalization + deterministic fallback.

The director (Ollama) improvises the plot, but every event must conform to this
fixed, executable vocabulary. `normalize_plan` repairs/drops anything that would
not execute (unknown actors, references to a beacon before it exists, evaluate
before close, ...) so a run can never fail on a malformed plan. If the model
produces nothing usable, `fallback_plan` yields a coherent skeleton using the
same vocabulary.

Symbolic ids:
  - users   -> the persona's slugged handle (e.g. "seed_maria")
  - beacons -> "b:<ref>" where <ref> is introduced by a create_beacon event
"""

from __future__ import annotations

import re
from typing import Any

from config import HANDLE_PREFIX

# event type -> required symbolic-id fields (besides type/hint)
EVENT_TYPES: dict[str, list[str]] = {
    "invite": ["from", "to"],
    "vote": ["from", "to"],
    "create_beacon": ["by", "beacon"],
    "forward": ["beacon", "from", "to"],
    "offer_help": ["beacon", "by"],
    "chat": ["beacon", "by"],
    "poll": ["beacon", "by"],
    "ask": ["beacon", "from", "to"],
    "promise": ["beacon", "from", "to"],
    "blocker": ["beacon", "by"],
    "close": ["beacon"],
    "evaluate": ["beacon"],
}


def slug_handle(raw: str, taken: set[str]) -> str:
    base = re.sub(r"[^a-z0-9_]", "", (raw or "").lower().replace(" ", "_"))
    base = base.strip("_") or "user"
    base = f"{HANDLE_PREFIX}{base}"[:30]
    candidate = base
    n = 1
    while candidate in taken:
        suffix = str(n)
        candidate = base[: 30 - len(suffix)] + suffix
        n += 1
    taken.add(candidate)
    return candidate


# Curated named archetypes used to pad/replace when the model under-delivers, so
# a run always yields believable characters (never "Persona 1").
FALLBACK_PERSONAS: list[dict] = [
    {"display_name": "Mara Okonkwo", "role": "Community organizer & retired nurse",
     "bio": "Coordinates neighbours for rides, meals and check-ins on the elderly.",
     "goals": "Build a reliable mutual-aid rota so nobody is left without help."},
    {"display_name": "Diego Salas", "role": "Bike courier & repair tinkerer",
     "bio": "Knows every shortcut in town; fixes bikes and small electronics for free.",
     "goals": "Start a tool-share so people can fix things instead of binning them."},
    {"display_name": "Priya Nair", "role": "Software developer & digital-skills mentor",
     "bio": "Builds little apps for local shops and teaches seniors to stay safe online.",
     "goals": "Run friendly mini-classes on basic digital literacy."},
    {"display_name": "Tomas Berg", "role": "Carpenter & weekend gardener",
     "bio": "Handy with wood and soil; quietly reliable, slow to make promises he can't keep.",
     "goals": "Get a community garden plot built before spring."},
    {"display_name": "Amina Hassan", "role": "Nursing student & new arrival",
     "bio": "Recently moved to the city, eager to find her people and lend a hand.",
     "goals": "Make friends and learn the ropes of local mutual aid."},
    {"display_name": "Greta Lindqvist", "role": "Schoolteacher & skeptic",
     "bio": "Warm but asks hard questions; won't sign onto a plan she doesn't trust.",
     "goals": "Make sure initiatives are fair and actually follow through."},
    {"display_name": "Kwame Mensah", "role": "Cafe owner & natural connector",
     "bio": "Everyone passes through his cafe; he knows who to introduce to whom.",
     "goals": "Be the bridge that gets the right help to the right person."},
    {"display_name": "Lena Petrova", "role": "Freelance photographer & documenter",
     "bio": "Captures local stories; a bit scattered but generous with her time.",
     "goals": "Document the neighbourhood's small acts of kindness."},
]


def normalize_cast(raw_cast: Any, want: int) -> list[dict]:
    """Coerce the director's cast into clean persona dicts with unique handles."""
    out: list[dict] = []
    taken: set[str] = set()
    items = raw_cast if isinstance(raw_cast, list) else []
    for item in items:
        if not isinstance(item, dict):
            continue
        name = str(item.get("display_name") or item.get("name") or "").strip()
        if not name:
            continue
        handle = slug_handle(str(item.get("handle") or name), taken)
        out.append(
            {
                "display_name": name[:60],
                "handle": handle,
                "role": str(item.get("role") or "member").strip()[:60],
                "bio": str(item.get("bio") or "").strip()[:280],
                "goals": str(item.get("goals") or "").strip()[:280],
            }
        )
    # Pad from the curated archetype pool (never generic "Persona N").
    fi = 0
    while len(out) < want:
        proto = FALLBACK_PERSONAS[fi % len(FALLBACK_PERSONAS)]
        fi += 1
        if any(p["display_name"] == proto["display_name"] for p in out):
            continue
        out.append({**proto, "handle": slug_handle(proto["display_name"], taken)})
    return out[:want]


def normalize_plan(cast: list[dict], raw_events: Any) -> list[dict]:
    """Validate + repair the event list. Returns executable events in order."""
    handles = {p["handle"] for p in cast}
    events = raw_events if isinstance(raw_events, list) else []
    created_beacons: dict[str, str] = {}  # beacon ref -> author handle
    closed: set[str] = set()
    clean: list[dict] = []

    def resolve_user(val: Any) -> str | None:
        if not isinstance(val, str):
            return None
        v = val.strip()
        if v.startswith("u:"):
            v = v[2:]
        # exact handle, slugged handle, or display-name match
        if v in handles:
            return v
        for p in cast:
            if v == p["handle"] or v.lower() == p["display_name"].lower():
                return p["handle"]
        # try slugging
        cand = re.sub(r"[^a-z0-9_]", "", v.lower())
        for h in handles:
            if cand and (cand in h or h.endswith(cand)):
                return h
        return None

    def norm_beacon_ref(val: Any) -> str | None:
        if not isinstance(val, str):
            return None
        v = val.strip()
        if v.startswith("b:"):
            v = v[2:]
        return re.sub(r"[^a-z0-9_]+", "_", v.lower()).strip("_") or None

    for ev in events:
        if not isinstance(ev, dict):
            continue
        etype = str(ev.get("type") or "").strip()
        if etype not in EVENT_TYPES:
            continue
        out = {"type": etype, "hint": str(ev.get("hint") or "").strip()[:200]}

        # resolve beacon
        if "beacon" in EVENT_TYPES[etype]:
            ref = norm_beacon_ref(ev.get("beacon") or ev.get("ref"))
            if not ref:
                continue
            if etype == "create_beacon":
                if ref in created_beacons:
                    continue  # duplicate beacon ref
            elif ref not in created_beacons:
                continue  # references a beacon that doesn't exist yet
            out["beacon"] = ref

        # resolve users
        ok = True
        for fld in ("from", "to", "by"):
            if fld in EVENT_TYPES[etype]:
                u = resolve_user(ev.get(fld))
                if u is None:
                    ok = False
                    break
                out[fld] = u
        if not ok:
            continue

        # type-specific integrity
        if etype == "create_beacon":
            created_beacons[out["beacon"]] = out["by"]
        elif etype == "evaluate":
            if out["beacon"] not in closed:
                continue  # can only evaluate after close
        elif etype == "close":
            if out["beacon"] in closed:
                continue
            closed.add(out["beacon"])
        elif etype in ("invite", "vote") and out["from"] == out["to"]:
            continue  # no self-edges

        if "amount" in ev and etype == "vote":
            try:
                out["amount"] = max(-1, min(1, int(ev["amount"])))
            except (TypeError, ValueError):
                out["amount"] = 1

        clean.append(out)

    return clean


def ensure_evaluable(cast: list[dict], events: list[dict]) -> list[dict]:
    """Guarantee every beacon that gets `evaluate`d has >=2 non-author helpers.

    The evaluation step needs participants to evaluate; a model plot can close a
    beacon nobody joined. For each such beacon we inject forward->offer_help->chat
    from spare cast members just before its close.
    """
    from collections import defaultdict

    handles = [p["handle"] for p in cast]
    beacon_author: dict[str, str] = {}
    helpers: dict[str, set] = defaultdict(set)
    for e in events:
        if e["type"] == "create_beacon":
            beacon_author[e["beacon"]] = e["by"]
        elif e["type"] == "offer_help":
            # Only offer_help -> admitted committer -> an evaluatable participant.
            helpers[e["beacon"]].add(e["by"])
    eval_beacons = {e["beacon"] for e in events if e["type"] == "evaluate"}

    out: list[dict] = []
    for e in events:
        if e["type"] == "close" and e["beacon"] in eval_beacons:
            b = e["beacon"]
            author = beacon_author.get(b)
            need = 2 - len(helpers[b])
            if author and need > 0:
                spare = [h for h in handles if h != author and h not in helpers[b]]
                for h in spare[:need]:
                    out.append({"type": "forward", "beacon": b, "from": author, "to": h, "hint": "joining in"})
                    out.append({"type": "offer_help", "beacon": b, "by": h, "hint": "glad to help"})
                    out.append({"type": "chat", "beacon": b, "by": h, "hint": "on it"})
                    helpers[b].add(h)
        out.append(e)
    return normalize_plan(cast, out)


def coverage_gaps(events: list[dict]) -> set[str]:
    """Event types from the vocabulary that the plan never exercises."""
    present = {e["type"] for e in events}
    return set(EVENT_TYPES) - present


def fallback_plan(cast: list[dict]) -> list[dict]:
    """Deterministic skeleton covering the full vocabulary.

    Builds an invite chain, two beacons with forwards/help/chat/coordination,
    one closure + evaluation, and trust votes.
    """
    h = [p["handle"] for p in cast]
    n = len(h)
    ev: list[dict] = []

    # Invite chain + reciprocal trust votes.
    for i in range(n - 1):
        ev.append({"type": "invite", "from": h[i], "to": h[i + 1], "hint": ""})
        ev.append({"type": "vote", "from": h[i], "to": h[i + 1], "amount": 1, "hint": ""})
        ev.append({"type": "vote", "from": h[i + 1], "to": h[i], "amount": 1, "hint": ""})

    def beacon_block(ref: str, author: str, helpers: list[str], topic: str, do_close: bool):
        ev.append({"type": "create_beacon", "by": author, "beacon": ref, "hint": topic})
        ev.append({"type": "chat", "beacon": ref, "by": author, "hint": f"kick off: {topic}"})
        for hp in helpers:
            ev.append({"type": "forward", "beacon": ref, "from": author, "to": hp, "hint": topic})
            ev.append({"type": "offer_help", "beacon": ref, "by": hp, "hint": topic})
            ev.append({"type": "chat", "beacon": ref, "by": hp, "hint": f"reply about {topic}"})
        if helpers:
            ev.append({"type": "ask", "beacon": ref, "from": author, "to": helpers[0], "hint": topic})
            ev.append({"type": "promise", "beacon": ref, "from": helpers[0], "to": author, "hint": topic})
        ev.append({"type": "poll", "beacon": ref, "by": author, "hint": f"decide on {topic}"})
        if len(helpers) > 1:
            ev.append({"type": "blocker", "beacon": ref, "by": helpers[1], "hint": topic})
        if do_close:
            ev.append({"type": "close", "beacon": ref, "hint": ""})
            ev.append({"type": "evaluate", "beacon": ref, "hint": ""})

    beacon_block("community_garden", h[0], h[1:3] if n > 2 else h[1:2],
                 "starting a neighborhood community garden", do_close=True)
    if n > 3:
        beacon_block("repair_cafe", h[1], h[2:4],
                     "monthly tool-share and repair cafe", do_close=False)

    return normalize_plan(cast, ev)
