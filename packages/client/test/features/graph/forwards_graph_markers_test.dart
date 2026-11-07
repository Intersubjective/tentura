// #774 31ve.9 — forwards graph markers, full edge set, committer dimming, +N ghost.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_graph.dart';
import 'package:tentura/features/forward/domain/entity/forward_recipient_offer_status.dart';
import 'package:tentura/features/forward/domain/entity/help_path_node.dart';
import 'package:tentura/features/graph/data/repository/forwards_graph_repository.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _beaconId = 'req-am-1';
const _authorId = 'Uam';
const _b = 'Uin';
const _v = 'Usm';
const _r = 'Uego';
const _d = 'Uoff-d';
const _k = 'Uoff-k';
const _l = 'Uoff-l';

const _ego = Profile(id: _r, displayName: 'Ego');

class _FakeForwardRepo implements ForwardRepository {
  _FakeForwardRepo({
    required this.forwardGraph,
    this.helpOffererGraph,
  });

  final ForwardGraph forwardGraph;

  /// When null, [fetchHelpOffererForwardPath] is not used.
  final ForwardGraph? helpOffererGraph;

  @override
  Future<ForwardGraph> fetchForwardGraph({required String beaconId}) async {
    expect(beaconId, _beaconId);
    return forwardGraph;
  }

  @override
  Future<ForwardGraph> fetchHelpOffererForwardPath({
    required String beaconId,
    required String helpOffererId,
  }) async {
    expect(beaconId, _beaconId);
    expect(helpOffererId, _v);
    final g = helpOffererGraph;
    expect(g, isNotNull);
    return g!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  Future<Profile> fetchById(String id) async => Profile(id: id, displayName: id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => ProfileState(profile: _ego);

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(ProfileState(profile: _ego));
}

/// Same topology as constellation forward-tree six-edge fixture.
ForwardGraph _sixEdgeGraph({bool anonRecipientOnBK = false}) {
  final t = DateTime.utc(2026, 11, 6, 12);
  return ForwardGraph(
    beaconId: _beaconId,
    authorId: _authorId,
    helpOffererIds: {_v},
    edges: [
      ForwardGraphEdge(
        id: 'e-ab',
        beaconId: _beaconId,
        senderId: _authorId,
        recipientId: _b,
        createdAt: t,
        senderDisplayName: 'Anna',
        recipientDisplayName: 'Boris',
      ),
      ForwardGraphEdge(
        id: 'e-bv',
        beaconId: _beaconId,
        senderId: _b,
        recipientId: _v,
        parentEdgeId: 'e-ab',
        createdAt: t.add(const Duration(seconds: 1)),
        offerStatus: ForwardRecipientOfferStatus.accepted,
        senderDisplayName: 'Boris',
        recipientDisplayName: 'Vera',
      ),
      ForwardGraphEdge(
        id: 'e-ar',
        beaconId: _beaconId,
        senderId: _authorId,
        recipientId: _r,
        createdAt: t.add(const Duration(seconds: 2)),
        senderDisplayName: 'Anna',
        recipientDisplayName: 'Ego',
      ),
      ForwardGraphEdge(
        id: 'e-bd',
        beaconId: _beaconId,
        senderId: _b,
        recipientId: _d,
        parentEdgeId: 'e-ab',
        createdAt: t.add(const Duration(seconds: 3)),
        declinedInvite: true,
        senderDisplayName: 'Boris',
        recipientDisplayName: 'Dan',
      ),
      ForwardGraphEdge(
        id: 'e-bk',
        beaconId: _beaconId,
        senderId: _b,
        recipientId: anonRecipientOnBK ? 'Ux' : _k,
        parentEdgeId: 'e-ab',
        createdAt: t.add(const Duration(seconds: 4)),
        forwardedOn: false,
        senderDisplayName: 'Boris',
        recipientDisplayName: 'Kim',
        recipientAnonymousCount: anonRecipientOnBK ? 1 : 0,
      ),
      ForwardGraphEdge(
        id: 'e-rl',
        beaconId: _beaconId,
        senderId: _r,
        recipientId: _l,
        parentEdgeId: 'e-ar',
        createdAt: t.add(const Duration(seconds: 5)),
        forwardedOn: true,
        senderDisplayName: 'Ego',
        recipientDisplayName: 'Lee',
      ),
    ],
  );
}

List<HelpPathNode> _pathToV() => const [
  HelpPathNode.named(userId: _authorId, displayName: 'Anna'),
  HelpPathNode.named(userId: _b, displayName: 'Boris'),
  HelpPathNode.named(userId: _v, displayName: 'Vera'),
];

const _edgeColors = GraphEdgeColors(
  negative: Color(0xFFF44336),
  ego: Color(0xFFFF9800),
  neutral: Color(0xFF2196F3),
  target: Color(0xFF4CAF50),
);

Future<GraphCubit> _pumpForwardsBody(
  WidgetTester tester, {
  required GraphCubit cubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GraphCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
        ],
        child: GraphBody(
          legendExpanded: false,
          onToggleLegend: () {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return cubit;
}

Finder _graphNode(String userId) =>
    find.byKey(TestIds.key(TestIds.graphNode(userId)));

void main() {
  testWidgets('six-edge forwards graph renders every edge and V/D/K markers',
      (tester) async {
    final cubit = GraphCubit(
      me: _ego,
      edgeColors: _edgeColors,
      forwardsGraphBeaconId: _beaconId,
      graphSourceRepository: ForwardsGraphRepository(
        _FakeForwardRepo(forwardGraph: _sixEdgeGraph()),
      ),
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _FakeProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await _pumpForwardsBody(tester, cubit: cubit);

    expect(cubit.graphController.edges, hasLength(6));
    expect(
      find.descendant(
        of: _graphNode(_v),
        matching: find.byKey(const ValueKey<String>('forwards_graph.marker.V')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _graphNode(_d),
        matching: find.byKey(const ValueKey<String>('forwards_graph.marker.D')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _graphNode(_k),
        matching: find.byKey(const ValueKey<String>('forwards_graph.marker.K')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'committer path keeps six edges; dims R and L off A→B→V spine',
    (tester) async {
    final base = _sixEdgeGraph();
    final cubit = GraphCubit(
      me: _ego,
      edgeColors: _edgeColors,
      forwardsGraphBeaconId: _beaconId,
      helpOffererFocusUserId: _v,
      graphSourceRepository: ForwardsGraphRepository(
        _FakeForwardRepo(
          forwardGraph: base,
          helpOffererGraph: base.copyWith(
            path: _pathToV(),
            viewerId: _authorId,
          ),
        ),
      ),
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _FakeProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await _pumpForwardsBody(tester, cubit: cubit);

    expect(cubit.graphController.edges, hasLength(6));
    expect(cubit.state.forwardsDimmedNodeIds, {_r, _l});

    Finder dimmedOpacity(String userId) => find.descendant(
          of: _graphNode(userId),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity < 1.0,
          ),
        );

    expect(dimmedOpacity(_r), findsOneWidget);
    expect(dimmedOpacity(_l), findsOneWidget);
    expect(
      tester.widget<Opacity>(dimmedOpacity(_r)).opacity,
      closeTo(0.55, 1e-6),
    );
    expect(dimmedOpacity(_authorId), findsNothing);
    expect(dimmedOpacity(_b), findsNothing);
    expect(dimmedOpacity(_v), findsNothing);
  });

  testWidgets('anonymous recipient endpoint shows +1 badge on ghost node',
      (tester) async {
    final ghostId = ForwardsGraphRepository.forwardGhostId('e-bk', sender: false);
    final cubit = GraphCubit(
      me: _ego,
      edgeColors: _edgeColors,
      forwardsGraphBeaconId: _beaconId,
      graphSourceRepository: ForwardsGraphRepository(
        _FakeForwardRepo(forwardGraph: _sixEdgeGraph(anonRecipientOnBK: true)),
      ),
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _FakeProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await _pumpForwardsBody(tester, cubit: cubit);

    expect(
      find.descendant(
        of: _graphNode(ghostId),
        matching: find.byKey(const ValueKey<String>('forwards_graph.anon.1')),
      ),
      findsOneWidget,
    );
  });
}
