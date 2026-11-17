// «Save to my facts» / «Remove from my facts» in the fact actions sheet:
// shown to every reader (read-only readers and archived Posts included),
// hidden when the host passes no onSave, one tap saves or unsaves through
// the fact repository, the tile then shows the new state, and a saved-fact
// limit failure says why (EN and RU) and changes nothing. Both entry points
// (the room's showFactActionsSheet and the Request detail's
// showBeaconFactActions) are covered, plus the RU strings at 375×667.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_fact_actions.dart';

import '../../support/fact_sheet_feedback.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart' show pumpUntil;
import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

const _save = 'Save to my facts';
const _remove = 'Remove from my facts';
const _limit = 'You have 200 saved facts; remove some first';

Finder _inSnackBar(String text) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.text(text, findRichText: true),
);

/// The production repository over a stubbed HTTP transport: Save and Unsave
/// answer `true`, or fail with GraphQL error `errorCode` when given.
class _Wire {
  _Wire(this.repository);

  final BeaconFactCardRepository repository;
  final sent = <({String operationName, Map<String, dynamic> variables})>[];
}

Future<_Wire> _startWire(WidgetTester tester, {int? errorCode}) async {
  late _Wire wire;
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
        wire = _Wire(BeaconFactCardRepository(remote));
      },
      () => MockClient((request) async {
        http.Response json(Object b) => http.Response(
          jsonEncode(b),
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
        wire.sent.add((
          operationName: name,
          variables: (body['variables'] as Map).cast<String, dynamic>(),
        ));
        if (errorCode != null) {
          return json({
            'data': null,
            'errors': [
              {
                'message': 'saved fact limit',
                'extensions': {'code': errorCode},
              },
            ],
          });
        }
        return json({
          'data': {'__typename': 'mutation_root', name: true},
        });
      }),
    );
  });
  addTearDown(() => tester.runAsync(remote.close));
  return wire;
}

BeaconFactCard _fact({required bool saved, String beaconId = 'Bsave0001'}) {
  final base = copiedFact(originBeaconKind: null, beaconId: beaconId);
  return base.copyWith(savedByMe: saved);
}

/// Records save/unsave; with `limitReached` save fails the way the real
/// mapper reports server code 1353.
class _RecordingRepository extends FakeBeaconViewFactCardRepository {
  _RecordingRepository({this.limitReached = false});

  final bool limitReached;
  final saves = <({String beaconId, String factCardId})>[];
  final unsaves = <String>[];

  @override
  Future<void> save({
    required String beaconId,
    required String factCardId,
  }) async {
    saves.add((beaconId: beaconId, factCardId: factCardId));
    if (limitReached) throwIfBeaconFactCardError(1353, null);
  }

  @override
  Future<void> unsave({required String factCardId}) async {
    unsaves.add(factCardId);
  }
}

Future<void> _openRoomSheet(
  WidgetTester tester,
  BeaconFactCard fact, {
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);
  final cubit = roomCubitForTest(fakeRoom);
  addTearDown(cubit.close);
  await awaitRoomCubitLoad(cubit);
  await pumpOpener(
    tester,
    locale: locale,
    size: size,
    open: (ctx) =>
        unawaited(showFactActionsSheet(ctx, cubit: cubit, fact: fact)),
  );
}

/// A room whose discussion is locked (closed Request or archived Post).
Future<void> _openLockedRoomSheet(
  WidgetTester tester,
  BeaconFactCard fact, {
  required bool isPost,
}) async {
  final cubit = RoomBodyHarnessCubit(
    roomBodyState(beaconId: fact.beaconId, beaconStatus: BeaconStatus.closed),
  );
  expect(cubit.state.canWriteDiscussion, isFalse);
  await pumpOpener(
    tester,
    open: (ctx) => unawaited(
      showFactActionsSheet(ctx, cubit: cubit, fact: fact, isPost: isPost),
    ),
  );
}

Future<BeaconViewCubit> _requestCubit(
  WidgetTester tester,
  BeaconFactCard fact,
  _RecordingRepository repo, {
  BeaconStatus status = BeaconStatus.open,
}) async {
  final beacon = Beacon(
    id: fact.beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: status,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );
  final cubit = (await tester.runAsync(() async {
    final c = BeaconViewCubit(
      id: fact.beaconId,
      myProfile: const Profile(id: 'Uviewer', displayName: 'Viewer'),
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => beacon,
        factCardsRepo: repo,
      ),
      effects: FakeUiEffectPort(),
    );
    await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
    return c;
  }))!;
  addTearDown(cubit.close);
  return cubit;
}

Future<void> _openRequestSheet(
  WidgetTester tester,
  BeaconViewCubit cubit,
  BeaconFactCard fact, {
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) => pumpOpener(
  tester,
  locale: locale,
  size: size,
  open: (ctx) =>
      unawaited(showBeaconFactActions(ctx, cubit: cubit, fact: fact)),
);

void main() {
  group('phone feedback from fact actions', () {
    setUp(registerPhoneFeedbackLogger);
    for (final code in [1353, 9999]) {
      testWidgets(
        '${code == 1353 ? 'the saved fact limit' : 'a failed save'} is visible and Copy text dismisses the actions sheet with confirmation',
        (tester) async {
          final wire = await _startWire(tester, errorCode: code);
          registerFactRepository(wire.repository);
          await _openRoomSheet(
            tester,
            _fact(saved: false),
            size: kPhoneSurface,
          );
          await tester.ensureVisible(find.text('Copy text'));
          final actionsRoute = ModalRoute.of(
            tester.element(find.text('Copy text')),
          )!;
          expect(actionsRoute.isActive, isTrue);
          await tester.tap(find.text('Copy text'));
          await pumpRealAsync(tester);
          expect(
            actionsRoute.isActive,
            isFalse,
            reason: 'Copy text must dismiss the fact actions route',
          );
          expect(find.text('Copy text'), findsNothing);
          expectPhoneFeedback(tester, 'Copied to clipboard.');
          await _openRoomSheet(
            tester,
            _fact(saved: false),
            size: kPhoneSurface,
          );
          await tester.ensureVisible(find.text(_save));
          await tester.tap(find.text(_save));
          await pumpRealAsync(tester);
          expect(wire.sent.map((s) => s.operationName), ['BeaconFactCardSave']);
          expectPhoneFeedback(
            tester,
            code == 1353 ? _limit : 'Something went wrong. Please try again.',
          );
        },
      );
    }
  });

  group('host sheet without onSave', () {
    testWidgets('shows neither «Save to my facts» nor «Remove from my '
        'facts»', (tester) async {
      registerFactRepository(_RecordingRepository());
      for (final saved in [false, true]) {
        await pumpOpener(
          tester,
          open: (ctx) => unawaited(
            showFactActionsHostSheet(
              ctx,
              fact: _fact(saved: saved),
              onCorrect:
                  ({
                    required factCardId,
                    required newText,
                    attachmentsJson,
                  }) async {},
              onRemove: ({required factCardId}) async {},
              onSetVisibility:
                  ({required factCardId, required visibility}) async {},
            ),
          ),
        );
        expect(find.text('Copy text'), findsOneWidget, reason: 'sheet open');
        expect(find.text(_save), findsNothing);
        expect(find.text(_remove), findsNothing);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
    });
  });

  group('read-only contexts in the room', () {
    for (final isPost in [false, true]) {
      testWidgets(
        isPost
            ? 'an archived Post still shows «Save to my facts» and no edit '
                  'tile'
            : 'a closed Request room still shows «Save to my facts» for a '
                  'reader who cannot write',
        (tester) async {
          final repo = _RecordingRepository();
          registerFactRepository(repo);
          final fact = _fact(saved: false);
          await _openLockedRoomSheet(tester, fact, isPost: isPost);

          expect(find.text('Edit text'), findsNothing);
          expect(find.text(_save), findsOneWidget);
          await tester.tap(find.text(_save));
          await tester.pumpAndSettle();
          expect(repo.saves.map((s) => s.factCardId), [fact.id]);
        },
      );
    }
  });

  group('room fact actions sheet', () {
    testWidgets('a fact not yet saved shows «Save to my facts»; one tap '
        'saves it with its Request id and fact id, and the tile then reads '
        '«Remove from my facts»', (tester) async {
      final repo = _RecordingRepository();
      registerFactRepository(repo);
      final fact = _fact(saved: false);
      await _openRoomSheet(tester, fact);

      expect(find.text(_save), findsOneWidget);
      expect(find.text(_remove), findsNothing);
      await tester.tap(find.text(_save));
      await tester.pumpAndSettle();

      expect(repo.saves, [(beaconId: fact.beaconId, factCardId: fact.id)]);
      expect(repo.unsaves, isEmpty);
      expect(find.text(_remove), findsOneWidget);
      expect(find.text(_save), findsNothing);
    });

    testWidgets('a saved fact shows «Remove from my facts»; one tap unsaves '
        'it and the tile then reads «Save to my facts»', (tester) async {
      final repo = _RecordingRepository();
      registerFactRepository(repo);
      final fact = _fact(saved: true);
      await _openRoomSheet(tester, fact);

      expect(find.text(_remove), findsOneWidget);
      expect(find.text(_save), findsNothing);
      await tester.tap(find.text(_remove));
      await tester.pumpAndSettle();

      expect(repo.unsaves, [fact.id]);
      expect(repo.saves, isEmpty);
      expect(find.text(_save), findsOneWidget);
      expect(find.text(_remove), findsNothing);
    });

    testWidgets('real wire: saving sends BeaconFactCardSave and the tile '
        'flips to «Remove from my facts»', (tester) async {
      final wire = await _startWire(tester);
      registerFactRepository(wire.repository);
      final fact = _fact(saved: false);
      await _openRoomSheet(tester, fact);

      await tester.tap(find.text(_save));
      await pumpRealAsync(tester);

      expect(wire.sent.map((s) => s.operationName), ['BeaconFactCardSave']);
      expect(wire.sent.single.variables, {
        'beaconId': fact.beaconId,
        'factCardId': fact.id,
      });
      expect(find.text(_remove), findsOneWidget);
      expect(find.text(_save), findsNothing);
    });

    testWidgets('real wire: removing sends BeaconFactCardUnsave and the '
        'tile flips to «Save to my facts»', (tester) async {
      final wire = await _startWire(tester);
      registerFactRepository(wire.repository);
      final fact = _fact(saved: true);
      await _openRoomSheet(tester, fact);

      await tester.tap(find.text(_remove));
      await pumpRealAsync(tester);

      expect(wire.sent.map((s) => s.operationName), ['BeaconFactCardUnsave']);
      expect(wire.sent.single.variables, {'factCardId': fact.id});
      expect(find.text(_save), findsOneWidget);
      expect(find.text(_remove), findsNothing);
    });

    testWidgets('the saved-fact limit error (server code 1353) shows its '
        'message and the tile keeps reading «Save to my facts»', (
      tester,
    ) async {
      final wire = await _startWire(tester, errorCode: 1353);
      registerFactRepository(wire.repository);
      await _openRoomSheet(tester, _fact(saved: false));

      await tester.tap(find.text(_save));
      await pumpRealAsync(tester);

      expect(_inSnackBar(_limit), findsOneWidget);
      expect(find.text(_save), findsOneWidget);
      expect(find.text(_remove), findsNothing);
    });

    testWidgets('Russian locale at 375×667: both tiles are translated, no '
        'overflow', (tester) async {
      final repo = _RecordingRepository();
      registerFactRepository(repo);
      await _openRoomSheet(
        tester,
        _fact(saved: false),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );
      final ruSave = russianFor(_save);
      expect(hasCyrillic(ruSave), isTrue);
      expect(find.text(ruSave), findsOneWidget);
      expect(find.text(_save), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(ruSave));
      await tester.pumpAndSettle();
      final ruRemove = russianFor(_remove);
      expect(hasCyrillic(ruRemove), isTrue);
      expect(find.text(ruRemove), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Russian locale: the limit failure shows the translated '
        'message and the tile stays', (tester) async {
      registerFactRepository(_RecordingRepository(limitReached: true));
      await _openRoomSheet(
        tester,
        _fact(saved: false),
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );
      final ruSave = russianFor(_save);

      await tester.tap(find.text(ruSave));
      await tester.pumpAndSettle();

      final ruLimit = russianFor(_limit);
      expect(_inSnackBar(ruLimit), findsOneWidget);
      expect(_inSnackBar(_limit), findsNothing);
      expect(find.text(ruSave), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('save strings', () {
    test('every key of the three strings exists in both ARB files with '
        'the same placeholders', () {
      Map<String, Object?> arb(String f) =>
          (jsonDecode(File(f).readAsStringSync()) as Map)
              .cast<String, Object?>();
      final en = arb('l10n/app_en.arb');
      final ru = arb('l10n/app_ru.arb');
      final keys = {
        for (final e in const [_save, _remove, _limit]) arbKeyFor(e),
      };
      expect(keys, hasLength(3));
      for (final k in keys) {
        expect(ru.containsKey(k), isTrue, reason: 'app_ru.arb has $k');
        final placeholders = RegExp(r'\{(\w+)\}');
        expect(
          placeholders
              .allMatches(ru[k]! as String)
              .map((m) => m.group(1))
              .toSet(),
          placeholders
              .allMatches(en[k]! as String)
              .map((m) => m.group(1))
              .toSet(),
          reason: k,
        );
      }
    });

    for (final english in const [_save, _remove, _limit]) {
      test('«$english» has its own Russian ARB entry', () {
        final key = arbKeyFor(english);
        final ru = russianFor(english);
        expect(hasCyrillic(ru), isTrue, reason: '$key reads «$ru»');
        expect(ru, isNot(english));
      });
    }
  });

  group('Request detail fact actions', () {
    testWidgets('tapping «Save to my facts» saves with the fact’s Request '
        'id and fact id', (tester) async {
      final repo = _RecordingRepository();
      registerFactRepository(repo);
      final fact = _fact(saved: false, beaconId: 'Bsave-view-1');
      final cubit = await _requestCubit(tester, fact, repo);
      await _openRequestSheet(tester, cubit, fact);

      await tester.tap(find.text(_save));
      await tester.pumpAndSettle();

      expect(repo.saves, [(beaconId: 'Bsave-view-1', factCardId: fact.id)]);
      expect(find.text(_remove), findsOneWidget);
    });

    testWidgets('a saved fact tapped in «Remove from my facts» unsaves it', (
      tester,
    ) async {
      final repo = _RecordingRepository();
      registerFactRepository(repo);
      final fact = _fact(saved: true, beaconId: 'Bsave-view-2');
      final cubit = await _requestCubit(tester, fact, repo);
      await _openRequestSheet(tester, cubit, fact);

      await tester.tap(find.text(_remove));
      await tester.pumpAndSettle();

      expect(repo.unsaves, [fact.id]);
      expect(find.text(_save), findsOneWidget);
    });

    testWidgets('the saved-fact limit failure shows its message and the '
        'tile keeps reading «Save to my facts»', (tester) async {
      final repo = _RecordingRepository(limitReached: true);
      registerFactRepository(repo);
      final fact = _fact(saved: false, beaconId: 'Bsave-view-4');
      final cubit = await _requestCubit(tester, fact, repo);
      await _openRequestSheet(tester, cubit, fact);

      await tester.tap(find.text(_save));
      await tester.pumpAndSettle();

      expect(_inSnackBar(_limit), findsOneWidget);
      expect(find.text(_save), findsOneWidget);
      expect(find.text(_remove), findsNothing);
    });

    testWidgets('a reader without edit rights in a closed (archived) Request '
        'still gets the tile and can save', (tester) async {
      final repo = _RecordingRepository();
      registerFactRepository(repo);
      final fact = _fact(saved: false, beaconId: 'Bsave-view-3');
      final cubit = await _requestCubit(
        tester,
        fact,
        repo,
        status: BeaconStatus.closed,
      );
      await _openRequestSheet(tester, cubit, fact);

      expect(find.text('Edit text'), findsNothing, reason: 'read-only reader');
      expect(find.text(_save), findsOneWidget);
      await tester.tap(find.text(_save));
      await tester.pumpAndSettle();
      expect(repo.saves.map((s) => s.factCardId), [fact.id]);
    });
  });
}
