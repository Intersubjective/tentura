// #965: every Field surface names a person with Profile.shownName (contact
// name first, else display name). Real wire mapping + cubit profile lookup +
// widget surfaces at 375×667 RU.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/constellation_people.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_semantics.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_label.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_trust_chain_line.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _peerId = 'Upeer00000001';
const _contactName = 'Икс';
const _displayName = 'Y-display';

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

ConstellationField _peerField({required String wireDisplayName}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 11, 3),
      context: '',
      directContactIds: const [_peerId],
      peers: [
        ConstellationPerson(id: _peerId, displayName: wireDisplayName),
      ],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'ego', dst: _peerId, tier: 1),
      ],
      requests: const [
        ConstellationRequest(
          id: 'req-peer-1',
          authorId: _peerId,
          title: 'Help',
          status: 0,
        ),
      ],
    );

Future<ConstellationCubit> _loadedCubit(ConstellationField field) async {
  final cubit = ConstellationStoreFixture(
    _StubRepository(field),
    accountId: 'ego',
  ).createCubit(viewer: _ego);
  await cubit.load();
  cubit.updateLabelBudgetContext(
    viewport: const Size(1200, 900),
    textScaleFactor: 1,
  );
  return cubit;
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit([GraphPersonContextState? initial])
    : super(initial ?? const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {
    emit(state.copyWith(selectedProfile: profile));
  }

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

void main() {
  group('Field person shownName (#965)', () {
    setUp(() async {
      if (GetIt.I.isRegistered<ContactNameStore>()) {
        await GetIt.I.unregister<ContactNameStore>();
      }
      final store = ContactNameStore()..set(_peerId, _contactName);
      GetIt.I.registerSingleton<ContactNameStore>(store);
    });

    tearDown(() async {
      if (GetIt.I.isRegistered<ContactNameStore>()) {
        await GetIt.I.unregister<ContactNameStore>();
      }
    });

    test(
      'wire field fetch peer maps to profileForPersonId with contact overlay',
      () async {
        final wire = {
          '__typename': 'query_root',
          'constellationField': {
            '__typename': 'v2_ConstellationField',
            'loadedAt': '2026-11-03T12:00:00.000Z',
            'context': '',
            'peersCapped': false,
            'requestsCapped': false,
            'directContactIds': [_peerId],
            'peers': [
              {
                '__typename': 'v2_ConstellationPeer',
                'id': _peerId,
                'contactOnly': false,
                'displayName': _displayName,
                'handle': null,
                'image': null,
                'presence': 'visible',
                'temporaryBeaconId': null,
                'bondContexts': <dynamic>[],
              },
            ],
            'edges': [
              {
                '__typename': 'v2_ConstellationTrustEdge',
                'src': 'ego',
                'dst': _peerId,
                'tier': 1,
              },
            ],
            'requests': <dynamic>[],
            'posts': <dynamic>[],
            'memberWebs': <dynamic>[],
            'anchorProjection': {
              '__typename': 'v2_ConstellationAnchorProjection',
              'revision': '0',
              'anchors': <dynamic>[],
              'pinnedPeers': <dynamic>[],
              'pinnedRequests': <dynamic>[],
              'supportPeers': <dynamic>[],
              'supportEdges': <dynamic>[],
              'serverFilteredBeaconIds': <dynamic>[],
              'serverFilteredBeaconCount': 0,
            },
          },
        };

        final mapped = mapConstellationFieldFromFieldFetch(
          GConstellationFieldFetchData.fromJson(wire)!.constellationField,
        );
        final field = mapped.copyWith(
          requests: [
            const ConstellationRequest(
              id: 'req-peer-1',
              authorId: _peerId,
              title: 'Help',
              status: 0,
            ),
          ],
        );
        final cubit = await _loadedCubit(field);
        addTearDown(() async {
          if (!cubit.isClosed) await cubit.close();
        });

        expect(cubit.profileForPersonId(_peerId)!.shownName, _contactName);
      },
    );

    test(
      'without contact overlay shownName falls back to display name',
      () async {
        GetIt.I<ContactNameStore>().set(_peerId, '');
        final cubit = await _loadedCubit(
          _peerField(wireDisplayName: _displayName),
        );
        addTearDown(() async {
          if (!cubit.isClosed) await cubit.close();
        });

        expect(cubit.profileForPersonId(_peerId)!.shownName, _displayName);
      },
    );

    test(
      'map node label uses the same shownName as profileForPersonId',
      () async {
        final cubit = await _loadedCubit(
          _peerField(wireDisplayName: _displayName),
        );
        addTearDown(() async {
          if (!cubit.isClosed) await cubit.close();
        });

        final node = cubit.graphController.nodes
            .whereType<FieldPersonNode>()
            .firstWhere((n) => n.id == _peerId);
        expect(node.person.shownName, _contactName);
        expect(
          node.person.shownName,
          cubit.profileForPersonId(_peerId)!.shownName,
        );
      },
    );

    testWidgets('375×667 RU: person panel title shows contact name', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final cubit = await _loadedCubit(
        _peerField(wireDisplayName: _displayName),
      );
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      final profile = cubit.profileForPersonId(_peerId)!;

      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ConstellationCubit>.value(value: cubit),
                BlocProvider<GraphPersonContextCubit>.value(
                  value: _StubContextCubit(
                    GraphPersonContextState(selectedProfile: profile),
                  ),
                ),
                BlocProvider<ScreenCubit>.value(
                  value: ScreenCubit.local(FakeUiEffectPort()),
                ),
              ],
              child: Scaffold(
                body: GraphPersonContextPanel(
                  profile: profile,
                  focusedNode: UserNode(user: profile),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(_contactName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test(
      'fieldPeople list uses contact shownName for search and text view',
      () async {
        final cubit = await _loadedCubit(
          _peerField(wireDisplayName: _displayName),
        );
        addTearDown(() async {
          if (!cubit.isClosed) await cubit.close();
        });

        final listed = cubit.fieldPeople.firstWhere((p) => p.id == _peerId);
        expect(listed.name, _contactName);
        expect(
          constellationPersonMatches(listed, _contactName),
          isTrue,
        );
      },
    );

    testWidgets('375×667 RU: trust chain forwarded presence uses shownName', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 11, 3),
        context: '',
        peers: [
          const ConstellationPerson(
            id: _peerId,
            displayName: _displayName,
            fieldMembership: ConstellationFieldMembership.temporary,
            temporaryBeaconId: 'Breq000000001',
          ),
        ],
        requests: const [
          ConstellationRequest(
            id: 'req-fwd-src',
            authorId: 'other',
            title: 'Source',
            status: 0,
          ),
        ],
      );
      final cubit = await _loadedCubit(field);
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      cubit.selectPerson(_peerId);

      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider<ConstellationCubit>.value(
              value: cubit,
              child: const Scaffold(
                body: ConstellationTrustChainLine(personId: _peerId),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining(_contactName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('375×667 RU: map node semantics include contact shownName', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final cubit = await _loadedCubit(
        _peerField(wireDisplayName: _displayName),
      );
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      final node = cubit.graphController.nodes
          .whereType<FieldPersonNode>()
          .firstWhere((n) => n.id == _peerId);
      final l10n = lookupL10n(const Locale('ru'));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Builder(
              builder: (context) {
                final label = constellationNodeSemanticLabel(
                  l10n: l10n,
                  tt: context.tt,
                  cubit: cubit,
                  node: node,
                );
                return Scaffold(body: Text(label));
              },
            ),
          ),
        ),
      );

      expect(find.textContaining(_contactName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('held forwarded annotation uses contact shownName', () {
      final l10n = lookupL10n(const Locale('en'));
      const request = ConstellationRequest(
        id: 'req-fwd',
        authorId: 'author',
        title: 'Need help',
        status: 0,
        viewerHasForwardEdge: true,
        forwardedBy: (id: _peerId, displayName: _displayName),
      );
      final text = constellationHeldAnnotation(l10n, request)!;
      expect(text, contains(_contactName));
      expect(text, isNot(contains(_displayName)));
    });

    test('composerPersonName returns contact shownName', () async {
      final cubit = await _loadedCubit(
        _peerField(wireDisplayName: _displayName),
      );
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });

      expect(cubit.composerPersonName(_peerId), _contactName);
      GetIt.I<ContactNameStore>().set(_peerId, '');
      expect(cubit.composerPersonName(_peerId), _displayName);
    });
  });
}
