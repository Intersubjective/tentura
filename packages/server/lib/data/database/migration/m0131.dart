part of '_migrations.dart';

/// Forward-only contraction: drop legacy icon columns and enforce primary-need
/// membership. Authorized by Step 10 release-owner sign-off (no production users).
final m0131 = Migration('0131', [
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_primary_need_membership_ck CHECK (
    (needs = '' AND primary_need_slug IS NULL)
    OR
    (needs <> ''
      AND primary_need_slug IS NOT NULL
      AND primary_need_slug =
          ANY (regexp_split_to_array(needs, '\s*,\s*')))
  );
''',
  r'''
ALTER TABLE public.beacon
  DROP COLUMN icon_code,
  DROP COLUMN icon_background;
''',
]);
