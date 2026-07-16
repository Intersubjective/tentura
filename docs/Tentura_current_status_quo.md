# Tentura — current status quo of design and decisions

This document compresses the **current shipped product direction** of Tentura. It supersedes older feed-centric, context-centric, and plan/journal docs where they conflict with the points below.

**Feature-level specs:** [`features/beacon_room.md`](features/beacon_room.md), [`watching-mechanism.md`](watching-mechanism.md), [`beacon-evaluation-principles.md`](beacon-evaluation-principles.md).

## 1. Core reframe

Tentura is not a social network, public forum, or reputation-driven feed. It is a graph-native coordination substrate whose job is to keep the social fabric continuous without overheating it.

The strategic shift is away from maximizing connectivity and engagement. The target is **selective percolation**: enough connectivity for help, discovery, and coordination to propagate, with inhibitors against redundant closure, corridor concentration, broker capture, and a single public stage.

Working metaphor: **reactor, not bomb**.

## 2. Main design axioms

- **No public feed.** No common stage where everything competes for visibility.
- **No global reputation score.** MeritRank is subjective and procedural, not a public status ladder.
- **No automatic connectivity maximization.** Preserve useful paths; do not maximize ties.
- **Selective visibility over universal visibility.** Scoped, relational, path-dependent.
- **Local memory over global social truth.** Continuity without a dossier machine.
- **Protocols over discourse.** Coordination objects with explicit state transitions, not open-ended discussion.

## 3. Decisive simplification (v1)

Older iterations assumed feed/discovery, comments, contexts, and broad social-network behavior. The current direction rejects that.

> Tentura v1 is a **feedless, inbox-driven, MR-scoped human relay system for requests**.

- Not Twitter/Facebook/Reddit.
- Virality is not the main primitive.
- Discovery is secondary and bounded.
- **Forwarding** matters more than posting.
- **Coordination state** matters more than discussion volume.

## 4. v1 object model

### 4.1 Beacon is the only first-class object

For v1, **beacon** is the only primary object: a request/need/task that can be forwarded, committed to, coordinated in a **Room**, and closed.

### 4.2 Explicitly out of scope for v1

Deferred (not rejected in principle):

- groups and membership machinery as a primary surface;
- governance roles and constitutional processes;
- treasury / fund logic;
- appeals / jury / steward systems at scale;
- care-thread machinery as a first-class object;
- signal/case/probe split as separate objects;
- **comments** under beacons;
- public reputation surfaces;
- **global 1:1 chat** as a product surface;
- **Registry / Group** home tab.

## 5. v1 surface model (as shipped)

**Home** bottom navigation — default tab **My Work**:

| Tab | Meaning |
|-----|---------|
| **My Work** | Beacons I authored and/or offered help on |
| **Inbox** | Forwarded to me — triage and passive follow |
| **Updates** | Unread attention receipts and their destinations |
| **Friends** | Network / forward targets |
| **Profile** | Capabilities, settings, account |

**Inbox** = push (items brought to me). **My Work** = pull on **my** responsibility.

**Inbox tabs:** **Needs me** (triage) and **Watching** (passive follow). **Not for me** lives in an **archive**, not a third tab.

**Updates** — dedicated home tab for unread attention receipts; it is not a substitute for Inbox semantics.

There is **no** ranked feed, **no** Registry/Group tab, **no** standalone chat tab.

## 6. Relay model

### 6.1 Manual forwarding

- Person-to-person, one or many recipients.
- Each forward carries a **personal note**.
- Forward chain visible in beacon context.
- Recipients see **scoped involvement** on the forward screen (committed, declined, watching, already forwarded, etc.).

**Manual relay with shared request-state awareness** — not central auto-routing.

### 6.2 Broadcast

Targeted forwarding is default. Broadcast is escalation, not the norm.

## 7. Inbox vs My Work

- **Inbox** — may need my action, or I am **Watching** without owning execution.
- **My Work** — I **authored** and/or **offered help**.

Offering help moves responsibility into My Work logic. This split prevents collapse into a passive feed.

**Watching** — triaged passive follow; not a third primary card action beside Forward / Not for me. See [`watching-mechanism.md`](watching-mechanism.md).

**Before-response tombstones** — when a beacon closes before I took an explicit stance, the app preserves “never chose” truth. See [`before-response-terminal-tombstone.md`](before-response-terminal-tombstone.md).

## 8. Commit and coordination (open beacon)

### 8.1 Commit is open by default

A **help offer** is a public, explicit action with a note — willingness to act, not mere interest. **Withdraw** is explicit and visible.

### 8.2 Overcommit = coordination, not gatekeeping

The author signals **coverage/fit** via beacon status and **per-offer responses** — not approval/rejection of people. Status includes phases such as: no offers yet, offers awaiting author review, more/different help needed, enough help in motion.

New offers are **not blocked** by “enough help” — the author coordinates openly.

### 8.3 Beacon detail + Room

Beacon detail: **Items**, **People**, **Log** + coordination header (STATUS / NOW / YOU / ACT).

**Room** — separate workspace for admitted helpers: messages, plan/ask/blocker/promise/resolution items, scoped facts. Room-private content does not leak to non-members on public beacon surfaces. See [`features/beacon_room.md`](features/beacon_room.md).

**No comment thread** on the beacon — deliberate anti-forum stance.

## 9. Post-close review

Framing: **“Acknowledge contributions / Close the loop”** — not public 360° review.

- Opens after **successful author closure**; bounded **review window**.
- Role-specific prompts (author / helper / forwarder on winning path).
- Raw reviews **private**; evaluated users see **beacon-local summaries** only.
- **No basis to judge** is explicit; strong ratings need reasons.
- Principles and no-go rules: [`beacon-evaluation-principles.md`](beacon-evaluation-principles.md).

Contest/dispute flows in principles are **north-star safeguards**; full contest UX may trail closure/review v1.

## 10. MeritRank (current interpretation)

**Not:** public rank, office legitimacy, universal goodness score.

**Is:** hidden procedural layer affecting who I see, who I can forward to, routing weight, queue ordering, and local trust calibration after closure.

> MR affects **scope, friction, routing, and evidentiary weight**, not sovereign power.

Users can override MR-derived recommendations with scoped consequences.

## 11. Visibility

Forwarding does **not** create general social visibility. Visibility is bounded by MR and relation to the specific beacon/path.

Anti-pattern: “I saw content, therefore a social tie was created.”

## 12. Longer-term ontology (not v1)

Signal / Case / Probe / Care Thread remain conceptual north stars. v1 **compresses** into beacon + Room coordination.

Repair loop: `NEED → RELAY → COMMIT → VERIFY → CLOSE`.

Morphogenesis loop (`AIM → PROBE → CANONIZE`) is strategic context, **not v1 commitment**.

## 13. Go-to-market wedge

**Replace chat chaos with trusted relay for scarce local help, tools, and time** — not “a new social network.”

Good early environments: neighborhood chats, cohousing/campus, repair/maker circles.

## 14. Explicit unresolved questions

- Balance between continuous fabric and bounded execution contexts;
- Exploration without feed logic;
- Anti-lock-in damping;
- Treasury across resource classes;
- When/if beacon splits into richer ontology objects;
- Full evaluation contest UX vs principles-only safeguards.

## 15. Superseded assumptions

Treat as legacy unless deliberately revived:

- main **feed** as primary surface;
- **Registry/Group** tab;
- **comments** as default substrate;
- **contexts** as v1 organizing abstraction;
- visible social ranking / quote surfaces;
- **1:1 chat** as core product;
- forwarding as ordinary content distribution;
- separate `coordination_status` field (merged into unified **beacon status** in product copy).

## 16. Short version

> Feedless, inbox-driven, MR-scoped human relay for requests: manual forwarding, relational visibility, open help offers, overcommit solved through coordination metadata and Room work, closure producing private contribution traces, MeritRank hidden as procedural routing — with beacon detail (Items/People/Log) and an admitted **Room** for execution coordination.
