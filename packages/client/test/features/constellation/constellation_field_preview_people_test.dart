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
    test('off-field forwarded members do not inflate the stack', () {
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
      expect(stack.hiddenCount, 3);
      expect(stack.isEmpty, isFalse);
    });

    test('plus count includes avatar overflow past max faces', () {
      final stack = ConstellationFieldPreviewMemberStack(
        profiles: [
          for (var i = 0; i < 5; i++)
            Profile(id: 'p$i', displayName: 'Person $i'),
        ],
        hiddenCount: 1,
      );
      expect(constellationFieldPreviewStackPlusCount(stack), 3);
      expect(constellationFieldPreviewStackHasDrawableContent(stack), isTrue);
    });

    test('peer on field without profile does not draw', () {
      const webs = [
        ConstellationMemberWeb(
          beaconId: 'b',
          personId: 'blocked',
          state: ConstellationMemberWebState.forwarded,
        ),
      ];
      final stack = constellationFieldPreviewMemberStack(
        webs: webs,
        state: ConstellationMemberWebState.forwarded,
        viewerId: 'ego',
        peerOnField: (_) => true,
        profileFor: (_) => null,
      );
      expect(stack.isEmpty, isTrue);
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
      expect(find.text('+5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Field preview empty forward section', () {
    const beaconId = 'req-empty-fwd';
    const viewerId = 'ego';
    const offFieldForward = 'off-field-fwd';
    const onFieldNoProfile = 'on-field-no-profile';
    const authorId = 'author';

    ConstellationField requestFieldForEmptyForward({
      required List<ConstellationMemberWeb> memberWebs,
      List<ConstellationPerson>? peers,
    }) {
      final defaultPeers =
          peers ??
          [
            const ConstellationPerson(
              id: authorId,
              displayName: 'Автор',
            ),
            const ConstellationPerson(
              id: onFieldNoProfile,
              displayName: 'Скрытый',
            ),
          ];
      return ConstellationField(
        loadedAt: _loadedAt,
        context: '',
        peers: defaultPeers,
        edges: [
          const ConstellationTrustEdgeEntity(
            src: viewerId,
            dst: authorId,
            tier: 1,
          ),
        ],
        requests: const [
          ConstellationRequest(
            id: beaconId,
            authorId: authorId,
            title: 'Запрос без цепочки',
            status: 0,
          ),
        ],
        memberWebs: memberWebs,
      );
    }

    Future<void> pumpRequestPreviewWithoutForward(
      WidgetTester tester, {
      required ConstellationField field,
      required String forwardedTitle,
      Locale locale = const Locale('ru'),
    }) async {
      await usePhoneSurface(tester);
      final cubit = await _cubit(field);
      cubit.selectRequest(beaconId);
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: locale,
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
      expect(find.text(forwardedTitle), findsNothing);
      expect(
        find.byKey(const Key('constellation.field_preview.forwarded')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }

    testWidgets('375×667 RU: off-field forward web only', (tester) async {
      await pumpRequestPreviewWithoutForward(
        tester,
        forwardedTitle: 'Через пересылку',
        field: requestFieldForEmptyForward(
          memberWebs: const [
            ConstellationMemberWeb(
              beaconId: beaconId,
              personId: authorId,
              state: ConstellationMemberWebState.inside,
            ),
            ConstellationMemberWeb(
              beaconId: beaconId,
              personId: offFieldForward,
              state: ConstellationMemberWebState.forwarded,
            ),
          ],
        ),
      );
    });

    testWidgets('375×667 EN: off-field forward web only', (tester) async {
      await pumpRequestPreviewWithoutForward(
        tester,
        locale: const Locale('en'),
        forwardedTitle: 'Forwarded through',
        field: requestFieldForEmptyForward(
          memberWebs: const [
            ConstellationMemberWeb(
              beaconId: beaconId,
              personId: authorId,
              state: ConstellationMemberWebState.inside,
            ),
            ConstellationMemberWeb(
              beaconId: beaconId,
              personId: offFieldForward,
              state: ConstellationMemberWebState.forwarded,
            ),
          ],
        ),
      );
    });

    testWidgets('375×667 RU: viewer alone on forward chain', (tester) async {
      final field = requestFieldForEmptyForward(
        memberWebs: const [
          ConstellationMemberWeb(
            beaconId: beaconId,
            personId: authorId,
            state: ConstellationMemberWebState.inside,
          ),
          ConstellationMemberWeb(
            beaconId: beaconId,
            personId: viewerId,
            state: ConstellationMemberWebState.forwarded,
          ),
        ],
      );
      final cubit = ConstellationCubit(
        case_: ConstellationStoreFixture(
          _StubRepository(field),
          accountId: viewerId,
        ).store,
        viewer: const Profile(id: viewerId, displayName: 'Я'),
      );
      await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
      await usePhoneSurface(tester);
      cubit.selectRequest(beaconId);
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
      expect(find.text('Через пересылку'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
