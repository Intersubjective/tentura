@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_field_preview_people.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_post_preview_sheet.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_preview_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';

final _loadedAt = DateTime.utc(2026, 11, 8, 12);

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

ConstellationField _manyPeopleField({
  required bool post,
  int hiddenReachCount = 2,
}) {
  const visibleIds = [
    'p01',
    'p02',
    'p03',
    'p04',
    'p05',
    'p06',
  ];
  const hiddenId = 'hidden-forward';
  final peers = [
    for (final id in visibleIds)
      ConstellationPerson(
        id: id,
        displayName: 'Очень длинное имя участника $id для проверки переноса',
      ),
  ];
  final beaconId = post ? 'post-1' : 'req-1';
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: peers,
    edges: [
      const ConstellationTrustEdgeEntity(src: 'ego', dst: 'p01', tier: 1),
      for (final id in visibleIds.skip(1))
        ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
    ],
    requests: post
        ? const []
        : [
            ConstellationRequest(
              id: beaconId,
              authorId: 'p01',
              title: 'Запрос с участниками',
              status: 0,
            ),
          ],
    posts: post
        ? [
            ConstellationPost(
              id: beaconId,
              authorId: 'p01',
              rootExcerpt: 'Пост с участниками',
              lastActivityAt: _loadedAt,
              hiddenReachCount: hiddenReachCount,
            ),
          ]
        : const [],
    memberWebs: [
      for (var i = 0; i < visibleIds.length; i++)
        ConstellationMemberWeb(
          beaconId: beaconId,
          personId: visibleIds[i],
          state: i.isEven
              ? ConstellationMemberWebState.inside
              : ConstellationMemberWebState.forwarded,
        ),
      ConstellationMemberWeb(
        beaconId: beaconId,
        personId: hiddenId,
        state: ConstellationMemberWebState.forwarded,
      ),
    ],
  );
}

Future<ConstellationCubit> _cubit(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    ).store,
    viewer: const Profile(id: 'ego', displayName: 'Я'),
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

void main() {
  group('constellationFieldPreviewMemberStack', () {
    test('invisible members count toward hidden only', () {
      const webs = [
        ConstellationMemberWeb(
          beaconId: 'b',
          personId: 'a',
          state: ConstellationMemberWebState.inside,
        ),
        ConstellationMemberWeb(
          beaconId: 'b',
          personId: 'ghost',
          state: ConstellationMemberWebState.forwarded,
        ),
      ];
      final stack = constellationFieldPreviewMemberStack(
        webs: webs,
        state: ConstellationMemberWebState.forwarded,
        viewerId: 'ego',
        peerOnField: (id) => id == 'a',
        profileFor: (id) =>
            id == 'a' ? const Profile(id: 'a', displayName: 'Ann') : null,
        additionalHiddenCount: 3,
      );
      expect(stack.profiles, isEmpty);
      expect(stack.hiddenCount, 4);
    });
  });

  group('Field preview people rows RU phone', () {
    testWidgets('request preview shows participants and +N without overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final field = _manyPeopleField(post: false);
      final cubit = await _cubit(field);
      cubit.selectRequest('req-1');
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: ConstellationRequestPreviewSheet(
                request: field.requests.single,
                authorDisplayName: 'Автор',
                onOpen: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.field_preview.participants')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('constellation.field_preview.forwarded')),
        findsOneWidget,
      );
      expect(find.textContaining('+'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('post preview maps hiddenReach into forwarded +N', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final field = _manyPeopleField(post: true, hiddenReachCount: 5);
      final cubit = await _cubit(field);
      cubit.selectRequest('post-1');
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: ConstellationPostPreviewSheet(
                post: field.posts.single,
                authorDisplayName: 'Автор',
                onOpen: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.field_preview.forwarded')),
        findsOneWidget,
      );
      expect(find.text('+6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
