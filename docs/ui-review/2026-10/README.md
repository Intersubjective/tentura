# UI review — October 2026

Umbrella issue: intersubjective/tentura#193 (sub-issues #194–#212).

Captured from a local stack seeded with a six-person society (QA email
test-login, `*@test.tentura.local`): everyone befriends everyone, four
requests, forwards, help offers with room admission, chat, polls, pinned
facts.

- `before/` — baseline, client 7.25.0.
- `after/` — client 7.26.0 (single colour palette + review fixes).

`m_*.jpg` are 390 px phone captures, light on the left, dark on the right.
`d_*.jpg` are 1280 px desktop captures.

The colour system and how to re-theme it are documented in
[`docs/tentura-design-system.md` § Colour system](../../tentura-design-system.md#colour-system).

## Round 3 — integration-test flows (`flows/`)

Walked the flows covered by `packages/client/integration_test/` on the
same stack: request creation (title/description, When?, Requirements
ontology picker, Cover, discoverability, recipients, forward), the People
tab with four applicants (accept / decline / withdrawn / declined), My Work
"Respond" sheet, offer-help sheet, chat actions, facts, polls, closure,
child request, My field, profile QR and the connect sheet.

`flows/before/` is the pre-round-3 build; `flows/after/` is the build with
round-3 fixes (the QR capture predates the 3c dialog-action change).
Images are halved and palette-reduced to keep the repo light.

`flows/after/i216_*` are the #216 follow-ups: the declined-offer notice, the
single-state discoverability copy and the quiet recipients hint.
