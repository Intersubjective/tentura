# Beacon ontology → Rounded Material icon

One row per ontology leaf. Icons are Flutter **`Icons.*_rounded`** constants (Rounded Material). Extracted from `deep-research-report.md` (118 rows; design target band was about 80–120).

**Shipped:** fixed ontology picker in the client (`kBeaconIdentityIcons`); persisted `icon_code` keys are snake_case leaves — not a dynamic FlutterIconPicker integration.

In the client catalog (`kBeaconIdentityIcons`), persisted `icon_code` keys are snake_case leaves; the two **Water** rows use distinct keys **`essentials_water`** and **`nature_water`**.

| Ontology node | Chosen icon |
| --- | --- |
| Civic → Documentation | `Icons.description_rounded` |
| Civic → Government | `Icons.account_balance_rounded` |
| Civic → Legal | `Icons.gavel_rounded` |
| Civic → Policy | `Icons.policy_rounded` |
| Civic → Verified identity | `Icons.verified_user_rounded` |
| Civic → Voting | `Icons.how_to_vote_rounded` |
| Community → Accessibility | `Icons.accessible_rounded` |
| Community → Childcare | `Icons.child_care_rounded` |
| Community → Collaboration | `Icons.handshake_rounded` |
| Community → Eldercare | `Icons.elderly_rounded` |
| Community → Family | `Icons.family_restroom_rounded` |
| Community → Group | `Icons.groups_rounded` |
| Community → Inclusivity | `Icons.diversity_3_rounded` |
| Community → Individual | `Icons.person_rounded` |
| Community → Support services | `Icons.support_agent_rounded` |
| Community → Volunteer | `Icons.volunteer_activism_rounded` |
| Communication → Link | `Icons.link_rounded` |
| Communication → Phone call | `Icons.call_rounded` |
| Communication → Send | `Icons.send_rounded` |
| Communication → Share | `Icons.share_rounded` |
| Communication → Text message | `Icons.sms_rounded` |
| Essentials → Clothing | `Icons.checkroom_rounded` |
| Essentials → Coffee | `Icons.local_cafe_rounded` |
| Essentials → Donation goods | `Icons.redeem_rounded` |
| Essentials → Food aid | `Icons.soup_kitchen_rounded` |
| Essentials → Groceries | `Icons.local_grocery_store_rounded` |
| Essentials → Meals | `Icons.restaurant_rounded` |
| Essentials → Shopping | `Icons.shopping_cart_rounded` |
| Essentials → Water | `Icons.water_drop_rounded` |
| Health → Hospital | `Icons.local_hospital_rounded` |
| Health → Medical services | `Icons.medical_services_rounded` |
| Health → Mental health | `Icons.psychology_rounded` |
| Health → Pharmacy | `Icons.local_pharmacy_rounded` |
| Health → Wellness | `Icons.self_improvement_rounded` |
| Home → Cleaning | `Icons.cleaning_services_rounded` |
| Home → Climate control | `Icons.thermostat_rounded` |
| Home → Construction | `Icons.construction_rounded` |
| Home → Electrical | `Icons.electrical_services_rounded` |
| Home → Furniture | `Icons.chair_rounded` |
| Home → Housing | `Icons.apartment_rounded` |
| Home → Kitchen and cooking | `Icons.kitchen_rounded` |
| Home → Laundry | `Icons.local_laundry_service_rounded` |
| Home → Painting | `Icons.format_paint_rounded` |
| Home → Plumbing | `Icons.plumbing_rounded` |
| Home → Property listing | `Icons.real_estate_agent_rounded` |
| Home → Repairs | `Icons.home_repair_service_rounded` |
| Home → Water damage | `Icons.water_damage_rounded` |
| Meta → Announcement | `Icons.campaign_rounded` |
| Meta → Discussion | `Icons.forum_rounded` |
| Meta → Event | `Icons.event_rounded` |
| Meta → Information | `Icons.info_rounded` |
| Meta → Location | `Icons.place_rounded` |
| Meta → Question | `Icons.help_rounded` |
| Meta → Report issue | `Icons.report_rounded` |
| Meta → Schedule | `Icons.schedule_rounded` |
| Meta → Task | `Icons.task_alt_rounded` |
| Meta → Urgent alert | `Icons.warning_rounded` |
| Mobility → Bike | `Icons.directions_bike_rounded` |
| Mobility → Car | `Icons.directions_car_rounded` |
| Mobility → Delivery | `Icons.local_shipping_rounded` |
| Mobility → Food delivery | `Icons.delivery_dining_rounded` |
| Mobility → Map | `Icons.map_rounded` |
| Mobility → Moving help | `Icons.moving_rounded` |
| Mobility → Parking | `Icons.local_parking_rounded` |
| Mobility → Public transit | `Icons.directions_bus_rounded` |
| Mobility → Walking | `Icons.directions_walk_rounded` |
| Money → Cash | `Icons.attach_money_rounded` |
| Money → Marketplace | `Icons.storefront_rounded` |
| Money → Payment | `Icons.payments_rounded` |
| Money → Receipt | `Icons.receipt_long_rounded` |
| Money → Savings | `Icons.savings_rounded` |
| Nature → Agriculture | `Icons.agriculture_rounded` |
| Nature → Air quality | `Icons.air_rounded` |
| Nature → Beach | `Icons.beach_access_rounded` |
| Nature → Compost | `Icons.compost_rounded` |
| Nature → Environment | `Icons.eco_rounded` |
| Nature → Forest | `Icons.forest_rounded` |
| Nature → Gardening | `Icons.yard_rounded` |
| Nature → Mountains | `Icons.terrain_rounded` |
| Nature → Park | `Icons.park_rounded` |
| Nature → Recycling | `Icons.recycling_rounded` |
| Nature → Water | `Icons.water_rounded` |
| Safety → Crisis | `Icons.crisis_alert_rounded` |
| Safety → Emergency | `Icons.emergency_rounded` |
| Safety → Emergency contacts | `Icons.emergency_share_rounded` |
| Safety → Fire | `Icons.local_fire_department_rounded` |
| Safety → General safety | `Icons.health_and_safety_rounded` |
| Safety → Police | `Icons.local_police_rounded` |
| Safety → Security | `Icons.security_rounded` |
| Weather → Cloudy | `Icons.wb_cloudy_rounded` |
| Weather → Storm | `Icons.thunderstorm_rounded` |
| Weather → Sunny | `Icons.wb_sunny_rounded` |
| Work → Design | `Icons.design_services_rounded` |
| Work → Engineering | `Icons.engineering_rounded` |
| Work → Hiring | `Icons.person_search_rounded` |
| Work → Idea | `Icons.lightbulb_rounded` |
| Work → Job | `Icons.work_rounded` |
| Work → Tools | `Icons.build_rounded` |
| Tech → Bug | `Icons.bug_report_rounded` |
| Tech → Cloud | `Icons.cloud_rounded` |
| Tech → Coding | `Icons.code_rounded` |
| Tech → Computer | `Icons.computer_rounded` |
| Tech → Internet | `Icons.wifi_rounded` |
| Tech → Phone | `Icons.smartphone_rounded` |
| Tech → Settings | `Icons.settings_rounded` |
| Tech → Tentura | custom Tentura font (graph, 0xe908) |
| Culture → Art | `Icons.palette_rounded` |
| Culture → Celebration | `Icons.celebration_rounded` |
| Culture → Museum | `Icons.museum_rounded` |
| Culture → Music | `Icons.music_note_rounded` |
| Culture → Sports | `Icons.sports_soccer_rounded` |
| Culture → Theater | `Icons.theater_comedy_rounded` |
| Culture → Worship | `Icons.church_rounded` |
| Education → Books | `Icons.menu_book_rounded` |
| Education → Language | `Icons.translate_rounded` |
| Education → School | `Icons.school_rounded` |
| Education → Workshop | `Icons.cast_for_education_rounded` |
| Animals → Animal welfare | `Icons.cruelty_free_rounded` |
| Animals → Pets and animals | `Icons.pets_rounded` |

---

## Coordination compound icon language

Coordination items (ask / promise / blocker / plan / resolution) and their
lifecycle events render with a **two-slot `[kind][state]` compound** instead of
a single status-driven glyph. The single source of truth is
`packages/client/lib/ui/widget/coordination_item_presenter.dart`; never
hard-code these glyphs in features.

**Slot 1 — kind** (`coordinationKindIcon`): ask `help_outline`, promise
`front_hand_outlined`, blocker `block`, plan `edit_note` (step `checklist`),
resolution `handshake_outlined`.

**Slot 2 — state change** (`coordinationStateIcon` / `coordinationEventStateIcon`,
nullable): open / created / updated → none; accepted → `thumb_up_alt_outlined`;
resolved → `check_circle` (filled); cancelled → `cancel_outlined`; superseded →
`swap_horiz`.

**Coloring rule** (in the compound builders): when a state glyph is present the
kind glyph is neutral (`colorScheme.onSurfaceVariant`) and the state glyph takes
the status accent; when there is no state glyph the lone kind glyph carries the
accent (preserving the amber "needs attention" cue for open asks/promises).

**Color model** (`coordinationItemColor`): `resolved` → `tt.good` (green)
**globally** — green is reserved for genuine completion; `ask`/`promise`
`accepted` → `tt.info` (not green, avoiding false completeness); other open
asks/promises → `tt.warn`; `blocker` → `tt.danger`; `plan`/`resolution` →
`tt.info`; `cancelled`/`superseded` → `tt.textMuted`.

The compound is decorative (the adjacent text label carries meaning); callers
wrap it in `ExcludeSemantics` or a single-`Semantics` row.
