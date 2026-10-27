@Tags(['repo-files'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:rxdart/rxdart.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';

import '../../support/fake_person_shared_context_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/person_untrust_mutation_contract.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';

const _bob = Profile(
  id: 'Ubbbbbbbbbbbb',
  displayName: 'Bob',
  myVote: 1,
  isMutualFriend: true,
  subjectExplicitlyTrustsViewer: true,
);

void main() {
  test(
    'profile screen, People list and graph card untrust call setLike with '
    'the production zero UserVote mutation',
    () async {
      final requests = <Map<String, dynamic>>[];
      var viewerTrustsBob = true;
      await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          final likes = _RecordingLikes(
            remoteApiService: remote,
            log: Logger('untrust-contract'),
          );
          final profiles = ProfileRepository(remote);
          final realtime = buildTestRealtimeSync();
          final authLocal = StreamingAuthLocal();
          final auth = buildTestAuthCase(authLocal, EmptyAuthRemote());
          final names = ContactNameStore();
          final contacts = ContactsCase(
            FakeContactsRepository(),
            auth,
            names,
            realtime.case_,
            env: const Env(),
            logger: Logger('untrust-contacts'),
          );
          // Construct the actual profile use case with the actual read and
          // write repositories. Only unrelated capability/contact I/O is fake.
          final profileCase = ProfileViewCase(
            profiles,
            likes,
            _Capabilities(),
            contacts,
            realtime.case_,
            FakePersonSharedContextPort(),
            env: const Env(),
            logger: Logger('untrust-profile'),
          );
          final account = BehaviorSubject<String>.seeded('Uaaaaaaaaaaaa');
          final writer = GraphTrustWriteCase(
            likes,
            FakeWakeUpPort(),
            _Account(account.stream),
            env: const Env(),
            logger: Logger('untrust-graph'),
          );
          final card = GraphPersonContextCubit(
            profileViewCase: profileCase,
            trustWriteCase: writer,
            viewerId: 'Uaaaaaaaaaaaa',
          );
          GetIt.I.pushNewScope();
          GetIt.I.registerSingleton<ProfileViewCase>(profileCase);
          ProfileViewCubit? screen;
          FriendsCubit? people;
          final invitations = InvitationRepository(remote);
          try {
            await remote.setSessionAuth();
            // Use the production constructor and its normal DI lookup, not
            // ProfileViewCubit.test or a graph fixture's profile use case.
            screen = ProfileViewCubit(
              id: _bob.id,
              blockCase: noopBlockCase(),
              effects: FakeUiEffectPort(),
            );
            if (screen.state.profile.myVote != 1) {
              await screen.stream
                  .firstWhere((state) => state.profile.myVote == 1)
                  .timeout(const Duration(seconds: 5));
            }
            await screen.removeFriend();
            expect(screen.state.profile.myVote, 0);
            expect(screen.state.profile.isMutualFriend, isFalse);
            expect(likes.calls, [(_bob.id, 0)]);
            expect(requests, hasLength(1));

            // Drive the independent production People/Trusted list path.
            // Reads use the real friends repository; presence is unrelated
            // to the mutation and remains inert in this contract test.
            viewerTrustsBob = true;
            people = FriendsCubit(
              FriendsCase(
                _Capabilities(),
                invitations,
                likes,
                FriendsRemoteRepository(
                  remoteApiService: remote,
                  log: Logger('untrust-friends'),
                ),
                _Presence(),
                contacts,
                auth,
                realtime.case_,
                noopBlockCase(),
                env: const Env(),
                logger: Logger('untrust-people'),
              ),
              FakeUiEffectPort(),
            );
            await pumpEventQueue();
            people.emit(FriendsState(friends: {_bob.id: _bob}));
            await people.removeFriend(_bob);
            await pumpEventQueue();
            expect(people.state.friends, isNot(contains(_bob.id)));
            expect(likes.calls, [(_bob.id, 0), (_bob.id, 0)]);
            expect(requests, hasLength(2));
            // Cancel the list's debounced background read before moving to
            // the independent graph-card scenario.
            await people.close();
            people = null;

            // Independently start the real graph card at a mutual pair and
            // invoke its public untrust action through its production writer.
            viewerTrustsBob = true;
            card.selectProfile(_bob, intentional: true);
            await pumpEventQueue();
            // Wait for server acknowledgement, not just the optimistic
            // return from setTrust/untrustSelected.
            final acknowledged = writer.acknowledgements.first;
            await card.untrustSelected();
            expect(
              (await acknowledged.timeout(const Duration(seconds: 5))).myVote,
              0,
            );
            expect(likes.calls, [(_bob.id, 0), (_bob.id, 0), (_bob.id, 0)]);
            expect(requests, hasLength(3));
            expect(requests[1], requests[0]);
            expect(requests[2], requests[0]);
            expect(requests[0]['operationName'], 'UserVote');
            expect(requests[0]['variables'], {
              'objectId': _bob.id,
              'amount': 0,
            });

            // Compare each actual request with the independently frozen
            // production contract, rather than the current source document.
            // The server pg test submits this contract through the API.
            String normalized(String document) =>
                document.replaceAll(RegExp(r'\s+'), ' ').trim();
            for (final request in requests) {
              expect(request['operationName'], 'UserVote');
              expect(request['variables'], {'objectId': _bob.id, 'amount': 0});
              expect(
                normalized(request['query']! as String),
                normalized(personUntrustMutationDocument),
              );
            }
          } finally {
            await people?.close();
            await screen?.close();
            await card.close();
            await writer.dispose();
            await account.close();
            await GetIt.I.popScope();
            await contacts.dispose();
            await realtime.port.dispose();
            await names.dispose();
            await authLocal.dispose();
            await profiles.dispose();
            await invitations.dispose();
            await likes.dispose();
            await remote.close();
          }
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return _response({
              'subject': 'Uaaaaaaaaaaaa',
              'access_token': 'test-token',
              'expires_in': 3600,
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['operationName'] == 'UserFetchById') {
            return _response({
              'data': {
                'user_by_pk': {
                  '__typename': 'user',
                  'id': _bob.id,
                  'display_name': _bob.displayName,
                  'description': '',
                  'my_vote': viewerTrustsBob ? 1 : 0,
                  'trusts_viewer': true,
                  'is_mutual_friend': viewerTrustsBob,
                  'image': null,
                  'scores': <Object>[],
                  'user_presence': null,
                  'user_availability': null,
                },
              },
            });
          }
          expect(request.url.path, endsWith('/api/v2/graphql'));
          expect(body['operationName'], 'UserVote');
          requests.add(body);
          viewerTrustsBob = false;
          return _response({
            'data': {'userVote': 0},
          });
        }),
      );
    },
  );
}

http.Response _response(Map<String, Object?> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

/// Observes the repository method without replacing its production behavior.
final class _RecordingLikes extends LikeRemoteRepository {
  _RecordingLikes({required super.remoteApiService, required super.log});

  final calls = <(String, int)>[];

  @override
  Future<T> setLike<T extends Likable>(T entity, {required int amount}) {
    expect(entity, isA<Profile>());
    calls.add((entity.id, amount));
    return super.setLike(entity, amount: amount);
  }
}

final class _Account implements ConstellationAccountPort {
  _Account(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

final class _Capabilities extends Fake implements CapabilityRepositoryPort {
  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) async => [];
}

final class _Presence extends Fake implements PresenceRepository {
  @override
  void watch(String sourceKey, Set<String> userIds) {}

  @override
  void unwatch(String sourceKey) {}
}
