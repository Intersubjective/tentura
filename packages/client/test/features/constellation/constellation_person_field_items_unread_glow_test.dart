// #1156: person panel rows glow for unread Field beacons (same signal as map).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/ui/bloc/screen_state.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_person_field_item.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_person_field_items_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_person_field_items_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_person_field_items_section.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 11, 7, 12);

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

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

final class _FakeItemsPort implements ConstellationPersonFieldItemsPort {
  _FakeItemsPort(this.page);
  final ConstellationPersonFieldItemsPage page;

  @override
  Future<ConstellationPersonFieldItemsPage> fetch({
    required String personId,
    required ConstellationPersonFieldBucket bucket,
    String query = '',
    String? cursor,
  }) async => page;
}

final class _RecordingHidePort implements ConstellationFieldHidePort {
  @override
  Future<void> hide({
    required int targetKind,
    required String targetId,
  }) async {}

  @override
  Future<void> unhide({
    required int targetKind,
    required String targetId,
  }) async {}

  @override
  Future<List<ConstellationFieldHiddenItem>> fetchHiddenItems({
    String? cursor,
  }) async => const [];
}

final class _StubTargetedReadPort implements ConstellationTargetedReadPort {
  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async => const [];

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async => const [];
}

ConstellationField _fieldWithUnread({
  required String unreadId,
  required String readId,
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'ego', displayName: 'Ego'),
    ConstellationPerson(id: 'am', displayName: 'Alex'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'am', tier: 1),
  ],
  directContactIds: const ['am'],
  requests: [
    ConstellationRequest(
      id: unreadId,
      authorId: 'am',
      title: 'Unread',
      status: 0,
      hasUnread: true,
      lastActivityAt: _loadedAt,
    ),
    ConstellationRequest(
      id: readId,
      authorId: 'am',
      title: 'Read',
      status: 0,
      hasUnread: false,
      lastActivityAt: _loadedAt,
    ),
  ],
  anchorProjection: ConstellationAnchorProjection(
    revision: _revision(1),
    anchors: const [],
    pinnedPeers: const [],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  ),
);

Future<ConstellationCubit> _cubit(ConstellationField field) async {
  final page = ConstellationPersonFieldItemsPage(
    items: [
      ConstellationPersonFieldItem(
        id: field.requests[0].id,
        kind: ConstellationFieldTargetKind.request,
        authorId: 'am',
        title:
            'ЗАПРОС-А: очень длинное название непрочитанного запроса на помощь с переездом',
        rootExcerpt: '',
        status: 0,
        hidden: false,
        lastActivityAt: _loadedAt,
      ),
      ConstellationPersonFieldItem(
        id: field.requests[1].id,
        kind: ConstellationFieldTargetKind.request,
        authorId: 'am',
        title:
            'ЗАПРОС-B: очень длинное название прочитанного запроса на помощь с переездом',
        rootExcerpt: '',
        status: 0,
        hidden: false,
        lastActivityAt: _loadedAt,
      ),
    ],
    counts: const ConstellationPersonFieldCounts(
      active: 2,
      closed: 0,
      hidden: 0,
    ),
  );
  final fixture = ConstellationStoreFixture(
    _StubRepository(field),
    accountId: 'ego',
  );
  final cubit = ConstellationCubit(
    case_: fixture.store,
    viewer: _ego,
    fieldHideCase: ConstellationFieldHideCase(
      _RecordingHidePort(),
      fixture.store,
      _StubTargetedReadPort(),
      env: const Env.fromEnvironment(),
      logger: Logger('test'),
    ),
    personFieldItemsCase: ConstellationPersonFieldItemsCase(
      _FakeItemsPort(page),
      env: const Env.fromEnvironment(),
      logger: Logger('test'),
    ),
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(child: child),
);

void main() {
  group('#1156 person panel unread row glow', () {
    testWidgets('375×667 RU glow key only on unread row with long text', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      const unreadId = 'req-unread-glow';
      const readId = 'req-read-glow';
      final cubit = await _cubit(
        _fieldWithUnread(unreadId: unreadId, readId: readId),
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: ConstellationPersonFieldItemsSection(personId: 'am'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(
          ConstellationPersonFieldItemsSection.personItemUnreadGlowKey(unreadId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ConstellationPersonFieldItemsSection.personItemUnreadGlowKey(readId),
        ),
        findsNothing,
      );
      expect(find.textContaining('ЗАПРОС-А'), findsOneWidget);
      expect(find.textContaining('ЗАПРОС-B'), findsOneWidget);
    });

    testWidgets('opening unread row clears glow', (tester) async {
      const unreadId = 'req-open-clear';
      const readId = 'req-read-open';
      final cubit = await _cubit(
        _fieldWithUnread(unreadId: unreadId, readId: readId),
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationPersonFieldItemsSection(personId: 'am'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ConstellationPersonFieldItemsSection.personItemUnreadGlowKey(unreadId),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(Key('constellation.person_items.row.$unreadId')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ConstellationPersonFieldItemsSection.personItemUnreadGlowKey(unreadId),
        ),
        findsNothing,
      );
      expect(cubit.unreadFieldBeaconIds(), isEmpty);
    });
  });

  test(
    'unreadFieldBeaconIds from wire-mapped Field (#1156 real-path)',
    () async {
      final wire = {
        '__typename': 'query_root',
        'constellationField': {
          '__typename': 'v2_ConstellationField',
          'loadedAt': '2026-11-07T12:00:00.000Z',
          'context': '',
          'peersCapped': false,
          'requestsCapped': false,
          'directContactIds': <String>[],
          'peers': <dynamic>[],
          'edges': <dynamic>[],
          'requests': [
            {
              '__typename': 'v2_ConstellationRequest',
              'id': 'r-unread',
              'pinState': null,
              'authorId': 'am',
              'title': 'Need',
              'status': 0,
              'needs': <String>[],
              'primaryNeedSlug': null,
              'startAt': null,
              'endAt': null,
              'lastActivityAt': '2026-11-07T12:00:00.000Z',
              'addressLabel': null,
              'hasCoordinates': false,
              'isMine': false,
              'viewerHasActiveHelpOffer': false,
              'viewerIsRoomParticipant': true,
              'viewerHasForwardEdge': false,
              'forwardedById': null,
              'forwardedByName': null,
              'parentBeaconId': null,
              'helpOfferCount': 0,
              'coverSource': 0,
              'coverThumb': null,
              'has_unread': true,
            },
          ],
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
      expect(mapped.requests.single.hasUnread, isTrue);

      final fixture = ConstellationStoreFixture(
        _StubRepository(mapped),
        accountId: 'ego',
      );
      final cubit = fixture.createCubit(viewer: _ego);
      await cubit.load();

    expect(cubit.unreadFieldBeaconIds(), {'r-unread'});
    cubit.openedFieldBeacon('r-unread');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.unreadFieldBeaconIds(), isEmpty);
    },
  );
}
