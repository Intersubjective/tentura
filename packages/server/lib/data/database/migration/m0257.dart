part of '_migrations.dart';

/// The Request **Questions** item (`coordination_item` kind 7) publishes no
/// `coordination_item` realtime hint (sprint follow-up to m0255).
///
/// Before: opening Questions inserts the kind-7 item (`ensureLobby`), and the
/// General `coordination_item` triggers (m0250) sent its hint (Request id
/// only) to every General room recipient plus the creator. People outside
/// the Questions audience (removed from Questions, blocked) therefore learned
/// that Questions had been opened.
///
/// After: the three General triggers skip kind 7 through their `WHEN` clause
/// (the trigger function is untouched, so every other kind is published
/// byte-for-byte as before; plan steps, kind 6, stay silenced as in m0250).
/// An UPDATE is skipped when the row is kind 7 before OR after (fail closed;
/// the API never changes a kind). No Questions-audience publisher replaces
/// it: no client reads the Questions item through `coordination_item`
/// (Questions access and counts come from the gated lobby API, refreshed by
/// the Questions message hints of m0255), so the audience needs no hint
/// either. Deleting the item (Request deletion) publishes nothing for it; its
/// messages still go to the audience first (m0255).
final m0257 = Migration('0257', [
  '''
DROP TRIGGER coordination_item_entity_notify_ins ON public.coordination_item
''',
  '''
CREATE TRIGGER coordination_item_entity_notify_ins
  AFTER INSERT ON public.coordination_item
  FOR EACH ROW WHEN (NEW.kind <> 6 AND NEW.kind <> 7)
  EXECUTE FUNCTION public.notify_entity_change('coordination_item')
''',
  '''
DROP TRIGGER coordination_item_entity_notify_upd ON public.coordination_item
''',
  '''
CREATE TRIGGER coordination_item_entity_notify_upd
  AFTER UPDATE ON public.coordination_item
  FOR EACH ROW WHEN (
    (OLD.kind <> 6 OR NEW.kind <> 6)
    AND OLD.kind <> 7
    AND NEW.kind <> 7
  )
  EXECUTE FUNCTION public.notify_entity_change('coordination_item')
''',
  '''
DROP TRIGGER coordination_item_entity_notify_del ON public.coordination_item
''',
  '''
CREATE TRIGGER coordination_item_entity_notify_del
  AFTER DELETE ON public.coordination_item
  FOR EACH ROW WHEN (OLD.kind <> 6 AND OLD.kind <> 7)
  EXECUTE FUNCTION public.notify_entity_change('coordination_item')
''',
]);
