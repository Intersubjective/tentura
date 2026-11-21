// `ForwardCase.loadPostBudInviteCandidates` turns the Post's invite candidate
// list into Forward picker rows: invitable members only, in server order, with
// their real profiles, «через X» reach and the server pretick.

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/post_bud_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';

class _FakePostBudPort implements PostBudPort {
  _FakePostBudPort(this.candidates);

  final List<PostBudInviteCandidate> candidates;
  final requestedPostIds = <String>[];

  @override
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
  }) async {
    requestedPostIds.add(postId);
    return candidates;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  _FakeProfileRepository(this.known);

  /// Profiles the server returns, by id; ids not here come back missing.
  final Map<String, Profile> known;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (known[id] != null) known[id]!,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Any call to the Forward candidate source fails the test.
class _NoForwardCandidatesRepository implements ForwardRepository {
  int fetchForwardCandidatesCalls = 0;

  @override
  Stream<String> get forwardChanges => const Stream.empty();

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    fetchForwardCandidatesCalls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PostBudInviteCandidate _candidate(
  String userId, {
  PostBudInviteOutcome outcome = PostBudInviteOutcome.invited,
  bool pretick = false,
  bool hasWritten = false,
  String? viaUserId,
}) => PostBudInviteCandidate(
  userId: userId,
  warm: viaUserId == null,
  outcome: outcome,
  pretick: pretick,
  hasWritten: hasWritten,
  viaUserId: viaUserId,
);

Profile _profile(String id, String name) => Profile(
  id: id,
  displayName: name,
  myVote: 1,
  subjectExplicitlyTrustsViewer: true,
);

final _serverList = [
  _candidate('A', hasWritten: true, pretick: true),
  _candidate('X', outcome: PostBudInviteOutcome.alreadyInvited, pretick: true),
  _candidate('B'),
  _candidate('C', viaUserId: 'V', pretick: true),
];

final _allProfiles = {
  'A': _profile('A', 'Anna'),
  'X': _profile('X', 'Xenia'),
  'B': _profile('B', 'Boris'),
  'C': _profile('C', 'Clara'),
  'V': _profile('V', 'Vadim'),
};

Future<
  ({
    ForwardCase forwardCase,
    _FakePostBudPort postBud,
    _NoForwardCandidatesRepository forwardRepo,
  })
>
_harness({
  List<PostBudInviteCandidate>? candidates,
  Map<String, Profile>? profiles,
}) async {
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final postBud = _FakePostBudPort(candidates ?? _serverList);
  final forwardRepo = _NoForwardCandidatesRepository();
  final forwardCase = ForwardCase(
    forwardRepo,
    authLocal,
    _FakeBeaconFactCardRepository(),
    _FakeProfileRepository(profiles ?? _allProfiles),
    contactsCase,
    ControllableBlockCase(),
    postBudPort: postBud,
  );
  contactsRepo.fetchMineHandler = () async => {};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('viewer');
  await syncReady;
  await Future<void>.delayed(Duration.zero);
  addTearDown(() async {
    await contactsCase.dispose();
    await GetIt.I.reset();
    await store.dispose();
  });
  return (forwardCase: forwardCase, postBud: postBud, forwardRepo: forwardRepo);
}

void main() {
  group('Loading Post members as invite candidates', () {
    test(
      'lists only invitable members, in server order, for that Post',
      () async {
        final h = await _harness();

        final load = await h.forwardCase.loadPostBudInviteCandidates('post-1');

        expect(h.postBud.requestedPostIds, ['post-1']);
        expect(load.candidates.map((c) => c.profile.id), ['A', 'B', 'C']);
        expect(
          load.candidates.map((c) => c.profile.displayName),
          ['Anna', 'Boris', 'Clara'],
        );
        expect(h.forwardRepo.fetchForwardCandidatesCalls, 0);
      },
    );

    test('a cold member (no vote, no trust, no shared context) is still '
        'tickable and keeps the server pretick', () async {
      final h = await _harness(
        profiles: {
          for (final id in ['A', 'X', 'B', 'C', 'V']) id: Profile(id: id),
        },
      );

      final load = await h.forwardCase.loadPostBudInviteCandidates('post-1');

      expect(load.candidates.map((c) => c.profile.id), ['A', 'B', 'C']);
      for (final c in load.candidates) {
        expect(c.isReachable, isTrue, reason: c.profile.id);
        expect(c.canForwardTo, isTrue, reason: c.profile.id);
      }
      expect(load.autoSelectIds, {'A', 'C'});
    });

    test('a warm member is reached directly; a member brought by someone '
        'shows «via» that person even when they are not a candidate', () async {
      final h = await _harness();

      final load = await h.forwardCase.loadPostBudInviteCandidates(
        'post-1',
      );
      final byId = {for (final c in load.candidates) c.profile.id: c};

      expect(byId['A']!.reach?.kind, ForwardReachKind.direct);
      expect(byId['B']!.reach?.kind, ForwardReachKind.direct);

      final viaReach = byId['C']!.reach;
      expect(viaReach?.kind, ForwardReachKind.viaConnection);
      expect(viaReach?.viaCount, 1);
      expect(viaReach?.via.map((p) => p.id), ['V']);
      expect(viaReach?.via.single.displayName, 'Vadim');
    });

    test(
      'a member whose profile did not load keeps their row and place',
      () async {
        final h = await _harness(
          profiles: Map.of(_allProfiles)..remove('B'),
        );

        final load = await h.forwardCase.loadPostBudInviteCandidates('post-1');

        expect(load.candidates.map((c) => c.profile.id), ['A', 'B', 'C']);
        expect(load.candidates[0].profile.displayName, 'Anna');
        expect(load.candidates[2].profile.displayName, 'Clara');
        // B falls back to a bare profile: its id, no borrowed name.
        expect(load.candidates[1].profile.id, 'B');
        expect(load.candidates[1].profile.displayName, isEmpty);
        expect(load.candidates[1].profile, const Profile(id: 'B'));
      },
    );

    test('carries no lineage or band and pre-ticks the invitable members the '
        'server preticked', () async {
      final h = await _harness();

      final load = await h.forwardCase.loadPostBudInviteCandidates(
        'post-1',
      );

      expect(load.lineageSuggestions, isEmpty);
      expect(load.band, isEmpty);
      // X is preticked by the server but cannot be invited: dropped with its row.
      expect(load.autoSelectIds, {'A', 'C'});
    });
  });
}
