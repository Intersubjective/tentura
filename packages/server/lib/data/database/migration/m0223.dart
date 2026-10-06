part of '_migrations.dart';

/// Bring all existing data into the default context.
///
/// Named contexts are a legacy topic feature: the client stopped offering
/// them (the Request form hides its context selector, the rating screen has
/// none), so reads already ran in the default context. MeritRank 0.12 isolates
/// contexts (a named context starts empty), so leftover named values would
/// now select an empty graph. Contexts stay in the schema (columns, the
/// `user_context` list, the `ctx` parameters): named contexts will come back
/// later, isolated. Until then everything runs in the default context.
///
/// The default context is NULL in `beacon`, `beacon_forward_edge` and
/// `inbox_item`, and '' in `ego_witness_window` and the retired
/// `person_mutual_visibility_cache`. This is a data cleanup, so user triggers
/// on the updated tables are disabled for it: it must not bump `updated_at`,
/// emit realtime hints, or re-run forward/inbox side effects. The witness
/// window and the old cache are derived, so named rows are deleted, not
/// merged. `user_context` (the names a user defined) is kept as is; nothing
/// refers to those names any more. Idempotent.
final m0223 = Migration('0223', [
  'ALTER TABLE public.beacon DISABLE TRIGGER USER',
  'UPDATE public.beacon SET context = NULL WHERE context IS NOT NULL',
  'ALTER TABLE public.beacon ENABLE TRIGGER USER',

  'ALTER TABLE public.beacon_forward_edge DISABLE TRIGGER USER',
  'UPDATE public.beacon_forward_edge SET context = NULL '
      'WHERE context IS NOT NULL',
  'ALTER TABLE public.beacon_forward_edge ENABLE TRIGGER USER',

  'ALTER TABLE public.inbox_item DISABLE TRIGGER USER',
  'UPDATE public.inbox_item SET context = NULL WHERE context IS NOT NULL',
  'ALTER TABLE public.inbox_item ENABLE TRIGGER USER',

  "DELETE FROM public.ego_witness_window WHERE context <> ''",
  "DELETE FROM public.person_mutual_visibility_cache WHERE ctx <> ''",
]);
