// #894: `mutual_since` on V2 forwardCandidates through the real Ferry link chain.

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_load.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

const _viewerId = 'Uviewer000001';
const _inviteeId = 'Uinvitee00001';

Map<String, dynamic> _v2ForwardUser({
  required String id,
  required String displayName,
  DateTime? mutualSince,
}) => {
  '__typename': 'v2_user',
  'id': id,
  'displayName': displayName,
  'handle': null,
  'description': '',
  'my_vote': 1,
  'trusts_viewer': true,
  'is_mutual_friend': true,
  'shares_active_context': false,
  if (mutualSince != null)
    'mutual_since': mutualSince.toUtc().toIso8601String(),
  'image': null,
  'scores': <Object>[],
  'user_presence': null,
  'user_availability': null,
};

class _NoBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ContactNameStore store;

  setUp(() {
    store = ContactNameStore();
  });

  tearDown(() async {
    await store.dispose();
  });

  test(
    'ForwardRepository maps mutual_since from ForwardCandidatesFetch',
    () async {
      final since = DateTime.utc(2026, 11, 3, 12);
      final sent = <WireSent>[];
      late Iterable<Profile> profiles;
      await withRemoteWire(
        {
          'ForwardCandidatesFetch': {
            '__typename': 'query_root',
            'forwardCandidates': [
              _v2ForwardUser(
                id: _inviteeId,
                displayName: 'Invitee',
                mutualSince: since,
              ),
            ],
          },
        },
        sent,
        (remote) async {
          final repo = ForwardRepository(
            remote,
            _NoBeaconRepository(),
            buildTestRealtimeSync().port,
          );
          profiles = await repo.fetchForwardCandidates();
        },
      );
      expect(sent.single.operationName, 'ForwardCandidatesFetch');
      expect(profiles.single.mutualSince, since);
    },
  );

  test(
    'ForwardRepository maps forward_reach from ForwardCandidatesFetch',
    () async {
      final sent = <WireSent>[];
      late ForwardRepository repo;
      await withRemoteWire(
        {
          'ForwardCandidatesFetch': {
            '__typename': 'query_root',
            'forwardCandidates': [
              {
                ..._v2ForwardUser(
                  id: _inviteeId,
                  displayName: 'Peer',
                ),
                'forward_reach': {
                  'kind': 'via_connection',
                  'via_count': 2,
                  'via': [
                    {'id': 'U-v1', 'displayName': 'Vadim', 'image': null},
                  ],
                  'shared_request_id': null,
                  'shared_request_title': null,
                },
              },
            ],
          },
        },
        sent,
        (remote) async {
          repo = ForwardRepository(
            remote,
            _NoBeaconRepository(),
            buildTestRealtimeSync().port,
          );
          await repo.fetchForwardCandidates();
        },
      );
      expect(repo.forwardReachFor(_inviteeId)?.kind, ForwardReachKind.viaConnection);
      expect(repo.forwardReachFor(_inviteeId)?.viaCount, 2);
      expect(repo.forwardReachFor(_inviteeId)?.via.single.displayName, 'Vadim');
    },
  );

  test(
    'loadForwardCandidates after invite mutual trust exposes mutualSince on '
    'ForwardCandidate (real wire path)',
    () async {
      final mutualSince = DateTime.utc(2026, 11, 3, 8, 30);
      final sent = <WireSent>[];
      final authLocal = StreamingAuthLocal();
      final contactsCase = ContactsCase(
        FakeContactsRepository(),
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
        store,
        buildTestRealtimeSync().case_,
        env: const Env(),
        logger: Logger('ForwardMutualSinceWireTest'),
      );
      authLocal.emit(_viewerId);
      await Future<void>.delayed(Duration.zero);

      late ForwardLoad load;
      await withRemoteWire(
        {
          'ForwardCandidatesFetch': {
            '__typename': 'query_root',
            'forwardCandidates': [
              _v2ForwardUser(
                id: _inviteeId,
                displayName: 'Новый друг',
                mutualSince: mutualSince,
              ),
            ],
          },
        },
        sent,
        (remote) async {
          final forwardCase = ForwardCase(
            ForwardRepository(
              remote,
              _NoBeaconRepository(),
              buildTestRealtimeSync().port,
            ),
            authLocal,
            _FakeBeaconFactCardRepository(),
            _FakeProfileRepository(),
            contactsCase,
            noopBlockCase(),
            env: const Env(),
            logger: Logger('ForwardMutualSinceWireTest'),
          );
          load = await forwardCase.loadForwardCandidates(beaconId: '');
        },
      );

      expect(
        sent.map((e) => e.operationName),
        contains('ForwardCandidatesFetch'),
      );
      final invitee = load.candidates.singleWhere((c) => c.id == _inviteeId);
      expect(invitee.mutualSince, mutualSince);
      expect(invitee.profile.mutualSince, mutualSince);
    },
  );
}
