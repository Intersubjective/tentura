import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/post_view/domain/port/post_lifecycle_port.dart';

import '../../support/remote_wire_harness.dart';

const _postId = 'Bpost00000001';
final _expiresAt = DateTime.parse('2026-10-27T16:00:00+02:00');

void main() {
  group('Post lifetime mutations', () {
    test('shortening sends the Post id and the new deadline in UTC', () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'PostShorten': {'__typename': 'mutation_root', 'postShorten': true},
        },
        sent,
        (remote) async {
          final PostLifecyclePort repository = PostMembershipRepository(
            remoteApiService: remote,
            log: Logger('PostLifecycleTest'),
          );
          await repository.postShorten(_postId, expiresAt: _expiresAt);
        },
      );

      expect(sent, hasLength(1));
      expect(sent.single.operationName, 'PostShorten');
      expect(sent.single.variables, {
        'id': _postId,
        'expiresAt': '2026-10-27T14:00:00.000Z',
      });
    });

    test('closing sends only the Post id', () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'PostClose': {'__typename': 'mutation_root', 'postClose': true},
        },
        sent,
        (remote) async {
          final PostLifecyclePort repository = PostMembershipRepository(
            remoteApiService: remote,
            log: Logger('PostLifecycleTest'),
          );
          await repository.postClose(_postId);
        },
      );

      expect(sent, hasLength(1));
      expect(sent.single.operationName, 'PostClose');
      expect(sent.single.variables, {'id': _postId});
    });

    for (final operation in ['PostShorten', 'PostClose']) {
      test('$operation routes directly to the Tentura V2 API', () {
        expect(isTenturaDirectOperation(operation), isTrue);
      });
    }

    for (final (code, description, matcher) in [
      (1349, 'invalid lifetime', isA<PostLifetimeInvalidException>()),
      (1350, 'deadline extension', isA<PostLifetimeExtendException>()),
    ]) {
      test('shortening preserves the typed $description failure', () async {
        final sent = <WireSent>[];
        await withRemoteWire(
          const {},
          sent,
          (remote) async {
            final repository = PostMembershipRepository(
              remoteApiService: remote,
              log: Logger('PostLifecycleTest'),
            );
            await expectLater(
              repository.postShorten(_postId, expiresAt: _expiresAt),
              throwsA(matcher),
            );
          },
          errors: {'PostShorten': wireCodeError(code)},
        );
        expect(sent.single.operationName, 'PostShorten');
      });
    }
  });
}
