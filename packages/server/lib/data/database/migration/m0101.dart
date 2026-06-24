part of '_migrations.dart';

/// Per-user daily upload byte ledger (image + file attachment quota).
/// One row per (user, UTC date); `bytes` accumulates accepted upload sizes.
final m0101 = Migration('0101', [
  '''
CREATE TABLE IF NOT EXISTS public.upload_daily_usage (
  user_id text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  usage_date date NOT NULL,
  bytes bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, usage_date)
);
''',
]);
