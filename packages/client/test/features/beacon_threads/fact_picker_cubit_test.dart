// FactPickerCubit: scopes (here / saved / all), query folding, debounced
// server search, bring (copy) outcomes and unsave, over a fake case and a
// fake clock.
//
// Contract under test (new): `FactPickerCubit(threadsCase:, destinationBeaconId:,
// mode:, hereFacts:)`, `start()`, `setScope(scope)`, `setQuery(text)`,
// `bring(factCardId)` -> `FactPickerBringResult{copyOutcome, error}`,
// `unsave(factCardId)`; state exposes `scopes`, `scope`, `hereRows`,
// `savedRows` (already filtered/hidden), `results`, `loading`, `failed`,
// `showHint`, `unavailableIds`.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_picker_cubit.dart';

import '../../support/test_realtime_sync.dart';

const _dest = 'Bdest00000001';

BeaconSavedFact _saved(String id, String text, {String beaconId = 'Bother'}) =>
    (
      factCardId: id,
      available: true,
      beaconId: beaconId,
      beaconKind: 0,
      factText: text,
      attachmentsJson: '[]',
    );

BeaconFactSearchHit _hit(String id, String text) => (
  factCardId: id,
  beaconId: 'Bother',
  beaconKind: 0,
  factText: text,
  attachmentsJson: '[]',
  saved: false,
);

BeaconFactCard _here(String id, String text) => BeaconFactCard(
  id: id,
  beaconId: _dest,
  factText: text,
  visibility: 0,
  pinnedBy: 'U1',
  createdAt: DateTime(2026),
  status: 0,
);

class _FakeRepo extends Fake implements BeaconFactCardRepository {
  List<BeaconSavedFact> saved = [];
  Future<List<BeaconFactSearchHit>> Function(String query)? onSearch;
  Object? copyError;
  BeaconFactCopyOutcome copyOutcome = BeaconFactCopyOutcome.created;

  int savedCalls = 0;
  final searchCalls = <({String query, String? exclude})>[];
  final copyCalls = <({String source, String dest})>[];
  final unsaveCalls = <String>[];

  @override
  Future<List<BeaconSavedFact>> savedList() async {
    savedCalls++;
    return List.of(saved);
  }

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) {
    searchCalls.add((query: query, exclude: excludeBeaconId));
    return onSearch?.call(query) ?? Future.value(const []);
  }

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    copyCalls.add((source: sourceFactCardId, dest: destinationBeaconId));
    if (copyError != null) {
      Error.throwWithStackTrace(copyError!, StackTrace.current);
    }
    return (factCardId: 'Fnew', outcome: copyOutcome);
  }

  @override
  Future<void> unsave({required String factCardId}) async {
    unsaveCalls.add(factCardId);
  }
}

class _FakeThreadsRepository extends Fake implements BeaconThreadsRepository {}

class _FakeHints extends Fake implements BeaconRoomHintsRepository {}

class _FakePolling extends Fake implements PollingRepository {}

/// The real case over the fake repository, so the cubit sees the case API.
BeaconThreadsCase _case(_FakeRepo repo) => BeaconThreadsCase(
  _FakeThreadsRepository(),
  repo,
  _FakePolling(),
  _FakeHints(),
  RoomReadWatermarkStore.testing(),
  buildTestRealtimeSync().case_,
);

FactPickerCubit _quote(_FakeRepo c, {List<BeaconFactCard> here = const []}) =>
    FactPickerCubit(
      threadsCase: _case(c),
      destinationBeaconId: _dest,
      mode: FactPickerMode.quote,
      hereFacts: here,
    );

FactPickerCubit _bringCubit(_FakeRepo c) => FactPickerCubit(
  threadsCase: _case(c),
  destinationBeaconId: _dest,
  mode: FactPickerMode.bring,
);

void _tick(FakeAsync a, [int ms = 0]) {
  a
    ..elapse(Duration(milliseconds: ms))
    ..flushMicrotasks();
}

void main() {
  group('FactPickerCubit scopes', () {
    test('quote mode offers here, saved, all and opens on here', () {
      fakeAsync((a) {
        final cubit = _quote(_FakeRepo());
        unawaited(cubit.start());
        _tick(a);
        expect(cubit.state.scopes, [
          FactPickerScope.here,
          FactPickerScope.saved,
          FactPickerScope.all,
        ]);
        expect(cubit.state.scope, FactPickerScope.here);
      });
    });

    test('bring mode has no here scope, opens on saved, hides destination '
        'rows', () {
      fakeAsync((a) {
        final c = _FakeRepo()
          ..saved = [
            _saved('F1', 'Elsewhere fact'),
            _saved('F2', 'Already here', beaconId: _dest),
          ];
        final cubit = _bringCubit(c);
        unawaited(cubit.start());
        _tick(a);
        expect(cubit.state.scopes, [
          FactPickerScope.saved,
          FactPickerScope.all,
        ]);
        expect(cubit.state.scope, FactPickerScope.saved);
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F1']);
      });
    });

    test('here filters locally with ё/е fold and every-word rule', () {
      fakeAsync((a) {
        final c = _FakeRepo();
        final cubit = _quote(
          c,
          here: [
            _here('H1', 'Ёлка на площади'),
            _here('H2', 'Ёлка в лесу'),
          ],
        );
        unawaited(cubit.start());
        _tick(a);
        cubit.setQuery('ПЛОЩАДИ елка');
        _tick(a, 1000);
        expect(cubit.state.hereRows.map((r) => r.id), ['H1']);
        expect(c.searchCalls, isEmpty);
      });
    });

    test('saved applies every-word rule and fold; empty query shows all', () {
      fakeAsync((a) {
        final c = _FakeRepo()
          ..saved = [
            _saved('F1', 'Купить елку'),
            _saved('F2', 'Елка в лесу'),
            _saved('F3', 'Ёлка на площади'),
          ];
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.saved));
        _tick(a);
        expect(cubit.state.savedRows, hasLength(3));
        cubit.setQuery('елка лес');
        _tick(a);
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F2']);
        cubit.setQuery('ёлка');
        _tick(a);
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F2', 'F3']);
        cubit.setQuery('');
        _tick(a);
        expect(cubit.state.savedRows, hasLength(3));
        _tick(a, 1000);
        expect(c.searchCalls, isEmpty);
      });
    });

    test('saved list is loaded once across scope switches and queries', () {
      fakeAsync((a) {
        final c = _FakeRepo()..saved = [_saved('F1', 'x')];
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.saved));
        _tick(a);
        for (final q in ['a', 'ab', 'abc']) {
          cubit.setQuery(q);
          _tick(a);
        }
        unawaited(cubit.setScope(FactPickerScope.all));
        _tick(a, 1000);
        unawaited(cubit.setScope(FactPickerScope.saved));
        _tick(a);
        expect(c.savedCalls, 1);
      });
    });
  });

  group('FactPickerCubit all-scope server search', () {
    test('searches once after 300 ms with the destination excluded', () {
      fakeAsync((a) {
        final c = _FakeRepo();
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('ab');
        _tick(a, 299);
        expect(c.searchCalls, isEmpty);
        _tick(a, 1);
        expect(c.searchCalls, hasLength(1));
        expect(c.searchCalls.single.query, 'ab');
        expect(c.searchCalls.single.exclude, _dest);
      });
    });

    test('debounce keeps only the last keystroke', () {
      fakeAsync((a) {
        final c = _FakeRepo();
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('ab');
        _tick(a, 100);
        cubit.setQuery('abc');
        _tick(a, 299);
        expect(c.searchCalls, isEmpty);
        _tick(a, 1);
        expect(c.searchCalls.map((e) => e.query), ['abc']);
      });
    });

    test('short query shows the hint and never calls the server', () {
      fakeAsync((a) {
        final c = _FakeRepo()
          ..onSearch = (_) async => [_hit('R1', 'one'), _hit('R2', 'two')];
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        _tick(a, 1000);
        for (final q in ['', 'a']) {
          cubit.setQuery(q);
          _tick(a, 1000);
          expect(cubit.state.showHint, isTrue);
          expect(cubit.state.results, isEmpty);
          expect(cubit.state.loading, isFalse);
        }
        expect(c.searchCalls, isEmpty);

        cubit.setQuery('abc');
        _tick(a, 300);
        expect(cubit.state.results, hasLength(2));
        final calls = c.searchCalls.length;
        cubit.setQuery('a');
        _tick(a, 1000);
        expect(cubit.state.results, isEmpty);
        expect(cubit.state.showHint, isTrue);
        expect(c.searchCalls, hasLength(calls));
      });
    });

    test('results keep server order; loading true while pending', () {
      fakeAsync((a) {
        final done = Completer<List<BeaconFactSearchHit>>();
        final c = _FakeRepo()..onSearch = (_) => done.future;
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('abc');
        _tick(a, 300);
        expect(cubit.state.loading, isTrue);
        done.complete([_hit('R2', 'b'), _hit('R1', 'a')]);
        _tick(a);
        expect(cubit.state.loading, isFalse);
        expect(cubit.state.results.map((r) => r.factCardId), ['R2', 'R1']);
      });
    });

    test('stale older response is dropped', () {
      fakeAsync((a) {
        final first = Completer<List<BeaconFactSearchHit>>();
        final second = Completer<List<BeaconFactSearchHit>>();
        final c = _FakeRepo()
          ..onSearch = (q) => q == 'ab' ? first.future : second.future;
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('ab');
        _tick(a, 300);
        cubit.setQuery('abc');
        _tick(a, 300);
        second.complete([_hit('NEW', 'new')]);
        _tick(a);
        first.complete([_hit('OLD', 'old')]);
        _tick(a);
        expect(cubit.state.results.map((r) => r.factCardId), ['NEW']);
        expect(cubit.state.loading, isFalse);
      });
    });

    test('failure sets failed; next success clears it', () {
      fakeAsync((a) {
        final c = _FakeRepo()
          ..onSearch = (q) async =>
              q == 'bad' ? throw Exception('boom') : [_hit('R1', 'ok')];
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('bad');
        _tick(a, 300);
        expect(cubit.state.failed, isTrue);
        expect(cubit.state.loading, isFalse);
        expect(cubit.state.results, isEmpty);
        cubit.setQuery('good');
        _tick(a, 300);
        expect(cubit.state.failed, isFalse);
        expect(cubit.state.results.map((r) => r.factCardId), ['R1']);
      });
    });
  });

  group('FactPickerCubit bring and unsave', () {
    test('bring copies into the destination and reports the outcome', () {
      fakeAsync((a) {
        for (final o in BeaconFactCopyOutcome.values) {
          final c = _FakeRepo()
            ..saved = [_saved('F1', 'x')]
            ..copyOutcome = o;
          final cubit = _bringCubit(c);
          unawaited(cubit.start());
          _tick(a);
          Object? thrown;
          FactPickerBringResult? r;
          unawaited(
            cubit
                .bring('F1')
                .then<void>(
                  (v) {
                    r = v;
                  },
                  onError: (Object e) {
                    thrown = e;
                  },
                ),
          );
          _tick(a);
          expect(c.copyCalls.single, (source: 'F1', dest: _dest));
          expect(thrown, isNull);
          expect(r?.copyOutcome, o);
          expect(r?.error, isNull);
        }
      });
    });

    test('unavailable source marks only that row, in saved and in results', () {
      fakeAsync((a) {
        final c = _FakeRepo()
          ..saved = [_saved('F1', 'x'), _saved('F2', 'y')]
          ..copyError = const BeaconFactCopySourceUnavailableException()
          ..onSearch = (_) async => [_hit('R1', 'a'), _hit('R2', 'b')];
        final cubit = _bringCubit(c);
        unawaited(cubit.start());
        _tick(a);
        Object? thrown;
        FactPickerBringResult? r;
        unawaited(
          cubit
              .bring('F1')
              .then<void>(
                (v) {
                  r = v;
                },
                onError: (Object e) {
                  thrown = e;
                },
              ),
        );
        _tick(a);
        expect(thrown, isNull);
        expect(r, isNotNull);
        expect(r?.copyOutcome, isNull);
        expect(r?.error, isA<BeaconFactCopySourceUnavailableException>());
        expect(cubit.state.unavailableIds, {'F1'});
        expect(cubit.state.savedRows.map((x) => x.factCardId), ['F1', 'F2']);

        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('abc');
        _tick(a, 300);
        r = null;
        unawaited(
          cubit
              .bring('R2')
              .then<void>(
                (v) {
                  r = v;
                },
                onError: (Object e) {
                  thrown = e;
                },
              ),
        );
        _tick(a);
        expect(thrown, isNull);
        expect(r, isNotNull);
        expect(r?.copyOutcome, isNull);
        expect(r?.error, isA<BeaconFactCopySourceUnavailableException>());
        expect(cubit.state.unavailableIds, {'F1', 'R2'});
        expect(cubit.state.unavailableIds, isNot(contains('R1')));
        expect(cubit.state.unavailableIds, isNot(contains('F2')));
        expect(cubit.state.results.map((x) => x.factCardId), ['R1', 'R2']);
      });
    });

    test('other copy errors fail without marking the row unavailable', () {
      fakeAsync((a) {
        final boom = StateError('boom');
        final c = _FakeRepo()
          ..saved = [_saved('F1', 'x')]
          ..copyError = boom;
        final cubit = _bringCubit(c);
        unawaited(cubit.start());
        _tick(a);
        Object? thrown;
        FactPickerBringResult? r;
        unawaited(
          cubit
              .bring('F1')
              .then<void>(
                (v) {
                  r = v;
                },
                onError: (Object e) {
                  thrown = e;
                },
              ),
        );
        _tick(a);
        expect(thrown, isNull);
        expect(r?.error, same(boom));
        expect(r?.copyOutcome, isNull);
        expect(cubit.state.unavailableIds, isEmpty);
      });
    });

    test('unsave removes the row and it stays gone without a reload', () {
      fakeAsync((a) {
        final c = _FakeRepo()..saved = [_saved('F1', 'x'), _saved('F2', 'y')];
        final cubit = _bringCubit(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.unsave('F1'));
        _tick(a);
        expect(c.unsaveCalls, ['F1']);
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F2']);
        cubit.setQuery('y');
        _tick(a);
        cubit.setQuery('');
        _tick(a);
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F2']);
        expect(c.savedCalls, 1);
      });
    });
  });
}
