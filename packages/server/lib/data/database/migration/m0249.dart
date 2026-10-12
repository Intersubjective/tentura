part of '_migrations.dart';

/// Freeze and resume Activity clear capture across bounded transaction commits.
final m0249 = Migration('0249', [
  '''
ALTER TABLE public.attention_clear_operation
  ADD COLUMN capture_snapshot jsonb,
  ADD COLUMN capture_cursor integer NOT NULL DEFAULT 0
    CHECK (capture_cursor >= 0)''',
]);
