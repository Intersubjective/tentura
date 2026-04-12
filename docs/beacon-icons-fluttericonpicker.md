# Beacon icons: FlutterIconPicker and curated Material (rounded)

## Goal

Beacon thumbnails should stay recognizable in feeds and inbox at small sizes, while staying easy to pick when someone creates a beacon. The plan is to use **FlutterIconPicker** with the **Rounded Material** style: those glyphs are drawn to read clearly when tiny, and names stay consistent and searchable.

## Curated set, not the full pack

The full Rounded Material catalog is huge. Showing all of it hits known UX problems (choice overload, slower decisions). The product approach is a **curated list** of ontology leaves (macro domain → subdomain → leaf), tuned for coordination use cases (requests, offers, errands, safety, events, community help), roughly in the **80–120** icon band.

The canonical **ontology node → icon** list lives in [`beacon-ontology-icon-mapping.md`](beacon-ontology-icon-mapping.md) (118 rows, extracted from `deep-research-report.md`).

## Pack generation and naming

FlutterIconPicker’s Material Rounded pack is **generated on demand** and may ship with an empty map until you run the package generator (see upstream `flutter_iconpicker` docs). For audits and code, treat **`Icons.*_rounded`** in Flutter’s `Icons` API as the stable name for each glyph.

## Persisting the user’s choice

FlutterIconPicker notes that framework upgrades can change codepoints. For thumbnails that must not drift, prefer persisting **`IconData` (codePoint + `fontFamily: 'MaterialIcons'`)** (and optional pack/name metadata), not only a symbolic reference. A small **custom pack** (`IconPack.custom` with a map of allowed icons) is a good fit if you only expose the curated subset.

## Known gaps

Rounded **Material `Icons`** do not expose dedicated cat/dog glyphs; **`Icons.pets_rounded`** is the practical fallback for pet-specific beacons. If species-specific icons become a requirement, consider a supplemental set (e.g. **Material Symbols**, rounded style) for a few extra leaves only.

## Picker UX (short)

Suggested layout: a fixed **starter favorites** row, then sections by rough usage frequency (coordination → community → home → essentials → mobility → health/safety → work/tech → nature → education/culture → civic/legal), with **broad** domain icons before **specific** leaves in each section. Optional: synonym tags on each icon for search (“delivery”, “courier”, “package”, etc.).

**Example starter favorites (12):**  
`help_rounded`, `volunteer_activism_rounded`, `campaign_rounded`, `event_rounded`, `warning_rounded`, `pets_rounded`, `home_repair_service_rounded`, `local_grocery_store_rounded`, `directions_car_rounded`, `local_shipping_rounded`, `medical_services_rounded`, `wifi_rounded`

## Accessibility

Icons sit on colored beacon backgrounds: aim for strong **icon vs background** contrast (non-text graphics often target about **3:1**; treat icons that replace text meaning as stricter). Prefer auto **light vs dark** glyph on the chosen background when users do not override.
