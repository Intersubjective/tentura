import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/invite_genealogy_gql_maps.dart';
import 'package:tentura_server/data/mapper/user_availability_mapper.dart';
import 'package:tentura_server/domain/entity/gql_public/user_availability_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/entity/user_availability_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

void main() {
  final todayUtc = DateTime.utc(2026, 8, 13);
  final futureResume = DateTime.utc(2026, 8, 20);
  final pastResume = DateTime.utc(2026, 8, 1);

  group('userAvailabilityEntityToPublicRecord', () {
    test('null entity maps to null (open)', () {
      expect(
        userAvailabilityEntityToPublicRecord(entity: null, todayUtc: todayUtc),
        isNull,
      );
    });

    test('limited maps to record without resume_on', () {
      final record = userAvailabilityEntityToPublicRecord(
        entity: const UserAvailabilityEntity(userId: 'U1', isLimited: true),
        todayUtc: todayUtc,
      );
      expect(record?.isLimited, isTrue);
      expect(record?.resumeOn, isNull);
    });

    test('future pause maps to record with resume_on', () {
      final record = userAvailabilityEntityToPublicRecord(
        entity: UserAvailabilityEntity(
          userId: 'U1',
          resumeOn: futureResume,
        ),
        todayUtc: todayUtc,
      );
      expect(record?.isLimited, isFalse);
      expect(record?.resumeOn, futureResume);
    });

    test('expired pause-only maps to null', () {
      expect(
        userAvailabilityEntityToPublicRecord(
          entity: UserAvailabilityEntity(
            userId: 'U1',
            resumeOn: pastResume,
          ),
          todayUtc: todayUtc,
        ),
        isNull,
      );
    });

    test('limited with expired pause retains limited and past resume_on', () {
      final record = userAvailabilityEntityToPublicRecord(
        entity: UserAvailabilityEntity(
          userId: 'U1',
          isLimited: true,
          resumeOn: pastResume,
        ),
        todayUtc: todayUtc,
      );
      expect(record?.isLimited, isTrue);
      expect(record?.resumeOn, pastResume);
    });
  });

  group('userPublicToGqlMap', () {
    test('open user emits null user_availability', () {
      const user = UserPublicRecord(
        id: 'U1',
        displayName: 'Alice',
        description: 'bio',
        userAvailability: null,
      );
      final map = userPublicToGqlMap(user);
      expect(map['user_availability'], isNull);
    });

    test('limited user emits is_limited without instant fields', () {
      const user = UserPublicRecord(
        id: 'U1',
        displayName: 'Alice',
        description: 'bio',
        userAvailability: UserAvailabilityRecord(isLimited: true),
      );
      final map = userPublicToGqlMap(user);
      expect(map['user_availability'], {
        'is_limited': true,
        'resume_on': null,
      });
      expect(map['user_availability'].keys, containsAll(['is_limited', 'resume_on']));
    });

    test('future pause emits calendar-date resume_on string only', () {
      final user = UserPublicRecord(
        id: 'U1',
        displayName: 'Alice',
        description: 'bio',
        userAvailability: UserAvailabilityRecord(
          isLimited: false,
          resumeOn: futureResume,
        ),
      );
      final map = userPublicToGqlMap(user);
      expect(map['user_availability'], {
        'is_limited': false,
        'resume_on': '2026-08-20',
      });
    });

    test('limited with past resume_on retains past calendar date', () {
      final user = UserPublicRecord(
        id: 'U1',
        displayName: 'Alice',
        description: 'bio',
        userAvailability: UserAvailabilityRecord(
          isLimited: true,
          resumeOn: pastResume,
        ),
      );
      final map = userPublicToGqlMap(user);
      expect(map['user_availability'], {
        'is_limited': true,
        'resume_on': '2026-08-01',
      });
    });

    test('userAvailabilityEntityToGqlMap matches serializer rules', () {
      expect(
        userAvailabilityEntityToGqlMap(
          entity: UserAvailabilityEntity(userId: 'U1', resumeOn: pastResume),
          todayUtc: todayUtc,
        ),
        isNull,
      );
      expect(
        userAvailabilityEntityToGqlMap(
          entity: UserAvailabilityEntity(
            userId: 'U1',
            isLimited: true,
            resumeOn: pastResume,
          ),
          todayUtc: todayUtc,
        ),
        {'is_limited': true, 'resume_on': '2026-08-01'},
      );
    });
  });

  test('invite genealogy mapper threads availability into nested user', () {
    const user = UserEntity(
      id: 'U2',
      displayName: 'Bob',
      description: 'desc',
    );
    final node = InviteGenealogyNodeEntity(
      nodeKey: 'Gnode',
      user: user,
    );
    final availability = UserAvailabilityRecord(
      isLimited: true,
      resumeOn: futureResume,
    );
    final map = inviteGenealogyNodeToGqlMap(
      node,
      userPublicToGqlMap: userPublicToGqlMap,
      availabilityByUserId: {'U2': availability},
    );
    final nestedUser = map['user']! as Map<String, dynamic>;
    expect(nestedUser['user_availability'], {
      'is_limited': true,
      'resume_on': '2026-08-20',
    });
  });

  test('invitation issuer patch shape uses calendar date without updated_at', () {
    final issuer = <String, dynamic>{
      'id': 'issuer-1',
      'displayName': 'Carol',
      'description': 'bio',
    };
    issuer['user_availability'] = userAvailabilityEntityToGqlMap(
      entity: UserAvailabilityEntity(
        userId: 'issuer-1',
        resumeOn: futureResume,
      ),
      todayUtc: todayUtc,
    );
    expect(issuer['user_availability'], {
      'is_limited': false,
      'resume_on': '2026-08-20',
    });
    expect(issuer['user_availability'].keys, isNot(contains('updated_at')));
  });
}
