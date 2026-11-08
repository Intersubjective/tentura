@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

Map<String, dynamic> _bobFieldWireResponse() {
  Map<String, dynamic> peer(String id, String displayName) => {
    '__typename': 'v2_ConstellationPeer',
    'id': id,
    'contactOnly': false,
    'displayName': displayName,
    'handle': null,
    'image': null,
    'isNew': false,
    'pinState': null,
    'presence': 'visible',
    'temporaryBeaconId': null,
    'bondContexts': <dynamic>[],
    'visible': true,
  };

  final peerIds = ['anna', 'boris', 'dima', 'kira', 'vera'];
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': '2026-11-07T10:00:00.000Z',
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': peerIds,
      'peers': [
        peer('bob', 'Боб'),
        for (final id in peerIds)
          peer(id, id[0].toUpperCase() + id.substring(1)),
      ],
      'edges': [
        for (final dst in peerIds)
          {
            '__typename': 'v2_ConstellationEdge',
            'src': 'bob',
            'dst': dst,
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
}

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

Future<void> _pumpField(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: const Locale('ru'),
      scaffoldMessengerKey: snackbarKey,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: kPhoneSurface),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider(
                create: (_) => constellationSelectionForFieldBodyTests(),
              ),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => FieldBodyTestGraphPersonContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: Scaffold(
              body: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await stabilizeConstellationFieldChromeForTests(tester, cubit);
}

void main() {
  test('ConstellationFieldFetch Bob+5 peers through the wire', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {'ConstellationFieldFetch': _bobFieldWireResponse()},
      sent,
      (remote) async {
        final field = await ConstellationRepository(remote).fetch();
        expect(sent.single.operationName, 'ConstellationFieldFetch');
        expect(field.peers, hasLength(6));
        expect(field.directContactIds, hasLength(5));
      },
    );
  });

  testWidgets('turning off 1st degree shows RU snack with Undo on phone', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final sent = <WireSent>[];
    late ConstellationField field;
    await withRemoteWire(
      {'ConstellationFieldFetch': _bobFieldWireResponse()},
      sent,
      (remote) async {
        field = await ConstellationRepository(remote).fetch();
      },
    );
    expect(sent, hasLength(1));

    final fixture = ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'bob',
    );
    final cubit = fixture.createCubit(
      viewer: const Profile(id: 'bob', displayName: 'Боб'),
    );
    await cubit.load();
    await _pumpField(tester, cubit);

    final l10n = lookupL10n(const Locale('ru'));
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('constellation.show.degree.first.count')),
          )
          .data,
      '5',
    );

    Set<String> peopleOnMap() {
      final composition = cubit.state.composition;
      return composition == null
          ? {}
          : Set<String>.from(composition.eligiblePersonIds);
    }

    expect(
      peopleOnMap(),
      containsAll(['anna', 'boris', 'dima', 'kira', 'vera']),
    );

    final beforeHide = cubit.state.visibility;
    expect(beforeHide.firstDegree, isTrue);

    final chip = find.byKey(const Key('constellation.show.degree.first'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(cubit.state.visibility.firstDegree, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.widgetWithText(SnackBarAction, l10n.constellationUndo),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(peopleOnMap(), isNot(contains('anna')));

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cubit.state.visibility.firstDegree, isTrue);
    expect(
      peopleOnMap(),
      containsAll(['anna', 'boris', 'dima', 'kira', 'vera']),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
