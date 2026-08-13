import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/model/person_action_policy.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

const _me = Profile(id: 'Ume', displayName: 'Me');

Profile _alice({
  int myVote = 0,
  double rScore = 0,
  bool trustsViewer = false,
}) => Profile(
  id: 'Ualice',
  displayName: 'Alice',
  myVote: myVote,
  rScore: rScore,
  subjectExplicitlyTrustsViewer: trustsViewer,
);

Profile _bob({int myVote = 0}) => Profile(
  id: 'Ubob',
  displayName: 'Bob',
  myVote: myVote,
);

EdgeDirected _e(
  String src,
  String dst, {
  NodeDetails? dstNode,
}) => (
  src: src,
  dst: dst,
  weight: 1,
  node: dstNode,
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

Future<void> _settle() => pumpEventQueue(times: 5);

NodeDetails _liveNode(GraphCubit cubit, String id) =>
    cubit.graphController.nodes.singleWhere((n) => n.id == id);

void main() {
  group('GraphPersonContextCubit', () {
    late _Harness harness;

    setUp(() => harness = _Harness());

    tearDown(() => harness.dispose());

    test(
      'successful trust patches graph and panel from authoritative profile',
      () async {
        final alice = _alice(rScore: 1);
        await harness.loadGraph(alice: alice, bob: _bob());
        harness
          ..profiles.refetchResult = _alice(
            myVote: 1,
            rScore: 1,
            trustsViewer: true,
          )
          ..likes.mutationResult = _alice(myVote: 1);

        harness.contextCubit.selectProfile(alice, intentional: true);
        await harness.contextCubit.trustSelected();
        await _settle();

        final node = _liveNode(harness.graphCubit, 'Ualice') as UserNode;
        expect(node.user.myVote, 1);
        expect(node.user.subjectExplicitlyTrustsViewer, isTrue);

        final panel = harness.contextCubit.state.selectedProfile!;
        final policy = PersonActionPolicy.from(
          panel,
          isSelf: false,
          isBlocked: false,
        );
        expect(policy.primaryAction, PersonPrimaryAction.sendRequest);
        expect(harness.contextCubit.state.trustLoading, isFalse);
        expect(harness.contextCubit.state.trustError, isNull);
      },
    );

    test('neither → viewer-only trust does not enable Send primary', () async {
      final alice = _alice();
      await harness.loadGraph(alice: alice, bob: _bob());
      harness
        ..profiles.refetchResult = _alice(myVote: 1)
        ..likes.mutationResult = _alice(myVote: 1);

      harness.contextCubit.selectProfile(alice, intentional: true);
      await harness.contextCubit.trustSelected();
      await _settle();

      final policy = PersonActionPolicy.from(
        harness.contextCubit.state.selectedProfile!,
        isSelf: false,
        isBlocked: false,
      );
      expect(policy.visibilityState, PersonVisibilityState.viewerOnly);
      expect(policy.primaryAction, PersonPrimaryAction.none);
      expect(policy.canDirectSendRequest, isFalse);
    });

    test('subject-only → mutual trust enables Send primary', () async {
      final alice = _alice(rScore: 1);
      await harness.loadGraph(alice: alice, bob: _bob());
      harness
        ..profiles.refetchResult = _alice(
          myVote: 1,
          rScore: 1,
          trustsViewer: true,
        )
        ..likes.mutationResult = _alice(myVote: 1, rScore: 1);

      harness.contextCubit.selectProfile(alice, intentional: true);
      await harness.contextCubit.trustSelected();
      await _settle();

      final policy = PersonActionPolicy.from(
        harness.contextCubit.state.selectedProfile!,
        isSelf: false,
        isBlocked: false,
      );
      expect(policy.visibilityState, PersonVisibilityState.mutual);
      expect(policy.primaryAction, PersonPrimaryAction.sendRequest);
    });

    test(
      'dismiss then intentional reselect retains patched trust projection',
      () async {
        final alice = _alice();
        await harness.loadGraph(alice: alice, bob: _bob());
        harness
          ..profiles.refetchResult = _alice(myVote: 1)
          ..likes.mutationResult = _alice(myVote: 1);

        harness.contextCubit.selectProfile(alice, intentional: true);
        await harness.contextCubit.trustSelected();
        await _settle();

        harness.contextCubit.dismiss();
        expect(harness.contextCubit.state.dismissedFocusId, 'Ualice');

        harness.contextCubit.selectProfile(
          harness.contextCubit.state.selectedProfile!,
          intentional: true,
        );
        expect(harness.contextCubit.state.dismissedFocusId, isNull);
        expect(harness.contextCubit.state.selectedProfile!.myVote, 1);
      },
    );

    test(
      'switch Alice to Bob while Alice trust pending patches Alice graph only',
      () async {
        final alice = _alice();
        final bob = _bob();
        await harness.loadGraph(alice: alice, bob: bob);
        harness.graphCubit.selectNode(_liveNode(harness.graphCubit, 'Ualice'));
        await _settle();

        final fetchCompleter = Completer<Profile>();
        harness.profiles.pendingFetch = fetchCompleter;

        harness.contextCubit.selectProfile(alice, intentional: true);
        final trustFuture = harness.contextCubit.trustSelected();
        expect(harness.contextCubit.state.trustLoading, isTrue);

        harness.contextCubit.selectProfile(bob, intentional: true);
        expect(harness.contextCubit.state.selectedProfile!.id, 'Ubob');
        expect(harness.contextCubit.state.trustLoading, isFalse);

        fetchCompleter.complete(_alice(myVote: 1));
        await expectLater(trustFuture, completes);
        await _settle();

        final aliceNode = _liveNode(harness.graphCubit, 'Ualice') as UserNode;
        expect(aliceNode.user.myVote, 1);
        expect(harness.contextCubit.state.selectedProfile!.id, 'Ubob');
        expect(harness.contextCubit.state.selectedProfile!.myVote, 0);
        expect(harness.contextCubit.state.trustError, isNull);
      },
    );

    test('late Alice trust error does not become Bob panel error', () async {
      final alice = _alice();
      final bob = _bob();
      await harness.loadGraph(alice: alice, bob: bob);

      final fetchCompleter = Completer<Profile>();
      harness.profiles.pendingFetch = fetchCompleter;

      harness.contextCubit.selectProfile(alice, intentional: true);
      final trustFuture = harness.contextCubit.trustSelected();

      harness.contextCubit.selectProfile(bob, intentional: true);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      fetchCompleter.completeError(StateError('alice failed'));
      await expectLater(trustFuture, completes);
      await _settle();

      expect(harness.contextCubit.state.selectedProfile!.id, 'Ubob');
      expect(harness.contextCubit.state.trustError, isNull);
      expect(harness.contextCubit.state.trustLoading, isFalse);
    });

    test('close during trust request causes no emit-after-close', () async {
      final alice = _alice();
      await harness.loadGraph(alice: alice, bob: _bob());

      final fetchCompleter = Completer<Profile>();
      harness.profiles.pendingFetch = fetchCompleter;

      harness.contextCubit.selectProfile(alice, intentional: true);
      final trustFuture = harness.contextCubit.trustSelected();
      final lastState = harness.contextCubit.state;

      await harness.contextCubit.close();
      fetchCompleter.complete(_alice(myVote: 1));
      await expectLater(trustFuture, completes);
      await _settle();

      expect(harness.contextCubit.isClosed, isTrue);
      expect(harness.contextCubit.state, lastState);
    });

    test(
      'repeated intentional tap on current person reopens dismissed panel',
      () async {
        final alice = _alice();
        await harness.loadGraph(alice: alice, bob: _bob());

        harness.contextCubit.selectProfile(alice, intentional: true);
        harness.contextCubit.dismiss();
        expect(harness.contextCubit.state.dismissedFocusId, 'Ualice');

        harness.contextCubit.selectProfile(alice, intentional: true);
        expect(harness.contextCubit.state.dismissedFocusId, isNull);
        expect(harness.contextCubit.state.selectedProfile!.id, 'Ualice');
      },
    );

    test(
      'graph-driven re-emission of dismissed focus does not reopen panel',
      () async {
        final alice = _alice();
        await harness.loadGraph(alice: alice, bob: _bob());

        harness.contextCubit.selectProfile(alice, intentional: true);
        harness.contextCubit.dismiss();

        harness.contextCubit.selectProfile(
          alice.copyWith(displayName: 'Alice refreshed'),
          intentional: false,
        );

        expect(harness.contextCubit.state.dismissedFocusId, 'Ualice');
        expect(
          harness.contextCubit.state.selectedProfile!.displayName,
          'Alice',
        );
      },
    );

    test('clearSelection resets panel state', () async {
      final alice = _alice();
      await harness.loadGraph(alice: alice, bob: _bob());

      harness.contextCubit.selectProfile(alice, intentional: true);
      harness.contextCubit.clearSelection();

      expect(harness.contextCubit.state.selectedProfile, isNull);
      expect(harness.contextCubit.state.dismissedFocusId, isNull);
      expect(harness.contextCubit.state.trustLoading, isFalse);
      expect(harness.contextCubit.state.trustError, isNull);
    });
  });
}

final class _Harness {
  _Harness() {
    profiles = _FakeProfileRepository();
    likes = _ControllableLikeRepository(profiles);
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    authCase = buildTestAuthCase(authLocal, EmptyAuthRemote());
    contactsCase = ContactsCase(
      contactsRepository,
      authCase,
      contactStore,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
    case_ = ProfileViewCase(
      profiles,
      likes,
      capabilities,
      contactsCase,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
  }

  final authLocal = StreamingAuthLocal();
  final contactsRepository = FakeContactsRepository();
  final contactStore = ContactNameStore();
  late final _FakeProfileRepository profiles;
  late final _ControllableLikeRepository likes;
  final capabilities = _FakeCapabilityRepository();
  final source = _FakeGraphSource();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final ProfileViewCase case_;
  late GraphCubit graphCubit;
  late GraphPersonContextCubit contextCubit;

  Future<void> loadGraph({required Profile alice, required Profile bob}) async {
    source.pages
      ..clear()
      ..addAll({
        null: {
          _e('Ume', 'Ualice', dstNode: UserNode(user: alice)),
          _e('Ume', 'Ubob', dstNode: UserNode(user: bob)),
        },
      });
    profiles.byId
      ..clear()
      ..addAll({
        'Ualice': alice,
        'Ubob': bob,
      });

    graphCubit = GraphCubit(
      me: _me,
      graphSourceRepository: source,
      edgeColors: _edgeColors,
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _GraphProfileRepository(profiles.byId),
      effects: FakeUiEffectPort(),
    );
    contextCubit = GraphPersonContextCubit(
      profileViewCase: case_,
      graphCubit: graphCubit,
    );
    await _settle();
  }

  Future<void> dispose() async {
    if (!contextCubit.isClosed) {
      await contextCubit.close();
    }
    await graphCubit.close();
    await contactsCase.dispose();
    await realtimePort.dispose();
    await contactStore.dispose();
    await profiles.dispose();
    await likes.dispose();
    await capabilities.dispose();
    await authLocal.dispose();
  }
}

class _FakeGraphSource implements GraphSourceRepository {
  final pages = <String?, Set<EdgeDirected>>{};

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async => pages[focus] ?? const {};

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async => const {};
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _GraphProfileRepository implements ProfileRepositoryPort {
  _GraphProfileRepository(this.byId);

  final Map<String, Profile> byId;

  @override
  Future<Profile> fetchById(String id) async => byId[id] ?? Profile(id: id);

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();
  final byId = <String, Profile>{};
  Profile? refetchResult;
  bool authoritativeOnNextFetch = false;
  Completer<Profile>? pendingFetch;
  int fetchCalls = 0;

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
    if (pendingFetch != null) {
      return pendingFetch!.future;
    }
    if (authoritativeOnNextFetch) {
      authoritativeOnNextFetch = false;
      return refetchResult ?? byId[id] ?? Profile(id: id);
    }
    return byId[id] ?? Profile(id: id);
  }

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    dynamic image,
    bool updateHandle = false,
    String? handle,
  }) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) async {}

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) async {}

  @override
  Future<void> resumeAvailability({required String profileId}) async {}

  @override
  Future<void> dispose() => _changes.close();
}

final class _ControllableLikeRepository implements LikeRemoteRepository {
  final _changes = StreamController<RepositoryEvent<Likable>>.broadcast();
  Profile mutationResult = Profile(id: 'Ualice');
  Completer<Profile>? pendingAddFriend;
  final _FakeProfileRepository profiles;

  _ControllableLikeRepository(this.profiles);

  @override
  Stream<RepositoryEvent<Likable>> get changes => _changes.stream;

  @override
  Future<T> setLike<T extends Likable>(T entity, {required int amount}) async {
    profiles.authoritativeOnNextFetch = true;
    if (pendingAddFriend != null) {
      return pendingAddFriend!.future as T;
    }
    return mutationResult as T;
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
