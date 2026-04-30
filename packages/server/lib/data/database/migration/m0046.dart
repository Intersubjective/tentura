part of '_migrations.dart';

/// Strict reciprocal friendship: viewer and peer both have vote_user(amount > 0).
final m0046 = Migration('0046', [
  r'''
CREATE OR REPLACE FUNCTION public.user_get_is_mutual_friend(
  user_row public."user",
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT EXISTS (
  SELECT 1 FROM vote_user vu
  WHERE vu.subject = (hasura_session ->> 'x-hasura-user-id')::TEXT
    AND vu.object = user_row.id
    AND vu.amount > 0
) AND EXISTS (
  SELECT 1 FROM vote_user vu
  WHERE vu.subject = user_row.id
    AND vu.object = (hasura_session ->> 'x-hasura-user-id')::TEXT
    AND vu.amount > 0
);
$$;
''',
]);
