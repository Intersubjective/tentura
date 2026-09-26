import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';

/// tentura-617.4 — plan §14.2: Freezed union `BeaconFactHistoryEntry` with
/// `.revision` (text versions) and `.event` (visibility/unpin events).
///
/// `when`/`map` are disabled in build.yaml, so variant payloads are read via
/// public variant types (Freezed redirecting-constructor names):
/// `.revision(...) = BeaconFactHistoryRevision` and
/// `.event(...) = BeaconFactHistoryEvent`.
String describe(BeaconFactHistoryEntry entry) => switch (entry) {
  BeaconFactHistoryRevision(:final seq, :final kind) => 'revision:$seq:$kind',
  BeaconFactHistoryEvent(:final type) => 'event:$type',
};

void main() {
  final createdAt = DateTime.utc(2026, 9);

  test('.revision carries seq, kind, text, restoredFromSeq and actor', () {
    final entry = BeaconFactHistoryEntry.revision(
      seq: 3,
      kind: BeaconFactCardRevisionKindBits.restored,
      factText: 'corrected',
      restoredFromSeq: 1,
      actorId: 'Uaaa',
      actorTitle: 'Alice',
      createdAt: createdAt,
    );
    expect(entry.actorId, 'Uaaa');
    expect(entry.actorTitle, 'Alice');
    expect(entry.createdAt, createdAt);
    expect(entry, isA<BeaconFactHistoryRevision>());
    final revision = entry as BeaconFactHistoryRevision;
    expect(revision.seq, 3);
    expect(revision.kind, BeaconFactCardRevisionKindBits.restored);
    expect(revision.factText, 'corrected');
    expect(revision.restoredFromSeq, 1);
    expect(
      describe(entry),
      'revision:3:${BeaconFactCardRevisionKindBits.restored}',
    );
  });

  test('.revision optional fields may be null', () {
    final entry = BeaconFactHistoryEntry.revision(
      seq: 1,
      kind: BeaconFactCardRevisionKindBits.imported,
      factText: 'baseline',
      actorTitle: '',
      createdAt: createdAt,
    );
    expect(entry.actorId, isNull);
    expect((entry as BeaconFactHistoryRevision).restoredFromSeq, isNull);
  });

  test('.event carries type, visibility transition and actor', () {
    final entry = BeaconFactHistoryEntry.event(
      activityEventId: 'Eaaa00000001',
      type: 20,
      visibilityFrom: BeaconFactCardVisibilityBits.room,
      visibilityTo: BeaconFactCardVisibilityBits.public,
      actorId: 'Ubbb',
      actorTitle: 'Bob',
      createdAt: createdAt,
    );
    expect(entry.actorId, 'Ubbb');
    expect(entry.actorTitle, 'Bob');
    expect(entry.createdAt, createdAt);
    expect(entry, isA<BeaconFactHistoryEvent>());
    final event = entry as BeaconFactHistoryEvent;
    expect(event.type, 20);
    expect(event.visibilityFrom, BeaconFactCardVisibilityBits.room);
    expect(event.visibilityTo, BeaconFactCardVisibilityBits.public);
    expect(describe(entry), 'event:20');
  });

  test('.event visibility fields are optional', () {
    final entry = BeaconFactHistoryEntry.event(
      activityEventId: 'Eaaa00000002',
      type: 19,
      actorTitle: '',
      createdAt: createdAt,
    );
    expect(entry.actorId, isNull);
    final event = entry as BeaconFactHistoryEvent;
    expect(event.visibilityFrom, isNull);
    expect(event.visibilityTo, isNull);
  });

  test('variants use value equality', () {
    BeaconFactHistoryEntry rev() => BeaconFactHistoryEntry.revision(
      seq: 2,
      kind: BeaconFactCardRevisionKindBits.edited,
      factText: 'x',
      actorTitle: 'A',
      createdAt: createdAt,
    );
    expect(rev(), rev());
    expect(
      rev(),
      isNot(
        BeaconFactHistoryEntry.event(
          activityEventId: 'Eaaa00000003',
          type: 19,
          actorTitle: 'A',
          createdAt: createdAt,
        ),
      ),
    );
  });
}
