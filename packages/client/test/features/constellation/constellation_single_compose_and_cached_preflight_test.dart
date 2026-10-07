import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_density.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

import '../../support/constellation_store_fixture.dart';

const _viewer = Profile(id: 'ego', displayName: 'Ego');
const _request = ConstellationRequest(
  id: 'request-on-map',
  authorId: 'author',
  title: 'Need a ride',
  status: 0,
  viewerHasActiveHelpOffer: true,
);

ConstellationField _field({
  List<ConstellationRequest> requests = const [_request],
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 7),
  context: '',
  peers: const [ConstellationPerson(id: 'author', displayName: 'Author')],
  requests: requests,
);

/// Stable composition seam: the cubit routes every presentation composition
/// through this injected callback. Store reads must never invoke it themselves.
final class _CountingComposer {
  final List<ConstellationField> fields = [];

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
    fields.add(field);
    return composeConstellationPresentation(
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
}

final class _CountingRepository implements ConstellationRepositoryPort {
  _CountingRepository(this.field);

  ConstellationField field;
  Future<ConstellationField> Function(ConstellationProjection)? respond;
  final List<ConstellationProjection> reads = [];

  int get fullFetchCount => reads
      .where((projection) => projection == ConstellationProjection.full)
      .length;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    reads.add(projection);
    return respond == null ? field : await respond!(projection);
  }
}

void main() {
  late _CountingRepository repository;
  late ConstellationStoreFixture fixture;
  late ConstellationFieldStoreCase store;
  late TestRealtimeSyncPort port;
  late FakeClockPort clock;
  late FakeWakeUpPort wakeUp;
  late _CountingComposer composer;
  late ConstellationCubit cubit;

  setUp(() async {
    repository = _CountingRepository(_field());
    final realtime = buildTestRealtimeSync();
    port = realtime.port;
    addTearDown(port.dispose);
    clock = FakeClockPort(DateTime.utc(2026, 10, 7));
    wakeUp = FakeWakeUpPort();
    fixture = ConstellationStoreFixture(
      repository,
      accountId: _viewer.id,
      clock: clock,
      wakeUp: wakeUp,
      realtime: realtime.case_,
    );
    store = fixture.store;
    await fixture.ready();
    composer = _CountingComposer();
    cubit = fixture.createCubit(
      viewer: _viewer,
      composePresentation: composer.compose,
    );
  });

  Future<void> advance(Duration duration) async {
    var remaining = duration;
    while (remaining > Duration.zero) {
      final step = remaining > const Duration(milliseconds: 100)
          ? const Duration(milliseconds: 100)
          : remaining;
      clock.advance(step);
      wakeUp.elapse(step);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      remaining -= step;
    }
  }

  group('FULL loads compose the constellation once', () {
    test('each loaded snapshot is composed exactly once', () async {
      for (var load = 0; load < 2; load++) {
        final field = _field();
        repository.field = field;
        final before = composer.fields.length;

        await cubit.load();

        expect(repository.fullFetchCount, load + 1);
        expect(store.current.field, same(field));
        expect(cubit.state.field, same(field));
        expect(composer.fields.length - before, 1);
        expect(composer.fields.last, same(field));
      }
    });

    test('a store refresh reaches the cubit without a second read', () async {
      await cubit.load();
      repository.field = _field(requests: const []);
      final before = repository.fullFetchCount;
      final compositions = composer.fields.length;

      await store.requestRefresh(ConstellationRefreshReason.load);
      await Future<void>.delayed(Duration.zero);

      expect(repository.fullFetchCount - before, 1);
      expect(cubit.state.field, same(store.current.field));
      expect(cubit.state.field!.requests, isEmpty);
      expect(composer.fields.length - compositions, 1);
    });
  });

  group('the cubit shares the store read lifecycle', () {
    test(
      'logout after the last screen closes clears the held snapshot',
      () async {
        await cubit.load();
        expect(store.current.field, isNotNull);
        await cubit.close();
        fixture.account.add('');
        await Future<void>.delayed(Duration.zero);
        expect(store.current.field, isNull);
      },
    );

    test('a hidden screen suppresses ANCHORS reads', () async {
      await cubit.load();
      final reads = repository.reads.length;
      cubit.setVisible(false);
      port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationAnchor,
          aggregateId: 'ego',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await advance(const Duration(seconds: 3));
      expect(repository.reads.length, reads);
    });

    test('catch-up with a mounted cubit issues exactly one FULL', () async {
      await cubit.load();
      final before = repository.reads.length;
      port.emitCatchUp(accountId: _viewer.id);
      await advance(const Duration(seconds: 3));
      expect(repository.reads.skip(before), [ConstellationProjection.full]);
    });

    test(
      'an obsolete params result cannot replace the current cubit snapshot',
      () async {
        await cubit.load();
        final obsolete = Completer<ConstellationField>();
        repository.respond = (_) => obsolete.future;
        final oldRead = store.requestRefresh(ConstellationRefreshReason.load);
        await Future<void>.delayed(Duration.zero);
        store.setProjectionParams(
          const ConstellationProjectionParams(context: 'new'),
        );
        repository.respond = (_) async => _field(requests: const []);
        await store.requestRefresh(ConstellationRefreshReason.load);
        final current = store.current.field;
        expect(current!.requests, isEmpty);

        obsolete.complete(_field());
        await oldRead;
        await Future<void>.delayed(Duration.zero);

        expect(store.current.field, same(current));
        expect(cubit.state.field, same(current));
      },
    );
  });

  group('request action preflight reads the current snapshot', () {
    test(
      'a readable request preserves its help-offer state without FULL fetch',
      () async {
        await cubit.load();
        final current = cubit.state.field;
        expect(store.current.field, same(current));
        final fullFetchCount = repository.fullFetchCount;
        // A different next response must not replace the current snapshot during
        // preflight. The mutation itself is responsible for server validation.
        repository.field = _field(requests: const []);

        final result = await cubit.preflightRequestAction(_request.id);

        expect(repository.fullFetchCount, fullFetchCount);
        expect(result, isA<ConstellationRequestPreflightReady>());
        final ready = result as ConstellationRequestPreflightReady;
        expect(ready.request, _request);
        expect(ready.viewerHasActiveHelpOffer, isTrue);
        expect(cubit.state.field, same(current));
        expect(store.current.field, same(current));
      },
    );

    test(
      'a request absent from current stays unavailable without FULL fetch',
      () async {
        repository.field = _field(requests: const []);
        await cubit.load();
        final fullFetchCount = repository.fullFetchCount;
        repository.field = _field();

        final result = await cubit.preflightRequestAction(_request.id);

        expect(repository.fullFetchCount, fullFetchCount);
        expect(result, isA<ConstellationRequestPreflightUnavailable>());
      },
    );

    test(
      'preflight before a snapshot is loaded is unavailable without FULL fetch',
      () async {
        final result = await cubit.preflightRequestAction(_request.id);

        expect(repository.fullFetchCount, 0);
        expect(result, isA<ConstellationRequestPreflightUnavailable>());
      },
    );
  });
}
