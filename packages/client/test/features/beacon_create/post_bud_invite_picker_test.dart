// Budding a Request from a Post, step 2 («Who to invite»): the step is the
// shared Forward recipient picker, not a list of its own.
//
// Everything runs through the real path a person hits: HTTP is faked, then
// the real Ferry link chain, PostBudRepository / ProfileRepository /
// ForwardRepository, the real ForwardCase and PostBudCase, a real
// BeaconCreateCubit, and the real BeaconCreateScreen. `UsersFetchByIds`
// answers at most 10 ids per request, as Hasura does for role `user`, so a
// 12-member Post needs the profile chunks to name everyone.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/users_fetch_by_ids_wire.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import 'post_bud_fakes.dart';

const _viewer = 'Uviewer000001';

String _member(int n) => 'Umember${n.toString().padLeft(5, '0')}';

String _nameOf(String id) => 'Name of $id';

final _en = lookupL10n(const Locale('en'));
final _ru = lookupL10n(const Locale('ru'));

/// One `postBudInviteCandidates` row; every member here can be invited.
Map<String, dynamic> _wireCandidate(String userId, {bool pretick = false}) => {
  '__typename': 'PostBudInviteCandidate',
  'userId': userId,
  'warm': true,
  'outcome': 'invited',
  'pretick': pretick,
  'viaUserId': null,
  'hasWritten': false,
};

/// The fake server: what it answers and what the client sent it.
final class _Server {
  _Server({
    required this.members,
    this.preticked = const {},
    this.notInvited = const {},
  });

  /// Post members other than the budder, in server order.
  final List<String> members;
  final Set<String> preticked;

  /// Ticked members the bud mutation reports as not invited.
  final Set<String> notInvited;

  final usersRequests = <List<String>>[];
  final buds = <Map<String, dynamic>>[];

  Map<String, dynamic>? answer(String name, Map<String, dynamic> vars) {
    switch (name) {
      case 'PostBudInviteCandidates':
        return {
          '__typename': 'query_root',
          'postBudInviteCandidates': [
            for (final id in members)
              _wireCandidate(id, pretick: preticked.contains(id)),
          ],
        };
      case 'UsersFetchByIds':
        final ids = (vars['ids'] as List).cast<String>();
        usersRequests.add(ids);
        return {
          '__typename': 'query_root',
          'user': [for (final id in ids.take(kWireUserRowCap)) wireUserRow(id)],
        };
      case 'PostBudFromPost':
        buds.add(vars);
        final sent = ((vars['invitees'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        return {
          '__typename': 'mutation_root',
          'beaconBudFromPost': {
            '__typename': 'PostBudResult',
            'outcome': 'created',
            'childBeaconId': 'Bchild0000001',
            'invitees': [
              for (final i in sent)
                {
                  '__typename': 'PostBudInviteeResult',
                  'userId': i['userId'],
                  'outcome': notInvited.contains(i['userId'])
                      ? 'recipientPaused'
                      : 'invited',
                },
            ],
          },
        };
    }
    return const <String, dynamic>{};
  }

  /// Invitees of the single bud mutation, as sent on the wire.
  List<Map<String, dynamic>> get sentInvitees {
    expect(buds, hasLength(1), reason: 'one PostBudFromPost was sent');
    return ((buds.single['invitees'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
  }
}

/// A real [RemoteApiService] whose transport is [server]; built inside the
/// mock client zone so every later request goes to it.
Future<RemoteApiService> _startWire(WidgetTester tester, _Server server) async {
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
      },
      () => MockClient((request) async {
        http.Response json(Object? body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path.endsWith('/session/access-token')) {
          return json({
            'subject': _viewer,
            'access_token': 'test-token',
            'expires_in': 3600,
          });
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final name = body['operationName'] as String;
        final vars = ((body['variables'] as Map?) ?? const {})
            .cast<String, dynamic>();
        return json({'data': server.answer(name, vars)});
      }),
    );
  });
  addTearDown(() => tester.runAsync(remote.close));
  return remote;
}

class _NoBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFactCards implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _Router extends Mock implements StackRouter {
  final opened = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }
}

typedef _Pumped = ({_Server server, BeaconCreateCubit cubit, _Router router});

/// Pumps the bud create screen for [server]'s Post, started by [postAuthor],
/// and lands on the invite step.
Future<_Pumped> _pumpInviteStep(
  WidgetTester tester,
  _Server server, {
  String postAuthor = _viewer,
  Locale locale = const Locale('en'),
}) async {
  final remote = await _startWire(tester, server);

  final effects = FakeUiEffectPort();
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository()
    ..fetchMineHandler = () async => {};
  final store = ContactNameStore();
  GetIt.I
    ..registerSingleton<Env>(const Env())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(authLocal, EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
    ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
    ..registerSingleton<ContactNameStore>(store);
  late ContactsCase contactsCase;
  await tester.runAsync(() async {
    contactsCase = ContactsCase(
      contactsRepo,
      buildTestAuthCase(authLocal, EmptyAuthRemote()),
      store,
      buildTestRealtimeSync().case_,
      env: const Env(),
      logger: Logger('PostBudInvitePickerTest'),
    );
    final syncReady = contactsRepo.nextSync();
    authLocal.emit(_viewer);
    await syncReady.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
  });
  addTearDown(
    () => tester.runAsync(() async {
      await contactsCase.dispose();
      await store.dispose();
    }),
  );

  GetIt.I.registerSingleton<ForwardCase>(
    ForwardCase(
      ForwardRepository(
        remote,
        _NoBeaconRepository(),
        buildTestRealtimeSync().port,
      ),
      authLocal,
      _NoFactCards(),
      ProfileRepository(remote),
      contactsCase,
      noopBlockCase(),
      postBudPort: PostBudRepository(remote),
      env: const Env(),
      logger: Logger('PostBudInvitePickerTest'),
    ),
  );

  final h = BudHarness(parent: budPost(authorId: postAuthor));
  final cubit = BeaconCreateCubit(
    beaconCreateCase: h.createCase,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      h.hierarchy,
      createCase: h.createCase,
      beacons: h.write,
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
    messagePrefillCase: h.prefillCase,
    postBudCase: PostBudCase(
      PostBudRepository(remote),
      OpIdService(),
      env: const Env(),
      logger: Logger('PostBudInvitePickerTest'),
    ),
    childCreationContext: kBudContext,
    effects: effects,
  );
  addTearDown(() => tester.runAsync(cubit.close));

  // Tall, so the whole member list is built.
  const surface = Size(900, 3000);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: surface),
        child: TenturaResponsiveScope(
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(create: (_) => ContextCubit()),
                  BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                ],
                child: const BeaconCreateScreen(
                  parentBeaconId: kBudPostId,
                  sourceMessageId: kBudSourceMessageId,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  final next = find.byKey(const Key('PostBud.NextButton'));
  expect(next, findsOneWidget, reason: 'the bud form opens on its first step');
  await tester.tap(next);
  await _settle(
    tester,
    until: () => find.byType(ForwardRecipientPicker).evaluate().isNotEmpty,
  );
  return (server: server, cubit: cubit, router: router);
}

/// Bounded pumps with real time in between, so the faked HTTP answers land.
Future<void> _settle(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= 8 && (until == null || until())) return;
  }
}

Finder _picker() => find.byType(ForwardRecipientPicker, skipOffstage: false);

Finder _rowOf(String id) => find.byWidgetPredicate(
  (w) => w is ForwardRecipientRow && w.candidate.id == id,
  skipOffstage: false,
);

ForwardCubit _forwardCubit(WidgetTester tester) =>
    BlocProvider.of<ForwardCubit>(tester.element(_picker()));

void _expectInviteStepIsThePicker() {
  expect(
    _picker(),
    findsOneWidget,
    reason: 'the invite step hosts the shared Forward recipient picker',
  );
}

Future<void> _tapRow(WidgetTester tester, String id) async {
  final row = find.byKey(TestIds.key(TestIds.forwardRecipient(id)));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await _settle(tester);
}

/// Opens [id]'s per-person note and types [text] into it.
Future<void> _writeNote(WidgetTester tester, String id, String text) async {
  final open = find.byTooltip(_en.forwardAddPersonalNoteForName(_nameOf(id)));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await _settle(tester);
  final field = find.descendant(
    of: find.byType(PerRecipientNoteInput),
    matching: find.byType(TextField),
  );
  expect(field, findsOneWidget, reason: 'the note for $id is open');
  await tester.enterText(field, text);
  await _settle(tester);
}

Finder _closePostTile() => find.widgetWithText(
  CheckboxListTile,
  _en.postBudClosePost,
  skipOffstage: false,
);

bool? _closePostValue(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(_closePostTile()).value;

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byKey(const Key('PostBud.SubmitButton'));
  expect(submit, findsOneWidget, reason: 'the screen bottom bar submits');
  expect(
    find.descendant(of: submit, matching: find.text(_en.postBudAction)),
    findsOneWidget,
    reason: 'the invite step bottom bar reads «Make a request»',
  );
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await _settle(tester);
}

void main() {
  setUp(() async => GetIt.I.reset());
  tearDown(() async => GetIt.I.reset());

  final twelve = [for (var n = 1; n <= 12; n++) _member(n)];

  group('Post bud invite step shows the Forward picker', () {
    testWidgets('a 12-member Post lists every member by name, ticks the '
        'pre-ticked ones and offers the explanation header', (tester) async {
      final p = await _pumpInviteStep(
        tester,
        _Server(members: twelve, preticked: {_member(2), _member(12)}),
      );
      _expectInviteStepIsThePicker();

      expect(_rowOf(twelve.first), findsOneWidget);
      expect(
        find.byType(ForwardRecipientRow, skipOffstage: false),
        findsNWidgets(12),
      );
      for (final id in twelve) {
        expect(
          find.descendant(of: _rowOf(id), matching: find.text(_nameOf(id))),
          findsOneWidget,
          reason: '$id is shown by name',
        );
      }
      expect(find.text(_en.unknownPerson, skipOffstage: false), findsNothing);
      expect(
        p.server.usersRequests.every((ids) => ids.length <= kWireUserRowCap),
        isTrue,
      );

      for (final id in twelve) {
        final ticked = id == _member(2) || id == _member(12);
        expect(
          tester.widget<ForwardRecipientRow>(_rowOf(id)).isSelected,
          ticked,
          reason: '$id ticked: $ticked',
        );
      }

      expect(
        find.descendant(
          of: _picker(),
          matching: find.text(_en.postBudInviteExplanation),
        ),
        findsOneWidget,
        reason: 'the explanation is the picker header',
      );
    });

    testWidgets("the step's ForwardCubit is the invite profile, embedded, "
        'with no Request id, and closes with the screen', (tester) async {
      await _pumpInviteStep(tester, _Server(members: twelve));
      _expectInviteStepIsThePicker();

      final forward = _forwardCubit(tester);
      expect(forward.state.targetProfile, ForwardTargetProfile.postBudInvite);
      expect(forward.state.beaconId, '');
      expect(forward.embedded, isTrue);
      expect(forward.budPostId, kBudPostId);
      expect(forward.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(forward.isClosed, isTrue, reason: 'the screen owns the cubit');
    });

    testWidgets("a ticked row's note field shows the invite note hint", (
      tester,
    ) async {
      await _pumpInviteStep(tester, _Server(members: twelve));
      _expectInviteStepIsThePicker();

      await _tapRow(tester, _member(1));
      final open = find.byTooltip(
        _en.forwardAddPersonalNoteForName(_nameOf(_member(1))),
      );
      await tester.ensureVisible(open);
      await tester.tap(open);
      await _settle(tester);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(PerRecipientNoteInput),
          matching: find.byType(TextField),
        ),
      );
      expect(field.decoration?.hintText, _en.postBudInviteNoteHint);
      expect(_en.postBudInviteNoteHint, "Why you're inviting them (optional)");
    });

    testWidgets('the many-invites warning shows above five ticked and counts '
        'the picker selection', (tester) async {
      await _pumpInviteStep(tester, _Server(members: twelve));
      _expectInviteStepIsThePicker();

      for (var n = 1; n <= 5; n++) {
        await _tapRow(tester, _member(n));
      }
      expect(_forwardCubit(tester).state.selectedIds, hasLength(5));
      expect(
        find.byKey(const Key('PostBud.ManyWarning'), skipOffstage: false),
        findsNothing,
      );

      await _tapRow(tester, _member(6));
      expect(_forwardCubit(tester).state.selectedIds, hasLength(6));
      final warning = find.byKey(
        const Key('PostBud.ManyWarning'),
        skipOffstage: false,
      );
      expect(warning, findsOneWidget);
      expect(
        find.descendant(
          of: warning,
          matching: find.text(_en.postBudInviteManyWarning(6)),
        ),
        findsOneWidget,
      );
      expect(
        _en.postBudInviteManyWarning(6),
        'Everyone ticked gets a request. Ticked: 6',
      );
    });

    for (final (locale, l10n) in [
      (const Locale('en'), _en),
      (const Locale('ru'), _ru),
    ]) {
      testWidgets('no text on the invite step says beacon or room, and its '
          'bottom bar offers «${l10n.postBudAction}» ($locale)', (
        tester,
      ) async {
        // Six ticked: the many-invites warning and the author's close-post
        // checkbox are on screen too.
        final six = [for (var n = 1; n <= 6; n++) _member(n)];
        await _pumpInviteStep(
          tester,
          _Server(members: six, preticked: six.toSet()),
          locale: locale,
        );
        _expectInviteStepIsThePicker();
        expect(
          find.byKey(const Key('PostBud.ManyWarning'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text(l10n.postBudClosePost, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('PostBud.SubmitButton')),
            matching: find.text(l10n.postBudAction),
          ),
          findsOneWidget,
        );

        // Open a note so its hint is on screen too.
        final openNote = find.byTooltip(
          l10n.forwardAddPersonalNoteForName(_nameOf(_member(1))),
        );
        await tester.ensureVisible(openNote);
        await tester.tap(openNote);
        await _settle(tester);
        expect(find.byType(PerRecipientNoteInput), findsOneWidget);

        // Everything a person can read on the invite step: painted text
        // (picker, header, warnings, checkbox, app bar, bottom bar), field
        // hints and labels, tooltips and semantics labels. The hidden form
        // step is offstage and not scanned.
        Iterable<W> under<W extends Widget>() => find
            .descendant(
              of: find.byType(BeaconCreateScreen),
              matching: find.byWidgetPredicate((w) => w is W),
            )
            .evaluate()
            .map((e) => e.widget as W);
        final texts = <String>[
          for (final w in under<RichText>()) w.text.toPlainText(),
          for (final w in under<InputDecorator>()) ...[
            ?w.decoration.hintText,
            ?w.decoration.labelText,
            ?w.decoration.helperText,
          ],
          for (final w in under<Tooltip>()) ?w.message,
          for (final w in under<Semantics>()) ...[
            ?w.properties.label,
            ?w.properties.hint,
            ?w.properties.tooltip,
          ],
        ];
        expect(
          texts,
          contains(l10n.postBudInviteNoteHint),
          reason: 'the scan reaches the note hint',
        );
        expect(texts, isNotEmpty);
        for (final t in texts) {
          expect(
            t.toLowerCase(),
            isNot(matches(RegExp('beacon|room|маяк|комнат'))),
            reason: '$locale text «$t»',
          );
        }
      });
    }
  });

  group('Post bud invite step sends the picker selection', () {
    testWidgets('ticking two members and noting one sends exactly them, in '
        'list order, with the trimmed note', (tester) async {
      final p = await _pumpInviteStep(tester, _Server(members: twelve));
      _expectInviteStepIsThePicker();

      // Tick the 3rd listed member, then the 1st.
      await _tapRow(tester, _member(3));
      await _tapRow(tester, _member(1));
      await _writeNote(tester, _member(1), '  see you  ');
      await _writeNote(tester, _member(3), '   ');
      await _submit(tester);

      final invitees = p.server.sentInvitees;
      expect(invitees.map((i) => i['userId']).toList(), [
        _member(1),
        _member(3),
      ]);
      expect(invitees[0]['note'], 'see you');
      expect(invitees[1]['note'], isNull);

      expect(p.router.opened, hasLength(1), reason: 'opens the new Request');
      expect(
        (p.router.opened.single.args! as BeaconViewRouteArgs).id,
        'Bchild0000001',
      );
    });

    testWidgets('a skipped invitee whose profile came in the second chunk is '
        'named in the snackbar', (tester) async {
      final p = await _pumpInviteStep(
        tester,
        _Server(
          members: twelve,
          preticked: {_member(12)},
          notInvited: {_member(12)},
        ),
      );
      _expectInviteStepIsThePicker();
      expect(
        p.server.usersRequests,
        everyElement(hasLength(lessThanOrEqualTo(kWireUserRowCap))),
      );
      // Twelve members need two capped reads; the 12th (beyond the first
      // ten listed) comes back in a different chunk from the 1st.
      expect(p.server.usersRequests.length, greaterThanOrEqualTo(2));
      final withTwelfth = p.server.usersRequests
          .where((ids) => ids.contains(_member(12)))
          .toList();
      expect(withTwelfth, isNotEmpty);
      for (final ids in withTwelfth) {
        expect(
          ids,
          isNot(contains(_member(1))),
          reason: 'the 12th member is not in the chunk of the 1st',
        );
      }

      await _submit(tester);

      expect(
        p.server.sentInvitees.map((i) => i['userId']),
        contains(_member(12)),
      );
      expect(
        find.text(
          _en.postBudNotInvitedSnack(_nameOf(_member(12))),
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          _en.postBudNotInvitedSnack(_en.unknownPerson),
          findRichText: true,
        ),
        findsNothing,
      );
    });
  });

  group('Close the post on the picker invite step', () {
    testWidgets('a 2-member Post starts with «Close the post» checked', (
      tester,
    ) async {
      await _pumpInviteStep(tester, _Server(members: [_member(1)]));
      _expectInviteStepIsThePicker();
      expect(_closePostTile(), findsOneWidget);
      expect(_closePostValue(tester), isTrue);
    });

    testWidgets('a 4-member Post: checked while every member is ticked, '
        'unchecked after one is unticked', (tester) async {
      final members = [_member(1), _member(2), _member(3)];
      await _pumpInviteStep(
        tester,
        _Server(members: members, preticked: members.toSet()),
      );
      _expectInviteStepIsThePicker();
      expect(_forwardCubit(tester).state.selectedIds, members.toSet());
      expect(_closePostValue(tester), isTrue);

      await _tapRow(tester, _member(2));
      expect(_forwardCubit(tester).state.selectedIds, {
        _member(1),
        _member(3),
      });
      expect(_closePostValue(tester), isFalse);
    });

    testWidgets('the author checks it by hand after unticking a member and '
        'the bud closes the Post', (tester) async {
      final members = [_member(1), _member(2), _member(3)];
      final p = await _pumpInviteStep(
        tester,
        _Server(members: members, preticked: members.toSet()),
      );
      _expectInviteStepIsThePicker();
      await _tapRow(tester, _member(2));
      expect(_closePostValue(tester), isFalse);

      await tester.ensureVisible(_closePostTile());
      await tester.tap(_closePostTile());
      await _settle(tester);
      expect(_closePostValue(tester), isTrue);

      await _submit(tester);
      expect(p.server.buds, hasLength(1));
      expect(p.server.buds.single['closePost'], isTrue);
      expect(p.server.sentInvitees.map((i) => i['userId']).toList(), [
        _member(1),
        _member(3),
      ]);
    });

    testWidgets('the author unchecks it by hand with every member ticked and '
        'the bud leaves the Post open', (tester) async {
      final members = [_member(1), _member(2), _member(3)];
      final p = await _pumpInviteStep(
        tester,
        _Server(members: members, preticked: members.toSet()),
      );
      _expectInviteStepIsThePicker();
      expect(_closePostValue(tester), isTrue);

      await tester.ensureVisible(_closePostTile());
      await tester.tap(_closePostTile());
      await _settle(tester);
      expect(_closePostValue(tester), isFalse);

      await _submit(tester);
      expect(p.server.buds, hasLength(1));
      expect(p.server.buds.single['closePost'], isFalse);
      expect(
        p.server.sentInvitees.map((i) => i['userId']).toList(),
        members,
      );
    });

    testWidgets('a co-member who did not start the Post gets no checkbox and '
        'the bud leaves the Post open', (tester) async {
      final members = [_member(1), _member(2), _member(3)];
      final p = await _pumpInviteStep(
        tester,
        _Server(members: members, preticked: members.toSet()),
        postAuthor: _member(1),
      );
      _expectInviteStepIsThePicker();
      expect(_closePostTile(), findsNothing);
      expect(
        find.text(_en.postBudClosePost, skipOffstage: false),
        findsNothing,
      );

      await _submit(tester);
      expect(p.server.buds, hasLength(1));
      expect(p.server.buds.single['closePost'], isFalse);
    });
  });
}
