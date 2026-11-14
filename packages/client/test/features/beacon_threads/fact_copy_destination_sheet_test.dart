// «Use in another Request» opens a destination picker (plan D4/D10/D12, §6.2):
// the fact being copied, the note that the copy is visible in that discussion
// only, the destinations in server order (a search field above five rows),
// and one tap copies at once. The result and every failure come back as a
// snackbar; a failure leaves the picker usable.
//
// The picker is reached the way a person reaches it: the room's fact actions
// sheet (`showFactActionsSheet`, no `onUseElsewhere` passed) and a tap on the
// «Use in another Request» tile. Copy and destinations go through the real
// BeaconThreadsCase; the repository is a fake, except in the real-path test
// where HTTP -> Ferry -> BeaconFactCardRepository answers instead.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/domain/exception/server_error_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _factId = 'Fkey00000001';
const _factText = 'Key is under the mat';
const _note = 'It will be visible in that discussion only.';
const _emptyState = 'You have no open Request or Post to copy into';
const _unavailable = 'This fact is no longer available';
const _unauthorized = "You can't add facts there";

BeaconFactCopyDestination _dest(String id, String title) =>
    (id: id, kind: 0, title: title, isDraft: false, expiresAt: null);

final _sixDestinations = [
  _dest('Bgarden0001', 'Garden day'),
  _dest('Bshed000001', 'Tool shed'),
  _dest('Broof000001', 'Roof repair'),
  _dest('Bfence00001', 'Garden fence'),
  _dest('Bmoving0001', 'Moving help'),
  _dest('Bparty00001', 'Kids Garden party'),
];

class _CopyRepo extends FakeOriginFactCardRepository {
  _CopyRepo({
    this.rows = const [],
    this.outcome = BeaconFactCopyOutcome.created,
    this.copyError,
  });

  List<BeaconFactCopyDestination> rows;
  BeaconFactCopyOutcome outcome;
  Object? copyError;

  final copyCalls = <({String sourceFactCardId, String destinationBeaconId})>[];
  final destinationCalls = <String>[];

  @override
  Future<List<BeaconFactCopyDestination>> destinations({
    required String sourceFactCardId,
  }) async {
    destinationCalls.add(sourceFactCardId);
    return rows;
  }

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    copyCalls.add((
      sourceFactCardId: sourceFactCardId,
      destinationBeaconId: destinationBeaconId,
    ));
    final error = copyError;
    // ignore: only_throw_errors -- the fake throws whatever a test sets.
    if (error != null) throw error;
    return (factCardId: 'Fnew00000001', outcome: outcome);
  }
}

BeaconFactCard _fact() => copiedFact(
  originBeaconKind: null,
  id: _factId,
  beaconId: kRoomCubitFakeBeaconId,
  factText: _factText,
);

void _registerLogger() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<Logger>()) return;
  getIt.registerSingleton<Logger>(Logger('test'));
  addTearDown(() {
    // ignore: discarded_futures -- best-effort unregister.
    getIt.unregister<Logger>();
  });
}

Future<RoomCubit> _roomCubit() async {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);
  final cubit = roomCubitForTest(
    fakeRoom,
    beaconRoomCase: GetIt.instance<BeaconThreadsCase>(),
  );
  addTearDown(cubit.close);
  await awaitRoomCubitLoad(cubit);
  return cubit;
}

/// Opens the room's fact actions sheet and taps «Use in another Request».
Future<void> _openPicker(
  WidgetTester tester,
  BeaconFactCardRepository repo, {
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
  bool realAsync = false,
}) async {
  _registerLogger();
  registerFactRepository(repo);
  final cubit = await _roomCubit();
  await pumpOpener(
    tester,
    locale: locale,
    size: size,
    open: (ctx) => unawaited(
      showFactActionsSheet(ctx, cubit: cubit, fact: _fact()),
    ),
  );
  final tile = locale.languageCode == 'ru'
      ? find.text(russianFor(kUseInAnotherRequest))
      : find.text(kUseInAnotherRequest);
  expect(tile, findsOneWidget);
  await tester.tap(tile);
  if (realAsync) {
    await pumpRealAsync(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

/// Elements of [what] that live in the same route (sheet) as [anchor].
List<Element> _inRouteOf(WidgetTester tester, Finder anchor, Finder what) {
  expect(anchor, findsWidgets, reason: 'the destination picker is open');
  final route = ModalRoute.of(tester.element(anchor.first));
  return what.evaluate().where((e) => ModalRoute.of(e) == route).toList();
}

List<Element> _searchFields(WidgetTester tester, [String note = _note]) =>
    _inRouteOf(tester, find.text(note), find.byType(TextField));

/// Titles of the destination rows on screen, top to bottom.
List<String> _shownTitles(WidgetTester tester, List<String> candidates) {
  final shown = [
    for (final t in candidates)
      if (find.text(t).evaluate().isNotEmpty) t,
  ];
  return shown..sort(
    (a, b) => tester
        .getTopLeft(find.text(a))
        .dy
        .compareTo(tester.getTopLeft(find.text(b)).dy),
  );
}

final _allTitles = [for (final d in _sixDestinations) d.title];

void main() {
  group('opening the picker from the fact actions sheet', () {
    testWidgets('the tile opens a sheet titled «Use in another Request» with '
        'the fact preview and the visible-in-that-discussion note', (
      tester,
    ) async {
      final repo = _CopyRepo(rows: _sixDestinations.take(2).toList());
      await _openPicker(tester, repo);

      expect(find.text(_note), findsOneWidget);
      expect(repo.destinationCalls, [_factId]);
      expect(
        _inRouteOf(tester, find.text(_note), find.text(kUseInAnotherRequest)),
        hasLength(1),
        reason: 'the picker sheet is titled «Use in another Request»',
      );
      expect(
        _inRouteOf(tester, find.text(_note), find.text(_factText)),
        isNotEmpty,
        reason: 'the picker previews the fact being copied',
      );
      final noteY = tester.getTopLeft(find.text(_note)).dy;
      expect(tester.getTopLeft(find.text('Garden day')).dy, greaterThan(noteY));
      expect(tester.takeException(), isNull);
    });
  });

  group('destination list', () {
    testWidgets('lists the destinations in server order', (tester) async {
      await _openPicker(
        tester,
        _CopyRepo(rows: _sixDestinations.take(5).toList()),
      );

      expect(
        _shownTitles(tester, _allTitles),
        _allTitles.take(5).toList(),
      );
    });

    testWidgets('five rows show no search field', (tester) async {
      await _openPicker(
        tester,
        _CopyRepo(rows: _sixDestinations.take(5).toList()),
      );

      expect(find.text('Garden day'), findsOneWidget);
      expect(_searchFields(tester), isEmpty);
    });

    testWidgets('six rows show a search field; typing «garden» keeps only '
        'matching titles, case-insensitively, in server order', (tester) async {
      await _openPicker(tester, _CopyRepo(rows: _sixDestinations));

      expect(_searchFields(tester), hasLength(1));
      expect(_shownTitles(tester, _allTitles), _allTitles);

      await tester.enterText(
        find.byWidget(_searchFields(tester).single.widget),
        'garden',
      );
      await tester.pumpAndSettle();

      expect(_shownTitles(tester, _allTitles), [
        'Garden day',
        'Garden fence',
        'Kids Garden party',
      ]);
    });

    testWidgets('an empty list shows the empty state, no rows, no search', (
      tester,
    ) async {
      await _openPicker(tester, _CopyRepo());

      expect(find.text(_emptyState), findsOneWidget);
      expect(_shownTitles(tester, _allTitles), isEmpty);
      expect(_searchFields(tester), isEmpty);
    });
  });

  group('tapping a destination', () {
    testWidgets('copies once, at once, with the fact and the tapped '
        'destination; created says «Copied to Garden day»', (tester) async {
      final repo = _CopyRepo(rows: _sixDestinations);
      await _openPicker(tester, repo);

      await tester.tap(find.text('Garden day'));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [
        (sourceFactCardId: _factId, destinationBeaconId: 'Bgarden0001'),
      ]);
      expect(
        find.text('Copied to Garden day', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('«Open» on the copied snackbar opens the destination Request', (
      tester,
    ) async {
      final repo = _CopyRepo(rows: _sixDestinations);
      _registerLogger();
      registerFactRepository(repo);
      final cubit = await _roomCubit();
      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => unawaited(
          showFactActionsSheet(ctx, cubit: cubit, fact: _fact()),
        ),
      );
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kUseInAnotherRequest));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden day'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SnackBarAction, kOpen));
      await tester.pumpAndSettle();

      expect(routerLocation(router).path, contains('Bgarden0001'));
      expect(find.text('source-page:Bgarden0001'), findsOneWidget);
    });

    testWidgets('alreadyThere says «Already there» and its «Open» opens the '
        'tapped destination Request', (tester) async {
      final repo = _CopyRepo(
        rows: _sixDestinations,
        outcome: BeaconFactCopyOutcome.alreadyThere,
      );
      _registerLogger();
      registerFactRepository(repo);
      final cubit = await _roomCubit();
      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => unawaited(
          showFactActionsSheet(ctx, cubit: cubit, fact: _fact()),
        ),
      );
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kUseInAnotherRequest));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tool shed'));
      await tester.pumpAndSettle();

      expect(find.text('Already there', findRichText: true), findsOneWidget);
      await tester.tap(find.widgetWithText(SnackBarAction, kOpen));
      await tester.pumpAndSettle();

      expect(routerLocation(router).path, contains('Bshed000001'));
      expect(find.text('source-page:Bshed000001'), findsOneWidget);
    });
  });

  group('copy failures (server error -> repository mapping -> snackbar)', () {
    // Each case is a GraphQL error on BeaconFactCardCopy, as the server
    // sends it, mapped by the real repository. «allowed» are the app's
    // existing strings for that error; none may be the generic fallback.
    final cases = <(String, int, String, FutureOr<List<String>> Function())>[
      (
        'source unavailable (1352)',
        1352,
        'Fact source unavailable',
        () => [_unavailable],
      ),
      (
        'not allowed: the server UnauthorizedException (1102)',
        1102,
        'User is not authorized',
        () => [_unauthorized],
      ),
      (
        'room read-only (1301)',
        1301,
        'Discussion is read-only for this request',
        () => [const DiscussionReadOnlyMessage().toEn],
      ),
      (
        'fact rate limit (1320)',
        1320,
        'rate limited',
        () async => [
          (await L10n.delegate.load(const Locale('en'))).planErrorRateLimited,
        ],
      ),
      (
        'daily upload cap (1005)',
        1005,
        'Daily upload limit reached, try again tomorrow',
        () => [kServerErrorCopy['1005']!.en],
      ),
    ];

    for (final (name, code, serverMessage, allowed) in cases) {
      testWidgets('$name shows its existing message and the sheet stays '
          'usable', (tester) async {
        final wire = await _CopyWire.start(
          tester,
          copyErrorCode: code,
          copyErrorMessage: serverMessage,
        );
        await _openPicker(tester, wire.repository, realAsync: true);
        final generic = (await L10n.delegate.load(
          const Locale('en'),
        )).errorGenericAction;
        final texts = await allowed();
        expect(texts, isNot(contains(generic)));

        await tester.tap(find.text('Wire garden day'));
        await pumpRealAsync(tester);

        expect(
          [
            for (final t in texts)
              if (find.text(t, findRichText: true).evaluate().isNotEmpty) t,
          ],
          hasLength(1),
          reason: 'one of $texts is shown',
        );
        expect(find.text(generic, findRichText: true), findsNothing);
        expect(wire.copyVariables, hasLength(1));
        // Still usable: the rows stay and a second tap copies again.
        expect(find.text(_note), findsOneWidget);
        wire.copyErrorCode = null;
        await tester.tap(find.text('Wire tool shed'));
        await pumpRealAsync(tester);
        expect(wire.copyVariables, hasLength(2));
        expect(
          find.text('Copied to Wire tool shed', findRichText: true),
          findsOneWidget,
        );
      });
    }
  });

  group('copy failures thrown by copyFact (case level, no wire)', () {
    const l10nLocale = Locale('en');
    final direct = <(String, Object, FutureOr<String> Function())>[
      (
        'BeaconFactCopySourceUnavailableException',
        const BeaconFactCopySourceUnavailableException(),
        () => _unavailable,
      ),
      (
        'unauthorized (RemoteApiException 1102)',
        const RemoteApiException('User is not authorized', code: '1102'),
        () => _unauthorized,
      ),
      (
        'room read-only (RemoteApiException 1301)',
        const RemoteApiException(
          'Discussion is read-only for this request',
          code: '1301',
        ),
        () => const DiscussionReadOnlyMessage().toEn,
      ),
      (
        'BeaconFactRateLimitedException',
        const BeaconFactRateLimitedException(),
        () async => (await L10n.delegate.load(l10nLocale)).planErrorRateLimited,
      ),
      (
        'daily upload cap (RemoteApiException 1005)',
        const RemoteApiException(
          'Daily upload limit reached, try again tomorrow',
          code: '1005',
        ),
        () => kServerErrorCopy['1005']!.en,
      ),
    ];

    for (final (name, error, expected) in direct) {
      testWidgets('$name shows its message and the sheet stays usable', (
        tester,
      ) async {
        final repo = _CopyRepo(rows: _sixDestinations, copyError: error);
        await _openPicker(tester, repo);
        final text = await expected();
        final generic = (await L10n.delegate.load(
          l10nLocale,
        )).errorGenericAction;

        await tester.tap(find.text('Garden day'));
        await tester.pumpAndSettle();

        expect(find.text(text, findRichText: true), findsOneWidget);
        expect(find.text(generic, findRichText: true), findsNothing);
        expect(repo.copyCalls, hasLength(1));
        expect(find.text(_note), findsOneWidget);
        repo.copyError = null;
        await tester.tap(find.text('Tool shed'));
        await tester.pumpAndSettle();
        expect(repo.copyCalls, hasLength(2));
      });
    }
  });

  group('strings', () {
    test('every new string has an English and a Russian entry', () {
      for (final en in [
        _note,
        'Copied to {title}',
        'Already there',
        _emptyState,
        _unavailable,
        _unauthorized,
        kUseInAnotherRequest,
      ]) {
        expect(
          hasCyrillic(russianFor(en)),
          isTrue,
          reason: 'app_ru.arb translates «$en»',
        );
      }
      expect(russianValuesFor(kOpen), isNotEmpty);
      expect(russianValuesFor(kOpen).every(hasCyrillic), isTrue);
    });

    testWidgets('the search hint has an English and a Russian ARB entry', (
      tester,
    ) async {
      await _openPicker(tester, _CopyRepo(rows: _sixDestinations));
      final field = _searchFields(tester).single.widget as TextField;
      final hint = field.decoration?.hintText ?? field.decoration?.labelText;
      expect(hint, isNotNull);
      expect(hint, isNotEmpty);
      expect(
        hasCyrillic(russianFor(hint!)),
        isTrue,
        reason: 'app_ru.arb translates the search hint «$hint»',
      );
    });

    testWidgets('Russian locale: title, hint, copied snackbar and its action '
        'are Russian', (tester) async {
      await _openPicker(
        tester,
        _CopyRepo(rows: _sixDestinations),
        locale: const Locale('ru'),
      );
      final ruTitle = russianFor(kUseInAnotherRequest);
      expect(
        _inRouteOf(tester, find.text(russianFor(_note)), find.text(ruTitle)),
        hasLength(1),
      );
      final field =
          _searchFields(tester, russianFor(_note)).single.widget as TextField;
      final hint = field.decoration?.hintText ?? field.decoration?.labelText;
      expect(hint, isNotNull);
      expect(hasCyrillic(hint!), isTrue, reason: 'search hint is Russian');

      await tester.tap(find.text('Garden day'));
      await tester.pumpAndSettle();

      final copied = russianFor('Copied to {title}').replaceAll(
        '{title}',
        'Garden day',
      );
      expect(find.text(copied, findRichText: true), findsOneWidget);
      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      expect(russianValuesFor(kOpen), contains(action.label));
    });

    testWidgets('English search field has a hint', (tester) async {
      await _openPicker(tester, _CopyRepo(rows: _sixDestinations));
      final field = _searchFields(tester).single.widget as TextField;
      final hint = field.decoration?.hintText ?? field.decoration?.labelText;
      expect(hint, isNotNull);
      expect(hint, isNotEmpty);
      expect(hasCyrillic(hint!), isFalse);
    });

    testWidgets('Russian locale at 375x667 shows the Russian note and empty '
        'state without overflow', (tester) async {
      await _openPicker(
        tester,
        _CopyRepo(),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      expect(find.text(russianFor(_note)), findsOneWidget);
      expect(find.text(russianFor(_emptyState)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Russian locale at 375x667 lists long destination titles '
        'without overflow', (tester) async {
      final long = 'Очень длинное название запроса про сад и инструменты ' * 3;
      await _openPicker(
        tester,
        _CopyRepo(
          rows: [
            for (var i = 0; i < 6; i++) _dest('Blong0000$i', '$long$i'),
          ],
        ),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      expect(find.text(russianFor(_note)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('real path (HTTP -> Ferry -> repository -> case -> sheet)', () {
    testWidgets('destinations and the copy result come from the GraphQL '
        'responses, with the right ids on the wire', (tester) async {
      final wire = await _CopyWire.start(tester);

      await _openPicker(tester, wire.repository, realAsync: true);

      expect(find.text('Wire garden day'), findsOneWidget);
      expect(find.text('Wire tool shed'), findsOneWidget);
      expect(wire.destinationVariables, [
        {'sourceFactCardId': _factId},
      ]);

      await tester.tap(find.text('Wire garden day'));
      await pumpRealAsync(tester);

      expect(wire.copyVariables, [
        {'sourceFactCardId': _factId, 'destinationBeaconId': 'Bwire000001'},
      ]);
      expect(
        find.text('Copied to Wire garden day', findRichText: true),
        findsOneWidget,
      );
    });
  });
}

/// The production GraphQL stack; only HTTP is faked. `BeaconFactCardCopy`
/// answers with a GraphQL error carrying [copyErrorCode] while it is set.
final class _CopyWire {
  _CopyWire._(this.repository);

  final BeaconFactCardRepository repository;
  int? copyErrorCode;
  String copyErrorMessage = 'failed';
  final destinationVariables = <Map<String, dynamic>>[];
  final copyVariables = <Map<String, dynamic>>[];

  static Future<_CopyWire> start(
    WidgetTester tester, {
    int? copyErrorCode,
    String copyErrorMessage = 'failed',
  }) async {
    late _CopyWire wire;
    late RemoteApiService remote;
    await tester.runAsync(() async {
      await http.runWithClient(
        () async {
          remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          await remote.setSessionAuth();
          await remote.getAuthToken();
          wire = _CopyWire._(BeaconFactCardRepository(remote))
            ..copyErrorCode = copyErrorCode
            ..copyErrorMessage = copyErrorMessage;
        },
        () => MockClient((request) async {
          http.Response json(Object body) => http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
          if (request.url.path.endsWith('/session/access-token')) {
            return json({
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final name = body['operationName'] as String;
          final vars = (body['variables'] as Map).cast<String, dynamic>();
          if (name == 'BeaconFactCopyDestinations') {
            wire.destinationVariables.add(vars);
          }
          if (name == 'BeaconFactCardCopy') {
            wire.copyVariables.add(vars);
            final code = wire.copyErrorCode;
            if (code != null) {
              return json({
                'data': null,
                'errors': [
                  {
                    'message': wire.copyErrorMessage,
                    'extensions': {'code': code},
                  },
                ],
              });
            }
          }
          return json({
            'data': switch (name) {
              'BeaconFactCopyDestinations' => {
                '__typename': 'query_root',
                'BeaconFactCopyDestinations': [
                  for (final (id, title) in [
                    ('Bwire000001', 'Wire garden day'),
                    ('Bwire000002', 'Wire tool shed'),
                  ])
                    {
                      '__typename': 'v2_BeaconFactCopyDestinationRow',
                      'id': id,
                      'kind': 0,
                      'title': title,
                      'isDraft': false,
                      'expiresAt': null,
                    },
                ],
              },
              'BeaconFactCardCopy' => {
                '__typename': 'mutation_root',
                'BeaconFactCardCopy': {
                  '__typename': 'v2_BeaconFactCardCopyResult',
                  'factCardId': 'Fnew00000001',
                  'outcome': 'created',
                },
              },
              _ => null,
            },
          });
        }),
      );
    });
    addTearDown(() => tester.runAsync(remote.close));
    return wire;
  }
}
