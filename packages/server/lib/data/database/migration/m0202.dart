part of '_migrations.dart';

/// P0.2: pgmer2 0.8.1 adds `mr_sync`, a barrier that flushes pending MR
/// writes to the MeritRank service. Every publish-epoch bump invalidates
/// witness-window caches, so the sync must happen first — centralize it in
/// `mr_bump_publish_epoch`, which all trust rebuild/notify functions already
/// `PERFORM` after their `mr_put_edge`/`mr_delete_edge` calls.
final m0202 = Migration('0202', [
  r'''
CREATE OR REPLACE FUNCTION public.mr_bump_publish_epoch() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.mr_sync();
  UPDATE public.mr_publish_epoch SET epoch = epoch + 1 WHERE id = true;
END;
$$
''',
]);
