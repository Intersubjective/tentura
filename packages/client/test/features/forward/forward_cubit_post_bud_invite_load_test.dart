// The Post→Request invite step loads its people through the Forward picker
// cubit. Real Ferry link chain (only HTTP is faked): `PostBudInviteCandidates`
// supplies the ids, `UsersFetchByIds` (capped at 10 rows per request, like
// Hasura's `user` permission) supplies the names, and `forwardCandidates` is
// never asked.

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/users_fetch_by_ids_wire.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpost00000001';
const _viaId = 'Uvia000000001';
const _notInvitableId = 'Uother0000001';

String _member(int i) => 'Umember${i.toString().padLeft(5, '0')}';

/// Member 3 was brought into the Post by [_viaId].
final _viaMemberId = _member(3);

/// Member 5 has paused new requests.
final _pausedMemberId = _member(5);

/// Server preticks members 1, 2, 3 and the paused member 5.
final _preticked = {_member(1), _member(2), _member(3), _pausedMemberId};

final _invitableInServerOrder = [for (var i = 1; i <= 12; i++) _member(i)];

String _nameOf(String id) => 'Name of $id';

Map<String, dynamic> _wireCandidate(
  String userId, {
  String outcome = 'invited',
  bool pretick = false,
  String? viaUserId,
  bool hasWritten = false,
}) => {
  '__typename': 'PostBudInviteCandidate',
  'userId': userId,
  'warm': viaUserId == null,
  'outcome': outcome,
  'pretick': pretick,
  'viaUserId': viaUserId,
  'hasWritten': hasWritten,
};

/// 12 invitable members (writers first) plus one already invited member in
/// the middle of the server list.
Map<String, dynamic> _inviteCandidatesResponse() => {
  '__typename': 'query_root',
  'postBudInviteCandidates': [
    for (final (i, id) in _invitableInServerOrder.indexed) ...[
      _wireCandidate(
        id,
        pretick: _preticked.contains(id),
        viaUserId: id == _viaMemberId ? _viaId : null,
        hasWritten: i < 4,
      ),
      if (i == 6)
        _wireCandidate(
          _notInvitableId,
          outcome: 'alreadyInvited',
          pretick: true,
        ),
    ],
  ],
};

Map<String, dynamic> _usersAnswer(WireSent request) {
  final base = cappedUsersAnswer(request);
  final rows = (base['user'] as List).cast<Map<String, dynamic>>();
  for (final row in rows) {
    if (row['id'] == _pausedMemberId) {
      row['user_availability'] = {
        '__typename': 'user_availability',
        'is_limited': false,
        'resume_on': '2099-01-01',
      };
    }
  }
  return base;
}

/// One mutual friend from the regular Forward candidate source.
Map<String, dynamic> _forwardCandidatesResponse() => {
  '__typename': 'query_root',
  'forwardCandidates': [
    {
      '__typename': 'v2_user',
      'id': 'Ufriend000001',
      'displayName': 'Forward Friend',
      'handle': null,
      'description': '',
      'my_vote': 1,
      'trusts_viewer': true,
      'is_mutual_friend': true,
      'shares_active_context': false,
      'image': null,
      'scores': <Object>[],
      'user_presence': null,
      'user_availability': null,
    },
  ],
};

class _NoBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with a [ForwardCubit] for the invite step of [_postId], built
/// on the real repositories over the fake HTTP transport.
Future<List<WireSent>> _withInviteCubit(
  Future<void> Function(ForwardCubit cubit) body, {
  ForwardTargetProfile targetProfile = ForwardTargetProfile.postBudInvite,
  String? budPostId = _postId,
  Map<String, Map<String, dynamic>> errors = const {},
}) async {
  final sent = <WireSent>[];
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository()
    ..fetchMineHandler = () async => {};
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('PostBudInviteForwardTest'),
  );
  addTearDown(() async {
    await contactsCase.dispose();
    await GetIt.I.reset();
    await store.dispose();
  });
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('Uviewer000001');
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  await withRemoteWire(
    const {},
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
        ProfileRepository(remote),
        contactsCase,
        noopBlockCase(),
        postBudPort: PostBudRepository(remote),
        env: const Env(),
        logger: Logger('PostBudInviteForwardTest'),
      );
      final cubit = ForwardCubit(
        beaconId: '',
        budPostId: budPostId,
        targetProfile: targetProfile,
        forwardCase: forwardCase,
        effects: FakeUiEffectPort(),
      );
      try {
        await cubit.stream
            .firstWhere(
              (s) =>
                  s.candidatesLoad is ForwardCandidatesReady ||
                  s.candidatesLoad is ForwardCandidatesEmpty ||
                  s.candidatesLoad is ForwardCandidatesError,
            )
            .timeout(const Duration(seconds: 20));
        await body(cubit);
      } finally {
        await cubit.close();
      }
    },
    errors: errors,
    responseFor: (request) async => switch (request.operationName) {
      'PostBudInviteCandidates' => _inviteCandidatesResponse(),
      'UsersFetchByIds' => _usersAnswer(request),
      'ForwardCandidatesFetch' => _forwardCandidatesResponse(),
      _ => const <String, dynamic>{},
    },
  );
  return sent;
}

void main() {
  group('Invite step of a Post→Request bud uses the Forward picker cubit', () {
    test('lists exactly the 12 invitable members in server order, each with '
        'their real name', () async {
      late ForwardState state;
      await _withInviteCubit((cubit) async => state = cubit.state);

      expect(state.candidatesLoad, isA<ForwardCandidatesReady>());
      expect(state.beaconId, '');
      expect(
        state.candidates.map((c) => c.profile.id),
        _invitableInServerOrder,
      );
      expect(
        state.candidates.map((c) => c.profile.displayName),
        [for (final id in _invitableInServerOrder) _nameOf(id)],
      );
      expect(state.lineageSuggestions, isEmpty);
      expect(state.band, isEmpty);
    });

    test(
      'a member brought in by someone else reads «via» that person',
      () async {
        late ForwardState state;
        await _withInviteCubit((cubit) async => state = cubit.state);

        final via = state.candidates.singleWhere((c) => c.id == _viaMemberId);
        expect(via.reach?.kind, ForwardReachKind.viaConnection);
        expect(via.reach?.viaCount, 1);
        expect(via.reach?.via.single.id, _viaId);
        expect(via.reach?.via.single.displayName, _nameOf(_viaId));

        final warm = state.candidates.firstWhere((c) => c.id == _member(1));
        expect(warm.reach?.kind, ForwardReachKind.direct);
      },
    );

    test('loads the Post members once and never asks for Forward '
        'candidates', () async {
      final sent = await _withInviteCubit((_) async {});

      final names = sent.map((r) => r.operationName).toList();
      expect(names.where((n) => n == 'PostBudInviteCandidates'), hasLength(1));
      expect(
        sent
            .singleWhere((r) => r.operationName == 'PostBudInviteCandidates')
            .variables['postId'],
        _postId,
      );
      expect(names, isNot(contains('ForwardCandidatesFetch')));
    });

    test('pre-ticks the server-preticked members after load, except a paused '
        'member, who cannot be ticked', () async {
      late Set<String> selectedAfterLoad;
      late Set<String> selectedAfterTickPaused;
      await _withInviteCubit((cubit) async {
        selectedAfterLoad = {...cubit.state.selectedIds};
        cubit.toggleSelection(_pausedMemberId);
        selectedAfterTickPaused = {...cubit.state.selectedIds};
      });

      expect(selectedAfterLoad, {_member(1), _member(2), _member(3)});
      // Preticked by the server but not invitable: dropped with its row.
      expect(selectedAfterLoad, isNot(contains(_notInvitableId)));
      expect(selectedAfterLoad, isNot(contains(_pausedMemberId)));
      expect(selectedAfterTickPaused, selectedAfterLoad);
    });

    test('a reload keeps the user unticking a preticked member', () async {
      late Set<String> selectedAfterReload;
      final sent = await _withInviteCubit((cubit) async {
        expect(cubit.state.selectedIds, contains(_member(1)));
        cubit.toggleSelection(_member(1));
        await cubit.reloadCandidates().timeout(const Duration(seconds: 20));
        selectedAfterReload = cubit.state.selectedIds;
      });

      // The reload really asked the server again.
      expect(
        sent.where((r) => r.operationName == 'PostBudInviteCandidates'),
        hasLength(2),
      );
      expect(selectedAfterReload, {_member(2), _member(3)});
    });
  });

  group('Invite step when the Post members fail to load', () {
    test('shows the load error and does not fall back to Forward '
        'candidates', () async {
      late ForwardState state;
      final sent = await _withInviteCubit(
        (cubit) async => state = cubit.state,
        errors: {'PostBudInviteCandidates': wireCodeError(500)},
      );

      expect(state.candidatesLoad, isA<ForwardCandidatesError>());
      expect(state.candidates, isEmpty);
      final names = sent.map((r) => r.operationName).toList();
      expect(names, contains('PostBudInviteCandidates'));
      expect(names, isNot(contains('ForwardCandidatesFetch')));
    });
  });

  group('Forwarding a Request or a Post without a bud Post', () {
    for (final profile in [
      ForwardTargetProfile.request,
      ForwardTargetProfile.post,
    ]) {
      test('${profile.name} still loads Forward candidates, not Post '
          'members', () async {
        late ForwardState state;
        final sent = await _withInviteCubit(
          (cubit) async => state = cubit.state,
          targetProfile: profile,
          budPostId: null,
        );

        final names = sent.map((r) => r.operationName).toList();
        expect(names, contains('ForwardCandidatesFetch'));
        expect(names, isNot(contains('PostBudInviteCandidates')));
        expect(
          state.candidates.map((c) => c.profile.displayName),
          ['Forward Friend'],
        );
      });
    }
  });
}
