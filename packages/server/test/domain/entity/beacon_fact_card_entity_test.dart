import 'package:test/test.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';

/// tentura-617.4 — entity catches up with `beacon_fact_cards` columns
/// (m0199) while existing construction sites keep compiling.
void main() {
  final createdAt = DateTime.utc(2026, 9);

  test('newId still generates F-prefixed ids', () {
    final a = BeaconFactCardEntity.newId;
    final b = BeaconFactCardEntity.newId;
    expect(a, startsWith('F'));
    expect(a.length, greaterThan(1));
    expect(a, isNot(b));
  });

  test('legacy construction with optional legacy fields still compiles', () {
    final updatedAt = DateTime.utc(2026, 9, 3);
    final entity = BeaconFactCardEntity(
      id: BeaconFactCardEntity.newId,
      beaconId: 'Bxyz',
      factText: 'fact',
      visibility: 1,
      pinnedBy: 'Uaaa',
      createdAt: createdAt,
      sourceMessageId: 'Mmsg',
      status: 1,
      updatedAt: updatedAt,
    );
    expect(entity.sourceMessageId, 'Mmsg');
    expect(entity.status, 1);
    expect(entity.updatedAt, updatedAt);
    expect(entity.revisionSeq, 1);
  });

  test('legacy construction gets fact-history defaults', () {
    final entity = BeaconFactCardEntity(
      id: 'Fabc',
      beaconId: 'Bxyz',
      factText: 'fact',
      visibility: 0,
      pinnedBy: 'Uaaa',
      createdAt: createdAt,
    );
    expect(entity.revisionSeq, 1);
    expect(entity.lastEditedBy, isNull);
    expect(entity.lastEditedByTitle, isNull);
    expect(entity.lastEditedAt, isNull);
    expect(entity.otherEditorCount, 0);
    expect(entity.historyTruncated, isFalse);
    expect(entity.pinnedByTitle, '');
  });

  test('fact-history fields can be set explicitly', () {
    final editedAt = DateTime.utc(2026, 9, 2);
    final entity = BeaconFactCardEntity(
      id: 'Fabc',
      beaconId: 'Bxyz',
      factText: 'fact',
      visibility: 0,
      pinnedBy: 'Uaaa',
      createdAt: createdAt,
      revisionSeq: 4,
      lastEditedBy: 'Ubbb',
      lastEditedByTitle: 'Bob',
      lastEditedAt: editedAt,
      otherEditorCount: 2,
      historyTruncated: true,
      pinnedByTitle: 'Alice',
    );
    expect(entity.revisionSeq, 4);
    expect(entity.lastEditedBy, 'Ubbb');
    expect(entity.lastEditedByTitle, 'Bob');
    expect(entity.lastEditedAt, editedAt);
    expect(entity.otherEditorCount, 2);
    expect(entity.historyTruncated, isTrue);
    expect(entity.pinnedByTitle, 'Alice');
  });
}
