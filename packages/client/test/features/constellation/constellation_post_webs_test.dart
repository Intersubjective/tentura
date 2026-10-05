import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_post_preview_sheet.dart';
import '../../support/test_realtime_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_post_fade.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fixtures/constellation_reference_fixture.dart'
    show pumpConstellationBody;
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';

final _loadedAt = DateTime.utc(2026, 10, 3, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  ConstellationField field;
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    return field;
  }
}

ConstellationField _field() => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    const ConstellationPerson(id: 'a'),
    const ConstellationPerson(id: 'b'),
  ],
  edges: [
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
  ],
  requests: const [],
  posts: [
    ConstellationPost(
      id: 'post-1',
      authorId: 'a',
      rootExcerpt: 'Who has a ladder?',
      lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
    ),
  ],
  memberWebs: const [
    ConstellationMemberWeb(
      beaconId: 'post-1',
      personId: 'a',
      state: ConstellationMemberWebState.inside,
    ),
    ConstellationMemberWeb(
      beaconId: 'post-1',
      personId: 'b',
      state: ConstellationMemberWebState.forwarded,
    ),
  ],
);

Future<ConstellationCubit> _load([ConstellationField? field]) async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(field ?? _field()),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationPostWebsTest'),
    ),
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Set<String> _semanticIds(ConstellationCubit cubit) =>
    cubit.graphController.edges.map((e) => e.semanticId).toSet();

Iterable<String> _webIds(ConstellationCubit cubit) => _semanticIds(
  cubit,
).where((id) => id.endsWith('#webForwarded') || id.endsWith('#webInside'));

String _padded(int i) => 'p${i.toString().padLeft(3, '0')}';

/// One more peer than the render cap; every peer is a forwarded member of
/// the Post, so exactly one visible member cannot be placed.
ConstellationField _fieldOverRenderCap({required int hiddenReachCount}) {
  final ids = [
    for (var i = 0; i <= kConstellationRenderPeerCap; i++) _padded(i),
  ];
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: [for (final id in ids) ConstellationPerson(id: id)],
    edges: [
      for (final id in ids)
        ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
    ],
    requests: const [],
    posts: [
      ConstellationPost(
        id: 'post-1',
        authorId: ids.first,
        rootExcerpt: 'Who has a ladder?',
        lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
        hiddenReachCount: hiddenReachCount,
      ),
    ],
    memberWebs: [
      for (final id in ids)
        ConstellationMemberWeb(
          beaconId: 'post-1',
          personId: id,
          state: ConstellationMemberWebState.forwarded,
        ),
      const ConstellationMemberWeb(
        beaconId: 'post-1',
        personId: 'ghost',
        state: ConstellationMemberWebState.forwarded,
      ),
    ],
  );
}

ConstellationField _fieldWithPostAge(Duration age) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    const ConstellationPerson(id: 'a'),
    const ConstellationPerson(id: 'b'),
  ],
  edges: [
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
  ],
  requests: const [],
  posts: [
    ConstellationPost(
      id: 'post-1',
      authorId: 'a',
      rootExcerpt: 'Who has a ladder?',
      lastActivityAt: _loadedAt.subtract(age),
      isPinned: true,
    ),
  ],
  memberWebs: const [
    ConstellationMemberWeb(
      beaconId: 'post-1',
      personId: 'b',
      state: ConstellationMemberWebState.forwarded,
    ),
  ],
);

void main() {
  test(
    'realtime coalesces Post changes, refreshes messages and catches up',
    () async {
      final sync = buildTestRealtimeSync();
      final repository = _StubRepository(
        _field().copyWith(posts: [], memberWebs: []),
      );
      final cubit = ConstellationCubit(
        case_: ConstellationFieldCase(
          repository,
          env: const Env.fromEnvironment(),
          logger: Logger('RealtimePostTest'),
          realtimeSyncCase: sync.case_,
        ),
        viewer: const Profile(id: 'ego'),
        loadOnCreate: false,
        realtimeRefreshMinInterval: Duration.zero,
      );
      addTearDown(sync.port.dispose);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.postById('post-1'), isNull);
      repository.field = _field();
      void change(RealtimeEntityKind kind) => sync.port.emitChange(
        RealtimeEntityChange(
          kind: kind,
          aggregateId: 'post-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      for (var i = 0; i < 5; i++) {
        change(RealtimeEntityKind.beacon);
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(repository.fetchCount, 2);
      expect(cubit.postById('post-1'), isNotNull);
      repository.field = repository.field.copyWith(
        posts: [
          repository.field.posts.single.copyWith(rootExcerpt: 'new message'),
        ],
      );
      change(RealtimeEntityKind.roomMessage);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cubit.postById('post-1')!.rootExcerpt, 'new message');
      repository.field = repository.field.copyWith(posts: [], memberWebs: []);
      sync.port.emitCatchUp();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cubit.postById('post-1'), isNull);
      final count = repository.fetchCount;
      change(RealtimeEntityKind.beacon);
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(repository.fetchCount, count);
    },
  );

  testWidgets(
    'Post preview shows excerpt and author and handles open and close',
    (tester) async {
      final cubit = await _load();
      addTearDown(cubit.close);
      var opened = false;
      var closed = false;
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: ConstellationPostPreviewSheet(
                post: _field().posts.single.copyWith(rootExcerpt: 'Post text'),
                authorDisplayName: 'Alice',
                onOpen: () => opened = true,
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Post text'), findsOneWidget);
      expect(find.textContaining('Alice'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(opened, isTrue);
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    },
  );

  group('Post webs only to placed members', () {
    test('webs go to placed members, not to capped or unknown ones', () async {
      final cubit = await _load(_fieldOverRenderCap(hiddenReachCount: 2));
      addTearDown(cubit.close);
      expect(cubit.state.keptPeerIds, {_padded(0)});

      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.keptPeerIds, hasLength(kConstellationRenderPeerCap));

      final webs = cubit.graphController.edges
          .where((e) => e.semanticId.endsWith('#webForwarded'))
          .toList();
      expect(webs, hasLength(kConstellationRenderPeerCap));
      expect(webs.map((e) => e.destination.id).toSet(), {
        for (final id in cubit.state.keptPeerIds) id,
      });
      expect(
        webs.map((e) => e.semanticId),
        everyElement(startsWith('fr:post-1->fp:')),
      );
      expect(
        webs.map((e) => e.semanticId),
        isNot(contains('fr:post-1->fp:ghost#webForwarded')),
      );
    });
  });

  group('Post fade in the graph', () {
    Future<ConstellationCubit> loadAged(Duration age) async {
      final cubit = await _load(_fieldWithPostAge(age));
      addTearDown(cubit.close);
      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);
      return cubit;
    }

    for (final (hours, expected) in [(24, 1.0), (60, 0.625), (72, 0.25)]) {
      test(
        'Post and its webs are drawn at opacity $expected after $hours h',
        () async {
          final cubit = await loadAged(Duration(hours: hours));

          expect(cubit.postFadeById['post-1'], closeTo(expected, 1e-9));
          final web = cubit.graphController.edges.singleWhere(
            (e) => e.semanticId.endsWith('#webForwarded'),
          );
          expect(
            cubit.edgeFadeBySemanticId[web.semanticId],
            closeTo(expected, 1e-9),
          );
        },
      );
    }
  });

  group('Post overflow chip', () {
    test(
      'counts hidden reach plus a visible member dropped by the render cap',
      () async {
        final cubit = await _load(_fieldOverRenderCap(hiddenReachCount: 2));
        addTearDown(cubit.close);
        cubit.selectRequest('post-1');
        await Future<void>.delayed(Duration.zero);

        expect(cubit.postOverflowCountByPostId['post-1'], 3);
      },
    );

    test('members off the field count into the chip until the Post is '
        'selected', () async {
      final cubit = await _load();
      addTearDown(cubit.close);

      expect(cubit.state.keptPeerIds, {'a'});
      expect(cubit.postOverflowCountByPostId['post-1'], 1);

      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.keptPeerIds, {'a', 'b'});

      cubit.selectRequest(null);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.keptPeerIds, {'a'});
    });

    test('has no chip entry when nothing is hidden or capped', () async {
      final cubit = await _load();
      addTearDown(cubit.close);
      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);

      expect(cubit.postOverflowCountByPostId['post-1'] ?? 0, 0);
    });

    testWidgets('viewport shows the +N chip only for the selected Post', (
      tester,
    ) async {
      final cubit = await _load(_fieldOverRenderCap(hiddenReachCount: 2));
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit, locale: const Locale('en'));
      await tester.pumpAndSettle();
      const chipKey = Key('constellation.postOverflow.post-1');
      expect(find.byKey(chipKey), findsNothing);

      cubit.selectRequest('post-1');
      await tester.pumpAndSettle();

      expect(find.byKey(chipKey), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(chipKey), matching: find.text('+3')),
        findsOneWidget,
      );
    });

    testWidgets('chip shows the +N label for the Post', (tester) async {
      final cubit = await _load(_fieldOverRenderCap(hiddenReachCount: 2));
      addTearDown(cubit.close);
      cubit.selectRequest('post-1');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 400)),
            child: TenturaResponsiveScope(
              child: BlocProvider.value(
                value: cubit,
                child: ConstellationPostOverflowChip(
                  postId: 'post-1',
                  hiddenCount: cubit.postOverflowCountByPostId['post-1'] ?? 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('constellation.postOverflow.post-1')),
        findsOneWidget,
      );
      expect(find.text('+3'), findsOneWidget);
    });
  });

  group('Post member webs in the graph', () {
    test('no web is drawn while the Post is not selected', () async {
      final cubit = await _load();
      addTearDown(cubit.close);

      expect(_webIds(cubit), isEmpty);
    });

    test('selecting a Post draws a star of webs by member state', () async {
      final cubit = await _load();
      addTearDown(cubit.close);

      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);

      expect(
        _webIds(cubit).toSet(),
        {'fr:post-1->fp:a#webInside', 'fr:post-1->fp:b#webForwarded'},
      );
    });

    test('deselecting the Post removes its webs', () async {
      final cubit = await _load();
      addTearDown(cubit.close);

      expect(_webIds(cubit), isEmpty);
      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);
      expect(_webIds(cubit), isNotEmpty);
      cubit.selectRequest(null);
      await Future<void>.delayed(Duration.zero);

      expect(_webIds(cubit), isEmpty);
    });

    test('a web and a trust path on the same pair are both drawn', () async {
      final cubit = await _load();
      addTearDown(cubit.close);

      cubit.selectRequest('post-1');
      await Future<void>.delayed(Duration.zero);

      final ids = _semanticIds(cubit);
      expect(ids, contains('fp:ego->fp:a#tier1Path'));
      expect(ids, contains('fr:post-1->fp:a#webInside'));
      expect(ids, contains('fp:a->fr:post-1#attachment'));
      expect(ids, contains('fr:post-1->fp:b#webForwarded'));
    });
  });

  group('Post fade', () {
    double fade(Duration age) => constellationPostFade(
      lastActivityAt: _loadedAt.subtract(age),
      asOfUtc: _loadedAt,
    );

    test('is fully opaque up to 48 hours', () {
      expect(fade(Duration.zero), 1);
      expect(fade(const Duration(hours: 24)), 1);
      expect(fade(const Duration(hours: 48)), 1);
    });

    test('fades linearly between 48 and 72 hours', () {
      expect(fade(const Duration(hours: 60)), closeTo(0.625, 1e-9));
    });

    test('bottoms out at 0.25 at 72 hours and beyond', () {
      expect(fade(const Duration(hours: 72)), closeTo(0.25, 1e-9));
      expect(fade(const Duration(hours: 100)), closeTo(0.25, 1e-9));
    });
  });

  group('Post overflow chip count', () {
    test('adds hidden reach to visible members dropped by the render cap', () {
      expect(
        constellationPostOverflowCount(
          hiddenReachCount: 2,
          visibleMemberCount: 2,
          placedMemberCount: 1,
        ),
        3,
      );
    });

    test('is zero when every visible member is placed and none are hidden', () {
      expect(
        constellationPostOverflowCount(
          hiddenReachCount: 0,
          visibleMemberCount: 2,
          placedMemberCount: 2,
        ),
        0,
      );
    });
  });
}
