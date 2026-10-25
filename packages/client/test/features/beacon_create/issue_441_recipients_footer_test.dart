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
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
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

// #441: on the new-Request Recipients step the list ran straight into the
// footer: no edge between the scrolling list and the send button, so the
// bottom row looked cut off under the footer. With nobody picked the footer
// showed the greyed words «Select recipients» with no outline, which read as
// a section label instead of a button.
//
// The fix this file pins: a `TenturaHairlineDivider` between the list's
// viewport and the send button (the same hairline the create screen's own
// bottom bar starts with), the list never running under the footer, and the
// disabled send button keeping a visible outline and its label «Send to 0»
// (ru «Отправить (0)»). Since #720 Forward and new-Post keep their count
// label too, with a helper line beside the button
// (issue_720_723_forward_send_button_test.dart).

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

final _rows = find.descendant(
  of: find.byType(ForwardRecipientPicker),
  matching: find.byType(ForwardRecipientRow),
);

/// Global rect of a laid-out element (the hairline is a const widget, so
/// `find.byWidget` would match every one of them).
Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

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

  /// Opens the author's Recipients step of a valid new Request (desktop
  /// 1280x800, as in the report) with [count] people to choose from and
  /// nobody picked.
  Future<void> pumpAuthorRecipients(
    WidgetTester tester, {
    int count = 20,
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
        candidates: [
          for (var i = 1; i <= count; i++)
            ForwardCandidate(
              profile: Profile(
                id: 'u$i',
                displayName: 'Person ${i.toString().padLeft(2, '0')}',
                rScore: 1,
                score: 100.0 - i,
              ),
            ),
        ],
        selectedIds: const <String>{},
        candidatesLoad: const ForwardCandidatesReady(),
        // The fake band never resolves, so the picker would stay loading.
        status: const StateIsSuccess(),
      ),
    );
    await _settle(tester);

    // Precondition: the rows are on screen and nobody is picked, so the
    // send button is disabled.
    expect(_rows, findsWidgets);
    final button = tester.widget<OutlinedButton>(_sendButton);
    expect(button.onPressed, isNull, reason: 'nobody picked: send disabled');
  }

  /// The border the disabled send button actually paints (the button's own
  /// Material shape), whatever way the style sets it.
  BorderSide paintedSide(WidgetTester tester) {
    final material = tester.widget<Material>(
      find.descendant(of: _sendButton, matching: find.byType(Material)).first,
    );
    final shape = material.shape;
    expect(shape, isA<OutlinedBorder>());
    return (shape! as OutlinedBorder).side;
  }

  testWidgets('nothing picked: the send button keeps its label Send to 0', (
    tester,
  ) async {
    await pumpAuthorRecipients(tester);

    expect(
      find.descendant(of: _sendButton, matching: find.text('Send to 0')),
      findsOneWidget,
    );
    expect(find.text('Select recipients'), findsNothing);
  });

  testWidgets('ru: nothing picked: the send button reads Otpravit (0)', (
    tester,
  ) async {
    await pumpAuthorRecipients(tester, locale: const Locale('ru'));

    expect(
      find.descendant(of: _sendButton, matching: find.text('Отправить (0)')),
      findsOneWidget,
    );
    expect(find.text('Выберите получателей'), findsNothing);
  });

  testWidgets('nothing picked: the disabled send button has an outline', (
    tester,
  ) async {
    await pumpAuthorRecipients(tester);

    final side = paintedSide(tester);
    expect(side.style, BorderStyle.solid, reason: 'no outline was drawn');
    expect(side.width, greaterThan(0));
    expect(side.color.a, greaterThan(0));

    // Guard: still disabled, and it must not look like the filled primary
    // button it becomes once someone is picked.
    final button = tester.widget<OutlinedButton>(_sendButton);
    expect(button.onPressed, isNull);
    final scheme = Theme.of(tester.element(_sendButton)).colorScheme;
    final material = tester.widget<Material>(
      find.descendant(of: _sendButton, matching: find.byType(Material)).first,
    );
    expect(material.color, isNot(scheme.primary));
  });

  testWidgets(
    'a hairline separates the recipients list from the send footer, '
    'and the last row scrolls fully above it',
    (tester) async {
      await pumpAuthorRecipients(tester);

      final picker = find.byType(ForwardRecipientPicker);
      final scrollView = find.descendant(
        of: picker,
        matching: find.byType(CustomScrollView),
      );
      expect(scrollView, findsOneWidget);
      final viewport = tester.getRect(scrollView);
      final buttonTop = tester.getRect(_sendButton).top;

      // Precondition: the list is longer than its viewport (it scrolls).
      final scrollable = find
          .descendant(of: scrollView, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));

      // An edge between the list and the footer: a hairline outside the
      // scrolling list, below its viewport and above the send button.
      final inList = find
          .descendant(
            of: scrollView,
            matching: find.byType(TenturaHairlineDivider),
          )
          .evaluate()
          .toSet();
      final edges = find
          .descendant(of: picker, matching: find.byType(TenturaHairlineDivider))
          .evaluate()
          .where((e) => !inList.contains(e))
          .map(_rectOf)
          .where(
            (r) =>
                r.top >= viewport.bottom - 0.5 && r.bottom <= buttonTop + 0.5,
          );
      expect(
        edges,
        isNotEmpty,
        reason:
            'no hairline between the list viewport '
            '(bottom ${viewport.bottom}) and the send button (top $buttonTop)',
      );

      // Guard: the list never runs under the footer. Scrolled to the end,
      // the last row sits wholly inside the viewport, above the button.
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      final lastBottom = _rows
          .evaluate()
          .map((e) => _rectOf(e).bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(lastBottom, lessThanOrEqualTo(viewport.bottom + 0.5));
      expect(lastBottom, lessThanOrEqualTo(buttonTop));
      expect(viewport.bottom, lessThanOrEqualTo(buttonTop));
    },
  );
}
