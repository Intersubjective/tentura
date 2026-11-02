// Person forward screen (contact profile → Forward), driven through the real
// PersonForwardCubit and PersonForwardCase (only the repositories are faked):
//
// * the note the sender typed is cleared from the field after a successful
//   send, not only from state;
// * when the screen cannot load whether this person already has a Request,
//   that Request is shown as unavailable with a way to try again — never
//   offered as a sendable Request (it may already have been sent to them).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_delivery_result.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

const _me = 'U-me';
const _dave = 'U-dave';
const _beaconId = 'B-open';
const _beaconTitle = 'Help moving the piano';

final _beacon = Beacon.empty.copyWith(
  id: _beaconId,
  title: _beaconTitle,
  status: BeaconStatus.open,
  author: const Profile(id: _me),
);

class _ForwardRepository implements ForwardRepository {
  final _forwardChanges = StreamController<String>.broadcast();
  final involvementFailures = <String>{};
  final sentNotes = <String?>[];

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(Beacon beacon) async {
    if (involvementFailures.contains(beacon.id)) {
      throw StateError('involvement unavailable for ${beacon.id}');
    }
    return (
      beacon: beacon,
      forwardedToIds: <String>{},
      helpOfferedIds: <String>{},
      withdrawnIds: <String>{},
      declinedOfferIds: <String>{},
      rejectedIds: <String>{},
      watchingIds: <String>{},
      onwardForwarderIds: <String>{},
      myForwardedRecipientNotes: <String, String>{},
      myForwardedRecipientEdgeIds: <String, String>{},
      myForwardedRecipientReadAts: <String, DateTime?>{},
      myForwardedRecipientHasOnwardChild: <String, bool>{},
      myForwardedRecipientRejected: <String, bool>{},
    );
  }

  @override
  Future<ForwardDeliveryResult> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
    List<String>? attributionParentEdgeIds,
    Map<String, ({String? tier, bool isExploration})>? recipientBandProvenance,
  }) async {
    sentNotes.add(note);
    return ForwardDeliveryResult(
      batchId: 'X-batch',
      deliveredRecipientIds: recipientIds,
      availabilitySkippedRecipientIds: const [],
    );
  }

  @override
  Future<void> dispose() => _forwardChanges.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OneBeaconRepository implements BeaconRepository {
  @override
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = 5,
  }) async => [_beacon];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DaveProfileRepository implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    if (ids.contains(_dave))
      const Profile(id: _dave, displayName: 'Dave', score: 1, rScore: 1),
  ];

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Harness = ({
  PersonForwardCubit cubit,
  _ForwardRepository forwardRepo,
  FakeUiEffectPort effects,
});

/// Builds the real case + cubit outside fake async (the contacts sync and
/// the first load run on real futures), then leaves the cubit loaded.
Future<_Harness> _buildHarness(
  WidgetTester tester, {
  Set<String> involvementFailures = const {},
}) async {
  final harness = await tester.runAsync(() async {
    final store = ContactNameStore();
    GetIt.I.registerSingleton<ContactNameStore>(store);
    final authLocal = StreamingAuthLocal(_me);
    final contactsRepo = FakeContactsRepository()
      ..fetchMineHandler = () async => {};
    final contactsCase = ContactsCase(
      contactsRepo,
      buildTestAuthCase(authLocal, EmptyAuthRemote()),
      store,
      buildTestRealtimeSync().case_,
      env: const Env(),
      logger: Logger('test'),
    );
    final syncReady = contactsRepo.nextSync();
    authLocal.emit(_me);
    await syncReady;

    final forwardRepo = _ForwardRepository()
      ..involvementFailures.addAll(involvementFailures);
    final effects = FakeUiEffectPort();
    final cubit = PersonForwardCubit(
      personId: _dave,
      personForwardCase: PersonForwardCase(
        forwardRepo,
        _OneBeaconRepository(),
        _DaveProfileRepository(),
        authLocal,
        contactsCase,
        env: const Env(),
        logger: Logger('test'),
      ),
      effects: effects,
    );
    await cubit.stream
        .firstWhere((s) => s.person != null && s.rows.isNotEmpty)
        .timeout(const Duration(seconds: 10));
    return (
      harness: (cubit: cubit, forwardRepo: forwardRepo, effects: effects),
      contactsCase: contactsCase,
      store: store,
    );
  });
  addTearDown(
    () => tester.runAsync(() async {
      await harness!.harness.cubit.close();
      await harness.harness.forwardRepo.dispose();
      await harness.contactsCase.dispose();
      if (GetIt.I.isRegistered<ContactNameStore>()) {
        await GetIt.I.unregister<ContactNameStore>();
      }
      await harness.store.dispose();
    }),
  );
  return harness!.harness;
}

Future<void> _pumpScreen(WidgetTester tester, PersonForwardCubit cubit) async {
  final screen = ScreenCubit(FakeUiEffectPort());
  addTearDown(screen.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 900)),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<PersonForwardCubit>.value(value: cubit),
              BlocProvider<ScreenCubit>.value(value: screen),
            ],
            child: Scaffold(
              body: BlocBuilder<PersonForwardCubit, PersonForwardState>(
                builder: (context, state) =>
                    personForwardBodyForTest(state: state),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _sendButton => find.widgetWithText(
  FilledButton,
  lookupL10n(const Locale('en')).beaconForwardPersonSend,
);

bool _sendEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_sendButton).onPressed != null;

final _retryLabel = RegExp(r'retry|try again', caseSensitive: false);

void main() {
  testWidgets('the note field is empty again after a successful send', (
    tester,
  ) async {
    final harness = await _buildHarness(tester);
    await _pumpScreen(tester, harness.cubit);

    await tester.tap(find.text(_beaconTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bring a van');
    await tester.pumpAndSettle();
    expect(_sendEnabled(tester), isTrue);

    await tester.tap(_sendButton);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(harness.forwardRepo.sentNotes, ['Bring a van']);
    expect(
      harness.effects.emitted.whereType<ShowMessage>(),
      isNotEmpty,
      reason: 'the send was delivered and confirmed',
    );
    expect(harness.cubit.state.note, isEmpty);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
      reason: 'the typed note must not stay visible after the send',
    );
    expect(find.text('Bring a van'), findsNothing);
  });

  group('involvement for a Request fails to load', () {
    testWidgets('the Request is not offered as sendable', (tester) async {
      final harness = await _buildHarness(
        tester,
        involvementFailures: {_beaconId},
      );
      await _pumpScreen(tester, harness.cubit);

      expect(find.text(_beaconTitle), findsOneWidget);
      await tester.tap(find.text(_beaconTitle));
      await tester.pumpAndSettle();

      expect(
        harness.cubit.state.selectedBeaconId,
        isNull,
        reason: 'a Request whose involvement is unknown must not be selectable',
      );
      expect(_sendEnabled(tester), isFalse);
      expect(
        harness.cubit.state.rows.single.isEligible,
        isFalse,
        reason: 'unknown involvement is not eligible `unseen`',
      );
    });

    testWidgets('the row offers a retry that makes it sendable once the '
        'involvement loads', (tester) async {
      final harness = await _buildHarness(
        tester,
        involvementFailures: {_beaconId},
      );
      await _pumpScreen(tester, harness.cubit);

      final retry = find.textContaining(_retryLabel);
      expect(retry, findsOneWidget, reason: 'the unavailable row offers retry');

      harness.forwardRepo.involvementFailures.clear();
      await tester.tap(retry);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.textContaining(_retryLabel), findsNothing);
      await tester.tap(find.text(_beaconTitle));
      await tester.pumpAndSettle();
      expect(harness.cubit.state.selectedBeaconId, _beaconId);
      expect(_sendEnabled(tester), isTrue);
    });
  });
}
