import 'package:drift_postgres/drift_postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/mapper/beacon_mapper.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';

void main() {
  final createdAt = PgDateTime(DateTime.utc(2030));
  final activityAt = PgDateTime(DateTime.utc(2030, 2));

  Beacon row({
    int kind = 0,
    int forwardPolicy = 1,
    bool isDiscoverable = true,
    PgDateTime? lastActivityAt,
    String? postRootMessageId,
  }) => Beacon(
    id: 'Bmapperkind1',
    userId: 'Umapperkind1',
    title: '',
    description: '',
    createdAt: createdAt,
    updatedAt: createdAt,
    ticker: 0,
    tags: '',
    needs: '',
    status: 3,
    coverSource: 0,
    reviewReopenCount: 0,
    hierarchyEventSequence: 0,
    isDiscoverable: isDiscoverable,
    kind: kind,
    forwardPolicy: forwardPolicy,
    lastActivityAt: lastActivityAt,
    postRootMessageId: postRootMessageId,
  );

  final author = User(
    id: 'Umapperkind1',
    displayName: 'Author',
    description: '',
    createdAt: createdAt,
    updatedAt: createdAt,
    publicKey: 'pk',
  );

  group('beaconModelToEntity post fields', () {
    test('maps a closed-policy undiscoverable post row', () {
      final entity = beaconModelToEntity(
        row(kind: 1, forwardPolicy: 0, isDiscoverable: false),
        author: author,
      );

      expect(entity.kind, BeaconKind.post);
      expect(entity.forwardPolicy, BeaconForwardPolicyValue.closed);
      expect(entity.isDiscoverable, isFalse);
    });

    test('maps a request row with the open policy', () {
      final entity = beaconModelToEntity(row(), author: author);

      expect(entity.kind, BeaconKind.request);
      expect(entity.forwardPolicy, BeaconForwardPolicyValue.open);
      expect(entity.isDiscoverable, isTrue);
    });

    test('maps last activity and the post root message id', () {
      final entity = beaconModelToEntity(
        row(
          kind: 1,
          isDiscoverable: false,
          lastActivityAt: activityAt,
          postRootMessageId: 'Rroot0000001',
        ),
        author: author,
      );

      expect(entity.lastActivityAt, DateTime.utc(2030, 2));
      expect(entity.postRootMessageId, 'Rroot0000001');
    });

    test('leaves last activity and root message empty when unset', () {
      final entity = beaconModelToEntity(row(), author: author);

      expect(entity.lastActivityAt, isNull);
      expect(entity.postRootMessageId, isNull);
    });
  });

  group('BeaconKind and BeaconForwardPolicyValue wire values', () {
    test('beacon kind round-trips its smallint', () {
      expect(BeaconKind.request.value, 0);
      expect(BeaconKind.post.value, 1);
      expect(BeaconKind.fromValue(0), BeaconKind.request);
      expect(BeaconKind.fromValue(1), BeaconKind.post);
    });

    test('forward policy values are closed 0 and open 1', () {
      expect(BeaconForwardPolicyValue.closed.value, 0);
      expect(BeaconForwardPolicyValue.open.value, 1);
    });

    test('an unknown beacon kind is rejected', () {
      expect(() => BeaconKind.fromValue(2), throwsA(anything));
    });
  });
}
