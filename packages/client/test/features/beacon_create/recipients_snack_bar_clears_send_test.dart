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
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../ui/snack_bar_clearance_support.dart';
import 'fake_beacon_ports.dart';

// #406: on the new-Request Recipients step the red «Image is not attached…»
// error bar and the «Invite saved» notice were drawn across the embedded
// «Send to N» send button (it read «Forward to N» before #439). The step
// keeps its own bottom bar («Make live without sending») under the picker,
// so a bar placed just above that bar still lands on the picker's send
// button.

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

const _errorText = 'Image is not attached to this request';

final _sendButton = find.byKey(TestIds.key(TestIds.forwardSubmit));

/// Lets cubit futures and post-frame callbacks run without waiting on the
/// never-resolving forward band.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the bar finish its entrance animation without waiting out its
/// auto-dismiss timer.
Future<void> _showBar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
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

  /// Opens the Recipients step of a valid new Request with one person picked.
  Future<void> pumpRecipientsWithOnePicked(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view
      ..physicalSize = size
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
        scaffoldMessengerKey: snackbarKey,
        locale: const Locale('en'),
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

    // Precondition: the step's primary action is the enabled «Send to 1».
    expect(
      find.descendant(of: _sendButton, matching: find.text('Send to 1')),
      findsOneWidget,
    );

    // Precondition: with no bar shown, a tap on the centre of «Send to 1»
    // reaches the button.
    final hit = tester.hitTestOnBinding(tester.getCenter(_sendButton));
    final buttonBox = tester.renderObject(_sendButton);
    expect(
      hit.path.any((entry) => identical(entry.target, buttonBox)),
      isTrue,
      reason: 'before any bar is shown, a tap on Send to 1 must reach it',
    );
  }

  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets(
      'Recipients ($label): an error bar raised by the create screen sits '
      'above Send to 1',
      (tester) async {
        await pumpRecipientsWithOnePicked(tester, size);

        // Raised from the create screen (its effect handler / cover upload),
        // not from inside the picker.
        showSnackBar(
          tester.element(find.byType(BeaconCreateScreen)),
          text: _errorText,
          isError: true,
        );
        await _showBar(tester);

        expectSnackBarClearsButton(
          tester,
          message: _errorText,
          button: _sendButton,
        );
      },
    );

    testWidgets(
      'Recipients ($label): the Invite saved notice sits above Send to 1',
      (tester) async {
        await pumpRecipientsWithOnePicked(tester, size);

        final pickerContext = tester.element(
          find.byType(ForwardRecipientPicker),
        );
        final message = L10n.of(pickerContext)!.forwardInviteCreatedHint;
        showSnackBar(
          pickerContext,
          text: message,
          action: SnackBarAction(
            label: L10n.of(pickerContext)!.forwardViewInvitations,
            onPressed: () {},
          ),
        );
        await _showBar(tester);

        expectSnackBarClearsButton(
          tester,
          message: message,
          button: _sendButton,
        );
      },
    );
  }
}
