import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/like/domain/exception.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../support/graph_trust_write_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// #359: after Stop trusting, the trust graph keeps the edge from Me and the
// mutual badge until a reload, and other people must stay on the canvas.
//
// The fake graph source deliberately keeps serving the pre-write pages: the
// trust write is lazy (GraphTrustWriteCase), so a refetch can race it and
// paint the stale edge again. The graph has to update from the local change.

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

  /// Server truth for edge-closure reads; empty unless a test sets it.
  final between = <EdgeDirected>{};
  final betweenCalls = <Set<String>>[];

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async {
    betweenCalls.add({...nodeIds});
    return {
      for (final e in between)
        if (nodeIds.contains(e.src) && nodeIds.contains(e.dst)) e,
    };
  }
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  final fetchedIds = <String>[];
  final byId = <String, Profile>{};

  @override
  Future<Profile> fetchById(String id) async {
    fetchedIds.add(id);
    return byId[id] ?? Profile(id: id, displayName: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

const _me = Profile(id: 'Ume', displayName: 'Me');

/// Alice and Me trust each other.
const _aliceMutual = Profile(
  id: 'Ualice',
  displayName: 'Alice',
  myVote: 1,
  subjectExplicitlyTrustsViewer: true,
  isMutualFriend: true,
);

/// Me trusts Alice; Alice does not trust Me.
const _aliceOneWay = Profile(id: 'Ualice', displayName: 'Alice', myVote: 1);

/// Alice trusts Me; Me does not (yet, or any more) trust Alice.
const _aliceTrustsMe = Profile(
  id: 'Ualice',
  displayName: 'Alice',
  subjectExplicitlyTrustsViewer: true,
);

/// Real Me -> peer edge weights are scores, not the 0/1 vote. Seeding a
/// non-1 weight makes a revert prove the original edge came back instead of
/// a freshly invented `weight: 1`.
const _myWeightToAlice = 0.42;

const _bob = Profile(id: 'Ubob', displayName: 'Bob', myVote: 1);
const _carol = Profile(id: 'Ucarol', displayName: 'Carol');

EdgeDirected _e(
  String src,
  String dst, {
  double weight = 1,
  NodeDetails? dstNode,
}) => (
  src: src,
  dst: dst,
  weight: weight,
  node: dstNode,
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

Future<void> _settle() => pumpEventQueue(times: 5);

/// Me -> Alice (weight [_myWeightToAlice]; plus Alice -> Me when [mutual]),
/// Me -> Bob, Alice -> Carol.
_FakeGraphSource _source({required bool mutual}) {
  final alice = mutual ? _aliceMutual : _aliceOneWay;
  return _FakeGraphSource()
    ..pages[null] = {
      _e(
        'Ume',
        'Ualice',
        weight: _myWeightToAlice,
        dstNode: UserNode(user: alice),
      ),
      if (mutual) _e('Ualice', 'Ume'),
      _e('Ume', 'Ubob', dstNode: const UserNode(user: _bob)),
      _e('Ualice', 'Ucarol', dstNode: const UserNode(user: _carol)),
    };
}

GraphCubit _trustCubit(
  _FakeGraphSource source, [
  _FakeProfileRepository? profileRepo,
]) => GraphCubit(
  me: _me,
  graphSourceRepository: source,
  edgeColors: _edgeColors,
  beaconRepository: _FakeBeaconRepository(),
  profileRepository: profileRepo ?? _FakeProfileRepository(),
  effects: FakeUiEffectPort(),
);

NodeDetails _liveNode(GraphCubit cubit, String id) =>
    cubit.graphController.nodes.singleWhere((n) => n.id == id);

Set<String> _liveNodeIds(GraphCubit cubit) => {
  for (final n in cubit.graphController.nodes) n.id,
};

Set<(String, String)> _edgePairs(GraphCubit cubit) => {
  for (final e in cubit.graphController.edges) (e.source.id, e.destination.id),
};

/// The single rendered edge joining [a] and [b], in either direction.
EdgeDetails? _edgeBetween(GraphCubit cubit, String a, String b) {
  final matches = [
    for (final e in cubit.graphController.edges)
      if ((e.source.id == a && e.destination.id == b) ||
          (e.source.id == b && e.destination.id == a))
        e,
  ];
  expect(matches.length, lessThanOrEqualTo(1));
  return matches.isEmpty ? null : matches.single;
}

void main() {
  group('Stop trusting updates the trust graph in place (#359)', () {
    test(
      'stopping trust in a mutual friend drops my edge and keeps theirs',
      () async {
        final profileRepo = _FakeProfileRepository();
        final cubit = _trustCubit(_source(mutual: true), profileRepo);
        addTearDown(cubit.close);
        await _settle();

        // Preconditions: a mutual pair is drawn as one reciprocal edge.
        expect(cubit.viewerLink('Ualice'), (
          fromViewer: _myWeightToAlice,
          toViewer: 1.0,
        ));
        expect(_edgeBetween(cubit, 'Ualice', 'Ume')!.isReciprocal, isTrue);
        expect(
          _liveNodeIds(cubit),
          containsAll(<String>['Ume', 'Ualice', 'Ubob', 'Ucarol']),
        );

        // Guard: a patch that keeps my trust must not touch any edge.
        final pairsBefore = _edgePairs(cubit);
        cubit.patchLoadedProfile(_aliceMutual.copyWith(rScore: 3));
        await _settle();
        expect(_edgePairs(cubit), pairsBefore);
        expect(cubit.viewerLink('Ualice'), (
          fromViewer: _myWeightToAlice,
          toViewer: 1.0,
        ));

        final fetchesBefore = profileRepo.fetchedIds.length;
        cubit.patchLoadedProfile(_aliceMutual.copyWith(myVote: 0));
        await _settle();

        // My edge to Alice is gone; Alice -> Me stays (one-way them -> you).
        expect(cubit.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));
        final link = _edgeBetween(cubit, 'Ualice', 'Ume');
        expect(link, isNotNull);
        expect(link!.source.id, 'Ualice');
        expect(link.destination.id, 'Ume');
        expect(link.isReciprocal, isFalse);

        // Nobody else moves.
        expect(
          _liveNodeIds(cubit),
          containsAll(<String>['Ume', 'Ualice', 'Ubob', 'Ucarol']),
        );
        expect(
          _edgePairs(cubit),
          containsAll(<(String, String)>[
            ('Ume', 'Ubob'),
            ('Ualice', 'Ucarol'),
          ]),
        );
        expect(cubit.viewerLink('Ubob'), (fromViewer: 1.0, toViewer: null));
        expect(profileRepo.fetchedIds.length, fetchesBefore);
      },
    );

    test(
      'stopping trust with the card open keeps the person and neighbours',
      () async {
        final cubit = _trustCubit(_source(mutual: true));
        addTearDown(cubit.close);
        await _settle();
        cubit.selectNode(_liveNode(cubit, 'Ualice'));
        await _settle();

        // Preconditions: focused mutual edge shows arrows at both ends.
        final before = _edgeBetween(cubit, 'Ualice', 'Ume')!;
        expect(before.isReciprocal, isTrue);
        expect(before.arrowAtSource, isTrue);
        expect(before.arrowAtDestination, isTrue);

        cubit.patchLoadedProfile(_aliceMutual.copyWith(myVote: 0));
        await _settle();

        expect(cubit.state.focus, 'Ualice');
        expect(_liveNodeIds(cubit), containsAll(<String>['Ume', 'Ualice']));
        expect(_liveNodeIds(cubit), contains('Ucarol'));
        expect(_edgePairs(cubit), contains(('Ualice', 'Ucarol')));

        final after = _edgeBetween(cubit, 'Ualice', 'Ume');
        expect(after, isNotNull);
        expect(after!.source.id, 'Ualice');
        expect(after.isReciprocal, isFalse);
        expect(after.arrowAtSource, isFalse);
        expect(after.arrowAtDestination, isTrue);

        // A rejected write puts my trust back: the edge is mutual again, with
        // the weight it had before (not a re-invented 1.0).
        cubit.patchLoadedProfile(_aliceMutual);
        await _settle();
        expect(cubit.viewerLink('Ualice'), (
          fromViewer: _myWeightToAlice,
          toViewer: 1.0,
        ));
        final restored = _edgeBetween(cubit, 'Ualice', 'Ume')!;
        expect(restored.isReciprocal, isTrue);
        expect(restored.arrowAtSource, isTrue);
        expect(restored.arrowAtDestination, isTrue);
        expect(_liveNodeIds(cubit), contains('Ucarol'));
      },
    );

    test(
      'stopping one-way trust removes the only link but keeps the open card',
      () async {
        final cubit = _trustCubit(_source(mutual: false));
        addTearDown(cubit.close);
        await _settle();
        cubit.selectNode(_liveNode(cubit, 'Ualice'));
        await _settle();
        expect(_edgeBetween(cubit, 'Ume', 'Ualice'), isNotNull);

        cubit.patchLoadedProfile(_aliceOneWay.copyWith(myVote: 0));
        await _settle();

        expect(cubit.viewerLink('Ualice'), isNull);
        expect(_edgeBetween(cubit, 'Ume', 'Ualice'), isNull);
        // The focused person (whose card is open) and her neighbours stay.
        expect(cubit.state.focus, 'Ualice');
        expect(
          _liveNodeIds(cubit),
          containsAll(<String>['Ume', 'Ualice', 'Ucarol']),
        );
        expect(_edgePairs(cubit), contains(('Ualice', 'Ucarol')));
      },
    );

    // Owner review (PR #614, point 1): with the graph focused on ME, the
    // person I stop trusting one-way must stay on the canvas until the next
    // fetch, even though no edge joins us any more.
    for (final focusOnMe in [false, true]) {
      test(
        'stopping one-way trust with the focus on me keeps the person '
        '(${focusOnMe ? 'me tapped' : 'overview'})',
        () async {
          // Alice's only link is Me -> Alice; Bob -> Carol is unrelated.
          final source = _FakeGraphSource()
            ..pages[null] = {
              _e(
                'Ume',
                'Ualice',
                weight: _myWeightToAlice,
                dstNode: const UserNode(user: _aliceOneWay),
              ),
              _e('Ume', 'Ubob', dstNode: const UserNode(user: _bob)),
              _e('Ubob', 'Ucarol', dstNode: const UserNode(user: _carol)),
            };
          final cubit = _trustCubit(source);
          addTearDown(cubit.close);
          await _settle();
          if (focusOnMe) {
            cubit.selectNode(_liveNode(cubit, 'Ume'));
            await _settle();
          }
          final focusBefore = cubit.state.focus;
          expect(focusBefore, focusOnMe ? 'Ume' : '');
          expect(_edgeBetween(cubit, 'Ume', 'Ualice'), isNotNull);
          final othersBefore = _liveNodeIds(cubit).difference({'Ualice'});

          cubit.patchLoadedProfile(_aliceOneWay.copyWith(myVote: 0));
          await _settle();

          // My edge is gone...
          expect(cubit.viewerLink('Ualice'), isNull);
          expect(_edgeBetween(cubit, 'Ume', 'Ualice'), isNull);
          // ...but Alice stays visible, and nobody else moves.
          expect(cubit.state.focus, focusBefore);
          expect(_liveNodeIds(cubit), contains('Ualice'));
          expect(_liveNodeIds(cubit), containsAll(othersBefore));
          expect(_edgePairs(cubit), contains(('Ume', 'Ubob')));
          expect(
            (_liveNode(cubit, 'Ualice') as UserNode).user.myVote,
            0,
          );
        },
      );
    }
  });

  group('Stop trusting from the person card reaches the graph (#359)', () {
    late GraphTrustWriteFixture fixture;

    setUp(() {
      fixture = GraphTrustWriteFixture();
      fixture.profiles.byId['Ualice'] = _aliceMutual;
    });
    tearDown(() => fixture.dispose());

    test('the writer reports the mutual bond as gone on withdrawal', () async {
      final reverts = <GraphTrustRevert>[];
      fixture.trustWriteCase.reverts.listen(reverts.add);
      await _settle();

      final shown = fixture.trustWriteCase.setTrust(_aliceMutual, add: false);
      expect(shown.myVote, 0);
      expect(shown.isMutualFriend, isFalse);
      // Their own trust in me is untouched.
      expect(shown.subjectExplicitlyTrustsViewer, isTrue);

      // GUARD (already green on current code; kept so the fix cannot break
      // it): a rejected withdrawal restores the mutual bond, because the
      // revert carries the pre-write profile.
      await _settle();
      fixture.likes.fail(0, const LikeSetException());
      await _settle();
      final restored = reverts.single.profile.copyWith(
        myVote: reverts.single.acknowledgedAmount,
      );
      expect(restored.myVote, 1);
      expect(restored.isMutualFriend, isTrue);
    });

    test(
      'untrust in the card drops the edge and badge, a revert restores them',
      () async {
        final graph = _trustCubit(_source(mutual: true));
        addTearDown(graph.close);
        final card = fixture.createCubit(
          onProfilePatched: graph.patchLoadedProfile,
        );
        await _settle();
        graph.selectNode(_liveNode(graph, 'Ualice'));
        card.selectProfile(_aliceMutual, intentional: true);
        await _settle();
        expect(
          (_liveNode(graph, 'Ualice') as UserNode).user.isMutualFriend,
          isTrue,
        );

        await card.untrustSelected();
        await _settle();

        expect(fixture.likes.amounts, [0]);
        expect(card.state.selectedProfile!.myVote, 0);
        expect(card.state.selectedProfile!.isMutualFriend, isFalse);
        final aliceNode = _liveNode(graph, 'Ualice') as UserNode;
        expect(aliceNode.user.myVote, 0);
        expect(aliceNode.user.isMutualFriend, isFalse);
        expect(graph.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));
        expect(_edgeBetween(graph, 'Ualice', 'Ume')!.isReciprocal, isFalse);
        expect(_liveNodeIds(graph), contains('Ucarol'));

        fixture.likes.fail(0, const LikeSetException());
        await _settle();

        final reverted = _liveNode(graph, 'Ualice') as UserNode;
        expect(reverted.user.myVote, 1);
        expect(reverted.user.isMutualFriend, isTrue);
        expect(graph.viewerLink('Ualice'), (
          fromViewer: _myWeightToAlice,
          toViewer: 1.0,
        ));
        expect(_edgeBetween(graph, 'Ualice', 'Ume')!.isReciprocal, isTrue);
        // The card and the graph must agree: the badge is back on the card.
        expect(card.state.selectedProfile!.myVote, 1);
        expect(card.state.selectedProfile!.isMutualFriend, isTrue);
      },
    );

    test('the writer reports the mutual bond on re-trust', () async {
      final shown = fixture.trustWriteCase.setTrust(_aliceTrustsMe, add: true);
      expect(shown.myVote, 1);
      expect(shown.isMutualFriend, isTrue);
      expect(shown.subjectExplicitlyTrustsViewer, isTrue);

      // GUARD: trusting someone who does not trust me is not mutual.
      final oneWay = fixture.trustWriteCase.setTrust(
        const Profile(id: 'Ubob', displayName: 'Bob'),
        add: true,
      );
      expect(oneWay.myVote, 1);
      expect(oneWay.isMutualFriend, isFalse);
    });

    test(
      're-trusting someone who trusts me brings back my edge and the badge',
      () async {
        fixture.profiles.byId['Ualice'] = _aliceTrustsMe;
        final profileRepo = _FakeProfileRepository()
          ..byId['Ualice'] = _aliceTrustsMe;
        // Only Alice -> Me: my trust was withdrawn earlier (or never given).
        final source = _FakeGraphSource()
          ..pages[null] = {
            _e('Ualice', 'Ume'),
            _e('Ume', 'Ubob', dstNode: const UserNode(user: _bob)),
            _e('Ualice', 'Ucarol', dstNode: const UserNode(user: _carol)),
          };
        final graph = _trustCubit(source, profileRepo);
        addTearDown(graph.close);
        final card = fixture.createCubit(
          onProfilePatched: graph.patchLoadedProfile,
        );
        await _settle();
        graph.selectNode(_liveNode(graph, 'Ualice'));
        card.selectProfile(_aliceTrustsMe, intentional: true);
        await _settle();

        // Preconditions: one-way them -> you, no badge.
        expect(graph.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));
        expect(_edgeBetween(graph, 'Ualice', 'Ume')!.isReciprocal, isFalse);
        expect(
          (_liveNode(graph, 'Ualice') as UserNode).user.isMutualFriend,
          isFalse,
        );

        await card.trustSelected();
        await _settle();

        expect(fixture.likes.amounts, [1]);
        expect(card.state.selectedProfile!.myVote, 1);
        expect(card.state.selectedProfile!.isMutualFriend, isTrue);
        final aliceNode = _liveNode(graph, 'Ualice') as UserNode;
        expect(aliceNode.user.myVote, 1);
        expect(aliceNode.user.isMutualFriend, isTrue);

        // My edge is back. Its weight is not pinned: there is no earlier
        // score to restore, only presence and direction matter.
        final link = graph.viewerLink('Ualice');
        expect(link, isNotNull);
        expect(link!.fromViewer, isNotNull);
        expect(link.fromViewer, greaterThan(0));
        expect(link.toViewer, 1.0);
        final edge = _edgeBetween(graph, 'Ualice', 'Ume')!;
        expect(edge.isReciprocal, isTrue);
        expect(edge.arrowAtSource, isTrue);
        expect(edge.arrowAtDestination, isTrue);

        // Nobody else moves.
        expect(
          _liveNodeIds(graph),
          containsAll(<String>['Ume', 'Ualice', 'Ucarol']),
        );
        expect(_edgePairs(graph), contains(('Ualice', 'Ucarol')));
      },
    );

    // Owner review (PR #614, point 2): a plain re-trust has no stashed score,
    // so the graph shows a provisional edge at once; once the write is
    // acknowledged the real server edge replaces it quietly — no reload, the
    // focus and the people on the canvas stay.
    test(
      're-trust swaps the provisional edge for the server one after the ack',
      () async {
        const serverWeight = 0.37;
        fixture.profiles.byId['Ualice'] = _aliceTrustsMe;
        final profileRepo = _FakeProfileRepository()
          ..byId['Ualice'] = _aliceTrustsMe;
        final source = _FakeGraphSource()
          ..pages[null] = {
            _e('Ualice', 'Ume'),
            _e('Ume', 'Ubob', dstNode: const UserNode(user: _bob)),
            _e('Ualice', 'Ucarol', dstNode: const UserNode(user: _carol)),
          };
        final graph = _trustCubit(source, profileRepo);
        addTearDown(graph.close);
        final card = fixture.createCubit(
          onProfilePatched: graph.patchLoadedProfile,
        );
        await _settle();
        graph.selectNode(_liveNode(graph, 'Ualice'));
        card.selectProfile(_aliceTrustsMe, intentional: true);
        await _settle();
        expect(graph.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));

        await card.trustSelected();
        await _settle();

        // Write in flight: my edge is drawn provisionally (any weight > 0).
        expect(fixture.likes.amounts, [1]);
        expect(graph.viewerLink('Ualice')?.fromViewer, greaterThan(0));
        expect(_edgeBetween(graph, 'Ualice', 'Ume')!.isReciprocal, isTrue);

        // The server now holds the real score; then the write is acked.
        final serverMeToAlice = _e('Ume', 'Ualice', weight: serverWeight);
        source
          ..between.addAll({serverMeToAlice, _e('Ualice', 'Ume')})
          ..pages[null] = {...source.pages[null]!, serverMeToAlice}
          ..pages['Ualice'] = {
            serverMeToAlice,
            _e('Ualice', 'Ume'),
            _e('Ualice', 'Ucarol', dstNode: const UserNode(user: _carol)),
          };
        fixture.likes.ack(0);
        await _settle();
        await _settle();

        // The real edge, not a made-up 1.0.
        expect(graph.viewerLink('Ualice'), (
          fromViewer: serverWeight,
          toViewer: 1.0,
        ));
        final edge = _edgeBetween(graph, 'Ualice', 'Ume')!;
        expect(edge.isReciprocal, isTrue);
        expect(edge.arrowAtSource, isTrue);
        expect(edge.arrowAtDestination, isTrue);

        // Quietly: focus, people and the card stay as they were.
        expect(graph.state.focus, 'Ualice');
        expect(
          _liveNodeIds(graph),
          containsAll(<String>['Ume', 'Ualice', 'Ucarol']),
        );
        expect(_edgePairs(graph), contains(('Ualice', 'Ucarol')));
        expect((_liveNode(graph, 'Ualice') as UserNode).user.myVote, 1);
        expect(card.state.selectedProfile!.myVote, 1);
        expect(card.state.selectedProfile!.isMutualFriend, isTrue);
      },
    );
  });
}
