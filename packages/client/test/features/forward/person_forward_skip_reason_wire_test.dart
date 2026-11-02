// The person forward screen (contact profile → Forward) sends one Request to
// one person. When the server delivers nothing, the reply says why: the
// sender already forwarded this Request to that person (an existing edge or
// a concurrent send), the person is blocked/hidden, or they paused new
// requests. The sender must read a plain, localized sentence for each case.
// An empty delivery is never an error: errors become the generic
// «Something went wrong» bar and a Sentry report.
//
// These tests run the real path: the `ForwardBeacon` and
// `BeaconInvolvementData` responses travel through the real Ferry link chain
// (only HTTP is faked), the real `ForwardRepository` mapper, the real
// `PersonForwardCase` and the real `PersonForwardCubit`.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/message/person_forward_messages.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
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

const _me = 'Uviewer000001';
const _dave = 'Udave00000001';
const _beaconId = 'Bbeacon000001';

final _beacon = Beacon.empty.copyWith(
  id: _beaconId,
  title: 'Help moving the piano',
  status: BeaconStatus.open,
  author: const Profile(id: _me),
);

const _davePerson = Profile(
  id: _dave,
  displayName: 'Dave',
  score: 1,
  rScore: 1,
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

class _DaveProfileRepository implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    if (ids.contains(_dave)) _davePerson,
  ];

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The involvement the client sees when it loads the screen: Dave is not
/// (yet) among this sender's recipients, so the Request is offered.
Map<String, dynamic> _involvementResponse() => {
  '__typename': 'query_root',
  'beaconInvolvement': {
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

/// The real person forward cubit for Dave over the real repository/case,
/// loaded until the Request row is shown.
Future<PersonForwardCubit> _loadedCubitForDave(
  RemoteApiService remote,
  _Contacts contacts,
  UiEffectPort effects,
) async {
  final beacons = _OneBeaconRepository();
  final cubit = PersonForwardCubit(
    personId: _dave,
    personForwardCase: PersonForwardCase(
      ForwardRepository(remote, beacons, buildTestRealtimeSync().port),
      beacons,
      _DaveProfileRepository(),
      contacts.authLocal,
      contacts.contactsCase,
      env: const Env(),
      logger: Logger('test'),
    ),
    effects: effects,
  );
  await cubit.stream
      .firstWhere((s) => s.person != null && s.rows.isNotEmpty)
      .timeout(const Duration(seconds: 10));
  expect(
    cubit.state.rows.single.isEligible,
    isTrue,
    reason: 'the Request is offered as sendable before Send',
  );
  return cubit;
}

/// Opens the person forward screen for Dave over the wire, selects the
/// offered Request and taps Send. Returns the effects the screen raised and
/// the cubit (still open; the caller closes it).
Future<({FakeUiEffectPort effects, PersonForwardCubit cubit})>
_sendToDaveOverWire(Map<String, dynamic> forwardResponse) async {
  final effects = FakeUiEffectPort();
  late PersonForwardCubit cubit;
  final contacts = await _signedInContacts();
  await withRemoteWire(
    {
      'BeaconInvolvementData': _involvementResponse(),
      'ForwardBeacon': forwardResponse,
    },
    <WireSent>[],
    (remote) async {
      cubit = await _loadedCubitForDave(remote, contacts, effects)
        ..selectBeacon(_beaconId);
      await cubit.send().timeout(const Duration(seconds: 10));
    },
  );
  await contacts.contactsCase.dispose();
  return (effects: effects, cubit: cubit);
}

/// The one message the screen showed. ShowError is what reaches Sentry and
/// shows the generic error bar, so an empty delivery must never raise it.
LocalizableMessage _onlyMessage(FakeUiEffectPort effects) {
  expect(
    effects.emitted.whereType<ShowError>(),
    isEmpty,
    reason:
        'an empty delivery must not raise ShowError (generic error + Sentry): '
        '${effects.emitted.whereType<ShowError>().map((e) => e.error)}',
  );
  final messages = effects.emitted.whereType<ShowMessage>().toList();
  expect(messages, hasLength(1), reason: 'the sender must be told why');
  return messages.single.message;
}

final _cyrillic = RegExp('[А-Яа-яЁё]');

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<ContactNameStore>()) {
      final store = GetIt.I<ContactNameStore>();
      await GetIt.I.unregister<ContactNameStore>();
      await store.dispose();
    }
  });

  group('person forward explains why the server delivered nothing', () {
    test('a Request this sender already forwarded to the person says so, '
        'naming them, in English and Russian', () async {
      final run = await _sendToDaveOverWire(
        _forwardResponse(alreadyForwarded: [_dave]),
      );
      addTearDown(run.cubit.close);

      final message = _onlyMessage(run.effects);
      expect(message.toEn, contains('Dave'));
      expect(
        message.toEn,
        matches(RegExp('already', caseSensitive: false)),
        reason: 'EN: ${message.toEn}',
      );
      expect(message.toEn, isNot(matches(_cyrillic)));
      expect(message.toRu, contains('Dave'));
      expect(
        message.toRu,
        matches(RegExp('уже', caseSensitive: false)),
        reason: 'RU: ${message.toRu}',
      );
    });

    test('a blocked or hidden person gets a message of its own that names '
        'them: not an error, not the already-sent, paused or no-reason '
        'copy', () async {
      Future<LocalizableMessage> messageFor(
        Map<String, dynamic> response,
      ) async {
        final run = await _sendToDaveOverWire(response);
        addTearDown(run.cubit.close);
        return _onlyMessage(run.effects);
      }

      final blocked = await messageFor(
        _forwardResponse(blockedSkipped: [_dave]),
      );
      final already = await messageFor(
        _forwardResponse(alreadyForwarded: [_dave]),
      );
      final noReason = await messageFor(_forwardResponse());
      const paused = PersonForwardAvailabilitySkippedMessage('Dave');

      expect(blocked.toEn, contains('Dave'), reason: 'EN: ${blocked.toEn}');
      expect(blocked.toRu, contains('Dave'), reason: 'RU: ${blocked.toRu}');
      expect(blocked.toEn, isNot(matches(_cyrillic)));
      expect(blocked.toRu, matches(_cyrillic));
      expect(
        blocked.toEn,
        isNot(matches(RegExp('already', caseSensitive: false))),
      );
      for (final other in [already, noReason, paused]) {
        expect(
          blocked.toEn,
          isNot(other.toEn),
          reason: 'blocked must have its own EN copy, got ${blocked.toEn}',
        );
        expect(
          blocked.toRu,
          isNot(other.toRu),
          reason: 'blocked must have its own RU copy, got ${blocked.toRu}',
        );
      }
    });

    test('an empty delivery with no known reason is a localized message, '
        'never an error', () async {
      final run = await _sendToDaveOverWire(_forwardResponse());
      addTearDown(run.cubit.close);

      final message = _onlyMessage(run.effects);
      expect(message.toEn, isNotEmpty);
      expect(message.toEn, isNot(matches(_cyrillic)));
      expect(message.toRu, matches(_cyrillic));
    });
  });

  group('the already-sent message on a 375×667 phone in Russian', () {
    setUp(() {
      GetIt.I
        ..registerSingleton<RootRouter>(_UnusedRootRouter())
        ..registerSingleton<Logger>(Logger('PersonForwardSkipReasonTest'));
    });
    tearDown(() async {
      await GetIt.I.unregister<RootRouter>();
      await GetIt.I.unregister<Logger>();
    });

    testWidgets('tapping Send shows it in full in a snackbar on the person '
        'forward screen', (tester) async {
      tester.view
        ..physicalSize = const Size(375, 667)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ru = lookupL10n(const Locale('ru'));

      final bus = UiEffectBus();
      final raised = <UiEffect>[];
      final sub = bus.effects.listen(raised.add);
      addTearDown(sub.cancel);
      final screen = ScreenCubit(FakeUiEffectPort());
      addTearDown(screen.close);

      late String shownText;
      late bool cutOff;
      late Rect rect;
      await tester.runAsync(() async {
        final contacts = await _signedInContacts();
        addTearDown(() => tester.runAsync(contacts.contactsCase.dispose));
        await withRemoteWire(
          {
            'BeaconInvolvementData': _involvementResponse(),
            'ForwardBeacon': _forwardResponse(alreadyForwarded: [_dave]),
          },
          <WireSent>[],
          (remote) async {
            final cubit = await _loadedCubitForDave(remote, contacts, bus);
            addTearDown(() => tester.runAsync(cubit.close));

            await tester.pumpWidget(
              MaterialApp(
                scaffoldMessengerKey: snackbarKey,
                locale: const Locale('ru'),
                theme: TenturaTheme.light(),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: UiEffectHandler(
                  effects: bus,
                  child: TenturaResponsiveScope(
                    child: MultiBlocProvider(
                      providers: [
                        BlocProvider<PersonForwardCubit>.value(value: cubit),
                        BlocProvider<ScreenCubit>.value(value: screen),
                      ],
                      child: Scaffold(
                        body:
                            BlocBuilder<PersonForwardCubit, PersonForwardState>(
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
            final send = find.widgetWithText(
              FilledButton,
              ru.beaconForwardPersonSend,
            );
            expect(send, findsOneWidget);
            await tester.tap(send);

            final snack = find.byType(SnackBar);
            for (var i = 0; i < 60 && snack.evaluate().isEmpty; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              await tester.pump(const Duration(milliseconds: 50));
            }
            await tester.pump(const Duration(milliseconds: 750));

            expect(
              raised.whereType<ShowError>(),
              isEmpty,
              reason:
                  'no generic error bar and no Sentry report: '
                  '${raised.whereType<ShowError>().map((e) => e.error)}',
            );
            expect(snack, findsOneWidget, reason: 'effects: $raised');
            final shown = find.descendant(
              of: snack,
              matching: find.textContaining('Dave', findRichText: true),
            );
            expect(shown, findsOneWidget, reason: 'effects: $raised');
            final paragraph = tester.renderObject<RenderParagraph>(shown);
            shownText = paragraph.text.toPlainText();
            cutOff = paragraph.didExceedMaxLines;
            rect = tester.getRect(shown);
          },
        );
      });

      expect(
        shownText,
        matches(RegExp('уже', caseSensitive: false)),
        reason: 'RU text: $shownText',
      );
      expect(shownText, isNot(contains('Something went wrong')));
      expect(cutOff, isFalse, reason: 'the message must not be cut off');
      expect(
        rect.left >= 0 &&
            rect.top >= 0 &&
            rect.right <= 375 &&
            rect.bottom <= 667,
        isTrue,
        reason: 'message rect $rect must fit on screen',
      );
    });
  });
}
