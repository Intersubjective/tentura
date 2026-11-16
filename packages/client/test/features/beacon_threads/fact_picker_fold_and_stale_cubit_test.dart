// FactPickerCubit local filtering follows the server's search fold (lower
// case, ё as е, every '@' removed, split on any whitespace) in both the
// «In this Request» rows (quote mode) and the Saved rows (bring mode), and a
// late answer for an old All-scope query never fills the results. One test
// runs the real repository over a stubbed HTTP transport.

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_picker_cubit.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/test_realtime_sync.dart';

const _dest = 'Bdest00000001';

BeaconSavedFact _saved(String id, String text) => (
  factCardId: id,
  available: true,
  beaconId: 'Bother',
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
  final searchCalls = <String>[];

  @override
  Future<List<BeaconSavedFact>> savedList() async => List.of(saved);

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) {
    searchCalls.add(query);
    return onSearch?.call(query) ?? Future.value(const []);
  }
}

class _FakeThreadsRepository extends Fake implements BeaconThreadsRepository {}

class _FakeHints extends Fake implements BeaconRoomHintsRepository {}

class _FakePolling extends Fake implements PollingRepository {}

BeaconThreadsCase _case(BeaconFactCardRepository repo) => BeaconThreadsCase(
  _FakeThreadsRepository(),
  repo,
  _FakePolling(),
  _FakeHints(),
  RoomReadWatermarkStore.testing(),
  buildTestRealtimeSync().case_,
  env: const Env(),
  logger: Logger('test'),
);

FactPickerCubit _quote(
  BeaconFactCardRepository c, {
  List<BeaconFactCard> here = const [],
}) => FactPickerCubit(
  threadsCase: _case(c),
  destinationBeaconId: _dest,
  mode: FactPickerMode.quote,
  hereFacts: here,
);

FactPickerCubit _bringCubit(BeaconFactCardRepository c) => FactPickerCubit(
  threadsCase: _case(c),
  destinationBeaconId: _dest,
  mode: FactPickerMode.bring,
);

void _tick(FakeAsync a, [int ms = 0]) {
  a
    ..elapse(Duration(milliseconds: ms))
    ..flushMicrotasks();
}

/// Ids of the here rows (quote mode) and of the saved rows (bring mode) that
/// stay visible for [query] over facts [texts] (fact i has id `i`).
({List<String> here, List<String> saved}) _visible(
  FakeAsync a,
  String query,
  List<String> texts,
) {
  final repo = _FakeRepo()
    ..saved = [for (var i = 0; i < texts.length; i++) _saved('$i', texts[i])];
  final quote = _quote(
    repo,
    here: [for (var i = 0; i < texts.length; i++) _here('$i', texts[i])],
  );
  unawaited(quote.start());
  _tick(a);
  quote.setQuery(query);
  _tick(a);
  final bring = _bringCubit(repo);
  unawaited(bring.start());
  _tick(a);
  bring.setQuery(query);
  _tick(a);
  final result = (
    here: quote.state.hereRows.map((r) => r.id).toList(),
    saved: bring.state.savedRows.map((r) => r.factCardId).toList(),
  );
  unawaited(quote.close());
  unawaited(bring.close());
  _tick(a);
  return result;
}

/// Nothing of the old query is offered once its hits are cleared.
bool _oldHitsOffered(FactPickerState state) => state.results.isNotEmpty;

void main() {
  group('FactPickerCubit local fold matches the server rule', () {
    test('@ is stripped before matching, here and saved rows', () {
      fakeAsync((a) {
        final v = _visible(a, '@ana', ['see banana', 'nothing']);
        expect(v.here, ['0']);
        expect(v.saved, ['0']);
      });
    });

    test('case and ё fold both ways, here and saved rows', () {
      fakeAsync((a) {
        for (final q in ['ЁЛКА', 'елка']) {
          final v = _visible(a, q, ['новая елка', 'Ёлка у дома', 'сосна']);
          expect(v.here, ['0', '1'], reason: q);
          expect(v.saved, ['0', '1'], reason: q);
        }
      });
    });

    test('a query of only @ keeps every here and saved row visible', () {
      fakeAsync((a) {
        for (final q in ['@', '@ @']) {
          final v = _visible(a, q, ['one', 'two']);
          expect(v.here, ['0', '1'], reason: q);
          expect(v.saved, ['0', '1'], reason: q);
        }
      });
    });

    test('each query splits into exactly the server words', () {
      fakeAsync((a) {
        // query -> words the server gives; rows: every word present (match),
        // each word missing in turn, and the words glued as one token.
        final table = <String, List<String>>{
          '@Anna  Ёлка': ['anna', 'елка'],
          '  @@x ': ['x'],
          'a b': ['a', 'b'],
          'ЁЖ': ['еж'],
          'x @ y': ['x', 'y'],
          'a@b': ['ab'],
        };
        for (final MapEntry(key: query, value: words) in table.entries) {
          final texts = [
            // 0: all words, reversed order.
            words.reversed.join(' | '),
            // 1..n: one word missing each.
            for (var skip = 0; skip < words.length && words.length > 1; skip++)
              [
                for (var i = 0; i < words.length; i++)
                  if (i != skip) words[i],
              ].join(' '),
            // last: an unrelated text.
            'zzz qqq',
          ];
          final v = _visible(a, query, texts);
          expect(v.here, ['0'], reason: 'here: «$query»');
          expect(v.saved, ['0'], reason: 'saved: «$query»');
        }
      });
    });

    test('all scope: @a is too short, hints and never searches', () {
      fakeAsync((a) {
        final c = _FakeRepo();
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        _tick(a);
        cubit.setQuery('@a');
        _tick(a, 1000);
        expect(cubit.state.showHint, isTrue);
        expect(c.searchCalls, isEmpty);
      });
    });
  });

  group('FactPickerCubit stale answers', () {
    test('changing the query at once stops offering the old hits', () {
      fakeAsync((a) {
        final c = _FakeRepo()
          ..onSearch = (q) async => q == 'anna' ? [_hit('H', 'Anna')] : [];
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('anna');
        _tick(a, 300);
        expect(cubit.state.results.map((r) => r.factCardId), ['H']);
        expect(cubit.state.searched, isTrue);
        cubit.setQuery('annab');
        // Same turn, before the debounce fires.
        expect(cubit.state.searched, isFalse);
        expect(_oldHitsOffered(cubit.state), isFalse);
        _tick(a, 100);
        expect(_oldHitsOffered(cubit.state), isFalse);
      });
    });

    test('a late response of an older query never replaces newer state', () {
      fakeAsync((a) {
        final first = Completer<List<BeaconFactSearchHit>>();
        final second = Completer<List<BeaconFactSearchHit>>();
        final third = Completer<List<BeaconFactSearchHit>>();
        final c = _FakeRepo()
          ..onSearch = (q) => switch (q) {
            'anna' => first.future,
            'annab' => second.future,
            _ => third.future,
          };
        final cubit = _quote(c);
        unawaited(cubit.start());
        _tick(a);
        unawaited(cubit.setScope(FactPickerScope.all));
        cubit.setQuery('anna');
        _tick(a, 300);
        first.complete([_hit('H', 'Anna')]);
        _tick(a);
        expect(cubit.state.results.map((r) => r.factCardId), ['H']);

        cubit.setQuery('annab');
        _tick(a, 300);
        cubit.setQuery('annac');
        _tick(a, 300);
        // The answer of «annab» arrives after «annac» was asked.
        second.complete([_hit('B', 'Annab')]);
        _tick(a);
        expect(cubit.state.results.any((r) => r.factCardId == 'B'), isFalse);
        expect(_oldHitsOffered(cubit.state), isFalse);
        third.complete([_hit('C', 'Annac')]);
        _tick(a);
        expect(cubit.state.results.map((r) => r.factCardId), ['C']);
        expect(cubit.state.searched, isTrue);
      });
    });
  });

  group('FactPickerCubit over the real repository and mapper', () {
    Future<List<String>> run(
      Future<void> Function(FactPickerCubit Function() bring, List<String> ops)
      body,
    ) async {
      final ops = <String>[];
      http.Response json(Object b) => http.Response(
        jsonEncode(b),
        200,
        headers: {'content-type': 'application/json'},
      );
      await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          try {
            await remote.setSessionAuth();
            await remote.getAuthToken();
            await body(
              () => _bringCubit(BeaconFactCardRepository(remote)),
              ops,
            );
          } finally {
            await remote.close();
          }
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return json({
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            });
          }
          final b = jsonDecode(request.body) as Map<String, dynamic>;
          final name = b['operationName'] as String;
          ops.add(name);
          return json({
            'data': switch (name) {
              'BeaconFactCardSavedList' => {
                '__typename': 'query_root',
                'BeaconFactCardSavedList': [
                  {
                    '__typename': 'v2_BeaconFactCardSavedRow',
                    'factCardId': 'F1',
                    'available': true,
                    'beaconId': 'Bother',
                    'beaconKind': 0,
                    'factText': 'see banana',
                    'attachmentsJson': '[]',
                  },
                ],
              },
              _ => {
                '__typename': 'query_root',
                'BeaconFactCardSearch': <Object?>[],
              },
            },
          });
        }),
      );
      return ops;
    }

    test('saved rows from a real response match @ana', () async {
      await run((bring, ops) async {
        final cubit = bring();
        await cubit.start();
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F1']);
        cubit.setQuery('@ana');
        expect(cubit.state.savedRows.map((r) => r.factCardId), ['F1']);
        cubit.setQuery('zzz');
        expect(cubit.state.savedRows, isEmpty);
        await cubit.close();
      });
    });

    test(
      'all scope sends no search request for @a but does for anna',
      () async {
        await run((bring, ops) async {
          final cubit = bring();
          await cubit.start();
          await cubit.setScope(FactPickerScope.all);
          cubit.setQuery('@a');
          await Future<void>.delayed(const Duration(milliseconds: 450));
          expect(cubit.state.showHint, isTrue);
          expect(ops, isNot(contains('BeaconFactCardSearch')));
          // Positive control: a searchable query records the operation.
          cubit.setQuery('anna');
          await Future<void>.delayed(const Duration(milliseconds: 450));
          expect(ops, contains('BeaconFactCardSearch'));
          await cubit.close();
        });
      },
    );
  });
}
