// A recipient can block the sender after the forward page has loaded.
// Use real Ferry, ForwardRepository, ProfileRepository and PersonForwardCase:
// the skipped mutation also publishes a local change and reloads the profile.
// An empty profile read is expected here, not a generic error/Sentry effect.
//
// Diagnosis reproduced on the unfixed tree (not a manually invoked load):
// ForwardRepository.forwardBeacon publishes forwardChanges even for a skip.
// PersonForwardCubit._subscribeLiveUpdates consumes that local event and calls
// load(). UsersFetchByIds then returns no row; PersonForwardCase.load throws
// ProfileFetchException(personId), and PersonForwardCubit.load:108 emits the
// second effect. A diagnostic run captured PersonForwardCubit.load:108 as
// the emitter; this finding is documentation, not an asserted implementation.
// Holding the empty response proves the neutral message survives until that
// read completes; there is no external push or explicit reload before it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/message/person_forward_messages.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

import '../../support/phone_surface.dart';

const _me = 'Uviewer000001';
const _dave = 'Udave00000001';
const _beaconId = 'Bbeacon000001';

final _beacon = Beacon.empty.copyWith(
  id: _beaconId,
  title: 'Help moving the piano',
  status: BeaconStatus.open,
  author: const Profile(id: _me),
);

class _UnusedRootRouter extends Mock implements RootRouter {}

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

/// The involvement the client sees when it loads the screen: Dave is not
/// (yet) among this sender's recipients, so the Request is offered.
Map<String, dynamic> _involvementResponse() => {
  '__typename': 'query_root',
  'beaconInvolvements': [
    {
      'beaconId': _beaconId,
      '__typename': 'v2_BeaconInvolvement',
      'forwardedToIds': <String>[],
      'helpOfferedIds': <String>[],
      'withdrawnIds': <String>[],
      'rejectedIds': <String>[],
      'watchingIds': <String>[],
      'onwardForwarderIds': <String>[],
      'declinedOfferIds': <String>[],
      'myForwardedRecipients': <Map<String, dynamic>>[],
    },
  ],
};

Map<String, dynamic> _forwardResponse({
  List<String> delivered = const [],
  List<String> availabilitySkipped = const [],
  List<String> alreadyForwarded = const [],
  List<String> blockedSkipped = const [],
}) => {
  '__typename': 'mutation_root',
  'beaconForward': {
    '__typename': 'v2_ForwardDeliveryResult',
    'batchId': 'Xbatch000001',
    'deliveredRecipientIds': delivered,
    'availabilitySkippedRecipientIds': availabilitySkipped,
    'alreadyForwardedRecipientIds': alreadyForwarded,
    'blockedSkippedRecipientIds': blockedSkipped,
  },
};

typedef _Contacts = ({StreamingAuthLocal authLocal, ContactsCase contactsCase});

/// Signs in as the viewer with an empty contact list (the real ContactsCase).
Future<_Contacts> _signedInContacts() async {
  final store = ContactNameStore();
  if (GetIt.I.isRegistered<ContactNameStore>()) {
    await GetIt.I.unregister<ContactNameStore>();
  }
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
  return (authLocal: authLocal, contactsCase: contactsCase);
}

class _RecipientWire {
  bool blocked = false;
  bool involvementUnavailable = false;
  bool profileUnavailable = false;
  int failedProfileReads = 0;
  Completer<void>? profileReadGate;
  final sent = <WireSent>[];

  Future<Map<String, dynamic>> answer(WireSent request) async {
    switch (request.operationName) {
      case 'UsersFetchByIds':
        if (blocked) {
          await profileReadGate?.future;
        }
        return {
          '__typename': 'query_root',
          'user': [
            if (!blocked)
              {
                '__typename': 'user',
                'id': _dave,
                'created_at': '2020-01-01T00:00:00Z',
                'display_name': 'Dave',
                'handle': null,
                'description': '',
                'my_vote': 1,
                'trusts_viewer': true,
                'is_mutual_friend': true,
                'image': null,
                'scores': <Object>[],
                'user_presence': null,
                'user_availability': null,
              },
          ],
        };
      case 'BeaconInvolvementsData':
        return _involvementResponse();
      case 'ForwardBeacon':
        expect(blocked, isTrue, reason: 'recipient blocks before Send');
        expect(request.variables['recipientIds'], [_dave]);
        expect(request.variables['beaconId'], _beaconId);
        return _forwardResponse(blockedSkipped: [_dave]);
      default:
        throw StateError('Unexpected operation ${request.operationName}');
    }
  }
}

Future<void> _withRecipient(
  UiEffectPort effects,
  Future<void> Function(PersonForwardCubit cubit, _RecipientWire wire) body,
) async {
  final contacts = await _signedInContacts();
  final wire = _RecipientWire();
  try {
    await withRemoteWire(
      {},
      wire.sent,
      (remote) async {
        final beacons = _OneBeaconRepository();
        final profiles = ProfileRepository(remote);
        final forwards = ForwardRepository(
          remote,
          beacons,
          buildTestRealtimeSync().port,
        );
        final cubit = PersonForwardCubit(
          personId: _dave,
          personForwardCase: PersonForwardCase(
            forwards,
            beacons,
            profiles,
            contacts.authLocal,
            contacts.contactsCase,
            env: const Env(),
            logger: Logger('test'),
          ),
          effects: effects,
        );
        try {
          await cubit.stream
              .firstWhere((s) => s.person != null && s.rows.isNotEmpty)
              .timeout(const Duration(seconds: 10));
          expect(cubit.state.rows.single.isEligible, isTrue);
          expect(cubit.state.person!.displayName, 'Dave');
          await body(cubit, wire);
        } finally {
          final gate = wire.profileReadGate;
          if (gate != null && !gate.isCompleted) gate.complete();
          await cubit.close();
          await forwards.dispose();
          await profiles.dispose();
        }
      },
      responseFor: wire.answer,
      errorFor: (request) async {
        if (wire.profileUnavailable &&
            request.operationName == 'UsersFetchByIds') {
          await wire.profileReadGate?.future;
          wire.failedProfileReads++;
          return wireCodeError(1000);
        }
        return wire.involvementUnavailable &&
                request.operationName == 'BeaconInvolvementsData'
            ? wireCodeError(1000)
            : null;
      },
    );
  } finally {
    await contacts.contactsCase.dispose();
  }
}

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<ContactNameStore>()) {
      final store = GetIt.I<ContactNameStore>();
      await GetIt.I.unregister<ContactNameStore>();
      await store.dispose();
    }
  });

  test(
    'a blocked recipient stays on screen without a load error or generic error',
    () async {
      final effects = FakeUiEffectPort();
      await _withRecipient(effects, (cubit, wire) async {
        cubit.selectBeacon(_beaconId);
        expect(cubit.state.canSend, isTrue);
        wire
          ..blocked = true
          ..profileReadGate = Completer<void>();
        await cubit.send().timeout(const Duration(seconds: 10));
        expect(
          effects.emitted.whereType<ShowMessage>().map((e) => e.message),
          contains(isA<PersonForwardBlockedMessage>()),
        );
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        wire.profileReadGate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(cubit.state.isLoading, isFalse);
        expect(
          cubit.state.loadError,
          isNull,
          reason: 'an unreadable recipient must be a handled state',
        );
        expect(cubit.state.person?.id, _dave);
        expect(cubit.state.person?.displayName, 'Dave');

        // The recipient unblocks while the page remains open. A subsequent
        // refresh has a genuine involvement transport failure. Handling the
        // preceding blocked refresh must not globally suppress retry rows.
        wire
          ..blocked = false
          ..involvementUnavailable = true;
        await cubit.load().timeout(const Duration(seconds: 10));
        expect(
          cubit.state.rows.single.block,
          PersonForwardBlock.involvementUnavailable,
        );
        expect(cubit.state.rows.single.isEligible, isFalse);
        expect(cubit.state.selectedBeaconId, isNull);
        wire.involvementUnavailable = false;
        await cubit.load().timeout(const Duration(seconds: 10));
        expect(cubit.state.rows.single.isEligible, isTrue);
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason:
              'blocked/unreadable is handled without a generic bar or '
              'Sentry effect',
        );
      });
    },
  );

  test(
    'a profile read failure after a blocked send offers retry and recovers',
    () async {
      final effects = FakeUiEffectPort();
      await _withRecipient(effects, (cubit, wire) async {
        cubit.selectBeacon(_beaconId);
        wire
          ..blocked = true
          ..profileUnavailable = true;
        await cubit.send().timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        // This public refresh also covers fixes that avoid the command's
        // redundant refresh: genuine later read failures still need recovery.
        await cubit.load().timeout(const Duration(seconds: 10));
        expect(wire.failedProfileReads, greaterThan(0));
        expect(cubit.state.isLoading, isFalse);
        expect(
          cubit.state.person?.id,
          _dave,
          reason: 'keep the known recipient so the sender can retry',
        );
        expect(
          cubit.state.rows.single.block,
          PersonForwardBlock.involvementUnavailable,
          reason: 'a genuine profile read failure must offer the retry row',
        );
        expect(cubit.state.rows.single.isEligible, isFalse);
        expect(cubit.state.selectedBeaconId, isNull);
        expect(
          effects.emitted.whereType<ShowMessage>().map((e) => e.message),
          contains(isA<PersonForwardBlockedMessage>()),
        );
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason: 'retryable reads must not replace the blocked explanation',
        );
        // The recipient unblocks; the sender retries on the same page.
        wire
          ..blocked = false
          ..profileUnavailable = false;
        await cubit.load().timeout(const Duration(seconds: 10));
        expect(cubit.state.loadError, isNull);
        expect(cubit.state.rows.single.isEligible, isTrue);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      });
    },
  );

  for (final phone in [true, false]) {
    final locale = Locale(phone ? 'ru' : 'en');
    for (final profileFailure in [false, true]) {
      testWidgets(
        'the blocked explanation stays visible without a generic error '
        '${profileFailure ? 'when the profile read fails' : 'when the recipient becomes unreadable'} '
        'on ${phone ? '375x667 RU' : 'desktop EN'}',
        (tester) async {
          if (phone) {
            await usePhoneSurface(tester);
          } else {
            await tester.binding.setSurfaceSize(const Size(1440, 1000));
            addTearDown(() => tester.binding.setSurfaceSize(null));
          }
          GetIt.I
            ..registerSingleton<RootRouter>(_UnusedRootRouter())
            ..registerSingleton<Logger>(Logger('BlockedForwardRefreshTest'));
          addTearDown(() async {
            await GetIt.I.unregister<RootRouter>();
            await GetIt.I.unregister<Logger>();
          });
          final bus = UiEffectBus();
          final raised = <UiEffect>[];
          final sub = bus.effects.listen(raised.add);
          addTearDown(sub.cancel);
          final screen = ScreenCubit(FakeUiEffectPort());
          addTearDown(screen.close);
          final l10n = lookupL10n(locale);
          const message = PersonForwardBlockedMessage('Dave');
          final expectedText = phone ? message.toRu : message.toEn;

          await tester.runAsync(
            () => _withRecipient(bus, (cubit, wire) async {
              try {
                await tester.pumpWidget(
                  MaterialApp(
                    scaffoldMessengerKey: snackbarKey,
                    locale: locale,
                    theme: TenturaTheme.light(),
                    localizationsDelegates: L10n.localizationsDelegates,
                    supportedLocales: L10n.supportedLocales,
                    home: UiEffectHandler(
                      effects: bus,
                      child: TenturaResponsiveScope(
                        child: MultiBlocProvider(
                          providers: [
                            BlocProvider<PersonForwardCubit>.value(
                              value: cubit,
                            ),
                            BlocProvider<ScreenCubit>.value(value: screen),
                          ],
                          child: Scaffold(
                            body:
                                BlocBuilder<
                                  PersonForwardCubit,
                                  PersonForwardState
                                >(
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
                await tester.tap(find.text(_beacon.title));
                await tester.pumpAndSettle();
                wire
                  ..blocked = true
                  ..profileUnavailable = profileFailure
                  ..profileReadGate = Completer<void>();
                await tester.tap(
                  find.widgetWithText(
                    FilledButton,
                    l10n.beaconForwardPersonSend,
                  ),
                );
                final snackText = find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.text(expectedText, findRichText: true),
                );
                for (var i = 0; i < 10 && snackText.evaluate().isEmpty; i++) {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  await tester.pump(const Duration(milliseconds: 50));
                }
                await tester.pump(const Duration(milliseconds: 200));
                expect(
                  snackText,
                  findsOneWidget,
                  reason: 'the neutral blocked message is initially visible',
                );
                wire.profileReadGate!.complete();
                // Pump real transport completions and UI animation together.
                for (var i = 0; i < 20; i++) {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  await tester.pump(const Duration(milliseconds: 50));
                }
                expect(
                  wire.sent.where((r) => r.operationName == 'ForwardBeacon'),
                  hasLength(1),
                );
                expect(
                  raised.whereType<ShowMessage>().map((e) => e.message),
                  contains(isA<PersonForwardBlockedMessage>()),
                );

                final genericError = find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.textContaining(
                    l10n.errorGenericAction,
                    findRichText: true,
                  ),
                );
                expect(
                  genericError,
                  findsNothing,
                  reason: 'the generic error copy must never replace the skip',
                );
                expect(
                  find.descendant(
                    of: find.byType(SnackBar),
                    matching: find.textContaining(
                      'Something went wrong',
                      findRichText: true,
                    ),
                  ),
                  findsNothing,
                );
                expect(
                  snackText,
                  findsOneWidget,
                  reason:
                      'the blocked skip must survive the profile refresh; '
                      'effects: ${raised.map((e) => e is ShowError ? e.error : e)}',
                );
                expect(raised.whereType<ShowError>(), isEmpty);

                // Continue the blocked-send flow: after unblocking, genuine
                // read failures still offer Retry without erasing the skip.
                wire
                  ..blocked = false
                  ..involvementUnavailable = !profileFailure
                  ..profileUnavailable = profileFailure;
                await cubit.load().timeout(const Duration(seconds: 10));
                await tester.pumpAndSettle();
                expect(
                  find.text(l10n.beaconForwardPersonReasonUnavailable),
                  findsOneWidget,
                );
                expect(
                  find.text(l10n.beaconForwardPersonRetry),
                  findsOneWidget,
                );
                wire
                  ..involvementUnavailable = false
                  ..profileUnavailable = false;
                final recovered = cubit.stream.firstWhere(
                  (s) => !s.isLoading && s.rows.single.isEligible,
                );
                await tester.tap(find.text(l10n.beaconForwardPersonRetry));
                await recovered.timeout(const Duration(seconds: 10));
                await tester.pumpAndSettle();
                expect(find.text(l10n.beaconForwardPersonRetry), findsNothing);

                final paragraph = tester.renderObject<RenderParagraph>(
                  snackText,
                );
                expect(paragraph.text.toPlainText(), expectedText);
                expect(paragraph.didExceedMaxLines, isFalse);
                final size = phone ? kPhoneSurface : const Size(1440, 1000);
                final rect = tester.getRect(snackText);
                expect(
                  rect.left >= 0 &&
                      rect.top >= 0 &&
                      rect.right <= size.width &&
                      rect.bottom <= size.height,
                  isTrue,
                );
                expect(tester.takeException(), isNull);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
              }
            }),
          );
        },
      );
    }
  }
}
