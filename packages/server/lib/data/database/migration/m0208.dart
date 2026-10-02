part of '_migrations.dart';

/// Hasura's `user_availability` select filter compared `resume_on` (a `date`)
/// with `now()`, which casts the date to midnight in the *session* TimeZone, so
/// the pause boundary moved with the connection's TimeZone instead of the UTC
/// calendar date. `utc_today()` is the bare no-argument function the filter
/// uses instead.
final m0208 = Migration('0208', [
  r'''
CREATE OR REPLACE FUNCTION public.utc_today() RETURNS date
    LANGUAGE sql STABLE
    AS $$ SELECT (now() AT TIME ZONE 'UTC')::date $$
''',
]);
