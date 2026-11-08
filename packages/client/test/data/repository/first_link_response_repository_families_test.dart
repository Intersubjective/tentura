// #1187 review: every repository family that awaits its Link response through
// firstLinkResponse(label:) throws GraphQLNoDataException(label) when the
// request stream closes without a Link response, not the bare StateError
// ("No element") that `firstWhere` threw. One representative method per
// family (feature folder / RemoteRepository base); the data/ core family is
// pinned through AttentionRepository in
// test/data/service/first_link_response_contract_test.dart.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart';
import 'package:tentura/data/repository/offer_accepted_dismissal_repository.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart'
    show RemoteApiService;
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_plan/data/repository/beacon_plan_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';
import 'package:tentura/features/block/data/repository/block_repository.dart';
import 'package:tentura/features/capability/data/repository/capability_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/contacts/data/repository/contacts_repository.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward_candidate_context/data/repository/forward_candidate_context_repository.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/notification_settings/data/repository/notification_settings_repository.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/data/repository/post_mute_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile_view/data/repository/mutual_friends_repository.dart';
import 'package:tentura/features/rating/data/repository/rating_repository.dart';
import 'package:tentura/features/settings/data/repository/trust_preference_repository.dart';

import '../../support/remote_wire_harness.dart';

/// Answers every request with a stream that closes at once: no Link (or any)
/// response ever arrives.
class _EmptyStreamClient implements RemoteRequestClient {
  int requests = 0;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    requests++;
    return const Stream.empty();
  }
}

final class _QuietRealtimeSync implements RealtimeSyncPort {
  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  @override
  Stream<RealtimeCatchUp> get catchUps => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}

  @override
  Future<void> dispose() async {}
}

Matcher _noData(String label) => throwsA(
  allOf(
    isNot(isA<StateError>()),
    isA<GraphQLNoDataException>().having((e) => e.label, 'label', label),
  ),
);

/// One family: [call] issues one request through the client it is handed and
/// must fail with
/// `GraphQLNoDataException(label)`.
void _family(
  String family,
  String method,
  String label,
  Future<Object?> Function(RemoteRequestClient remote) call,
) => test(
  '$family: $method on an empty request stream throws '
  'GraphQLNoDataException($label), not StateError',
  () async {
    final remote = _EmptyStreamClient();
    await expectLater(call(remote), _noData(label));
    expect(remote.requests, 1);
  },
);

/// For the two families still typed on the concrete RemoteApiService: the
/// real service over the real link chain, its client disposed while the
/// request is in flight (the #999 path), so the stream ends with no Link
/// response.
Future<void> _disposedMidRequest(
  Future<Object?> Function(RemoteApiService remote) call,
  String label,
) async {
  final release = Completer<Map<String, dynamic>>();
  final sent = <WireSent>[];
  await withRemoteWire(
    const {},
    sent,
    (remote) async {
      final failure = expectLater(
        call(remote),
        throwsA(
          allOf(
            isNot(isA<StateError>()),
            isA<GraphQLNoDataException>(),
          ),
        ),
        reason: label,
      );
      while (sent.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await remote.dropAuth();
      await failure;
    },
    responseFor: (_) => release.future,
  );
  release.complete(const {});
}

void main() {
  _family(
    'auth',
    'AuthRemoteRepository.authTokenFetcher',
    'Auth',
    (remote) => AuthRemoteRepository.authTokenFetcher(remote.request, 'jwt'),
  );
  _family(
    'beacon',
    'AuthorInviteRepository.accept',
    'AuthorInvite',
    (remote) => AuthorInviteRepository(remote).accept(inviteId: 'i-1'),
  );
  _family(
    'beacon_plan',
    'BeaconPlanRepository.fetch',
    'BeaconPlan',
    (remote) => BeaconPlanRepository(remote, _QuietRealtimeSync()).fetch('B1'),
  );
  _family(
    'beacon_threads',
    'BeaconFactCardRepository.list',
    'BeaconFactCard',
    (remote) => BeaconFactCardRepository(remote).list(beaconId: 'B1'),
  );
  _family(
    'beacon_view',
    'CoordinationRepository.fetchMyHelpOffer',
    'Coordination',
    (remote) => CoordinationRepository(remote).fetchMyHelpOffer(beaconId: 'B1'),
  );
  _family(
    'block',
    'BlockRepository.unblock',
    'Block',
    (remote) => BlockRepository(remote).unblock(objectId: 'U1'),
  );
  _family(
    'capability',
    'CapabilityRepository.fetchCues',
    'Capability',
    (remote) =>
        CapabilityRepository(remote, _QuietRealtimeSync()).fetchCues('U1'),
  );
  _family(
    'closure',
    'ClosureRepository.fetchState',
    'ClosureRepository',
    (remote) => ClosureRepository(remote).fetchState('B1'),
  );
  _family(
    'contacts',
    'ContactsRepository.fetchMine',
    'Contacts',
    (remote) => ContactsRepository(
      remote,
      Database(const Env(), Logger('test'), NativeDatabase.memory()),
    ).fetchMine(),
  );
  _family(
    'context',
    'ContextRepository.fetch(fromCache: false)',
    'Context',
    (remote) => ContextRepository(remote).fetch(fromCache: false),
  );
  _family(
    'forward',
    'ForwardRepository.currentUserHasForwardedBeacon',
    'Forward',
    (remote) => ForwardRepository(
      remote,
      BeaconRepository(remote, _QuietRealtimeSync()),
      _QuietRealtimeSync(),
    ).currentUserHasForwardedBeacon('B1'),
  );
  _family(
    'forward_candidate_context',
    'ForwardCandidateContextRepository.load',
    'ForwardCandidateContextFetch',
    (remote) => ForwardCandidateContextRepository(
      remote,
    ).load(candidateId: 'U1', context: ''),
  );
  _family(
    'inbox',
    'PostsRepository.myPosts',
    'MyPosts',
    (remote) => PostsRepository(remote).myPosts(),
  );
  _family(
    'notification_settings',
    'NotificationSettingsRepository.fetch',
    'NotificationSettings',
    (remote) => NotificationSettingsRepository(remote).fetch(),
  );
  _family(
    'people_tags',
    'PeopleTagsRepository.personTags',
    'PersonTags',
    (remote) => PeopleTagsRepository(remote).personTags(),
  );
  _family(
    'polling',
    'PollingRepository.vote',
    'Polling',
    (remote) =>
        PollingRepository(remote).vote(pollingId: 'P1', variantIds: ['v1']),
  );
  _family(
    'post_view',
    'BeaconKindRepository.fetchKind',
    'BeaconKindFetch',
    (remote) => BeaconKindRepository(remote).fetchKind('B1'),
  );
  _family(
    'profile',
    'ProfileRepository.fetchById',
    'Profile',
    (remote) => ProfileRepository(remote).fetchById('U1'),
  );
  _family(
    'profile_view',
    'MutualFriendsRepository.fetchMutualFriends',
    'MutualFriends',
    (remote) => MutualFriendsRepository(remote).fetchMutualFriends('U1'),
  );
  _family(
    'rating',
    'RatingRepository.fetch',
    'Rating',
    (remote) => RatingRepository(remote).fetch(context: ''),
  );
  _family(
    'settings',
    'TrustPreferenceRepository.fetchNoisyWallEnabled',
    'TrustPreference',
    (remote) => TrustPreferenceRepository(remote).fetchNoisyWallEnabled(),
  );
  _family(
    'core data/',
    'OfferAcceptedDismissalRepository.load',
    'OfferAcceptedDismissals',
    (remote) => OfferAcceptedDismissalRepository(remote).load(viewerId: 'U1'),
  );

  test(
    'invitation: InvitationRepository.fetchTtlHours with the client '
    'disposed mid-request throws GraphQLNoDataException, not StateError',
    () => _disposedMidRequest(
      (remote) => InvitationRepository(remote).fetchTtlHours(),
      'Invitation',
    ),
  );

  test(
    'RemoteRepository base: PostMuteRepository.clearMute with the client '
    'disposed mid-request throws GraphQLNoDataException, not StateError',
    () => _disposedMidRequest(
      (remote) => PostMuteRepository(
        remoteApiService: remote,
        log: Logger('test'),
      ).clearMute('B1'),
      'PostMute',
    ),
  );
}
