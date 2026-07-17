part of '_migrations.dart';

/// Makes the locale-neutral attention payload searchable without channel copy.
final m0119 = Migration('0119', [
  '''
CREATE INDEX notification_outbox__payload_search
  ON public.notification_outbox
  USING gin (
    to_tsvector(
      'simple',
      coalesce(presentation_payload ->> 'eventType', '') || ' ' ||
      coalesce(presentation_payload ->> 'beaconId', '') || ' ' ||
      coalesce(presentation_payload ->> 'coordinationItemId', '') || ' ' ||
      coalesce(presentation_payload ->> 'targetEntityId', '') || ' ' ||
      coalesce(presentation_payload ->> 'messageId', '')
    )
  );
''',
]);
