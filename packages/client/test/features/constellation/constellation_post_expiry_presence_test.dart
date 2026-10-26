import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_density.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_visibility.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';

// A Post is on the Field while it is open and its `expiresAt` is still in the
// future; its opacity follows the time it has left, not its last activity.

const _ego = 'U_ego';
final _asOf = DateTime.utc(2026, 10, 26, 12);

/// Last activity long past the former 72 h window; the Post is still open.
final _longIdle = _asOf.subtract(const Duration(hours: 100));

ConstellationPost _post(
  String id, {
  required Duration expiresIn,
  String authorId = 'peer-a',
  DateTime? lastActivityAt,
  bool isPinned = false,
  int status = 0,
}) => ConstellationPost(
  id: id,
  authorId: authorId,
  rootExcerpt: 'Who has a ladder?',
  lastActivityAt: lastActivityAt ?? _longIdle,
  expiresAt: _asOf.add(expiresIn),
  isPinned: isPinned,
  status: status,
);

ConstellationAnchorProjection _projectionPinning(String beaconId) =>
    ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision.zero,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.beacon(beaconId),
          position: const ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 1,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
          placedAt: DateTime.utc(2026, 10),
          revision: ConstellationAnchorRevision.zero,
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    );

ConstellationField _field(
  List<ConstellationPost> posts, {
  ConstellationAnchorProjection? projection,
  DateTime? loadedAt,
}) => ConstellationField(
  loadedAt: loadedAt ?? _asOf,
  context: '',
  peers: const [ConstellationPerson(id: 'peer-a')],
  edges: const [
    ConstellationTrustEdgeEntity(src: _ego, dst: 'peer-a', tier: 1),
  ],
  posts: posts,
  anchorProjection: projection,
);

ConstellationComposedPresentation _compose(
  ConstellationField field, {
  DateTime? asOfUtc,
}) => composeConstellationPresentation(
  viewerId: _ego,
  field: field,
  localFilters: const (
    capabilitySlugs: {},
    location: LocationFilter.any,
    timing: TimingFilterAny(),
    includeUnspecified: true,
  ),
  asOfUtc: asOfUtc ?? _asOf,
  labelBudget: (perPerson: 3, total: 150),
);

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

/// Delegates to the real composer and keeps the latest composed scene, so a
/// test can see what the cubit composed and not only what it drew.
final class _RecordingComposer {
  final _real = constellationPresentationComposer();
  ConstellationComposedPresentation? last;
  int composeCount = 0;

  ConstellationComposedPresentation compose({
    required String viewerId,
    required ConstellationField field,
    required ConstellationFilters localFilters,
    required DateTime asOfUtc,
    required ConstellationLabelBudget labelBudget,
    Set<String> expandedSatelliteAuthorIds = const {},
    List<ConstellationMemberWeb> selectedRequestWebs = const [],
    Set<String> extraKeptPeerIds = const {},
  }) {
    composeCount++;
    return last = _real(
      viewerId: viewerId,
      field: field,
      localFilters: localFilters,
      asOfUtc: asOfUtc,
      labelBudget: labelBudget,
      expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
      selectedRequestWebs: selectedRequestWebs,
      extraKeptPeerIds: extraKeptPeerIds,
    );
  }

  bool composes(String beaconId) =>
      last!.beaconNodes.any((node) => node.id == beaconId) ||
      last!.labelPlan.drawnRequestIds.contains(beaconId);
}

/// The cubit runs on the real clock: Posts are built relative to
/// `DateTime.now()` and the field's own `loadedAt` is deliberately older.
Future<ConstellationCubit> _loadCubit(
  _StubRepository repository,
  _RecordingComposer composer,
) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(repository, accountId: _ego).store,
    viewer: const Profile(id: _ego, displayName: 'Ego'),
    composePresentation: composer.compose,
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

DateTime _now() => DateTime.now().toUtc();

ConstellationPost _postExpiringIn(
  Duration left, {
  Duration idle = const Duration(hours: 100),
}) => ConstellationPost(
  id: 'post-1',
  authorId: 'peer-a',
  rootExcerpt: 'Who has a ladder?',
  lastActivityAt: _now().subtract(idle),
  expiresAt: _now().add(left),
);

Set<String> _edgeIds(ConstellationCubit cubit) =>
    cubit.graphController.edges.map((e) => e.semanticId).toSet();

const _attachment = 'fp:peer-a->fr:post-1#attachment';

/// Polls the condition on the real clock, bounded so a missing tick fails the
/// test instead of hanging it.
Future<bool> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return condition();
}

void main() {
  group('Post presence in the composed scene follows expiry', () {
    test('a long-idle Post that has not expired is drawn', () {
      final composed = _compose(
        _field([_post('post-1', expiresIn: const Duration(hours: 10))]),
      );

      expect(composed.labelPlan.drawnRequestIds, contains('post-1'));
      expect(composed.beaconNodes.map((n) => n.id), contains('post-1'));
      expect(composed.dormantBeaconIds, isNot(contains('post-1')));
    });

    test('an expired Post with recent activity is absent when not pinned', () {
      final composed = _compose(
        _field([
          _post(
            'post-1',
            expiresIn: const Duration(minutes: -1),
            lastActivityAt: _asOf.subtract(const Duration(hours: 1)),
          ),
        ]),
      );

      expect(composed.labelPlan.drawnRequestIds, isNot(contains('post-1')));
      expect(composed.beaconNodes.map((n) => n.id), isNot(contains('post-1')));
      expect(composed.dormantBeaconIds, isNot(contains('post-1')));
    });

    test('a Post is expired at the instant of its expiry', () {
      final composed = _compose(
        _field([_post('post-1', expiresIn: Duration.zero)]),
      );

      expect(composed.beaconNodes.map((n) => n.id), isNot(contains('post-1')));
    });

    test('an expired pinned anchored Post is dormant at its anchor', () {
      final composed = _compose(
        _field(
          [
            _post(
              'post-1',
              expiresIn: const Duration(minutes: -1),
              lastActivityAt: _asOf.subtract(const Duration(hours: 1)),
              isPinned: true,
            ),
          ],
          projection: _projectionPinning('post-1'),
        ),
      );

      expect(composed.dormantBeaconIds, contains('post-1'));
      expect(composed.pinnedPostIds, contains('post-1'));
      expect(composed.beaconNodes.map((n) => n.id), contains('post-1'));
      expect(composed.labelPlan.drawnRequestIds, isNot(contains('post-1')));
    });

    test('an unexpired pinned anchored Post is drawn, not dormant', () {
      final composed = _compose(
        _field(
          [
            _post(
              'post-1',
              expiresIn: const Duration(hours: 10),
              isPinned: true,
            ),
          ],
          projection: _projectionPinning('post-1'),
        ),
      );

      expect(composed.dormantBeaconIds, isNot(contains('post-1')));
      expect(composed.labelPlan.drawnRequestIds, contains('post-1'));
    });

    test('the as-of time, not the load time, decides presence', () {
      final field = _field([
        _post('post-1', expiresIn: const Duration(hours: 1)),
      ]);

      final before = _compose(field);
      final after = _compose(
        field,
        asOfUtc: _asOf.add(const Duration(hours: 2)),
      );

      expect(before.beaconNodes.map((n) => n.id), contains('post-1'));
      expect(after.beaconNodes.map((n) => n.id), isNot(contains('post-1')));
    });
  });

  group('A closed Post is not active although its expiry is still ahead', () {
    // Closing a Post leaves `expiresAt` where it was.
    const closed = 6;

    test('an unpinned closed Post is absent', () {
      final composed = _compose(
        _field([
          _post('post-1', expiresIn: const Duration(hours: 10), status: closed),
        ]),
      );

      expect(composed.beaconNodes.map((n) => n.id), isNot(contains('post-1')));
      expect(composed.dormantBeaconIds, isNot(contains('post-1')));
    });

    test('a pinned anchored closed Post is dormant at its anchor', () {
      final composed = _compose(
        _field(
          [
            _post(
              'post-1',
              expiresIn: const Duration(hours: 10),
              isPinned: true,
              status: closed,
            ),
          ],
          projection: _projectionPinning('post-1'),
        ),
      );

      expect(composed.dormantBeaconIds, contains('post-1'));
      expect(composed.beaconNodes.map((n) => n.id), contains('post-1'));
      expect(composed.labelPlan.drawnRequestIds, isNot(contains('post-1')));
    });

    test('an unpinned closed Post is not counted', () {
      final counts = constellationVisibilityCounts(
        field: _field([
          _post('post-1', expiresIn: const Duration(hours: 10), status: closed),
        ]),
        viewerId: _ego,
        peopleOnField: {'peer-a'},
        asOfUtc: _asOf,
      );

      expect(counts.posts, 0);
    });

    test('the author of an unpinned closed Post is not a holder', () {
      final holders = constellationHiddenItemHolderIds(
        field: _field([
          _post('post-1', expiresIn: const Duration(hours: 10), status: closed),
        ]),
        viewerId: _ego,
        visibility: const ConstellationVisibility(posts: false),
      );

      expect(holders, isEmpty);
    });
  });

  group('Post counts on the visibility chips follow expiry', () {
    test('count unexpired long-idle Posts and skip expired unpinned ones', () {
      final field = _field([
        _post('live', expiresIn: const Duration(hours: 10)),
        _post(
          'gone',
          expiresIn: const Duration(minutes: -1),
          lastActivityAt: _asOf.subtract(const Duration(hours: 1)),
        ),
      ]);

      final counts = constellationVisibilityCounts(
        field: field,
        viewerId: _ego,
        peopleOnField: {'peer-a'},
        asOfUtc: _asOf,
      );

      expect(counts.posts, 1);
    });

    test('count an expired Post only while it is pinned and anchored', () {
      final field = _field(
        [
          _post(
            'dormant',
            expiresIn: const Duration(minutes: -1),
            isPinned: true,
          ),
        ],
        projection: _projectionPinning('dormant'),
      );

      final counts = constellationVisibilityCounts(
        field: field,
        viewerId: _ego,
        peopleOnField: {'peer-a'},
        asOfUtc: _asOf,
      );

      expect(counts.posts, 1);
    });
  });

  group('Post holders hidden by type follow expiry', () {
    Set<String> holders(ConstellationField field) =>
        constellationHiddenItemHolderIds(
          field: field,
          viewerId: _ego,
          visibility: const ConstellationVisibility(posts: false),
        );

    test('an author of an unexpired long-idle Post stays a holder', () {
      final field = _field([
        _post(
          'post-1',
          expiresIn: const Duration(hours: 10),
        ),
      ]);

      expect(holders(field), {'peer-a'});
    });

    test('an author of an expired unpinned Post is not a holder', () {
      final field = _field([
        _post(
          'post-1',
          expiresIn: const Duration(minutes: -1),
          lastActivityAt: _asOf.subtract(const Duration(hours: 1)),
        ),
      ]);

      expect(holders(field), isEmpty);
    });

    test('an author of an expired pinned anchored Post stays a holder', () {
      final field = _field(
        [
          _post(
            'post-1',
            expiresIn: const Duration(minutes: -1),
            isPinned: true,
          ),
        ],
        projection: _projectionPinning('post-1'),
      );

      expect(holders(field), {'peer-a'});
    });
  });

  group('Post expiry in the cubit', () {
    test('draws a long-idle Post at the fade of its remaining time', () async {
      final composer = _RecordingComposer();
      final cubit = await _loadCubit(
        _StubRepository(
          _field([_postExpiringIn(const Duration(hours: 10))]),
        ),
        composer,
      );

      expect(composer.composes('post-1'), isTrue);
      expect(
        cubit.postFadeById['post-1'],
        closeTo(0.25 + 0.75 * 10 / 24, 1e-3),
      );
    });

    test(
      'fades the same whether the Post was active recently or not',
      () async {
        final idle = await _loadCubit(
          _StubRepository(
            _field([_postExpiringIn(const Duration(hours: 10))]),
          ),
          _RecordingComposer(),
        );
        final recent = await _loadCubit(
          _StubRepository(
            _field([
              _postExpiringIn(
                const Duration(hours: 10),
                idle: const Duration(minutes: 1),
              ),
            ]),
          ),
          _RecordingComposer(),
        );

        expect(
          idle.postFadeById['post-1'],
          closeTo(recent.postFadeById['post-1']!, 1e-3),
        );
      },
    );

    test(
      'leaves out a Post that expired after the field was loaded',
      () async {
        final composer = _RecordingComposer();
        final cubit = await _loadCubit(
          _StubRepository(
            _field(
              [_postExpiringIn(const Duration(hours: -1))],
              // Still open at load time; expired by the current time.
              loadedAt: _now().subtract(const Duration(hours: 2)),
            ),
          ),
          composer,
        );

        expect(composer.composes('post-1'), isFalse);
        expect(cubit.postFadeById, isNot(contains('post-1')));
        expect(_edgeIds(cubit), isNot(contains(_attachment)));
      },
    );

    test(
      'fades by the current time, not by the time the field loaded',
      () async {
        final composer = _RecordingComposer();
        // Loaded 14 h ago, when the Post still had a full day left.
        final cubit = await _loadCubit(
          _StubRepository(
            _field(
              [_postExpiringIn(const Duration(hours: 10))],
              loadedAt: _now().subtract(const Duration(hours: 14)),
            ),
          ),
          composer,
        );

        expect(
          cubit.postFadeById['post-1'],
          closeTo(0.25 + 0.75 * 10 / 24, 1e-3),
        );
      },
    );

    test(
      'removes a Post from the composed scene when its expiry passes, '
      'without a refetch',
      () async {
        final composer = _RecordingComposer();
        final repository = _StubRepository(
          _field([
            _postExpiringIn(
              const Duration(milliseconds: 1500),
              idle: const Duration(minutes: 5),
            ),
          ]),
        );
        final cubit = await _loadCubit(repository, composer);
        expect(composer.composes('post-1'), isTrue);
        expect(cubit.postFadeById, contains('post-1'));
        expect(_edgeIds(cubit), contains(_attachment));
        final composedBefore = composer.composeCount;

        final recomposedWithoutPost = await _eventually(
          () =>
              composer.composeCount > composedBefore &&
              !composer.composes('post-1'),
        );

        expect(
          recomposedWithoutPost,
          isTrue,
          reason: 'the cubit never recomposed without the expired Post',
        );
        expect(cubit.postFadeById, isNot(contains('post-1')));
        expect(_edgeIds(cubit), isNot(contains(_attachment)));
        expect(repository.fetchCount, 1);
      },
    );
  });

  group('Post fade refreshes as time passes, with no refetch', () {
    // The cubit reads the current time from the store's clock; the fixture's
    // `now` and fakeAsync's timers advance together.
    void withCubit(
      void Function(
        FakeAsync async,
        ConstellationCubit cubit,
        _RecordingComposer composer,
        _StubRepository repository,
      )
      body, {
      ConstellationField? field,
    }) {
      fakeAsync((async) {
        final sync = buildTestRealtimeSync();
        final repository = _StubRepository(
          field ??
              _field([_post('post-1', expiresIn: const Duration(hours: 3))]),
        );
        final composer = _RecordingComposer();
        final fixture = ConstellationStoreFixture(
          repository,
          accountId: _ego,
          realtime: sync.case_,
          now: () => _asOf.add(async.elapsed),
        );
        async.flushMicrotasks();
        final cubit = fixture.createCubit(
          viewer: const Profile(id: _ego, displayName: 'Ego'),
          composePresentation: composer.compose,
        );
        unawaited(cubit.load());
        async.flushMicrotasks();
        expect(repository.fetchCount, 1, reason: 'initial load');

        body(async, cubit, composer, repository);

        unawaited(cubit.close());
        unawaited(fixture.store.dispose());
        unawaited(fixture.account.close());
        unawaited(sync.port.dispose());
        async.flushMicrotasks();
      });
    }

    double expectedFade(Duration left) => 0.25 + 0.75 * left.inSeconds / 86400;

    test('fade follows the shrinking time left while the Post is open', () {
      withCubit((async, cubit, composer, repository) {
        expect(
          cubit.postFadeById['post-1'],
          closeTo(expectedFade(const Duration(hours: 3)), 1e-4),
        );
        final composedBefore = composer.composeCount;

        // 2 h 2 min 30 s in: 57.5 min left, still open. Fade may lag the
        // exact value by at most the minute between refreshes.
        async.elapse(const Duration(hours: 2, minutes: 2, seconds: 30));

        expect(composer.composeCount, greaterThan(composedBefore));
        expect(composer.composes('post-1'), isTrue);
        expect(
          cubit.postFadeById['post-1'],
          closeTo(
            expectedFade(const Duration(minutes: 57, seconds: 30)),
            1e-3,
          ),
        );
        expect(repository.fetchCount, 1);
      });
    });

    test('the Post leaves the composed scene at its expiry, not before', () {
      withCubit((async, cubit, composer, repository) {
        async.elapse(const Duration(hours: 2, minutes: 59));
        expect(composer.composes('post-1'), isTrue);
        final composedBefore = composer.composeCount;

        async.elapse(const Duration(minutes: 1, seconds: 1));

        expect(composer.composeCount, greaterThan(composedBefore));
        expect(composer.composes('post-1'), isFalse);
        expect(cubit.postFadeById, isNot(contains('post-1')));
        expect(
          cubit.graphController.edges.map((e) => e.semanticId),
          isNot(contains(_attachment)),
        );
        expect(repository.fetchCount, 1);
      });
    });

    test(
      'the author of a hidden Post stops being kept once the Post expires',
      () {
        // peer-b is two steps away: on the field only as a holder of the
        // hidden Post, which expires at the end of the third hour.
        final field = ConstellationField(
          loadedAt: _asOf,
          context: '',
          peers: const [
            ConstellationPerson(id: 'peer-a'),
            ConstellationPerson(
              id: 'peer-b',
              fieldMembership: ConstellationFieldMembership.contactOnly,
            ),
          ],
          edges: const [
            ConstellationTrustEdgeEntity(src: _ego, dst: 'peer-a', tier: 1),
            ConstellationTrustEdgeEntity(src: 'peer-a', dst: 'peer-b', tier: 1),
          ],
          posts: [
            _post(
              'post-1',
              expiresIn: const Duration(hours: 3),
              authorId: 'peer-b',
            ),
          ],
        );
        withCubit((async, cubit, composer, repository) {
          cubit.setVisibility(const ConstellationVisibility(posts: false));
          expect(cubit.state.keptPeerIds, contains('peer-b'));

          async.elapse(const Duration(hours: 3, seconds: 1));

          expect(cubit.state.keptPeerIds, isNot(contains('peer-b')));
          expect(repository.fetchCount, 1);
        }, field: field);
      },
    );
  });
}
