import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_author_invites_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../../features/inbox/author_invite_test_support.dart'
    show buildActorProfiles;
import '../../../ui/effect/fake_ui_effect_port.dart';
import 'retry_later_wire_support.dart';

// A loader that fires two reads at once (a record `.wait`) turns two server
// admission rejections into one ParallelWaitError. These tests drive such a
// real loader over the real RemoteApiService against a stubbed HTTP server, so
// they hold whichever layer does the retrying.

const _retryAfterMs = 100;
const _invitesOp = 'BeaconAuthorInvites';
const _observersOp = 'BeaconBudObservers';
const _inviteCreateOp = 'AuthorInviteCreate';
const _bob = Profile(id: 'Ubob', displayName: 'Bob');

Map<String, Object?> _loaded(String operation) => jsonResponseData(
  operation == _invitesOp
      ? {
          'beaconAuthorInvites': [
            {
              '__typename': 'v2_BeaconAuthorInvite',
              'inviteId': 'I1',
              'inviteeId': 'Ubob',
              'status': 'pending',
              'note': null,
              'createdAt': '2026-10-15T12:00:00.000Z',
            },
          ],
        }
      : {
          'beaconBudObservers': ['Ubob'],
        },
);

Map<String, Object?> jsonResponseData(Map<String, Object?> data) => {
  'data': {'__typename': 'query_root', ...data},
};

({BeaconAuthorInvitesCubit cubit, FakeUiEffectPort effects}) _loader(
  RemoteApiService remote,
) {
  final effects = FakeUiEffectPort();
  return (
    cubit: BeaconAuthorInvitesCubit(
      beaconId: 'B1',
      authorInviteCase: AuthorInviteCase(
        AuthorInviteRepository(remote),
        env: const Env(),
        logger: Logger('parallel-loader-retry-test'),
      ),
      actorProfiles: buildActorProfiles(const [_bob]),
      effects: effects,
    ),
    effects: effects,
  );
}

void main() {
  group('parallel loader on server admission backoff', () {
    test('both concurrent reads rejected once load without surfacing an '
        'error', () async {
      final server = stubServer(
        (call, attempt) => attempt == 1
            ? retryLaterResponse(_retryAfterMs)
            : jsonResponse(_loaded(call.operation)),
      );

      final loader = await withRemote(server.client, (remote) async {
        final loader = _loader(remote);
        await loader.cubit.load();
        return loader;
      });

      expect(loader.cubit.state.invites.map((i) => i.id), ['I1']);
      expect(loader.cubit.state.observerIds, ['Ubob']);
      expect(
        loader.effects.emitted,
        isEmpty,
        reason: 'a recovered busy answer must not reach the user or Sentry',
      );
    });

    test('a loader that stays busy gives up after a few attempts per read, '
        'then reports the retry-later failure once', () async {
      final server = stubServer(
        (call, attempt) => retryLaterResponse(10),
      );

      final loader = await withRemote(server.client, (remote) async {
        final loader = _loader(remote);
        await loader.cubit.load();
        return loader;
      });

      for (final operation in [_invitesOp, _observersOp]) {
        expect(
          server.calls.where((c) => c.operation == operation).length,
          inInclusiveRange(2, 3),
          reason: '$operation: two or three attempts in total, never more',
        );
      }
      expect(loader.effects.emitted, hasLength(1));
      expect(
        loader.effects.emitted.single,
        isA<ShowError>().having(
          (e) => e.error,
          'error',
          isA<RemoteApiRetryLaterException>(),
        ),
        reason:
            'the parallel wait failure is unwrapped to its retry-later cause, '
            'not reported as a ParallelWaitError or a generic server error',
      );
    });

    test('a mutation rejected with retry-later is not retried while the '
        'reads that follow it still recover', () async {
      final server = stubServer((call, attempt) {
        if (call.operation == _inviteCreateOp) {
          return retryLaterResponse(10);
        }
        return attempt == 1
            ? retryLaterResponse(_retryAfterMs)
            : jsonResponse(_loaded(call.operation));
      });

      final loader = await withRemote(server.client, (remote) async {
        final loader = _loader(remote);
        await loader.cubit.invite('Ubob');
        return loader;
      });

      expect(
        server.calls.where((c) => c.operation == _inviteCreateOp),
        hasLength(1),
        reason: 'a mutation is sent once, whatever the answer',
      );
      expect(
        loader.effects.emitted,
        [
          isA<ShowError>().having(
            (e) => e.error,
            'error',
            isA<RemoteApiRetryLaterException>(),
          ),
        ],
        reason: 'only the rejected mutation is reported; the reload recovers',
      );
      expect(loader.cubit.state.invites.map((i) => i.id), ['I1']);
    });
  });
}
