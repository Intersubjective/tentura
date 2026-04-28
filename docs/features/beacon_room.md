# Tentura Beacon Room — Feature Specification for LLM Implementation

## Context

The current Beacon screen has this high-level structure:

```text
Beacon (single)
│
├─ Orientation
│  ├─ What it is (title, identity)
│  ├─ Who’s behind it (author → profile)
│  └─ Why it exists (need / context at a glance)
│
├─ Relationship & state
│  └─ “Where I stand” strip (commit / watch / inbox / coordination cues)
│
├─ Primary actions
│  ├─ Author: status / post update
│  ├─ Participant: commit · withdraw (rules)
│  └─ Everyone: forward · view chain (when relevant)
│
├─ Deep actions (overflow / dialogs)
│  ├─ Author: edit · close/unlist · delete · share
│  ├─ Participant: inbox paths (watch / stop / can’t help / unreject)
│  └─ Escalations: complaint · graphs
│
└─ Three lenses (same beacon, different depth)
   ├─ Overview      → need · coordination story · context & media
   ├─ People        → who’s in · roles · statuses · expected moves
   └─ Activity      → timeline of what changed
```

The new feature adds a **Room screen/mode**, not a fourth tab. The existing Beacon screen keeps its three tabs: **Overview**, **People**, and **Activity**. Room is opened from the Beacon screen as a separate coordination mode.

The purpose is not to turn Beacon into a forum. The purpose is to prevent coordination from escaping into Telegram/WhatsApp while preserving Beacon as a coordination object.

Core product idea:

```text
Beacon = visible coordination object
Room = involved-only coordination mode
Public entries = visible to everyone who can see the Beacon
Room entries = visible only to involved/admitted people
Semantic actions = explicit user actions that mutate Beacon/Room/People state
Activity = clean history of meaningful state changes, respecting visibility
```

## Product principle

Goal:

```text
Unblock social action by reducing ambiguity / ambage.
```

Each participant should quickly understand:

```text
What is this Beacon?
What is publicly known?
Am I involved or merely seeing/forwarding it?
If involved, what is the current plan?
What is expected of me?
What changed because of my / others’ actions?
```

The Room supports normal emotional/social chat, but the state layer prevents important coordination facts from being buried.

Do not infer state changes from arbitrary chat text. Without AI, state changes must be explicit and deterministic.

## Core visibility model

There are exactly two visibility categories for entries/state.

### 1. Public / Beacon-visible

Visible to everyone who can see the Beacon through normal Beacon visibility rules.

Examples:

```text
Beacon title
Beacon description / need
Author
Public status / outward need signal
Public fact cards
Forwarders / forwardees / visible path provenance
Public media/context chosen by author
Public Activity events
```

Public does **not** mean Internet-public. It means visible to the Beacon’s normal audience: recipients, visible path actors, and users who can see the Beacon under existing MR/path visibility rules.

### 2. Room / involved-visible

Visible only to people admitted into the Room.

Examples:

```text
Room chat
Current plan
Private fact cards
Detailed blockers
Next expected moves
Detailed participant statuses
Need-info requests
Room system inserts
Private Room activity/state changes
```

Room-visible information should not leak into Inbox, Forward, Overview, People, or Activity for non-room users.

## Minimal roles

```text
Author
Beacon Steward
Room member / involved person
Candidate helper
Watcher / recipient / forwarder
```

### Author

The Beacon creator. Always has full control over Room admission and Beacon closure.

### Beacon Steward

A person promoted by the author to help coordinate the Beacon.

Steward can:

```text
approve / reject help offers
admit people into Room
manage Room-visible state
pin facts
update Room plan
mark blockers / done / need info
```

Steward cannot:

```text
delete the Beacon
transfer authorship
change author-only destructive settings
promote another steward unless explicitly allowed later
```

### Room member / involved person

A person admitted by Author or Steward.

Room member can:

```text
read/write Room messages
see Room plan
see private fact cards
see detailed blockers and next moves
use semantic actions according to permissions
```

### Candidate helper

A person who offered help but has not yet been approved/admitted.

Candidate helper can:

```text
see the Beacon public surface
send an offer/help note to Author/Steward
wait for approval
withdraw the offer
```

Candidate helper cannot see Room-private content until admitted.

### Watcher / recipient / forwarder

A person who can see or forward the Beacon but is not involved in Room coordination.

## Commit / help model

The old “commit is open” model must be adjusted because Room access is private and involved-only.

New minimal rule:

```text
Offering help is open.
Becoming committed/involved requires approval by Author or Beacon Steward.
```

Use this flow:

```text
User taps Offer help / Commit
├─ enters short note: what they can do
├─ becomes Candidate helper
├─ Author/Steward receives approval prompt
├─ Author/Steward chooses:
│  ├─ Admit to Room
│  ├─ Keep as candidate / ask clarification
│  ├─ Not needed now
│  └─ Decline / remove
└─ if admitted:
   ├─ user becomes Room member
   ├─ participant status = checking / committed
   └─ Beacon moves to My Work for that user
```

Avoid heavy approval UX. This should feel like admitting someone into the working room, not like bureaucratic permissioning.

## Public outward state vs Room internal state

To avoid leaking private coordination details, maintain two state layers.

### Public Beacon status / outward signal

Visible to Beacon-visible users.

Minimal values:

```text
Open
Help being coordinated
More / different help needed
Enough help for now
Closed
```

Optional compact public blocker state:

```text
Blocked
```

Use `Blocked` publicly only if the author/steward explicitly chooses to expose that the Beacon is blocked. Do not expose blocker details by default.

### Room internal state

Visible only to Room members.

```text
current_plan
open blockers with details
private facts
participant statuses
next expected moves
need-info cards
```

## Updated Beacon structure

Room should **not** be added to the Beacon tab bar. The Beacon screen remains structurally stable: Orientation, Relationship & State, Primary Actions, Deep Actions, and three tabs.

Room is entered through explicit affordances:

```text
Open Room button, for admitted Room members
Room access pending cue, for candidates
Unread/needs-me cue in “Where I stand” strip, for Room members
Latest Room cue in Overview, for Room members only
Person actions in People: mention in room / ask info, for Room members
Notification deep link, for Room members
```

```text
Beacon (single)
│
├─ Orientation
│  ├─ What it is
│  │  ├─ title
│  │  ├─ icon / image / media cue
│  │  └─ public status: open / coordinating / more help / enough help / closed
│  │
│  ├─ Who’s behind it
│  │  └─ author → profile
│  │
│  └─ Why it exists
│     ├─ public need / context at a glance
│     └─ public fact highlights, if any
│
├─ Relationship & state
│  ├─ “Where I stand” strip
│  │  ├─ my relation: recipient / watching / candidate / involved / author / steward
│  │  ├─ room access: none / requested / admitted / muted
│  │  ├─ my next expected move, if admitted
│  │  └─ quick cue: needs me / room unread / offer pending / closed
│  │
│  └─ Public status strip
│     ├─ outward signal: open / coordinating / more help / enough help / closed
│     ├─ public fact count / highlights
│     └─ last public meaningful change
│
├─ Primary actions
│  ├─ Author
│  │  ├─ update public status
│  │  ├─ post public update
│  │  ├─ open room
│  │  └─ manage room access
│  │
│  ├─ Steward
│  │  ├─ open room
│  │  ├─ manage room access
│  │  ├─ update public status
│  │  └─ pin fact / update plan from Room
│  │
│  ├─ Candidate / participant
│  │  ├─ offer help / request admission
│  │  ├─ withdraw offer / withdraw commitment
│  │  ├─ open room, if admitted
│  │  └─ mark done / need info, if admitted
│  │
│  └─ Everyone
│     ├─ forward
│     ├─ view chain
│     └─ watch / stop watching
│
├─ Deep actions
│  ├─ Author
│  │  ├─ edit
│  │  ├─ close / unlist
│  │  ├─ delete
│  │  ├─ share
│  │  ├─ manage room access
│  │  └─ promote / remove Beacon Steward
│  │
│  ├─ Steward
│  │  ├─ manage room access
│  │  ├─ approve / decline candidates
│  │  └─ mute / leave room
│  │
│  ├─ Participant
│  │  ├─ watch
│  │  ├─ stop
│  │  ├─ can’t help
│  │  ├─ unreject
│  │  ├─ leave room
│  │  └─ mute room
│  │
│  └─ Escalations
│     ├─ complaint
│     └─ graphs
│
├─ Three tabs
│  ├─ Overview
│  │  ├─ public need
│  │  ├─ public status / outward signal
│  │  ├─ public fact cards
│  │  ├─ context & media
│  │  ├─ latest Room cue only for Room members
│  │  └─ open/request room CTA depending on access
│  │
│  ├─ People
│  │  ├─ author
│  │  ├─ steward(s)
│  │  ├─ public visible people / provenance
│  │  ├─ candidates / offers, visible to author/steward
│  │  ├─ involved people, visible to Room members
│  │  └─ room access state, respecting visibility
│  │
│  └─ Activity
│     ├─ public timeline for non-room viewers
│     ├─ public facts pinned
│     ├─ public status updated
│     ├─ forwarded
│     ├─ offer submitted / admitted, if visibility permits
│     ├─ closed / review opened
│     └─ Room-private activity visible only to Room members
│
└─ Separate Room mode / screen
   ├─ opened from Beacon
   ├─ compact Beacon header
   ├─ Room-private NOW/YOU strips
   ├─ involved-only chat
   ├─ semantic message actions
   ├─ public/private fact pinning
   ├─ blocker / next-move cards
   └─ returns back to same Beacon tab/state
```

## Room mode purpose

The Room is the involved-only coordination mode attached to a Beacon. It lets admitted people talk, attach media, ask questions, pin facts, update the private plan, and convert important messages into state.

Room is a separate screen/mode, not a tab inside the Beacon tab bar.

The Room must not become a public comment section. It is:

```text
beacon-scoped
temporary / operational
visible only to involved/admitted people
state-coupled
separate from public Activity
```

The Room should feel like chat, but with a small number of state-changing affordances.

## Room screen/mode structure

Room opens as a full-screen route or modal mode from Beacon. It preserves enough Beacon context at the top, but optimizes the rest of the screen for chat.

Navigation behavior:

```text
Beacon Screen → Open room → Room Screen/Mode
Room back → returns to same Beacon tab + scroll position when possible
Notification → opens Room directly, with back to Beacon or previous stack
```

```text
Room Screen/Mode
├─ Compact Beacon Header
│  ├─ title
│  ├─ public status: open / coordinating / more help / enough help / closed
│  └─ tap → full Beacon screen
│
├─ Room NOW strip
│  ├─ private current plan
│  ├─ open private blocker, if any
│  ├─ key private/public facts
│  └─ last Room meaningful change
│
├─ YOU strip
│  ├─ your role
│  ├─ your next expected move
│  └─ quick action, if any
│
├─ Chat Stream
│  ├─ user messages
│  ├─ photo/file attachments
│  ├─ emoji reactions
│  ├─ fact cards
│  ├─ blocker / next-move cards
│  └─ system state-change inserts
│
└─ Composer
   ├─ text input
   ├─ attach photo/file
   ├─ send
   └─ optional quick semantic action entry point
```

## Room admission

Room admission is controlled by Author and Beacon Steward(s).

Admission rules:

```text
Author is always admitted.
Beacon Steward is admitted by definition.
A user who offers help becomes Candidate helper.
Candidate helper becomes Room member only after Author/Steward approval.
Committed/involved status requires Room admission.
Forwarding alone never grants Room access.
Watching alone never grants Room access.
```

Approval should be lightweight.

Candidate offer card for Author/Steward:

```text
Alex offered help
“I can fly on Apr 19 and take the cat in cabin.”
[Admit to room] [Ask clarification] [Not needed now]
```

Avoid stigmatizing options like `Not suitable` unless necessary. Prefer:

```text
Not needed now
Need different help
Ask clarification
```

## Minimal semantic actions

Semantic actions in v1:

```text
Update plan
Pin fact card
Mark blocker
Mark done
Need info
```

`Pin fact card` has two visibility variants:

```text
Pin public fact
Pin private fact
```

These actions may be available:

```text
from long-press / overflow on a Room message
from a small action row near selected message
from contextual buttons on fact/blocker/next-move cards
from primary actions when applicable
```

Do not add a large taxonomy such as Evidence, Decision, Risk, Route, Verify, etc. These can be introduced later.

## Message vs state distinction

Every Room interaction affects at least one stream:

```text
Message stream = what people said
State stream = what changed in Beacon/Room/People state
```

Normal message:

```text
Room message created
Unread badge updates for Room members
No BeaconState mutation
No ParticipantState mutation
No Activity event, except optional unread/message count
```

Semantic action:

```text
Room message created or selected
Semantic action applied
Public or private visibility selected when relevant
BeaconState / RoomState / ParticipantState / FactCard mutates
ActivityEvent created with matching visibility
Screens update according to visibility
```

## State objects

### BeaconPublicState

Visible to Beacon-visible users.

```text
BeaconPublicState
├─ status: open | coordinating | more_help_needed | enough_help | closed
├─ public_summary?: string
├─ last_public_meaningful_change?: string
├─ public_fact_count
├─ updated_at
└─ updated_by
```

### RoomState

Visible only to Room members.

```text
RoomState
├─ beacon_id
├─ current_plan: string
├─ open_blocker_id?: string
├─ last_room_meaningful_change?: string
├─ updated_at
└─ updated_by
```

### ParticipantState

```text
ParticipantState
├─ beacon_id
├─ user_id
├─ role
│  ├─ author
│  ├─ steward
│  ├─ helper
│  ├─ candidate
│  ├─ verifier
│  ├─ forwarder
│  ├─ watcher
│  └─ domain-specific role, e.g. carrier / adopter / driver
│
├─ status
│  ├─ watching
│  ├─ offered_help
│  ├─ candidate
│  ├─ admitted
│  ├─ checking
│  ├─ committed
│  ├─ needs_info
│  ├─ blocked
│  ├─ done
│  └─ withdrawn
│
├─ next_move_text?
├─ next_move_source
│  ├─ self
│  ├─ request_from_other
│  ├─ author_suggestion
│  ├─ steward_suggestion
│  └─ system_default
│
├─ next_move_status
│  ├─ active
│  ├─ requested
│  ├─ done
│  ├─ declined
│  └─ obsolete
│
├─ linked_message_id?
├─ room_access_state
│  ├─ none
│  ├─ requested
│  ├─ invited
│  ├─ admitted
│  ├─ muted
│  └─ left
│
└─ updated_at
```

### RoomMessage

Visible only to Room members.

```text
RoomMessage
├─ id
├─ beacon_id
├─ author_id
├─ text
├─ attachments[]
├─ created_at
├─ reply_to_message_id?
├─ linked_blocker_id?
├─ linked_next_move_id?
├─ linked_fact_card_id?
└─ semantic_marker?
   ├─ update_plan
   ├─ pin_fact_public
   ├─ pin_fact_private
   ├─ blocker
   ├─ done
   └─ need_info
```

### FactCard

A pinned operational fact. Can be public or private.

```text
FactCard
├─ id
├─ beacon_id
├─ text
├─ visibility: public | room
├─ pinned_by
├─ source_message_id?
├─ created_at
├─ updated_at?
└─ status: active | corrected | removed
```

Public fact cards appear in Overview, Forward screen, public Activity, and public Beacon-visible surfaces.

Private fact cards appear only inside Room and Room-visible state surfaces.

### Blocker

Room-private by default.

```text
Blocker
├─ id
├─ beacon_id
├─ title
├─ status: open | resolved | cancelled
├─ visibility: room
├─ opened_by
├─ opened_from_message_id
├─ affected_participant_id?
├─ resolver_participant_id?
├─ resolved_by?
├─ resolved_from_message_id?
└─ created_at / resolved_at
```

Do not expose blocker details publicly unless separately converted into a public fact or public status update by Author/Steward.

### ActivityEvent

```text
ActivityEvent
├─ id
├─ beacon_id
├─ visibility: public | room
├─ type
│  ├─ public_status_updated
│  ├─ plan_updated
│  ├─ fact_pinned
│  ├─ fact_corrected
│  ├─ blocker_opened
│  ├─ blocker_resolved
│  ├─ need_info_opened
│  ├─ need_info_answered
│  ├─ participant_status_changed
│  ├─ offer_submitted
│  ├─ candidate_admitted
│  ├─ done_marked
│  ├─ withdrawn
│  ├─ forwarded
│  ├─ closed
│  └─ review_opened
│
├─ actor_id
├─ target_user_id?
├─ source_message_id?
├─ diff
└─ created_at
```

## Current plan visibility

The current plan is **Room-private**.

Rules:

```text
Plan is visible only in Room and only to Room members.
Plan must not appear in public Overview for non-room viewers.
Plan must not appear in Forward screen unless explicitly summarized as public status/fact.
Plan must not appear in Inbox/My Work for non-room users.
```

For non-room viewers, show public outward status instead:

```text
Open
Help being coordinated
More / different help needed
Enough help for now
Closed
```

For Room members, show the private plan in:

```text
Room NOW strip
Beacon “Where I stand” strip
My Work card
People lens participant context
Room-private Activity
```

## Fact cards

Fact cards are pinned facts extracted from Room messages or entered manually.

They reduce ambiguity without requiring a full task-management system.

### Pin public fact

Purpose: expose a stable fact to everyone who can see the Beacon.

Examples:

```text
Earliest legal travel date: Feb 16
Cat weight: 3.6kg
Destination: Netherlands
Need: passenger flying Georgia → NL/EU
```

Flow:

```text
Select Room message → Pin fact card → Public
├─ compact edit dialog
├─ user writes/edits fact text
├─ save
└─ creates public FactCard + public ActivityEvent(fact_pinned)
```

Effects:

```text
Room:
  message gets “Public fact” marker
  system insert: “Public fact pinned by X”

Overview:
  public fact card appears

Forward screen:
  public fact appears in compact state summary

Inbox:
  public fact may affect card summary only if chosen for highlight

Activity:
  public fact_pinned event appears
```

### Pin private fact

Purpose: pin an operational fact visible only to involved people.

Examples:

```text
Alex privately prefers no cargo hold
Adopter phone number
Temporary pickup address
Internal price estimate
Sensitive document detail
```

Flow:

```text
Select Room message → Pin fact card → Private
├─ compact edit dialog
├─ user writes/edits fact text
├─ save
└─ creates room-visible FactCard + room ActivityEvent(fact_pinned)
```

Effects:

```text
Room:
  message gets “Private fact” marker
  private fact card appears in Room

Room NOW strip:
  fact can appear under key Room facts

Overview:
  not visible to non-room viewers

Forward screen:
  not visible unless separately promoted to public fact

Activity:
  visible only to Room members
```

## Next expected move

“Next expected move” is not a hard task assignment. It is a visible coordination hint.

Definition:

```text
next_expected_move = the smallest visible promise / request / wait-state attached to a person in this Beacon
```

Authority rules:

```text
Self can set own next move.
Room members can request a move from another Room member.
Author/Steward can suggest or coordinate a move.
System can prefill deterministic defaults.
Only explicit user action changes state.
```

Do not create next moves from arbitrary chat text.

Next expected move may be created from:

```text
Offer help / admission approval
Need info
Mark blocker
Update plan
Change my status
Author/Steward coordination cue
```

Wording should avoid managerial coercion.

Use:

```text
Next
Asked of you
Waiting on
You offered to
Can you?
```

Avoid:

```text
Assigned to you
Overdue
Required
Failed
Must
```

## Semantic action behavior

### Update plan

Purpose: turn a Room message into a private current plan.

Flow:

```text
Select Room message → Update plan
├─ show compact edit dialog
├─ prefill from selected message if feasible through manual selection/copy, not AI
├─ user edits RoomState.current_plan
├─ save
└─ emit room ActivityEvent(plan_updated)
```

Effects:

```text
Room:
  message gets “Plan updated” marker
  system insert appears: “Plan updated by X”

Room NOW strip:
  current_plan updates
  last_room_meaningful_change updates

Overview:
  no public plan update for non-room viewers
  Room members may see room cue/snippet only if allowed by screen design

Inbox:
  non-room users do not see plan
  Room members may see private plan snippet in My Work / needs-me context

Activity:
  plan_updated event appears only for Room members

Notifications:
  notify Room members if relevant; do not notify passive non-room viewers
```

### Pin fact card

Purpose: convert a message into a stable fact card with explicit visibility.

Flow:

```text
Select Room message → Pin fact card
├─ choose visibility:
│  ├─ Public fact
│  └─ Private fact
├─ compact edit dialog
├─ save
└─ emit ActivityEvent(fact_pinned) with matching visibility
```

Rules:

```text
Public fact is visible on Beacon public surfaces.
Private fact is visible only in Room.
Only Author/Steward can pin public facts by default.
Room members may pin private facts.
```

### Mark blocker

Purpose: make an obstacle visible and actionable inside the Room.

Flow:

```text
Select Room message → Mark blocker
├─ blocker title dialog
├─ optional affected person
├─ optional who can resolve it
├─ save
└─ emit room ActivityEvent(blocker_opened)
```

Effects:

```text
Room:
  message gets “Blocker” marker
  blocker card appears in stream

Room NOW strip:
  open_blocker = new blocker

Room internal status:
  status may become blocked

Public Beacon status:
  unchanged by default
  Author/Steward may separately set public status to More / different help needed or Blocked

People:
  affected Room member may move to blocked / needs_info
  next expected move may be requested if resolver is selected

Inbox/My Work:
  Room members only see related responsibility state
  non-room users only see public status

Notifications:
  notify author/steward + affected/resolver people
```

### Mark done

Purpose: explicitly complete a known next step, blocker, or personal action.

Without AI, Mark done must not infer what is done from text. It must ask the user to link it.

Flow:

```text
Select Room message → Mark done
├─ show picker: “What is done?”
│  ├─ My next step
│  ├─ Blocker: [open blocker 1]
│  ├─ Blocker: [open blocker 2]
│  ├─ Whole Room plan step
│  └─ Just mark this message as done
├─ user selects target
├─ save
└─ emit room ActivityEvent(done_marked / blocker_resolved / participant_status_changed)
```

If there is exactly one open blocker, preselect it but still require confirmation:

```text
Resolve blocker: Waiting for cat weight?
[Resolve] [Choose another] [Just mark message]
```

Precise rule:

```text
A blocker is cleared only when a user explicitly resolves that blocker, either from the blocker card or by linking a Mark done action to it.
```

Public status is not automatically changed when a private blocker is resolved. Author/Steward may separately update the public outward signal.

### Need info

Purpose: request a small missing piece of information from a specific Room member or candidate.

Flow:

```text
Select message → Need info
├─ choose target person
├─ write short request
├─ save
└─ emit ActivityEvent(need_info_opened) with room visibility by default
```

Target user sees:

```text
Asked of you: [request]
[Answer] [Can’t] [Not me]
```

Effects:

```text
Room:
  need-info card appears

YOU strip for target:
  shows requested next move

People:
  target status = needs_info
  target next_move_status = requested

Inbox/My Work for target:
  card shows “Needs me” if target is admitted

Activity:
  need_info_opened event appears with room visibility

Notifications:
  notify target person
```

## Public status / outward need signal

To keep minimalism, do not expose detailed usefulness labels publicly.

Use only these outward signals:

```text
Open
Help being coordinated
More / different help needed
Enough help for now
Closed
```

Meaning:

```text
Open:
  Beacon is active; offers/forwards are welcome.

Help being coordinated:
  Author/Steward is working with admitted people; new offers may still be possible.

More / different help needed:
  Current internal coordination is insufficient; forward/help search is useful.

Enough help for now:
  Do not pile on more offers unless directly asked.

Closed:
  Beacon is done/closed.
```

Do not publicly label people as `useful`, `overlapping`, `not suitable`, etc. Use private Author/Steward handling only.

Private candidate handling options:

```text
Admit to Room
Ask clarification
Keep as candidate
Not needed now
Decline / remove
```

This preserves minimalism and avoids turning the People tab into a social judgment surface.

## Blocker cards

When a blocker is created, insert a small state card into the Room stream.

```text
BLOCKER
Waiting for cat weight
Opened by Julia
Affected: Sergei
[Reply] [Resolve]
```

Interactions:

```text
Reply:
  composer links message to blocker_id

Resolve:
  closes blocker after confirmation
  asks optional source message if not resolving from a message
```

Blocker cards are Room-private by default.

## Fact cards in Room

Fact cards appear as compact cards in the Room stream and/or Room NOW area.

```text
PUBLIC FACT
Cat weight: 3.6kg
Visible to everyone who can see this Beacon
[source message]
```

```text
PRIVATE FACT
Alex prefers cabin only; no cargo hold
Visible only to Room members
[source message]
```

Public/private visibility should be visually explicit.

## Room system inserts

The Room stream may include lightweight system inserts for state changes.

Examples:

```text
Plan updated by Julia
Public fact pinned: Cat weight 3.6kg
Private fact pinned by Sergei
Blocker opened: cabin unavailable on Turkish
Need info requested from Sergei: exact cat weight
Blocker resolved: waiting for cat weight
Alex marked next step done
```

System inserts should be visually quieter than user messages but more visible than tiny metadata.

## People lens changes

The People lens replaces the previous “Commitments” lens. It should contain all relevant people, but visibility depends on viewer access.

```text
People
├─ Author
│  ├─ profile
│  ├─ author status
│  └─ author controls
│
├─ Beacon Steward(s)
│  ├─ profile
│  ├─ steward badge
│  └─ room/admission controls, if current user can see them
│
├─ Public visible people / provenance
│  ├─ forwarders visible on this path
│  ├─ forwardees visible where allowed
│  ├─ watchers only if public/visible by existing rules
│  └─ public candidate/offer aggregates, if exposed
│
├─ Candidate helpers [author/steward only]
│  ├─ offered help note
│  ├─ provenance
│  ├─ admit to Room
│  ├─ ask clarification
│  └─ not needed now
│
├─ Involved Room people [Room members only]
│  ├─ active helpers
│  ├─ admitted candidates
│  ├─ verifiers
│  ├─ domain-specific roles
│  └─ withdrawn / no longer involved
│
├─ Person cards
│  ├─ avatar / name-as-seen-by-me
│  ├─ role in this Beacon
│  ├─ room access state
│  ├─ current status, if visible
│  ├─ next expected move, if visible
│  ├─ last meaningful update, if visible
│  └─ actions, depending on permissions
│
└─ Visibility/provenance
   ├─ how this person is connected to the Beacon
   ├─ forwarded by / forwarded to
   └─ room access state if visible
```

Person statuses:

```text
watching
offered_help
candidate
admitted
checking
committed
needs_info
blocked
done
withdrawn
```

People lens should answer:

```text
For everyone:
  Who is publicly connected to this Beacon?
  Who authored/stewards it?
  How did it reach me?

For Author/Steward:
  Who offered help?
  Who should be admitted?
  Who is involved?

For Room members:
  Who is involved?
  What is each person’s role/status?
  Who is waiting on whom?
```

## Overview lens changes

Overview remains non-chatty. It summarizes public Beacon state and provides Room entry points where allowed.

```text
Overview
├─ public need / description
├─ public status / outward signal
├─ public fact cards
├─ context & media
├─ offer help / request admission CTA for non-room viewers
└─ latest Room cue / Open Room button for Room members only
```

Do not show private plan in Overview for non-room viewers.

Do not display full Room inside Overview.

## Activity lens changes

Activity remains the clean history of meaningful changes.

It should respect event visibility.

```text
Activity
├─ Public events
│  ├─ Beacon created
│  ├─ public status updated
│  ├─ public fact pinned/corrected
│  ├─ forwarded
│  ├─ offer submitted / admitted only if visibility permits
│  ├─ closed
│  └─ review opened
│
└─ Room-private events [Room members only]
   ├─ plan updated
   ├─ private fact pinned/corrected
   ├─ blocker opened / resolved
   ├─ need-info opened / answered
   ├─ done marked
   └─ participant status changed
```

Rule:

```text
Room contains human conversation and private coordination state.
Activity contains state history, split by visibility.
Do not merge chat into Activity.
Do not add Room as a fourth Beacon tab.
```

## Inbox interaction

Inbox should show state consequences allowed for the viewer.

For non-room users:

```text
title
who forwarded / why
public status / outward signal
public fact highlights
my relation: recipient / watcher / candidate
offer pending, if candidate
```

For Room members:

```text
title
public status
private current plan snippet, if appropriate
my expected next move
latest private meaningful state change
unread room count
```

Examples:

```text
Move cat to NL
More / different help needed
Public facts: cat 3.6kg · cabin preferred
Forwarded by Julia
```

```text
Move cat to NL
Room: cabin unavailable on Turkish
Asked of you: know anyone flying after Mar 22?
3 new room messages
```

## My Work interaction

My Work shows authored, stewarded, admitted, or committed Beacons.

For author/steward:

```text
Authored / Stewarding
Public status: More help needed
Room: blocked — cabin unavailable
Candidate offers: 2 pending
Room: 8 unread
```

For admitted helper:

```text
Involved as carrier candidate
Your status: checking
Next: confirm cabin reservation
Room: 2 unread
```

For candidate not yet admitted:

```text
Offer pending
Waiting for author/steward response
```

## Forward screen interaction

Forward screen must use only public-visible information unless current viewer is a Room member and explicitly chooses what to include.

Default forward summary:

```text
Public status:
  More / different help needed

Public facts:
  Cat weight: 3.6kg
  Destination: Netherlands

Do not include:
  private plan
  private blockers
  private facts
  Room messages
```

Room member forwarding flow may include an optional step:

```text
Include public note from Room state?
[Choose public facts] [Write forward note]
```

Private Room content must never be auto-included in a forward.

## Notifications

Do not notify for every Room message by default.

Notify on:

```text
Room admission approved
Help offer received, for Author/Steward
Mention
Need info requested from me
My participant status changed
My next expected move changed
Public fact pinned/corrected, if relevant
Private fact pinned/corrected, for Room members if relevant
Blocker opened/resolved if I am involved
Plan updated, for Room members if relevant
Beacon closed
Review opened
```

Use unread badges for normal chat messages instead of push notifications.

## Permission model

Suggested v1 permissions:

```text
Normal Room message:
  any Room member

Emoji reaction:
  any Room member

Offer help:
  any Beacon-visible user

Approve/admit candidate:
  Author or Beacon Steward

Promote Beacon Steward:
  Author only

Update public status:
  Author or Beacon Steward

Update plan:
  Author or Beacon Steward by default
  optionally admitted Room member can suggest plan update for confirmation

Pin public fact:
  Author or Beacon Steward

Pin private fact:
  any Room member
  Author/Steward can correct/remove

Mark blocker:
  any Room member

Mark done:
  self for own next move
  blocker resolver for linked blocker
  Author/Steward for Room coordination state

Need info:
  any Room member can request from another Room member
  Author/Steward can request from candidate/helper

Manage room access:
  Author or Beacon Steward
```

Keep this simple. If uncertain:

```text
public state is controlled by Author/Steward
private coordination state is controlled by Room members, with Author/Steward override
personal next moves are self-owned or requested, not imposed
```

## No-AI deterministic rules

Explicitly avoid AI dependencies in v1.

Do not:

```text
auto-detect blockers from text
auto-clear blockers from answers
auto-assign tasks from chat
auto-summarize Room as source of truth
auto-infer who is responsible
auto-promote private facts to public
auto-include private plan in forwards
```

Do:

```text
let users explicitly mark messages
show tiny pickers when linking state changes
insert blocker / need-info / fact cards
require explicit resolve
require explicit public/private visibility choice for fact cards
preselect obvious targets only when deterministic, e.g. exactly one open blocker
```

## Event propagation summary

```text
Room message
└─ updates Room unread state for Room members only

Room message + Update plan
├─ updates RoomState.current_plan
├─ updates Room NOW strip
├─ updates Room members’ My Work snippets if relevant
└─ creates room ActivityEvent(plan_updated)

Room message + Pin public fact
├─ creates public FactCard
├─ updates Overview public fact list
├─ updates Forward screen public fact list
├─ may update Inbox public summary
└─ creates public ActivityEvent(fact_pinned)

Room message + Pin private fact
├─ creates room FactCard
├─ updates Room NOW strip / Room fact cards
└─ creates room ActivityEvent(fact_pinned)

Room message + Mark blocker
├─ creates room-private Blocker
├─ updates Room NOW strip
├─ updates People affected participant, if selected and visible
├─ updates Room members’ My Work state
├─ sends targeted notifications
└─ creates room ActivityEvent(blocker_opened)

Author/Steward public status update
├─ updates BeaconPublicState.status
├─ updates Overview
├─ updates Inbox / Forward public status
└─ creates public ActivityEvent(public_status_updated)

Room message + Need info
├─ creates requested next move for target
├─ updates target ParticipantState.status = needs_info
├─ updates target YOU strip
├─ updates People card where visible
├─ makes Beacon “Needs me” for target if admitted
├─ sends target notification
└─ creates room ActivityEvent(need_info_opened)

Room message + Mark done
├─ asks user what is done
├─ if blocker selected: resolves that blocker
├─ if own next move selected: marks own next move done
├─ updates People status where visible
├─ updates Room members’ My Work responsibility state
└─ creates room ActivityEvent(done_marked / blocker_resolved / participant_status_changed)

Offer help
├─ creates Candidate helper state
├─ notifies Author/Steward
├─ appears in People for Author/Steward
└─ if approved: grants Room access and creates candidate_admitted event
```

## UX writing examples

Use human, non-managerial phrasing.

Good:

```text
Your offer is pending
The author/steward will admit helpers into the room.
```

```text
Your part
You offered to check airline availability.
Next: confirm cabin slot or mark blocked.
```

```text
Asked of you
Can you provide the cat’s exact weight?
[Answer] [Can’t] [Not me]
```

```text
Public fact
Cat weight: 3.6kg
Visible to everyone who can see this Beacon.
```

```text
Private fact
Pickup phone number saved for Room members only.
```

Bad:

```text
Task assigned to you
You are overdue
You failed to complete
Mandatory action required
Rejected as not useful
```

## Minimal implementation order

### Phase 1 — Room as admitted chat

* Add Room as separate screen/mode, opened from Beacon.
* Add Room admission state.
* Author can admit candidates.
* Author can promote one Beacon Steward.
* Text messages.
* Attachments/photos.
* Emoji reactions.
* Unread room badges.

### Phase 2 — Public/private visibility split

* Add BeaconPublicState.
* Add RoomState.
* Ensure plan is Room-private.
* Ensure Overview/Forward show only public facts/status.
* Add public/private Activity visibility.

### Phase 3 — Fact cards

* Add Pin fact card.
* Support Public fact and Private fact.
* Public fact appears in Overview/Forward/Public Activity.
* Private fact appears only in Room.

### Phase 4 — State strips

* Add Room NOW strip.
* Add YOU strip for Room members.
* Add People participant statuses with visibility rules.
* Show Room cue in Overview only for Room members.

### Phase 5 — Semantic actions

* Add Update plan.
* Add Mark blocker.
* Add Need info.
* Add Mark done with explicit target picker.
* Add blocker / need-info cards.
* Add Activity events for semantic changes.

### Phase 6 — Propagation

* Update Inbox card from visible state.
* Update My Work card from visible/private state depending on access.
* Update Forward screen with public facts/status.
* Add targeted notifications.

## Non-goals for v1

Do not implement yet:

```text
AI summaries
AI extraction of facts/blockers/tasks
large semantic taxonomy
full task management
sub-beacons
multiple rooms per beacon
public comments
public reputation impact from Room messages
leaderboards
complex moderation
appeals/jury systems
treasury/governance
full care-thread machinery
automatic private-to-public promotion
complex role hierarchy beyond Author + Steward
```

## Acceptance criteria

A successful implementation should satisfy:

```text
1. Beacon screen still has exactly three tabs: Overview, People, Activity.
2. Room opens as a separate screen/mode.
3. Users who can see the Beacon do not automatically see the Room.
4. Room admission is controlled by Author and/or Beacon Steward.
5. Offering help is open, but becoming committed/involved requires approval.
6. The current plan is visible only to Room members.
7. Public fact cards are visible on public Beacon surfaces.
8. Private fact cards are visible only in Room.
9. Normal chat does not mutate state.
10. Important messages can be explicitly converted into plan/fact/blocker/done/need-info.
11. Public and private state changes propagate only to screens allowed to see them.
12. Activity remains clean and does not show every chat message.
13. People lens respects visibility and shows candidate/admission controls only to Author/Steward.
14. No blocker is resolved automatically from text; resolution requires explicit user action.
15. Notifications are targeted and do not recreate Telegram-style noise.
16. Public outward signals stay minimal and non-stigmatizing.
```

## Short implementation mantra

```text
Overview is public orientation.
People is visible roles/provenance plus private involvement where allowed.
Activity is clean state history, split by visibility.
Room is the separate mode where admitted people coordinate.
Plan is private to Room.
Facts can be public or private by explicit choice.
Author/Steward admit people and control public state.
Semantic actions reduce ambiguity without turning chat into bureaucracy.
```

