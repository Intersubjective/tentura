import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_create/ui/widget/recipients_tab.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

// #439: on the new-Request Recipients step the author sends their own
// Request, yet the primary button read «Forward to N», the shared-note sheet
// it opens read «Forward to N» too, and the per-person note hint read
// «Note for Clara». Forwarding is what other people do with someone else's
// Request: the author's step says «Send to N» and the note hint reads
// «Add a note for this person (optional)». The forward flow keeps
// «Forward to N»; that side is pinned by forward_recipient_picker_test.dart.

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<void> dispose() async {}
}

/// Forward repository whose band never resolves; the test fills the picker
/// itself.
class _NeverLoadingForwardRepository implements ForwardRepository {
  @override
  Stream<String> get forwardChanges => const Stream<String>.empty();

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      Completer<Iterable<Profile>>().future;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) => Completer<BeaconInvolvementData>().future;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ForwardCase _buildForwardCase(ContactNameStore store) {
  final authLocal = StreamingAuthLocal();
  final contactsCase = ContactsCase(
    FakeContactsRepository(),
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  return ForwardCase(
    _NeverLoadingForwardRepository(),
    authLocal,
    _FakeBeaconFactCardRepository(),
    _FakeProfileRepository(),
    contactsCase,
    noopBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
}

class _NavRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

final _sendButton = find.byKey(TestIds.key(TestIds.forwardSubmit));

/// Lets cubit futures and post-frame callbacks run without waiting on the
/// never-resolving forward band.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BeaconCreateCubit createCubit;
  late ContextCubit contextCubit;

  setUp(() {
    final store = ContactNameStore();
    GetIt.I
      ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<Logger>(Logger('test'))
      ..registerSingleton<ContactNameStore>(store)
      ..registerSingleton<ForwardCase>(_buildForwardCase(store))
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
    contextCubit = ContextCubit(
      authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      contextRepository: _ContextRepositoryFake(),
      effects: FakeUiEffectPort(),
    );
  });

  tearDown(() async {
    await createCubit.close();
    await contextCubit.close();
    await GetIt.I.reset();
  });

  /// Opens the author's Recipients step of a valid new Request with Clara
  /// picked and no personal note written for her yet.
  Future<void> pumpAuthorRecipientsWithOnePicked(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    createCubit =
        BeaconCreateCubit(
            beaconCreateCase: fakeBeaconCreateCase(),
            effects: FakeUiEffectPort(),
          )
          ..setTitle('Need a piano moved')
          ..setDescription('Two flights of stairs, this weekend.');
    final router = _NavRouter();
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: RouterScope(
          controller: router,
          stateHash: 0,
          inheritableObserversBuilder: () => const [],
          child: StackRouterScope(
            controller: router,
            stateHash: 0,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ContextCubit>.value(value: contextCubit),
                BlocProvider<BeaconCreateCubit>.value(value: createCubit),
                BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              ],
              child: const BeaconCreateScreen(
                initialTab: kBeaconCreateTabRecipients,
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    // Precondition: the draft exists and the embedded picker is shown.
    expect(find.byType(BeaconRecipientsTab), findsOneWidget);
    final forwardCubit = tester
        .element(find.byType(BeaconRecipientsTab))
        .read<ForwardCubit>();
    forwardCubit.emit(
      forwardCubit.state.copyWith(
        candidates: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: 'Clara',
              rScore: 1,
              score: 70,
            ),
          ),
        ],
        selectedIds: const {'u1'},
        candidatesLoad: const ForwardCandidatesReady(),
        // The fake band never resolves, so the picker would stay loading and
        // absorb every tap on its send button.
        status: const StateIsSuccess(),
      ),
    );
    await _settle(tester);

    // Precondition: the send button is enabled (one person picked and the
    // Request is ready), so it shows its count label, not «Select
    // recipients».
    final button = tester.widget<OutlinedButton>(_sendButton);
    expect(button.onPressed, isNotNull, reason: 'send must be enabled');
    // Ticking no longer opens the note (#893): open Clara's note from her
    // row's «+ Note» control, as a person would.
    expect(find.byType(PerRecipientNoteInput), findsNothing);
    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await _settle(tester);
    // Precondition: Clara has the per-person note field under her row.
    expect(find.byType(PerRecipientNoteInput), findsOneWidget);
  }

  String noteHint(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(PerRecipientNoteInput),
        matching: find.byType(TextField),
      ),
    );
    return field.decoration?.hintText ?? '';
  }

  testWidgets('author send button reads Send to 1, not Forward to 1', (
    tester,
  ) async {
    await pumpAuthorRecipientsWithOnePicked(tester);

    expect(
      find.descendant(of: _sendButton, matching: find.text('Send to 1')),
      findsOneWidget,
    );
    expect(find.text('Forward to 1'), findsNothing);
  });

  testWidgets(
    'author shared-note sheet confirms with Send to 2, not Forward to 2',
    (tester) async {
      await pumpAuthorRecipientsWithOnePicked(tester);
      // A shared note only makes sense for two or more people (#669), so
      // pick a second person.
      final forwardCubit = tester
          .element(find.byType(BeaconRecipientsTab))
          .read<ForwardCubit>();
      forwardCubit.emit(
        forwardCubit.state.copyWith(
          candidates: const [
            ForwardCandidate(
              profile: Profile(
                id: 'u1',
                displayName: 'Clara',
                rScore: 1,
                score: 70,
              ),
            ),
            ForwardCandidate(
              profile: Profile(
                id: 'u2',
                displayName: 'Dan',
                rScore: 1,
                score: 60,
              ),
            ),
          ],
          selectedIds: const {'u1', 'u2'},
        ),
      );
      await _settle(tester);

      await tester.tap(_sendButton);
      await _settle(tester);

      // Precondition: neither has a personal note, so send first opens the
      // shared-note sheet instead of sending.
      expect(find.text('Shared note'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Send to 2'),
        findsOneWidget,
      );
      expect(find.text('Forward to 2'), findsNothing);
    },
  );

  testWidgets('author per-person note hint reads as an optional note', (
    tester,
  ) async {
    await pumpAuthorRecipientsWithOnePicked(tester);

    expect(noteHint(tester), 'Add a note for this person (optional)');
  });

  testWidgets('ru: author send button reads Otpravit, not Pereslat', (
    tester,
  ) async {
    await pumpAuthorRecipientsWithOnePicked(
      tester,
      locale: const Locale('ru'),
    );

    expect(
      find.descendant(of: _sendButton, matching: find.text('Отправить (1)')),
      findsOneWidget,
    );
    expect(find.text('Переслать (1)'), findsNothing);
  });

  testWidgets('ru: author per-person note hint is translated and nameless', (
    tester,
  ) async {
    await pumpAuthorRecipientsWithOnePicked(
      tester,
      locale: const Locale('ru'),
    );

    final hint = noteHint(tester);
    expect(hint, isNotEmpty);
    expect(hint, isNot('Add a note for this person (optional)'));
    expect(hint, isNot(contains('Clara')));
    expect(hint, isNot(startsWith('Заметка для')));
  });
}
