# Tentura Beacon Room Semantic Coordination Design

## Purpose

Tentura is a feedless, trust-scoped coordination substrate. It is not a social network, messenger, project-management board, or generic task app.

A Beacon turns a situated need into a temporary coordination cell. The Beacon Room provides warm human communication, but important messages can be promoted into typed coordination objects that mutate shared state.

Core product rule:

```text
Chat remains easy.
State remains explicit.
Important work lives in typed objects, not in scrollback.
```

## Core screen model

```text
Beacon
├─ NOW      // shared current situation
├─ YOU      // what this means for me
├─ People   // who is involved and in what state
├─ Room     // warm chat + semantic state inserts
├─ Items    // Plan / Ask / Blocker / Resolution with local threads
└─ Log      // brief chronological log of semantic actions only
```

The Room is the control surface. Item threads hold execution detail. The main Room receives semantic deltas, not all raw detail.

## Main design invariant

Every coordination object must answer:

```text
What is happening?
Who is involved?
What is expected next?
How will we know it is resolved?
```

If it does not answer these, it is probably just a message.

## Minimal v1 object vocabulary

Use one generic internal entity:

```text
CoordinationItem
```

with four variants:

```text
plan        // shared orientation: what are we doing now?
ask         // request for action/input/confirmation from someone
blocker     // obstacle preventing progress
resolution  // explicit claim that something is done/resolved/closed
```

Avoid expanding v1 into separate Fact, Decision, Evidence, Risk, Route, Milestone, Subtask, Protocol Note, etc. These may become metadata or later specializations.

## Persisted item model

No persisted draft states. Drafting happens inside UI sheets only. A CoordinationItem exists only after confirmation.

```text
CoordinationItem
├─ id
├─ beacon_id
├─ type: plan | ask | blocker | resolution
├─ status: open | resolved | cancelled | superseded | stale | rejected
├─ text
├─ created_by
├─ target_user_id?        // mostly for ask
├─ linked_message_id?
├─ linked_item_id?        // resolution targets ask/blocker/plan-step/etc.
├─ visibility: room | public
├─ created_at
├─ updated_at
└─ stale_after?
```

Recommended derived states:

```text
BeaconState:
  active | blocked | enough_help | closed | cancelled | expired

ParticipantState:
  watching | offered_help | involved | asked | waiting | blocked | done | withdrawn
```

Do not over-persist derived status if it can be computed cleanly from open items and participations.

## Naming: disambiguate participation from promise

Do not use `commit` ambiguously.

Beacon-level participation and item-level obligation are different speech acts.

```text
Beacon-level action: OfferHelp
Ask-level action:    AcceptAsk
```

User-facing labels:

```text
Beacon CTA:  Offer help
Ask CTA:     I’ll do this
```

Internal model:

```text
BeaconParticipation
├─ beacon_id
├─ user_id
├─ role: author | helper | watcher | forwarder | verifier
├─ state: offered | involved | withdrawn | completed
├─ offer_note?
└─ capabilities?
```

```text
AskAcceptance / WorkPromise
├─ ask_id
├─ accepted_by
├─ state: accepted | in_progress | resolved | withdrawn
├─ note?
├─ expected_by?
└─ resolution_id?
```

Rule:

```text
AcceptAsk implies BeaconParticipation.
OfferHelp does not imply AcceptAsk.
```

Avoid these names:

```text
Commit
Commitment
TaskCommit
BeaconCommit
Assignment
```

## Semantic actions

Minimal v1 semantic actions:

```text
UpdatePlan
CreateAsk
OpenBlocker
CreateResolution
AcceptAsk
DeclineAsk
CancelAsk
ResolveAsk
ResolveBlocker
SupersedePlan
CloseBeacon
OfferHelp
WithdrawHelp
```

Normal messages do not mutate state. Semantic actions do.

Rule:

```text
RoomMessage changes Room.
SemanticAction changes CoordinationItem / BeaconState / ParticipantState.
Activity records semantic changes only.
```

No silent AI-created obligations. AI or heuristics may suggest semantic actions, but users must confirm.

## Object transitions

### Plan

```text
Plan published
→ CurrentPlan updated
→ NOW updated
→ may create Ask
→ may reveal Blocker
→ may remain current
→ later replaced / superseded / completed
```

Plan is shared orientation, not a task list. It should be short, attributed, and supersedable.

### Ask

```text
Ask opened
→ target sees “Asked of you”
→ target responds:
   answer
   accept
   decline
   redirect
   request clarification
   no response → stale

answer → sufficient? → resolved / clarification needed
accept → waiting / in progress → resolution or blocker
stale → remind / re-ask / cancel
```

Ask is a request, not an assignment. Others may ask; the target accepts, declines, redirects, or asks for clarification.

### Blocker

```text
Blocker opened
→ Beacon may become blocked
→ NOW shows open blocker
→ affected people marked blocked/waiting
→ unblock path:
   need information → Ask
   someone must act → Ask
   plan wrong → UpdatePlan
   already solved → Resolution
   impossible/irrelevant → cancel blocker

Resolution targeting blocker
→ blocker resolved
→ if no open blockers remain, Beacon returns active
```

Blocker is a shared error signal, not a complaint. It must be explicit, attributed, and resolvable.

### Resolution

```text
Resolution created
→ target chosen:
   Ask
   Blocker
   Plan step
   Whole Beacon
   Message only

accepted → linked object closed/resolved
rejected → linked object remains open
needs proof → Ask / clarification
whole beacon valid → Beacon closed / partially closed / remains active / disputed
```

Resolution is not automatically trusted. It can be accepted, rejected, or require proof.

## Item threads vs main Room

Every Ask and Blocker should have a local thread.

```text
Main Room:
  orientation
  cross-cutting state changes
  emotional/social glue
  high-level blockers
  plan changes
  closures

Item thread:
  execution detail
  micro-clarifications
  photos/proofs
  partial progress
  small back-and-forth
```

When a thread produces a meaningful change, post a semantic delta to the Room:

```text
Ask resolved: demo posts created.
Blocker opened: login email rejected for creacl.co.
Plan updated: optimization after joint-document release.
```

Do not repost raw thread replies to the main Room.

Slack-style `also send to channel` should become:

```text
Post semantic update to Room
```

not:

```text
Copy this reply to Room
```

## Anti-flood mechanics

When a message appears related to an open item, suggest linking it:

```text
This looks related to: Ask: Prepare demo content
[Move to item thread] [Keep in Room]
```

For v1 this can be manual:

```text
Every Ask / Blocker card has:
[Discuss] [Resolve] [Cancel]
```

Strong rule:

```text
Main Room is not the container for all coordination.
Main Room is the shared operational picture.
```

## NOW / YOU behavior

NOW card should summarize global state:

```text
current plan
open blocker, if any
enough/more help state
last meaningful change
```

YOU card should summarize personal state:

```text
my role
asks directed to me
accepted asks / promises
things waiting on me
things I am waiting for
quick actions
```

People view should summarize per-person local state:

```text
role
participation state
asked / waiting / blocked / done / withdrawn
last meaningful update
linked open items
```

## Activity and Log

Activity is the canonical semantic event source, not all chat.

Log is the user-facing view of Activity. Log entries are brief, human-readable semantic events derived from Activity records.

Record in Activity:

```text
plan_updated
ask_opened
ask_accepted
ask_declined
ask_resolved
ask_cancelled
blocker_opened
blocker_resolved
blocker_cancelled
resolution_created
beacon_closed
help_offered
help_withdrawn
```

Show in Log as concise readable entries, for example:

```text
Plan updated by Julia
Ask opened for Dmitry: prepare demo content
Blocker resolved: login email rejected for creacl.co
Beacon closed by author
```

Do not dump ordinary Room messages into Activity or Log.

## UI language

Use social, non-managerial wording.

Prefer:

```text
Offer help
I’ll do this
Asked of you
Waiting on
Can you?
You offered to
No longer needed
Resolved
Withdraw
```

Avoid:

```text
Assigned to you
Task owner
Overdue
Failed
Required
Must
Manager
Ticket
```

Reason: Tentura should create clarity without managerial authority.

## Creation UX

Keep creation sheets tiny.

Ask sheet minimal fields:

```text
What is needed?
Who is asked?
What counts as done?
Due/stale time? optional
Why? optional
```

Blocker sheet:

```text
What blocks us?
What is affected?
Who can unblock / what is needed? optional
Stale/escalation time? optional
```

Resolution sheet:

```text
What is resolved?
Optional proof / note
```

Plan update sheet:

```text
New current plan
Optional reason
```

No mandatory heavy forms except where ambiguity would break coordination.

## Staleness

All open operational items should be able to become stale.

```text
open → stale → remind | re-ask | cancel | supersede
```

Staleness is not blame. It means the shared state needs attention.

### v1 implementation note (2026-06)

Shipped v1 **derives** staleness from `stale_at` + active status (`open` / `accepted`) instead of persisting `status: stale`. Default follow-up is **3 days** at publish (configurable in the composer). **Remind** sends a private FCM nudge to the status-aware responsible person, throttled 24h via `last_reminded_at`; there is **no** public room timeline event for reminds. `re-ask` / supersede-from-stale remain follow-ups.

## State authority and reversibility

State-changing actions are power moves. Therefore:

```text
All state changes are attributed.
All state changes appear in Activity.
All state changes can be superseded or contested.
No AI silently changes shared state.
```

Plan and blocker changes especially must be visible and reversible.

## Post-close review

After successful or partial closure, optionally open a private contribution acknowledgement flow.

Rules:

```text
local to beacon
private by default
role-specific prompts
No basis distinct from neutral
strong ratings require reason tag
no public score
no leaderboard
```

Frame as:

```text
Acknowledge contributions / Close the loop
```

not:

```text
Reputation review / 360 rating
```

## Failure modes to design against

### 1. Telegram-with-forms

Symptom: users still coordinate in main chat; semantic items are after-the-fact bureaucracy.

Countermeasure: one-tap promotion, item threads, NOW/YOU summaries.

### 2. Slack-clone drift

Symptom: channels, threads, tasks, AI summaries, but no primary coordination object.

Countermeasure: Beacon and CoordinationItem are primary; chat is attached.

### 3. Thread burial

Symptom: details are contained but shared state is invisible.

Countermeasure: every item thread updates NOW/YOU/People/Activity through semantic deltas.

### 4. Jira-ification

Symptom: people feel assigned, monitored, and judged.

Countermeasure: use Ask/Offer/Resolve language, not task/assignment language.

### 5. Ambiguous acceptance

Symptom: “ok” could mean seen, understood, accepted, or done.

Countermeasure: model Ask response states explicitly.

### 6. Stale object rot

Symptom: asks and blockers remain open forever.

Countermeasure: stale_after, reminders, cancel/supersede paths.

### 7. False urgency / panic abuse

Symptom: “everything broken, urgent” later turns out to be demo-prep failure.

Countermeasure: blockers require scope/evidence/workaround and can resolve as false alarm/process issue.

### 8. External-channel leakage

Symptom: people say “let’s just do this in Telegram.”

Countermeasure: preserve warm chat, photos, files, and social repair, but make operational consequences easier inside Tentura.

### 9. Ontology creep

Symptom: every edge case becomes a new object type.

Countermeasure: keep v1 to Plan / Ask / Blocker / Resolution.

### 10. Review anxiety

Symptom: users fear hidden scoring.

Countermeasure: private, local, contribution-oriented acknowledgement; no public reputation surfaces.

## Hard constraints for implementation LLM

Do:

```text
- Treat Beacon as the temporary coordination cell.
- Treat CoordinationItem as the core Room object.
- Keep Plan / Ask / Blocker / Resolution as the only v1 item types.
- Give every Ask and Blocker a local thread.
- Promote only semantic deltas to main Room.
- Keep all state changes explicit, attributed, and reversible/supersedable.
- Use OfferHelp for beacon-level participation.
- Use AcceptAsk for item-level promise.
- Make AcceptAsk imply BeaconParticipation.
- Keep ordinary chat available.
```

Do not:

```text
- Use Commit ambiguously.
- Create persisted draft CoordinationItems.
- Build generic DM outside beacon context.
- Make the Room a general channel.
- Add public reputation or leaderboards.
- Silently infer obligations from text.
- Dump all messages into Activity.
- Add heavy task-management vocabulary.
- Add many item types in v1.
```

## Minimal v1 flow

```text
Message / note
→ user promotes to Plan | Ask | Blocker | Resolution
→ item appears in Room and relevant card/thread
→ item updates NOW / YOU / People if relevant
→ execution details stay in item thread
→ accepted/resolved/cancelled/superseded semantic deltas appear in Room
→ Activity records semantic history
→ Beacon closes
→ optional private contribution acknowledgement
```

## One-sentence product definition

Tentura Beacon Room is a warm chat surface wrapped around typed, lightweight coordination objects, where Plan, Ask, Blocker, and Resolution maintain a shared operational picture without turning cooperation into bureaucracy.

