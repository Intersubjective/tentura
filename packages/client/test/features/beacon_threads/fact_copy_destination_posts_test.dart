// «Use in another Request or Post» (plan §6.2, block B): a fact can be copied
// into a Post as well as a Request. The actions sheet tile and the
// destination sheet say so, a Post row shows how long the Post has left
// (Posts live at most 72 h; a Request row shows no such time), tapping the
// Post row copies into that Post, and the empty text names Posts too. EN and
// RU, and RU at 375x667 without overflow.
//
// Reached the way a person reaches it: the room's fact actions sheet
// (`showFactActionsSheet` over a real RoomCubit) and a tap on its tile.
// Destinations and copy go through the real BeaconThreadsCase over a fake
// fact-card repository.

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
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _factId = 'Fkey00000001';
const _factText = 'Key is under the mat';
const _useElsewhere = 'Use in another Request or Post';
const _oldUseElsewhere = 'Use in another Request';
const _note = 'It will be visible in that discussion only.';

const _requestId = 'Bgarden0001';
const _requestTitle = 'Garden day';
const _postId = 'Bladder0001';
const _postTitle = 'Who has a ladder?';

/// A Post with three and a half hours left: «3 h left».
const _postLeft = Duration(hours: 3, minutes: 30);

BeaconFactCopyDestination _request() => (
  id: _requestId,
  kind: 0,
  title: _requestTitle,
  isDraft: false,
  expiresAt: null,
);

BeaconFactCopyDestination _post() => (
  id: _postId,
  kind: 1,
  title: _postTitle,
  isDraft: false,
  expiresAt: DateTime.now().add(_postLeft),
);

class _CopyRepo extends FakeOriginFactCardRepository {
  _CopyRepo({this.rows = const []});

  final List<BeaconFactCopyDestination> rows;
  final copiedInto = <String>[];

  @override
  Future<List<BeaconFactCopyDestination>> destinations({
    required String sourceFactCardId,
  }) async => rows;

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    copiedInto.add(destinationBeaconId);
    return (factCardId: 'Fnew00000001', outcome: BeaconFactCopyOutcome.created);
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

Future<RoomCubit> _requestRoomCubit() async {
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

/// Opens a Request room's fact actions sheet.
Future<void> _openActions(
  WidgetTester tester,
  BeaconFactCardRepository repo, {
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  _registerLogger();
  registerFactRepository(repo);
  final cubit = await _requestRoomCubit();
  await pumpOpener(
    tester,
    locale: locale,
    size: size,
    open: (ctx) => unawaited(
      showFactActionsSheet(ctx, cubit: cubit, fact: _fact()),
    ),
  );
}

/// Opens the actions sheet and taps «Use in another Request or Post».
Future<void> _openPicker(
  WidgetTester tester,
  _CopyRepo repo, {
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  await _openActions(tester, repo, locale: locale, size: size);
  final label = locale.languageCode == 'ru'
      ? russianFor(_useElsewhere)
      : _useElsewhere;
  final tile = find.text(label);
  expect(tile, findsOneWidget, reason: 'the actions sheet offers «$label»');
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// The tappable row that holds [title].
Finder _rowOf(String title) => find
    .ancestor(
      of: find.textContaining(title, findRichText: true),
      matching: find.byWidgetPredicate((w) => w is ListTile || w is InkWell),
    )
    .first;

/// Every remaining-time label a Post row could show, in [l10n]'s language.
Set<String> _allRemainingLabels(L10n l10n) => {
  for (var m = 1; m < 60; m++) postRemainingLabel(l10n, Duration(minutes: m)),
  for (var h = 1; h < 24; h++) postRemainingLabel(l10n, Duration(hours: h)),
  for (var d = 1; d <= 3; d++) postRemainingLabel(l10n, Duration(days: d)),
};

void main() {
  group('the actions sheet tile', () {
    testWidgets('reads «Use in another Request or Post» in a Request room; '
        'the old «Use in another Request» is gone', (tester) async {
      await _openActions(tester, _CopyRepo());

      expect(find.text(_useElsewhere), findsOneWidget);
      expect(find.text(_oldUseElsewhere), findsNothing);
    });

    testWidgets('reads its Russian translation in RU, which names Posts', (
      tester,
    ) async {
      await _openActions(tester, _CopyRepo(), locale: const Locale('ru'));

      final ru = russianFor(_useElsewhere);
      expect(hasCyrillic(ru), isTrue);
      expect(ru.toLowerCase(), contains('пост'));
      expect(find.text(ru), findsOneWidget);
      expect(find.text(_useElsewhere), findsNothing);
    });
  });

  group('the destination sheet', () {
    testWidgets('is titled «Use in another Request or Post»', (tester) async {
      await _openPicker(tester, _CopyRepo(rows: [_request()]));

      // The title belongs to the destination sheet, not to the actions
      // sheet tile left behind it.
      final note = find.text(_note);
      expect(note, findsOneWidget);
      final sheetRoute = ModalRoute.of(tester.element(note));
      final titles = find
          .text(_useElsewhere)
          .evaluate()
          .where((e) => ModalRoute.of(e) == sheetRoute);
      expect(titles, hasLength(1));
    });

    testWidgets('lists a Request and a Post; only the Post row shows its '
        'remaining time', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _openPicker(tester, _CopyRepo(rows: [_request(), _post()]));

      expect(find.textContaining(_requestTitle), findsOneWidget);
      expect(find.textContaining(_postTitle), findsOneWidget);

      final left = postRemainingLabel(l10n, _postLeft);
      expect(left, '3 h left');
      expect(
        find.descendant(
          of: _rowOf(_postTitle),
          matching: find.textContaining(left, findRichText: true),
        ),
        findsWidgets,
        reason: 'the Post row says how long the Post has left',
      );

      final requestTexts = textsUnder(tester, _rowOf(_requestTitle));
      final labels = _allRemainingLabels(l10n);
      expect(
        requestTexts.where((t) => labels.any(t.contains)),
        isEmpty,
        reason: 'a Request has no lifetime: its row shows no remaining time',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the Post row copies the fact into that Post', (
      tester,
    ) async {
      final repo = _CopyRepo(rows: [_request(), _post()]);
      await _openPicker(tester, repo);

      await tester.tap(find.textContaining(_postTitle));
      await tester.pumpAndSettle();

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(repo.copiedInto, [_postId]);
      expect(
        find.text(l10n.beaconFactCopyCopiedTo(_postTitle), findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('with nothing to copy into, the empty text names Posts', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _openPicker(tester, _CopyRepo());

      final empty = l10n.beaconFactCopyEmpty;
      expect(empty, matches(RegExp(r'\bPosts?\b')));
      expect(find.text(empty), findsOneWidget);
    });

    testWidgets('Russian: the empty text names Posts', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      await _openPicker(tester, _CopyRepo(), locale: const Locale('ru'));

      final empty = l10n.beaconFactCopyEmpty;
      expect(hasCyrillic(empty), isTrue);
      expect(empty.toLowerCase(), matches(RegExp('(^|[^а-яё])пост')));
      expect(find.text(empty), findsOneWidget);
    });

    testWidgets('Russian at 375x667: a Request and a Post with long titles, '
        'the Post row in Russian with its remaining time, no overflow', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      final long =
          'Очень длинное название про сад, лестницу и инструменты ' * 3;
      await _openPicker(
        tester,
        _CopyRepo(
          rows: [
            (
              id: _requestId,
              kind: 0,
              title: 'Запрос $long',
              isDraft: false,
              expiresAt: null,
            ),
            (
              id: _postId,
              kind: 1,
              title: 'Пост $long',
              isDraft: false,
              expiresAt: DateTime.now().add(_postLeft),
            ),
          ],
        ),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      final left = postRemainingLabel(l10n, _postLeft);
      expect(hasCyrillic(left), isTrue);
      expect(
        find.descendant(
          of: _rowOf('Пост '),
          matching: find.textContaining(left, findRichText: true),
        ),
        findsWidgets,
      );
      expect(find.text(russianFor(_useElsewhere)), findsOneWidget);
      expect(find.text(_useElsewhere), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('real path (HTTP -> Ferry -> repository -> case -> sheet)', () {
    testWidgets('a Post row from BeaconFactCopyDestinations shows its '
        'remaining time; a Request row shows none; tapping the Post copies '
        'into it on the wire', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final expiresAt = DateTime.now().toUtc().add(_postLeft);
      final wire = await _DestinationWire.start(
        tester,
        rows: [
          {
            '__typename': 'v2_BeaconFactCopyDestinationRow',
            'id': _requestId,
            'kind': 0,
            'title': _requestTitle,
            'isDraft': false,
            'expiresAt': null,
          },
          {
            '__typename': 'v2_BeaconFactCopyDestinationRow',
            'id': _postId,
            'kind': 1,
            'title': _postTitle,
            'isDraft': false,
            'expiresAt': expiresAt.toIso8601String(),
          },
        ],
      );
      await _openActions(tester, wire.repository);
      await tester.tap(find.text(_useElsewhere));
      await pumpRealAsync(tester);

      expect(find.textContaining(_requestTitle), findsOneWidget);
      expect(find.textContaining(_postTitle), findsOneWidget);
      final left = postRemainingLabel(l10n, _postLeft);
      expect(
        find.descendant(
          of: _rowOf(_postTitle),
          matching: find.textContaining(left, findRichText: true),
        ),
        findsWidgets,
      );
      final labels = _allRemainingLabels(l10n);
      expect(
        textsUnder(
          tester,
          _rowOf(_requestTitle),
        ).where((t) => labels.any(t.contains)),
        isEmpty,
      );

      await tester.tap(find.textContaining(_postTitle));
      await pumpRealAsync(tester);
      expect(wire.copyVariables, [
        {'sourceFactCardId': _factId, 'destinationBeaconId': _postId},
      ]);
    });
  });

  group('strings', () {
    test('the renamed action has a Russian entry', () {
      expect(hasCyrillic(russianFor(_useElsewhere)), isTrue);
    });
  });
}

/// The production GraphQL stack; only HTTP is faked.
final class _DestinationWire {
  _DestinationWire._(this.repository);

  final BeaconFactCardRepository repository;
  final copyVariables = <Map<String, dynamic>>[];

  static Future<_DestinationWire> start(
    WidgetTester tester, {
    required List<Map<String, Object?>> rows,
  }) async {
    late _DestinationWire wire;
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
          wire = _DestinationWire._(BeaconFactCardRepository(remote));
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
          if (name == 'BeaconFactCardCopy') wire.copyVariables.add(vars);
          return json({
            'data': switch (name) {
              'BeaconFactCopyDestinations' => {
                '__typename': 'query_root',
                'BeaconFactCopyDestinations': rows,
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
