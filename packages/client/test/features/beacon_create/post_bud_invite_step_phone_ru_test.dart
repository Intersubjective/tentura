// Budding a Request from a Post, step 2 («Who to invite»): the copy reads
// right and fits on a 375×667 RU phone and a 1280×800 EN desktop, and the ARB
// files carry no dead or unpaired invite keys.
//
// Everything runs through the real path a person hits: HTTP is faked, then
// the real Ferry link chain, PostBudRepository / ProfileRepository /
// ForwardRepository, the real ForwardCase and PostBudCase, a real
// BeaconCreateCubit, and the real BeaconCreateScreen. `UsersFetchByIds`
// answers at most 10 ids per request, as Hasura does for role `user`, so a
// 12-member Post needs the profile chunks to name everyone.

@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../../support/phone_surface.dart';
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
Map<String, dynamic> _wireCandidate(
  String userId, {
  bool pretick = false,
  String? via,
}) => {
  '__typename': 'PostBudInviteCandidate',
  'userId': userId,
  'warm': true,
  'outcome': 'invited',
  'pretick': pretick,
  'viaUserId': via,
  'hasWritten': false,
};

/// The fake server: what it answers and what the client sent it.
final class _Server {
  _Server({
    required this.members,
    this.preticked = const {},
    this.via = const {},
  });

  /// member id -> id of the person they are reached through.
  final Map<String, String> via;

  /// Post members other than the budder, in server order.
  final List<String> members;
  final Set<String> preticked;

  final usersRequests = <List<String>>[];
  final buds = <Map<String, dynamic>>[];

  Map<String, dynamic>? answer(String name, Map<String, dynamic> vars) {
    switch (name) {
      case 'PostBudInviteCandidates':
        return {
          '__typename': 'query_root',
          'postBudInviteCandidates': [
            for (final id in members)
              _wireCandidate(
                id,
                pretick: preticked.contains(id),
                via: via[id],
              ),
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
                  'outcome': 'invited',
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
  Size surface = const Size(900, 3000),
  bool phone = false,
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
  if (phone) {
    await usePhoneSurface(tester);
  } else {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: phone ? kPhoneSurface : surface),
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

/// Non-@ keys of an ARB file.
Set<String> _arbKeys(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>).keys
        .where((k) => !k.startsWith('@'))
        .toSet();

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

const _privacyKey = 'postBudInvitePrivacyHint';

// Keep the concepts within a clause without pinning the translation to a
// single wording. Editorial review still checks the meaning in context.
const _withinClause = r'[^.!?;()\n]*';
const _enUnticked =
    r'(?:\bun(?:ticked|checked|selected|chosen|marked)|(?:\bnot|n[’\x27]t)\s+(?:\w+\s+){0,2}(?:tick\w*|check\w*|select\w*|choos\w*|chosen|pick\w*|mark\w*))\b';
const _enUnaware =
    r'\b(?:not|won[’\x27]t|never)\s+(?:be\s+)?(?:know|learn|find out|hear|see|become aware|aware)\b';
const _ruUnticked = r'(?:не\s*(?:отмет|выбер|выбра)[а-яё]*|без отметки)';
const _ruUnaware =
    r'(?:не\s+(?:узна[а-яё]*|увид[а-яё]*|услыш[а-яё]*|буд[а-яё]*\s+(?:знать|в курсе))|остан[а-яё]*\s+в неведении)';

Matcher _privacyCopy(Locale locale) => switch (locale.languageCode) {
  'ru' => allOf(
    anyOf(
      matches(
        '$_ruUnticked$_withinClause$_ruUnaware$_withinClause'
        'запрос',
      ),
      matches(
        '$_ruUnticked$_withinClause'
        'запрос$_withinClause$_ruUnaware',
      ),
      matches(
        '(?:о запросе|про запрос)$_withinClause$_ruUnaware$_withinClause$_ruUnticked',
      ),
      matches(
        '(?:о запросе|про запрос)$_withinClause(?:узна[а-яё]*|увид[а-яё]*)'
        r'\s+только\s+(?:отмеч|выбран)[а-яё]*',
      ),
      matches(
        r'только\s+(?:отмеч|выбран)[а-яё]*'
        '$_withinClause(?:узна[а-яё]*|увид[а-яё]*)$_withinClause'
        'запрос',
      ),
    ),
    matches(
      r'пост\s+(?:(?:остан[а-яё]*|оста[её]тся|сохранится)\s+)?(?:без изменени[яй]|как есть|как был[оа]?|прежним)|'
      r'пост\s+не (?:изменится|меняется|будет измен[её]н)|'
      '(?:не изменит|не меняет|не затронет)$_withinClauseпост',
    ),
    isNot(contains('просьб')),
    isNot(contains('маяк')),
    isNot(contains('beacon')),
  ),
  _ => allOf(
    matches(RegExp(r"\bnot\b|won['’]t")),
    anyOf(
      matches(
        '$_enUnticked$_withinClause$_enUnaware$_withinClause\\brequest\\b',
      ),
      matches(
        '$_enUnaware$_withinClause\\brequest\\b$_withinClause$_enUnticked',
      ),
      matches(
        r'\bonly\s+(?:the\s+)?(?:ticked|checked|selected|chosen|picked|marked)'
        '$_withinClause(?:know|learn|hear|see|find out)$_withinClause\\brequest\\b',
      ),
      matches(
        '$_enUnaware$_withinClause\\brequest\\b$_withinClause\\bunless\\b'
        '$_withinClause(?:tick|check|select|choose|pick|mark)',
      ),
    ),
    matches(
      r'\bpost\s+(?:itself\s+)?(?:will\s+)?(?:(?:stays?|remains?|is|be)\s+)?(?:unchanged|as (?:it is|it was|is)|the same)|'
      r'\bpost\s+(?:itself\s+)?(?:will\s+)?(?:not|won[’\x27]t)\s+(?:be\s+)?(?:change[ds]?|affected)|'
      '(?:not|won[’\\x27]t)\\s+(?:change|affect)$_withinClause\\bpost\\b',
    ),
    isNot(contains('beacon')),
  ),
};

Finder _privacyLine(Locale locale, {bool skipOffstage = true}) {
  final arbText = _arb('l10n/app_${locale.languageCode}.arb')[_privacyKey];
  if (arbText is String && arbText.trim().isNotEmpty) {
    return find.text(arbText, skipOffstage: skipOffstage);
  }
  // On a checkout without the ARB entry, still check the rendered text.
  final copy = _privacyCopy(locale);
  final l10n = lookupL10n(locale);
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        widget.data != l10n.postBudInviteExplanation &&
        widget.data != l10n.postBudClosePost &&
        copy.matches(widget.data!.toLowerCase(), {}),
    description: 'invite privacy line about the Request and its source Post',
    skipOffstage: skipOffstage,
  );
}

void _expectPrivacyLine(WidgetTester tester, Finder line, {String? after}) {
  expect(line, findsOneWidget, reason: after);
  expect(
    tester.renderObject<RenderParagraph>(line).didExceedMaxLines,
    isFalse,
    reason: after,
  );
  final tt = tester.element(line).tt;
  expect(tester.widget<Text>(line).style, TenturaText.bodySmall(tt.textMuted));
}

Finder _recipient(String id) =>
    find.byKey(TestIds.key(TestIds.forwardRecipient(id)));

double _budBottomBarTop(WidgetTester tester) {
  final scaffold = tester.widget<Scaffold>(
    find.descendant(
      of: find.byType(BeaconCreateScreen),
      matching: find.byType(Scaffold),
    ),
  );
  return tester.getTopLeft(find.byWidget(scaffold.bottomNavigationBar!)).dy;
}

Finder _manyWarning({bool skipOffstage = true}) => find.byKey(
  const Key('PostBud.ManyWarning'),
  skipOffstage: skipOffstage,
);

void _expectWarningCount(
  WidgetTester tester,
  L10n l10n,
  int count, {
  bool skipOffstage = true,
}) {
  final warning = _manyWarning(skipOffstage: skipOffstage);
  if (count < 6) {
    expect(warning, findsNothing);
    return;
  }
  expect(warning, findsOneWidget);
  final message = find.descendant(
    of: warning,
    matching: find.byType(Text, skipOffstage: skipOffstage),
    skipOffstage: skipOffstage,
  );
  expect(message, findsOneWidget);
  final text = tester.widget<Text>(message).data;
  expect(
    text,
    l10n.postBudInviteManyWarning(count),
    reason: 'the displayed warning reports $count selected recipients',
  );
  if (l10n.localeName == 'ru') {
    expect(text, endsWith('Отмечено: $count'));
  }
  expect(
    tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
    isFalse,
  );
}

List<String> _overflowExceptions(WidgetTester tester) {
  final found = <String>[];
  Object? e;
  while ((e = tester.takeException()) != null) {
    found.add(e.toString());
  }
  return found;
}

/// Asserts the paragraph that paints [text] was not cut short by maxLines /
/// ellipsis (find.text matches the string even when it is visually truncated).
void _expectParagraphNotTruncated(
  WidgetTester tester,
  String text, {
  Finder? within,
}) {
  final finder = within == null
      ? find.text(text, skipOffstage: false)
      : find.descendant(
          of: within,
          matching: find.text(text, skipOffstage: false),
          skipOffstage: false,
        );
  expect(finder, findsOneWidget, reason: '«$text» is on screen');
  final render = tester.renderObject<RenderParagraph>(finder);
  expect(
    render.didExceedMaxLines,
    isFalse,
    reason: '«$text» is rendered in full, not ellipsized',
  );
}

List<String> _dartFilesMentioning(RegExp pattern, List<String> roots) => [
  for (final root in roots)
    for (final f in Directory(root).listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          pattern.hasMatch(f.readAsStringSync()))
        f.path,
];

void main() {
  setUp(() async => GetIt.I.reset());
  tearDown(() async => GetIt.I.reset());

  final twelve = [for (var n = 1; n <= 12; n++) _member(n)];
  // Built from parts so this file itself never spells a removed key.
  final deadKeys = [
    for (final tail in ['Via', 'LoadFailed', 'Retry']) 'postBudInvite$tail',
  ];

  group('Bud invite privacy', () {
    for (final locale in const [Locale('ru'), Locale('en')]) {
      final l10n = lookupL10n(locale);
      final language = locale.languageCode.toUpperCase();
      for (final count in [0, 6]) {
        testWidgets('the $language phone shows the full privacy line with '
            '$count recipients ticked and room for the first row', (
          tester,
        ) async {
          await _pumpInviteStep(
            tester,
            _Server(members: twelve, preticked: twelve.take(count).toSet()),
            locale: locale,
            phone: true,
          );
          _expectInviteStepIsThePicker();
          final first = _recipient(_member(1));
          expect(first, findsOneWidget);
          final firstTop = tester.getTopLeft(first).dy;
          expect(firstTop, inInclusiveRange(0, kPhoneSurface.height));
          expect(firstTop, lessThan(_budBottomBarTop(tester)));
          _expectWarningCount(tester, l10n, count);
          expect(_overflowExceptions(tester), isEmpty);

          final explanation = find.text(l10n.postBudInviteExplanation);
          expect(explanation, findsOneWidget);
          final line = _privacyLine(locale);
          _expectPrivacyLine(tester, line);
          expect(
            tester.getTopLeft(line).dy,
            greaterThan(tester.getTopLeft(explanation).dy),
          );
          expect(tester.getBottomLeft(line).dy, lessThanOrEqualTo(firstTop));
          if (count == 6) {
            expect(
              find.descendant(of: _manyWarning(), matching: line),
              findsNothing,
            );
          }
        });
      }

      test('$language translates the privacy line in Request and Post '
          'vocabulary and exposes it through L10n', () {
        final arb = _arb('l10n/app_${locale.languageCode}.arb');
        final source = arb[_privacyKey];
        expect(source, isA<String>(), reason: '$_privacyKey in $language ARB');
        final copy = (source as String).trim();
        expect(copy, isNotEmpty);
        expect(copy.toLowerCase(), _privacyCopy(locale));
        if (locale.languageCode == 'en') {
          expect(
            arb['@$_privacyKey'],
            containsPair(
              'description',
              matches(
                RegExp(
                  r'\bbud\w*\b.*\binvite step\b|\binvite step\b.*\bbud\w*\b',
                  caseSensitive: false,
                ),
              ),
            ),
          );
        }
        expect(_arbKeys('l10n/app_ru.arb'), _arbKeys('l10n/app_en.arb'));
        // The getter is generated by gen-l10n once the ARB key exists.
        final dynamic generated = l10n;
        // Dynamic lookup lets the baseline compile before gen-l10n adds it.
        // ignore: avoid_dynamic_calls
        expect(generated.postBudInvitePrivacyHint, source);
      });
    }

    testWidgets('the Russian privacy line survives ticking and unticking '
        'seven people', (tester) async {
      const locale = Locale('ru');
      await _pumpInviteStep(
        tester,
        _Server(members: twelve),
        locale: locale,
        phone: true,
      );
      // The header can scroll out of view as the tester reaches later rows.
      final line = _privacyLine(locale, skipOffstage: false);
      final visibleLine = _privacyLine(locale);
      final explanation = find.text(
        _ru.postBudInviteExplanation,
        skipOffstage: false,
      );
      final missingAt = <String>[];
      Future<void> checkSelection(int count, String action) async {
        _expectWarningCount(tester, _ru, count, skipOffstage: false);
        for (final previousCount in [6, 7]) {
          if (previousCount == count) continue;
          expect(
            find.text(
              _ru.postBudInviteManyWarning(previousCount),
              skipOffstage: false,
            ),
            findsNothing,
            reason: '$action leaves no warning for $previousCount selections',
          );
        }
        expect(
          explanation,
          findsOneWidget,
          reason: '$action keeps the explanation',
        );
        expect(_overflowExceptions(tester), isEmpty);
        final matches = line.evaluate().length;
        if (matches == 1) {
          _expectPrivacyLine(tester, line, after: action);
        } else {
          missingAt.add('$action ($matches matches)');
        }
        await tester.ensureVisible(explanation);
        await tester.pump();
        if (matches == 1) {
          _expectPrivacyLine(tester, visibleLine, after: action);
          final bounds = tester.getRect(visibleLine);
          expect(bounds.top, greaterThanOrEqualTo(0), reason: action);
          expect(
            bounds.bottom,
            lessThanOrEqualTo(_budBottomBarTop(tester)),
            reason: action,
          );
        }
      }

      Future<void> toggleMember(int n, {required bool ticked}) async {
        final id = _member(n);
        final row = _recipient(id);
        if (row.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            row,
            150,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
        await tester.pump();
        await tester.tap(row);
        await _settle(tester);
        expect(
          tester.widget<ForwardRecipientRow>(_rowOf(id)).isSelected,
          ticked,
        );
        await checkSelection(
          ticked ? n : n - 1,
          '${ticked ? 'tick' : 'untick'} $n',
        );
      }

      await checkSelection(0, 'before any selection');
      for (var n = 1; n <= 7; n++) {
        await toggleMember(n, ticked: true);
      }
      for (var n = 7; n >= 1; n--) {
        await toggleMember(n, ticked: false);
      }
      expect(
        missingAt,
        isEmpty,
        reason: 'the privacy line appears exactly once at every step',
      );
    });

    for (final locale in const [Locale('ru'), Locale('en')]) {
      final l10n = lookupL10n(locale);
      final language = locale.languageCode.toUpperCase();
      testWidgets('the $language phone fits the privacy line between the '
          'explanation and the empty invite list', (tester) async {
        await _pumpInviteStep(
          tester,
          _Server(members: const []),
          locale: locale,
          phone: true,
        );
        _expectInviteStepIsThePicker();
        final explanation = find.text(l10n.postBudInviteExplanation);
        final emptyList = find.text(l10n.postBudInviteEmpty);
        expect(explanation, findsOneWidget);
        expect(emptyList, findsOneWidget);
        _expectParagraphNotTruncated(tester, l10n.postBudInviteEmpty);
        final listRect = tester.getRect(emptyList);
        expect(listRect.bottom, lessThanOrEqualTo(_budBottomBarTop(tester)));
        expect(listRect.bottom, lessThanOrEqualTo(kPhoneSurface.height));
        expect(_manyWarning(), findsNothing);
        expect(_overflowExceptions(tester), isEmpty);

        final line = _privacyLine(locale);
        _expectPrivacyLine(tester, line);
        final lineRect = tester.getRect(line);
        expect(lineRect.top, greaterThanOrEqualTo(0));
        expect(lineRect.top, greaterThan(tester.getTopLeft(explanation).dy));
        expect(lineRect.bottom, lessThanOrEqualTo(listRect.top));
      });
    }

    for (final profile in ForwardTargetProfile.values) {
      if (profile == ForwardTargetProfile.postBudInvite) continue;
      final target = profile == ForwardTargetProfile.request
          ? 'Request'
          : 'Post';
      testWidgets('the privacy line belongs to budding and is absent when '
          'forwarding a $target', (tester) async {
        await _pumpInviteStep(tester, _Server(members: twelve));
        final first = _rowOf(_member(1));
        expect(first, findsOneWidget);
        final candidate = tester.widget<ForwardRecipientRow>(first).candidate;
        final line = _privacyLine(const Locale('en'));
        final buddingCount = line.evaluate().length;

        const beaconId = 'Bforward00001';
        final title = profile == ForwardTargetProfile.post
            ? _en.forwardPostTitle
            : _en.forwardBeaconTitle;
        for (final hasCandidates in [false, true]) {
          final forward = ForwardCubit(
            beaconId: beaconId,
            debugSkipInitialLoad: true,
            debugInitialState: ForwardState(
              beaconId: beaconId,
              targetProfile: profile,
              candidates: hasCandidates ? [candidate] : const [],
              candidatesLoad: hasCandidates
                  ? const ForwardCandidatesReady()
                  : const ForwardCandidatesEmpty(),
            ),
          );
          addTearDown(forward.close);
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              theme: TenturaTheme.light(),
              home: MultiBlocProvider(
                key: ValueKey(hasCandidates),
                providers: [
                  BlocProvider<ForwardCubit>.value(value: forward),
                  BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
                ],
                child: const Scaffold(
                  body: ForwardRecipientPicker(beaconId: beaconId),
                ),
              ),
            ),
          );
          await _settle(tester);
          expect(find.text(title), findsOneWidget);
          expect(first, hasCandidates ? findsOneWidget : findsNothing);
          expect(_overflowExceptions(tester), isEmpty);
          expect(line, findsNothing);
        }
        expect(buddingCount, 1, reason: 'budding shows the privacy line once');
      });
    }
  });

  group('Bud invite step copy on a 375×667 RU phone', () {
    testWidgets('title, explanation, warning and close-post label render in '
        'full, the voucher is named, no overflow', (tester) async {
      final p = await _pumpInviteStep(
        tester,
        _Server(
          members: twelve,
          preticked: twelve.take(6).toSet(),
          via: {_member(8): _member(1)},
        ),
        locale: const Locale('ru'),
        phone: true,
      );
      _expectInviteStepIsThePicker();
      expect(p.server.usersRequests, isNotEmpty);

      expect(
        find.text(_ru.postBudInviteTitle, skipOffstage: false),
        findsWidgets,
      );
      expect(
        find.text(_ru.postBudInviteExplanation, skipOffstage: false),
        findsOneWidget,
      );
      final warning = find.byKey(
        const Key('PostBud.ManyWarning'),
        skipOffstage: false,
      );
      expect(warning, findsOneWidget);
      expect(
        find.descendant(
          of: warning,
          matching: find.text(_ru.postBudInviteManyWarning(6)),
        ),
        findsOneWidget,
      );
      expect(_ru.postBudInviteManyWarning(6), endsWith('Отмечено: 6'));
      _expectParagraphNotTruncated(
        tester,
        _ru.postBudInviteManyWarning(6),
        within: warning,
      );
      expect(
        find.text(_ru.postBudClosePost, skipOffstage: false),
        findsOneWidget,
      );

      // The member reached through one other person names that person.
      await tester.scrollUntilVisible(
        find.byKey(TestIds.key(TestIds.forwardRecipient(_member(8)))),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _settle(tester);
      expect(
        p.server.usersRequests.expand((ids) => ids),
        contains(_member(1)),
        reason: 'the voucher profile was fetched from the faked response',
      );
      final reach = _ru.forwardReachVouchedByOne(_nameOf(_member(1)));
      expect(
        find.descendant(
          of: _rowOf(_member(8)),
          matching: find.text(reach, skipOffstage: false),
        ),
        findsOneWidget,
        reason: 'the reach line names the voucher in full',
      );
      _expectParagraphNotTruncated(tester, reach, within: _rowOf(_member(8)));
      expect(find.text(_ru.unknownPerson, skipOffstage: false), findsNothing);
      expect(_overflowExceptions(tester), isEmpty);
    });

    testWidgets('the warning counts exactly the ticked rows', (tester) async {
      await _pumpInviteStep(
        tester,
        _Server(members: twelve),
        locale: const Locale('ru'),
        phone: true,
      );
      for (var n = 1; n <= 7; n++) {
        await _tapRow(tester, _member(n));
      }
      final warning = find.byKey(
        const Key('PostBud.ManyWarning'),
        skipOffstage: false,
      );
      expect(warning, findsOneWidget);
      expect(
        find.descendant(
          of: warning,
          matching: find.text(
            _ru.postBudInviteManyWarning(7),
            skipOffstage: false,
          ),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(_ru.postBudInviteManyWarning(7), endsWith('Отмечено: 7'));
      _expectParagraphNotTruncated(
        tester,
        _ru.postBudInviteManyWarning(7),
        within: warning,
      );
      expect(_overflowExceptions(tester), isEmpty);
    });

    testWidgets('a ticked row opens its note with the RU hint, no overflow', (
      tester,
    ) async {
      await _pumpInviteStep(
        tester,
        _Server(members: twelve),
        locale: const Locale('ru'),
        phone: true,
      );
      await _tapRow(tester, _member(1));
      final open = find.byTooltip(
        _ru.forwardAddPersonalNoteForName(_nameOf(_member(1))),
      );
      await tester.ensureVisible(open);
      await tester.tap(open);
      await _settle(tester);
      expect(_ru.postBudInviteNoteHint, 'Почему зовёте (необязательно)');
      _expectParagraphNotTruncated(
        tester,
        _ru.postBudInviteNoteHint,
        within: find.byType(PerRecipientNoteInput),
      );
      expect(_overflowExceptions(tester), isEmpty);
    });

    testWidgets('a Post with nobody else to invite shows the RU empty state', (
      tester,
    ) async {
      await _pumpInviteStep(
        tester,
        _Server(members: const []),
        locale: const Locale('ru'),
        phone: true,
      );
      expect(
        find.text(_ru.postBudInviteEmpty, skipOffstage: false),
        findsOneWidget,
      );
      expect(_ru.postBudInviteEmpty, 'В посте больше некого позвать');
      _expectParagraphNotTruncated(tester, _ru.postBudInviteEmpty);
      expect(_overflowExceptions(tester), isEmpty);
    });
  });

  group('Bud invite step copy on a 1280×800 EN desktop', () {
    testWidgets('title, explanation, warning, close-post label and bud invite '
        'privacy render, no overflow, nobody unknown', (tester) async {
      await _pumpInviteStep(
        tester,
        _Server(members: twelve, preticked: twelve.take(6).toSet()),
        surface: const Size(1280, 800),
      );
      _expectInviteStepIsThePicker();
      expect(_en.postBudInviteTitle, 'Who to invite');
      expect(
        find.text(_en.postBudInviteTitle, skipOffstage: false),
        findsWidgets,
      );
      _expectParagraphNotTruncated(tester, _en.postBudInviteExplanation);
      expect(
        find.descendant(
          of: find.byKey(const Key('PostBud.ManyWarning'), skipOffstage: false),
          matching: find.text(_en.postBudInviteManyWarning(6)),
        ),
        findsOneWidget,
      );
      _expectParagraphNotTruncated(
        tester,
        _en.postBudInviteManyWarning(6),
        within: find.byKey(
          const Key('PostBud.ManyWarning'),
          skipOffstage: false,
        ),
      );
      expect(
        _en.postBudClosePost,
        'Close the post and continue in the request',
      );
      _expectParagraphNotTruncated(tester, _en.postBudClosePost);
      expect(find.text(_en.unknownPerson, skipOffstage: false), findsNothing);
      expect(_overflowExceptions(tester), isEmpty);
      _expectPrivacyLine(tester, _privacyLine(const Locale('en')));
    });
  });

  group('Bud invite ARB copy', () {
    test('the invite keys left unused by the picker are removed', () {
      for (final path in ['l10n/app_en.arb', 'l10n/app_ru.arb']) {
        final arb = _arb(path);
        for (final k in deadKeys) {
          expect(arb.containsKey(k), isFalse, reason: '$k in $path');
          expect(arb.containsKey('@$k'), isFalse, reason: '@$k in $path');
        }
      }
    });

    test('the RU and EN files carry exactly the same keys', () {
      final en = _arbKeys('l10n/app_en.arb');
      final ru = _arbKeys('l10n/app_ru.arb');
      expect(ru.difference(en), isEmpty, reason: 'RU keys without EN twin');
      expect(en.difference(ru), isEmpty, reason: 'EN keys without RU twin');
    });

    test('the kept invite-step keys are non-empty in both languages', () {
      for (final path in ['l10n/app_en.arb', 'l10n/app_ru.arb']) {
        final arb = _arb(path);
        for (final k in [
          'postBudInviteTitle',
          'postBudInviteExplanation',
          'postBudInviteManyWarning',
          'postBudInviteNoteHint',
          'postBudClosePost',
          'postBudInviteEmpty',
        ]) {
          expect((arb[k] as String?)?.trim(), isNotEmpty, reason: '$k $path');
        }
        expect(arb['postBudInviteManyWarning'], contains('{count}'));
      }
    });

    test('the RU many-invites warning does not call a request «просьба»', () {
      final ru = _arb('l10n/app_ru.arb')['postBudInviteManyWarning'] as String;
      expect(ru.toLowerCase(), isNot(contains('просьб')));
    });

    test('the RU many-invites warning names what a ticked person gets as '
        '«запрос» or «приглашение»', () {
      final ru = (_arb('l10n/app_ru.arb')['postBudInviteManyWarning'] as String)
          .toLowerCase();
      expect(ru, matches(RegExp('запрос|приглашен')));
      final explanation =
          (_arb('l10n/app_ru.arb')['postBudInviteExplanation'] as String)
              .toLowerCase();
      final noun = RegExp('запрос|приглашен').firstMatch(ru)!.group(0)!;
      expect(
        explanation,
        contains(noun),
        reason: "the warning uses the explanation's noun",
      );
    });

    test('no lib/ or test/ file and no generated l10n class mentions the '
        'removed invite keys', () {
      final pattern = RegExp(
        'postBudInvite(${[
          for (final k in deadKeys) k.substring('postBudInvite'.length),
        ].join('|')})',
      );
      expect(_dartFilesMentioning(pattern, ['lib', 'test']), isEmpty);
    });

    test('check-user-facing-terminology.sh passes', () {
      final r = Process.runSync('bash', [
        '../../scripts/check-user-facing-terminology.sh',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
