# Tentura — current status quo of design and decisions

This document compresses the current design direction of Tentura. It is meant to supersede older feed-centric and context-centric descriptions where they conflict with the points below.

## 1. Core reframe

Tentura is not being designed as a social network, a public forum, or a reputation-driven feed. It is a graph-native coordination substrate whose job is to keep the social fabric continuous without overheating it.

The key strategic shift is away from maximizing connectivity and engagement. The target is selective percolation: enough connectivity for help, discovery, and coordination to propagate, but with inhibitors against redundant closure, corridor concentration, broker capture, and the conversion of the whole system into one public stage.

Working metaphor: **reactor, not bomb**.

## 2. Main design axioms

- **No public feed.** Do not create one common stage where everything competes for visibility.
- **No global reputation score.** MeritRank is subjective and procedural, not a public status ladder.
- **No automatic connectivity maximization.** The system should preserve useful paths, not maximize ties.
- **Selective visibility over universal visibility.** Visibility must remain scoped, relational, and path-dependent.
- **Local memory over global social truth.** The system should preserve useful continuity without turning into a dossier machine.
- **Protocols over discourse.** The primary unit is a coordination object with explicit state transitions, not open-ended discussion.

## 3. Most important turning point

Older Tentura iterations assumed a feed/discovery surface, comments, contexts, and broader social-network behavior. The current direction rejects that product logic.

The most important shift is:

> Tentura v1 is now a **feedless, inbox-driven, MR-scoped human relay system for requests**.

This is the decisive simplification. It means:

- the app is no longer trying to be a new Twitter/Facebook/Reddit;
- virality is not the main primitive;
- discovery is secondary and bounded;
- forwarding is more important than posting;
- coordination state is more important than discussion volume.

## 4. Current v1 object model

### 4.1 Beacon is the only first-class object in v1

For v1, **beacon** is the only primary object.

A beacon is a request / need / task-like object that can be forwarded, committed to, updated, and closed. It is deliberately narrower than the longer-term ontology.

### 4.2 Explicitly out of scope for v1

The following are deliberately deferred:

- groups and membership machinery;
- governance roles and constitutional processes;
- treasury / fund logic;
- appeals / jury / steward systems;
- care-thread machinery;
- signal/case/probe split as separate first-class objects;
- comments under beacons;
- public reputation surfaces;
- complex commons institutions.

These are not rejected in principle. They are postponed so that v1 can validate the relay model cleanly.

## 5. Current v1 surface model

Bottom-level mental model:

- **Inbox** = what needs my attention now;
- **My Work / Requests** = what I started or committed to;
- **Group / Registry** = shared pull-based list of active objects, not a ranked feed;
- **Network** = reachable people / groups / forwarding targets;
- **Profile** = capabilities, availability, settings.

The important distinction is between **push** and **pull**:

- **Inbox** is push: items explicitly brought to me.
- **Registry** is pull: a shared index/state view, not an engagement-optimized stream.

## 6. Relay model: the core operational primitive

### 6.1 Manual forwarding replaced algorithmic routing

The default delivery model is no longer auto-routing.

Instead:

- requests are forwarded manually, person to person;
- forwarding can target one or several recipients;
- forwarding preserves the chain;
- every forward carries a personal note;
- the forward chain remains visible in beacon detail.

The key idea is **manual relay with shared request-state awareness**.

When Alice forwards a beacon to Bob and Carol, Bob does not operate in the dark. For that specific beacon, Bob can see scoped statuses such as who has already committed, forwarded, declined, or cannot help. That reduces duplicate work and lets the network learn routing socially, through repeated use, rather than through central dispatch.

### 6.2 Broadcast is an escalation path, not the default

The default is targeted forwarding. Broadcast exists only for escalation or exceptional cases.

## 7. Responsibility split: Inbox vs My Work

This split is now structurally important.

- **Inbox** contains items that may need my action or that I am merely watching.
- **My Work** contains beacons I authored and/or committed to.

When I commit to a beacon, it moves out of passive triage logic and into explicit responsibility.

This split prevents the app from collapsing back into a feed or a passive watchlist.

## 8. Commit model

### 8.1 Commit is open by default

Ordinary commits do not require pre-approval.

A commit is a public, explicit action with a note. It signals real willingness to act, not merely interest.

### 8.2 Uncommit exists and is visible

The system acknowledges that commitments can change. Retreat must be explicit, not hidden.

### 8.3 Overcommit is handled by coordination metadata, not permissioning

Instead of forcing commit approval, Tentura surfaces coordination state.

Author-level request states may include:

- `No commitments yet`
- `Commitments waiting for review`
- `More or different help needed`
- `Enough help committed`

Per-commit coordination labels may include:

- `Useful`
- `Overlapping`
- `Need different skill`
- `Need coordination`
- `Not suitable`

This is a major philosophical choice: solve overcommit as coordination, not as gatekeeping.

## 9. Beacon detail is not a discussion thread

Comments are removed from v1.

Beacon detail is now intentionally narrow. It should show only:

- author updates;
- commit notes;
- forward notes;
- timeline;
- forward-chain graph.

This is a deliberate anti-forum move. Tentura should not drift into discourse-first behavior.

## 10. Post-close review model

### 10.1 Review is local, private, and contribution-oriented

The framing is **“Acknowledge contributions / Close the loop”**, not reputation management and not public 360 review.

### 10.2 Narrow review scope in phase 1

Only the following are in scope:

- author;
- committers;
- only the forwarder(s) directly adjacent to successful committers on the winning path.

Dead branches, failed closures, disputed cases, and broader participant sets are excluded in phase 1.

### 10.3 Trigger and output

Review opens only after successful author closure.

- committers then see `ready_for_review` in My Work;
- prompts are role-specific for author / committer / forwarder;
- raw reviews are private by default;
- there are no public scores or leaderboards;
- evaluated users receive only a private, beacon-local summary;
- `No basis` is explicit and distinct from neutral;
- strong ratings require reason tags.

This keeps post-close learning without turning Tentura into a visible prestige market.

## 11. MeritRank: current interpretation

The role of MeritRank has become narrower and more disciplined.

It is **not**:

- a public rank;
- office legitimacy;
- a universal goodness score;
- a replacement for institutions.

It **is** a hidden procedural layer that affects:

- who I can see;
- who I can forward to;
- whose relay / commit / verify is weighty for me;
- whether an action is self-sufficient or needs co-sign / extra friction;
- how queueing and triage are ordered;
- which next counterparty is most plausible;
- how post-close updates modify my local trust / utility graph.

The right summary is:

> MR should mostly affect **scope, friction, routing, and evidentiary weight**, not sovereign power.

A user must still be able to override their own MR-derived recommendation, but with scoped consequences rather than absolute immunity.

Manual endorsement/surety edges may exist later, but must stay separate from observed work/utility edges.

## 12. Visibility model

Visibility is not caused by forwarding itself. Forwarding does not create general social visibility.

Visibility is bounded by personalized MR and relation to the specific beacon/path. This matters because the system is trying to preserve a continuous social fabric without generating indiscriminate graph closure.

The important anti-pattern is: “I saw content, therefore a social tie was effectively created.” Tentura is trying to avoid that.

## 13. Longer-term ontology beyond v1

The fuller conceptual model is still useful, but it is **not** the current v1 object model.

The longer-term ontology currently looks like this:

- **Signal** = weak pre-case friction (`Blocked`, `Ask for Help`, `Protocol Check`);
- **Case** = concrete repair object around a real gap in the world;
- **Probe / Aim** = a small experiment toward a future form or new rule;
- **Care Thread** = typed continuity log around a subject-in-context;
- **Beacon** = current v1 simplification that temporarily compresses much of this.

Important distinction:

- **Signal layer** catches weak signals early.
- **Case layer** closes concrete gaps.
- **Probe layer** tests future forms.
- **Care layer** preserves continuity between episodes.

The current system is intentionally collapsing most of this into beacon-centric v1. That simplification is tactical, not theoretical.

## 14. Repair loop vs morphogenesis loop

A major conceptual insight from recent work is that the current five-step repair logic is not enough.

### 14.1 Repair loop

Current operational loop:

`NEED -> RELAY -> COMMIT -> VERIFY -> CLOSE`

This is the immune / repair loop. It fixes tears in the fabric.

### 14.2 Missing layer: morphogenesis

A system that only repairs gaps does not generate a future form. It maintains a minimum, but it does not create a shared attractor.

Therefore the next conceptual extension is:

`AIM -> JUSTIFY -> PROBE -> VERIFY -> CANONIZE / DROP`

Where:

- **AIM** defines a desired next state of the commons;
- **JUSTIFY** gives a plural, contestable rationale;
- **PROBE** runs a reversible experiment;
- **VERIFY** checks effect;
- **CANONIZE / DROP** either stabilizes the new pattern or discards it.

This is the bridge from repair to morphogenesis.

Current stance: this is strategically important, but **not a v1 feature commitment**.

## 15. Continuous fabric vs bounded groups

A major synthesis emerged here.

Earlier thinking leaned toward cells / groups / federation as primary.
Current thinking treats **continuous social fabric** as primary, while still recognizing that bounded execution contexts are necessary.

Best current synthesis:

- the fabric is continuous;
- bounded groups are local execution / treasury / appeal / support contexts inside that fabric;
- between groups, what should travel is not giant discourse, but tested forms, summaries, closures, and portable rules.

So federation, if it exists, is for **protocol compatibility and exchange of forms**, not for building a giant public square.

## 16. Resource allocation thesis

A strong design thesis emerged for rival, non-storable, access-like resources.

For some classes of goods, **MR-based priority ordering may be enough to replace token logic**.
Examples:

- shared tools;
- time/help/services;
- vehicle slots;
- immediate local energy windows;
- scarce access rights.

But pure priority ordering is insufficient by itself. The real risk is not moral unfairness; it is lock-in and metabolic stagnation.

Therefore allocation for these resource classes should eventually be:

- MR priority,
- plus exploration lane,
- plus upkeep/provision weight,
- plus challenge/error-correction path,
- plus anti-lock-in memory over time.

The key problem is discovering “Alex,” the better new path, instead of endlessly reusing incumbent “Petya.”

## 17. Commons / institutional layer (later, not v1)

If Tentura goes beyond relay-v1 into an actual commons operating system, the minimal viable social unit is no longer “social network for everyone” but a **small local commons with a concrete reproduction loop**.

Likely ingredients:

- bounded circle of roughly 30–150 people;
- rotating stewards rather than permanent admins;
- small local arbitration;
- some explicit material substrate / fund;
- hidden MR separated into different procedural reliabilities rather than one global score.

This remains longer-horizon architecture, not present product scope.

## 18. Go-to-market consequence

Tentura should not launch as a “new social network.”

The strongest wedge remains: **replace chat chaos with trusted relay for scarce local help, tools, and time**.

Good early environments:

- apartment / street / neighborhood chats;
- cohousing / dorm / campus communities;
- repair / tool / maker circles.

Why this wedge fits:

- pain is frequent;
- value is visible quickly;
- resources are rival and often non-storable;
- existing chat channels are already failing at this job;
- relay + scoped trust is more useful here than a feed.

## 19. Explicit unresolved questions

These remain genuinely open and should not be accidentally treated as solved:

- exact balance between continuous fabric and bounded execution contexts;
- exact exploration mechanism without reintroducing feed logic;
- anti-lock-in damping formula;
- treasury logic across mixed resource classes;
- inter-group layer at scale;
- care-thread visibility / contestability policy;
- liability and mechanics of endorsement/surety edges;
- whether and when the v1 beacon should split back into signal/case/probe/care objects.

## 20. Superseded assumptions from older design docs

The following ideas from older Tentura materials should be treated as legacy unless later reintroduced deliberately:

- main feed as primary app surface;
- discovery as central growth mechanic;
- comments as default discussion substrate under objects;
- contexts as the main organizing abstraction for v1;
- visible social-ranking or “quotes” surfaces as core UX;
- assumption that forwarding/reposts can safely function like ordinary content distribution.

They may still contain useful local ideas, but they no longer define the product.

## 21. Short version

Tentura is currently best understood as:

> a feedless, inbox-driven, MR-scoped human relay system for requests, where forwarding is manual, visibility is relational, commit is open, overcommit is solved through coordination metadata rather than permissioning, closure produces private contribution traces rather than public reputation, and MeritRank stays hidden as a procedural routing layer.

The next conceptual step beyond this is not “better feed ranking,” but the addition of a second loop:

> repair (`NEED`) plus morphogenesis (`AIM/PROBE`).

That is the current status quo.
