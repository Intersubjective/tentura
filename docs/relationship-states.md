# Relationship states (user-facing)

Tentura uses a **directed trust relation** between people:

- **You trust them**: you have set trust toward this person (one-way).
- **They trust you**: they have set trust toward you (one-way).
- **Mutual trust**: you trust each other (two one-way links).
- **No trust relation**: neither direction is set.

## What the action does

On a profile, **“Trust this user”** means:

- **Confirmation**: not required (it applies immediately).
- **Direction**: one-way (you → them).
- **Notification**: not sent by this action.

## How to read the reciprocity label

Profile screens and person cards show a small trust label:

- **Mutual**: you trust each other.
- **One-way out**: you trust them.
- **One-way in**: they trust you.
- **None**: no trust relation.

## What changes after trusting someone

Trust can affect:

- **Network surfaces**: the person appears in your “friends/network” views (one-way relationship on your side).
- **Mutual trust**: a person only counts as “mutual trust” when both directions exist.
- **Forwarding suggestions**: Tentura uses your trust graph when suggesting who might help on a forwarded request. Mutual trust is a stronger routing signal than one-way trust.

Trust does **not** by itself let you open another person’s requests. You need an involvement path (forwarded to you, help offered, room admitted, etc.).

