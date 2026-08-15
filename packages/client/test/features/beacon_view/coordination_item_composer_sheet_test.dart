import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_item_composer_sheet.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/test_ids.dart';

import '../beacon_threads/fake_coordination_item_case.dart';

const _myUserId = 'Ume0000000001';
const _otherUserId = 'Uother0000001';
const _beaconId = 'B1';

final _l10n = L10nEn();

BeaconParticipant _participant({
  required String userId,
  String userTitle = '',
  int status = BeaconParticipantStatusBits.committed,
  int roomAccess = RoomAccessBits.admitted,
}) {
  final t = DateTime.utc(2025, 1, 2);
  return BeaconParticipant(
    id: 'P-$userId',
    beaconId: _beaconId,
    userId: userId,
    role: BeaconParticipantRoleBits.helper,
    status: status,
    roomAccess: roomAccess,
    userTitle: userTitle,
    createdAt: t,
    updatedAt: t,
  );
}

class TrackingPromiseCoordinationItemCase extends FakeCoordinationItemCaseForRoom {
  String? createdPromiseTargetId;

  @override
  Future<CoordinationItem> createPromise({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    createdPromiseTargetId = targetPersonId;
    return CoordinationItem(
      id: 'promise-1',
      beaconId: beaconId,
      kind: CoordinationItemKind.promise,
      status: CoordinationItemStatus.open,
      creatorId: _myUserId,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required CoordinationItemKind kind,
  required List<BeaconParticipant> participants,
  required bool participantsLoaded,
  required Stream<CoordinationParticipantsSnapshot> participantsUpdates,
  CoordinationItemCase? coordinationCase,
  String beaconAuthorId = _myUserId,
  bool isAuthorOrSteward = true,
}) async {
  final case_ = coordinationCase ?? const FakeCoordinationItemCaseForRoom();
  if (GetIt.I.isRegistered<CoordinationItemCase>()) {
    await GetIt.I.unregister<CoordinationItemCase>();
  }
  GetIt.I.registerSingleton<CoordinationItemCase>(case_);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCoordinationItemComposerSheet(
              context,
              kind: kind,
              beaconId: _beaconId,
              participants: participants,
              participantsLoaded: participantsLoaded,
              participantsUpdates: participantsUpdates,
              beaconAuthorId: beaconAuthorId,
              myUserId: _myUserId,
              isAuthorOrSteward: isAuthorOrSteward,
              onSaved: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    if (GetIt.I.isRegistered<CoordinationItemCase>()) {
      GetIt.I.unregister<CoordinationItemCase>();
    }
    GetIt.I.registerSingleton<CoordinationItemCase>(
      const FakeCoordinationItemCaseForRoom(),
    );
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<CoordinationItemCase>()) {
      await GetIt.I.unregister<CoordinationItemCase>();
    }
  });

  testWidgets('shows inline spinner while participants are not yet loaded', (
    tester,
  ) async {
    await _pumpHarness(
      tester,
      kind: CoordinationItemKind.promise,
      participants: const [],
      participantsLoaded: false,
      participantsUpdates: const Stream.empty(),
    );

    await _openSheet(tester);

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.strokeWidth, 2);
    expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
    expect(find.text(_l10n.coordinationCreatePromiseNoTargets), findsNothing);
  });

  testWidgets('promise picker renders and submits selected target id', (
    tester,
  ) async {
    final coordinationCase = TrackingPromiseCoordinationItemCase();
    final target = _participant(userId: _otherUserId, userTitle: 'Alice');

    await _pumpHarness(
      tester,
      kind: CoordinationItemKind.promise,
      participants: [target],
      participantsLoaded: true,
      participantsUpdates: const Stream.empty(),
      coordinationCase: coordinationCase,
    );

    await _openSheet(tester);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);

    await tester.enterText(
      find.byKey(TestIds.key(TestIds.coordinationComposerTitle)),
      'I will ship it',
    );
    await tester.pump();

    final submit = find.byKey(TestIds.key(TestIds.coordinationComposerSubmit));
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(find.text(_l10n.coordinationPublishPromise), findsOneWidget);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(coordinationCase.createdPromiseTargetId, _otherUserId);
  });

  testWidgets('loaded empty promise shows no-targets copy, not spinner or dropdown', (
    tester,
  ) async {
    await _pumpHarness(
      tester,
      kind: CoordinationItemKind.promise,
      participants: const [],
      participantsLoaded: true,
      participantsUpdates: const Stream.empty(),
    );

    await _openSheet(tester);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
    expect(find.text(_l10n.coordinationCreatePromiseNoTargets), findsOneWidget);
  });

  testWidgets('loaded empty ask shows draft guidance, not spinner or dropdown', (
    tester,
  ) async {
    await _pumpHarness(
      tester,
      kind: CoordinationItemKind.ask,
      participants: const [],
      participantsLoaded: true,
      participantsUpdates: const Stream.empty(),
      beaconAuthorId: _myUserId,
    );

    await _openSheet(tester);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
    expect(
      find.text(_l10n.coordinationComposerNoTargetWillSaveDraft),
      findsWidgets,
    );
  });

  testWidgets('live participant stream transitions picker from spinner to target', (
    tester,
  ) async {
    final controller = StreamController<CoordinationParticipantsSnapshot>();
    addTearDown(controller.close);

    final target = _participant(userId: _otherUserId, userTitle: 'Alice');

    await _pumpHarness(
      tester,
      kind: CoordinationItemKind.promise,
      participants: const [],
      participantsLoaded: false,
      participantsUpdates: controller.stream,
    );

    await _openSheet(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
    expect(find.text('Alice'), findsNothing);

    controller.add((participants: [target], loaded: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text(_l10n.coordinationCreatePromiseNoTargets), findsNothing);
  });
}
