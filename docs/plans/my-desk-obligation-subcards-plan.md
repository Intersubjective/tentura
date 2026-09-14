# My Desk obligation sub-cards

Accepted implementation decisions (copied from the working plan on land).

## Terminology

- User-facing surface: **My Desk** (internal: My Work).
- User-facing object: **Request** (internal: Beacon). No `Request` domain entity.
- Desk «updates» here = **live obligations** (`AttentionReceipt.isLiveObligation`).

## Decisions

- **D-SC1 — objects.** Sub-cards = live obligations only.
- **D-SC2 — multi-choice primary.** Help offer: **Respond** opens People `HelpOfferTile` sheet. Review: **Review** pushes `ReviewContributionsRoute`.
- **D-SC3 — nested surface.** Compact outlined nested container via `TenturaTechCardStatic`: fill `tt.bg`, border `tt.borderSubtle`, padding `tt.cardGap`, optional `radius: TenturaRadii.cardDense`. No second elevation.
- **D-SC4 — secondary settle + 48dp actions.** Keep Done on typed sub-cards. Copy above a `Wrap` of primary + secondary. Hit targets ≥ 48 on the button (`minInteractive`).
- **D-SC5 — destination identity.** Dedupe exact destinations. Per-offer Respond must not suppress aggregate Review offers. Authored phase `reviewContributions` opens the review route (not the Request).
- **D-SC6 — catalog + grouped settle.** Live kinds: `help_offer_submitted`, `review_opened`. Unknown: one sub-card per receipt. Offers: one sub-card per person; Done settles all represented receipt IDs via `MyWorkCubit.settleObligations`.
- **D-SC7 — collapse after grouping.** Visible group cap = 3, then «ещё N».
- **D-SC8 — footer composer.** Obligations live in `BeaconCardShell.footer` (outside InkWell). What's-new stays in `child`. Footer is `null` only when sub-cards, fallback CTAs, and existing controls are all absent.

## Help-offer sheet

- Cubit: `BeaconViewCase` + `UiEffectPort`.
- `load()`: `fetchBeaconById` + help offers + participants. Disable admit until load succeeds and People permission rules pass on the loaded Beacon.
- Mutations via `BeaconViewCase`; failures emit effects and do not pop. Accept/decline pop; desk refresh via `helpOfferChanges`. Do not settle attention from the sheet.

## Version

Client minor `7.6.17` → `7.7.0` + `web/index.html` `?v=`. Do not raise `kDefaultMinClientVersion`.
