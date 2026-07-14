import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/realtime_watch_grant_repository.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';

void main() {
  group('RealtimeWatchGrantRepository mapping', () {
    test('encodes only the closed graph projection contract', () {
      final json = RealtimeWatchGrantRepository.encodeDescriptor(
        const RealtimeWatchDescriptor.graph(
          requestedSubjectIds: {'user-b', 'user-a'},
          focusId: 'focus-user',
          context: 'network',
          positiveOnly: true,
        ),
      );

      expect(json, {
        'scope': 'graph',
        'subjectIds': ['user-a', 'user-b'],
        'projection': {
          'focus': 'focus-user',
          'context': 'network',
          'positiveOnly': true,
        },
      });
    });

    test('decodes a bounded opaque grant', () {
      final grant = RealtimeWatchGrantRepository.decodeGrant(
        {
          'grant': 'signed-value',
          'scope': 'profile',
          'subjectIds': ['profile-a'],
          'expiresAt': '2026-07-14T12:02:00Z',
          'protocolVersion': 1,
        },
        expectedScope: RealtimeWatchScope.profile,
      );

      expect(grant.token, 'signed-value');
      expect(grant.scope, RealtimeWatchScope.profile);
      expect(grant.authorizedSubjectIds, {'profile-a'});
      expect(grant.expiresAt, DateTime.utc(2026, 7, 14, 12, 2));
    });

    test('rejects scope mismatch and unsupported protocol versions', () {
      Map<String, dynamic> response({required int version}) => {
        'grant': 'signed-value',
        'scope': 'people',
        'subjectIds': ['user-a'],
        'expiresAt': '2026-07-14T12:02:00Z',
        'protocolVersion': version,
      };

      expect(
        () => RealtimeWatchGrantRepository.decodeGrant(
          response(version: 1),
          expectedScope: RealtimeWatchScope.graph,
        ),
        throwsFormatException,
      );
      expect(
        () => RealtimeWatchGrantRepository.decodeGrant(
          response(version: 2),
          expectedScope: RealtimeWatchScope.people,
        ),
        throwsFormatException,
      );
    });
  });
}
