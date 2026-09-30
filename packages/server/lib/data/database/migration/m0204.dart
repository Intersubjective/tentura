part of '_migrations.dart';

/// A1b: seed trust kind 9 `supported_colleague` (Arch §4.1, §5.9b).
///
/// Same column list as the kind 8 insert in `m0202`; `m0202` itself is not
/// edited. Linear 180-day window, not counted for immunity.
final m0204 = Migration('0204', [
  r'''
INSERT INTO public.trust_kind_config
    (kind, slug, polarity, half_life_s, k_sat, mix_weight, linear_window_s, counts_for_immunity)
VALUES
    (9, 'supported_colleague', 0, NULL, 1, 0.1, 15552000, false)
''',
]);
