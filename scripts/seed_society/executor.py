"""Executes a validated event plan against the live local GraphQL API.

Maintains symbol tables (handle -> UserSession, beacon ref -> state), enforces
the server's participation gating (forward -> offer help -> admit before a user
can post/coordinate), lazily generates all human text via Ollama, and records an
audit log of created rows for the backdater.
"""

from __future__ import annotations

import random

from api_client import GraphQLError, UserSession, seed_to_b64
from ollama import Ollama

# Positive reason tags per evaluation participant role (see
# server/lib/domain/evaluation/evaluation_reason_tags.dart). value 4 = pos1.
_POSITIVE_TAGS = {
    0: "fair_closure",          # author
    1: "delivered_as_promised",  # committer
    2: "reached_right_person",   # forwarder
}


class Executor:
    def __init__(self, cfg, ollama: Ollama, rng: random.Random):
        self.cfg = cfg
        self.ollama = ollama
        self.rng = rng
        self.users: dict[str, UserSession] = {}        # handle -> session
        self.cast_by_handle: dict[str, dict] = {}      # handle -> persona dict
        self.beacons: dict[str, dict] = {}             # ref -> state
        self.audit: list[dict] = []
        self.counts: dict[str, int] = {}

    # -- audit/counters --------------------------------------------------- #
    def _tick(self, key: str):
        self.counts[key] = self.counts.get(key, 0) + 1

    def _rec(self, table: str, ts: str, *, id: str | None = None, where: dict | None = None):
        entry = {"table": table, "ts": ts}
        if id is not None:
            entry["id"] = id
        if where is not None:
            entry["where"] = where
        self.audit.append(entry)

    # -- text gen (best-effort; never fatal) ------------------------------ #
    def _persona_sys(self, handle: str) -> str:
        p = self.cast_by_handle.get(handle, {})
        return (
            f"You are {p.get('display_name', handle)}, {p.get('role', 'a member')} "
            f"in a mutual-aid app. {p.get('bio', '')} "
            "Write in first person, casual, concise. No quotes around your reply."
        )

    def _line(self, handle: str, instruction: str, *, fallback: str, n: int = 60) -> str:
        try:
            txt = self.ollama.chat(self._persona_sys(handle), instruction, num_predict=n)
            txt = txt.strip().strip('"').replace("\n", " ").strip()
            return txt[:600] or fallback
        except Exception:
            return fallback

    # -- user setup ------------------------------------------------------- #
    def create_users(self, cast: list[dict], ts: str):
        for p in cast:
            self.cast_by_handle[p["handle"]] = p
            sess = UserSession(self.cfg.graphql_url)
            try:
                sess.sign_up(p["display_name"], p["handle"])
            except GraphQLError as e:
                print(f"  ! signUp failed for {p['handle']}: {e}")
                continue
            self.users[p["handle"]] = sess
            self._tick("users")
            self._rec("user", ts, id=sess.subject)
            if p.get("bio"):
                try:
                    # Pass handle too: userUpdate's `handle` arg defaults to null,
                    # so omitting it would clear the handle set at signUp.
                    sess.gql(
                        "mutation($d:String,$h:String){ userUpdate(description:$d, handle:$h){ id handle } }",
                        {"d": p["bio"][:280], "h": p["handle"]},
                    )
                except GraphQLError:
                    pass
        # store seed for app login
        for p in cast:
            s = self.users.get(p["handle"])
            if s:
                p["seed"] = seed_to_b64(s.seed)
                p["subject"] = s.subject

    # -- access/participation gating -------------------------------------- #
    def _ensure_aware(self, b: dict, handle: str, ts: str):
        """Make sure `handle` has received the beacon (can offer help / forward)."""
        if handle == b["author"] or handle in b["aware"]:
            return
        author = self.users[b["author"]]
        target = self.users[handle]
        try:
            data = author.gql(
                "mutation($id:String!,$r:[String!]){ beaconForward(id:$id, recipientIds:$r) }",
                {"id": b["id"], "r": [target.subject]},
            )
            b["aware"].add(handle)
            self._tick("forwards")
            self._rec("beacon_forward_edge", ts, id=data.get("beaconForward"))
        except GraphQLError as e:
            print(f"    ! forward(access) {b['ref']}->{handle}: {e}")

    def _join(self, b: dict, handle: str, ts: str):
        """Make `handle` a committer: offer help (the help_offer path), which both
        makes them an evaluation participant AND, because the author has directly
        forwarded them the beacon, auto-admits them to the room so they can post.
        """
        if handle == b["author"] or handle in b["room"]:
            return
        self._ensure_aware(b, handle, ts)
        user = self.users.get(handle)
        if not user:
            return
        try:
            msg = self._line(handle, f"One short sentence offering to help with: {b['topic']}",
                            fallback="Happy to help with this.")
            user.gql(
                "mutation($id:String!,$m:String){ beaconOfferHelp(id:$id, message:$m) }",
                {"id": b["id"], "m": msg},
            )
            b["room"].add(handle)
        except GraphQLError as e:
            print(f"    ! join {b['ref']}<-{handle}: {e}")

    # -- event dispatch --------------------------------------------------- #
    def run_event(self, ev: dict):
        handler = getattr(self, f"_ev_{ev['type']}", None)
        if handler is None:
            return
        try:
            handler(ev)
        except GraphQLError as e:
            print(f"  ! {ev['type']} failed: {e}")

    def _ev_invite(self, ev):
        a, b = self.users.get(ev["from"]), self.users.get(ev["to"])
        if not a or not b:
            return
        data = a.gql(
            "mutation($n:String!){ invitationCreate(addresseeName:$n){ id } }",
            {"n": self.cast_by_handle[ev["to"]]["display_name"]},
        )
        inv_id = data["invitationCreate"]["id"]
        b.gql("mutation($id:String!){ invitationAccept(id:$id) }", {"id": inv_id})
        self._tick("connections")

    def _ev_vote(self, ev):
        a, b = self.users.get(ev["from"]), self.users.get(ev["to"])
        if not a or not b:
            return
        amount = ev.get("amount", 1)
        a.gql(
            "mutation($o:String!,$a:Int){ userVote(objectId:$o, amount:$a) }",
            {"o": b.subject, "a": amount},
        )
        self._tick("votes")

    def _ev_create_beacon(self, ev):
        author = self.users.get(ev["by"])
        if not author:
            return
        ts = ev["ts"]
        meta = self._beacon_meta(ev["by"], ev.get("hint", ""))
        data = author.gql(
            """
            mutation($t:String!,$d:String,$n:String,$g:String){
              beaconCreate(title:$t, description:$d, needSummary:$n, tags:$g){ id }
            }
            """,
            {"t": meta["title"], "d": meta["description"], "n": meta["need_summary"], "g": meta["tags"]},
        )
        bid = data["beaconCreate"]["id"]
        self.beacons[ev["beacon"]] = {
            "ref": ev["beacon"],
            "id": bid,
            "author": ev["by"],
            "topic": ev.get("hint", "") or meta["title"],
            "aware": set(),
            "room": set(),
        }
        self._tick("beacons")
        self._rec("beacon", ts, id=bid)

    @staticmethod
    def _need_summary(text: str, topic: str) -> str:
        """Server requires 16-280 chars for a published beacon."""
        s = (text or "").strip()
        if len(s) < 16:
            s = f"Looking for help with {topic}. A few volunteers would make a difference."
        return s[:280]

    def _beacon_meta(self, handle: str, hint: str) -> dict:
        topic = hint or "a community initiative"
        default = {
            "title": topic[:80].capitalize() or "Community initiative",
            "description": f"Let's organize around: {topic}.",
            "need_summary": self._need_summary("", topic),
            "tags": "community",
        }
        try:
            raw = self.ollama.chat_json(
                self._persona_sys(handle),
                f"Create a beacon (a request/initiative) about: {topic}. "
                'Return JSON {"title": short, "description": 1-2 sentences, '
                '"needs": one sentence on what help is needed, "tags": comma-separated keywords}.',
                num_predict=400,
            )
            if isinstance(raw, dict) and raw.get("title"):
                return {
                    "title": str(raw.get("title"))[:80] or default["title"],
                    "description": str(raw.get("description", default["description"]))[:600],
                    "need_summary": self._need_summary(str(raw.get("needs", "")), topic),
                    "tags": str(raw.get("tags", default["tags"]))[:120],
                }
        except Exception:
            pass
        return default

    def _ev_forward(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b:
            return
        frm, to = ev["from"], ev["to"]
        if to == b["author"] or to == frm or to in b["aware"]:
            return
        self._ensure_aware(b, frm, ev["ts"])
        sender = self.users.get(frm)
        target = self.users.get(to)
        if not sender or not target:
            return
        note = self._line(frm, f"One line forwarding note for: {b['topic']}",
                          fallback="Thought of you for this.")
        data = sender.gql(
            "mutation($id:String!,$r:[String!],$n:String){ beaconForward(id:$id, recipientIds:$r, note:$n) }",
            {"id": b["id"], "r": [target.subject], "n": note},
        )
        b["aware"].add(to)
        self._tick("forwards")
        self._rec("beacon_forward_edge", ev["ts"], id=data.get("beaconForward"))

    def _ev_offer_help(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b or ev["by"] not in self.users:
            return
        self._join(b, ev["by"], ev["ts"])
        self._tick("help_offers")

    def _ev_chat(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b or ev["by"] not in self.users:
            return
        self._join(b, ev["by"], ev["ts"])
        body = self._line(ev["by"], f"Write a short chat message about: {ev.get('hint') or b['topic']}",
                         fallback=f"Count me in on {b['topic']}.")
        data = self.users[ev["by"]].gql(
            "mutation($id:String!,$b:String!){ RoomMessageCreate(beaconId:$id, body:$b){ id } }",
            {"id": b["id"], "b": body},
        )
        self._tick("messages")
        mid = (data.get("RoomMessageCreate") or {}).get("id")
        if mid:
            self._rec("beacon_room_message", ev["ts"], id=mid)

    def _ev_poll(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b or ev["by"] not in self.users:
            return
        self._join(b, ev["by"], ev["ts"])
        q, variants = self._poll_meta(ev["by"], ev.get("hint") or b["topic"])
        data = self.users[ev["by"]].gql(
            "mutation($id:String!,$q:String!,$v:[String!]!){ RoomPollCreate(beaconId:$id, question:$q, variants:$v){ id } }",
            {"id": b["id"], "q": q, "v": variants},
        )
        self._tick("polls")
        mid = (data.get("RoomPollCreate") or {}).get("id")
        if mid:
            self._rec("beacon_room_message", ev["ts"], id=mid)

    def _poll_meta(self, handle: str, topic: str):
        default = (f"What should we do about {topic}?",
                   ["Option A", "Option B", "Option C"])
        try:
            raw = self.ollama.chat_json(
                self._persona_sys(handle),
                f"Make a quick poll about: {topic}. "
                'Return JSON {"question": str, "variants": [3 short strings]}.',
                num_predict=300,
            )
            if isinstance(raw, dict) and raw.get("question") and isinstance(raw.get("variants"), list):
                vs = [str(v)[:80] for v in raw["variants"] if str(v).strip()][:6]
                if len(vs) >= 2:
                    return str(raw["question"])[:200], vs
        except Exception:
            pass
        return default

    def _ev_ask(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b:
            return
        frm, to = ev["from"], ev["to"]
        if frm == to or frm not in self.users or to not in self.users:
            return
        self._join(b, frm, ev["ts"])
        self._join(b, to, ev["ts"])
        title = self._line(frm, f"A short ask/request title about: {ev.get('hint') or b['topic']}",
                          fallback="Can you help with this?", n=24)
        data = self.users[frm].gql(
            "mutation($b:String!,$t:String!,$p:String!){ markAsk(beaconId:$b, title:$t, targetPersonId:$p){ id } }",
            {"b": b["id"], "t": title, "p": self.users[to].subject},
        )
        item_id = data["markAsk"]["id"]
        self._tick("asks")
        self._rec("coordination_item", ev["ts"], id=item_id)
        # target accepts
        try:
            self.users[to].gql("mutation($id:String!){ acceptAsk(itemId:$id){ id } }", {"id": item_id})
        except GraphQLError:
            pass

    def _ev_promise(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b:
            return
        frm, to = ev["from"], ev["to"]
        if frm == to or frm not in self.users or to not in self.users:
            return
        self._join(b, frm, ev["ts"])
        self._join(b, to, ev["ts"])
        title = self._line(frm, f"A short promise title about: {ev.get('hint') or b['topic']}",
                          fallback="I'll take care of this.", n=24)
        body = self._line(frm, f"One sentence describing what you promise to do about: {ev.get('hint') or b['topic']}",
                         fallback=f"I'll handle {b['topic']} and report back.")
        data = self.users[frm].gql(
            "mutation($b:String!,$t:String!,$p:String!,$y:String!){ createPromise(beaconId:$b, title:$t, targetPersonId:$p, body:$y){ id } }",
            {"b": b["id"], "t": title, "p": self.users[to].subject, "y": body},
        )
        item_id = data["createPromise"]["id"]
        self._tick("promises")
        self._rec("coordination_item", ev["ts"], id=item_id)
        try:
            self.users[to].gql("mutation($id:String!){ acceptPromise(itemId:$id){ id } }", {"id": item_id})
        except GraphQLError:
            pass

    def _ev_blocker(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b or ev["by"] not in self.users:
            return
        self._join(b, ev["by"], ev["ts"])
        title = self._line(ev["by"], f"A short blocker title about: {ev.get('hint') or b['topic']}",
                          fallback="We're blocked on this.", n=24)
        data = self.users[ev["by"]].gql(
            "mutation($b:String!,$t:String!){ markBlocker(beaconId:$b, title:$t){ id } }",
            {"b": b["id"], "t": title},
        )
        self._tick("blockers")
        self._rec("coordination_item", ev["ts"], id=data["markBlocker"]["id"])

    def _ev_close(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b:
            return
        author = self.users[b["author"]]
        author.gql("mutation($id:String!){ beaconCloseWithReview(id:$id){ id state closesAt } }",
                  {"id": b["id"]})
        b["closed"] = True
        self._tick("closures")
        self._rec("beacon_review_window", ev["ts"], where={"beacon_id": b["id"]})

    def _ev_evaluate(self, ev):
        b = self.beacons.get(ev["beacon"])
        if not b or not b.get("closed"):
            return
        evaluators = {b["author"], *b["room"]}
        for handle in evaluators:
            sess = self.users.get(handle)
            if not sess:
                continue
            try:
                data = sess.gql(
                    "query($id:String!){ evaluationParticipants(id:$id){ userId role } }",
                    {"id": b["id"]},
                )
            except GraphQLError:
                continue
            targets = data.get("evaluationParticipants") or []
            submitted = False
            for t in targets:
                if t["userId"] == sess.subject:
                    continue
                role = int(t.get("role", 1))
                tag = _POSITIVE_TAGS.get(role, "delivered_as_promised")
                note = self._line(handle, f"One sentence of positive feedback for a collaborator on {b['topic']}",
                                 fallback="Great to work with.")
                try:
                    sess.gql(
                        """
                        mutation($id:String!,$u:String!,$v:Int!,$r:[String!]!,$n:String){
                          evaluationSubmit(id:$id, evaluatedUserId:$u, value:$v, reasonTags:$r, note:$n)
                        }
                        """,
                        {"id": b["id"], "u": t["userId"], "v": 4, "r": [tag], "n": note},
                    )
                    submitted = True
                    self._tick("evaluations")
                    self._rec("beacon_evaluation", ev["ts"], where={"beacon_id": b["id"]})
                except GraphQLError as e:
                    print(f"    ! evaluationSubmit {handle}->{t['userId']}: {e}")
            if submitted:
                try:
                    sess.gql("mutation($id:String!){ evaluationFinalize(id:$id) }", {"id": b["id"]})
                except GraphQLError:
                    pass

    # -- trust/meritrank rebuild ----------------------------------------- #
    def rebuild_trust(self):
        # Any authenticated user can trigger; mrInit privilege may be required.
        for sess in self.users.values():
            try:
                sess.gql("mutation{ trustForceRefreshAll }")
                return True
            except GraphQLError:
                continue
        return False
